module jupiter_sdram_controller #(
    parameter integer POWERUP_CYCLES          = 4000,
    parameter integer TRP_CYCLES              = 1,
    parameter integer TRFC_CYCLES             = 2,
    parameter integer TMRD_CYCLES             = 1,
    parameter integer TRCD_CYCLES             = 1,
    parameter integer CAS_CYCLES              = 3,
    parameter integer READ_RECOVERY_CYCLES    = 2,
    parameter integer WRITE_RECOVERY_CYCLES   = 3,
    parameter integer REFRESH_INTERVAL_CYCLES = 120
) (
    input  wire        clk,
    input  wire        reset,

    output reg         initialized,

    // Abstract 16-bit transaction interface from
    // jupiter_sdram_frontend.
    input  wire        half_valid,
    input  wire        half_write,
    input  wire [25:0] half_addr,
    input  wire [15:0] half_wdata,
    input  wire  [1:0] half_wstrb,
    output reg  [15:0] half_rdata,
    output reg         half_ready,

    // Physical SDR SDRAM command/address interface.
    //
    // SDRAM_CLK is intentionally not generated in this module.
    // A later integration checkpoint will provide the MiSTer-compatible
    // clock phase relationship at the top level.
    output wire        SDRAM_CKE,
    output reg  [12:0] SDRAM_A,
    output reg   [1:0] SDRAM_BA,
    inout  wire [15:0] SDRAM_DQ,
    output reg         SDRAM_DQML,
    output reg         SDRAM_DQMH,
    output reg         SDRAM_nCS,
    output reg         SDRAM_nCAS,
    output reg         SDRAM_nRAS,
    output reg         SDRAM_nWE
);

    localparam [2:0] CMD_NOP          = 3'b111;
    localparam [2:0] CMD_ACTIVE       = 3'b011;
    localparam [2:0] CMD_READ         = 3'b101;
    localparam [2:0] CMD_WRITE        = 3'b100;
    localparam [2:0] CMD_PRECHARGE    = 3'b010;
    localparam [2:0] CMD_AUTO_REFRESH = 3'b001;
    localparam [2:0] CMD_LOAD_MODE    = 3'b000;

    // Burst length 1, sequential burst, CAS latency 3.
    localparam [12:0] MODE_REGISTER = 13'h030;

    localparam [4:0] ST_POWERUP        = 5'd0;

    localparam [4:0] ST_INIT_PRE0      = 5'd1;
    localparam [4:0] ST_INIT_PRE0_WAIT = 5'd2;
    localparam [4:0] ST_INIT_REF0_A    = 5'd3;
    localparam [4:0] ST_INIT_REF0_A_W  = 5'd4;
    localparam [4:0] ST_INIT_REF0_B    = 5'd5;
    localparam [4:0] ST_INIT_REF0_B_W  = 5'd6;
    localparam [4:0] ST_INIT_MRS0      = 5'd7;
    localparam [4:0] ST_INIT_MRS0_WAIT = 5'd8;

    localparam [4:0] ST_INIT_PRE1      = 5'd9;
    localparam [4:0] ST_INIT_PRE1_WAIT = 5'd10;
    localparam [4:0] ST_INIT_REF1_A    = 5'd11;
    localparam [4:0] ST_INIT_REF1_A_W  = 5'd12;
    localparam [4:0] ST_INIT_REF1_B    = 5'd13;
    localparam [4:0] ST_INIT_REF1_B_W  = 5'd14;
    localparam [4:0] ST_INIT_MRS1      = 5'd15;
    localparam [4:0] ST_INIT_MRS1_WAIT = 5'd16;

    localparam [4:0] ST_IDLE           = 5'd17;
    localparam [4:0] ST_REFRESH0       = 5'd18;
    localparam [4:0] ST_REFRESH0_WAIT  = 5'd19;
    localparam [4:0] ST_REFRESH1       = 5'd20;
    localparam [4:0] ST_REFRESH1_WAIT  = 5'd21;

    localparam [4:0] ST_ACCESS_ACTIVE         = 5'd22;
    localparam [4:0] ST_ACCESS_TRCD_WAIT      = 5'd23;
    localparam [4:0] ST_ACCESS_READ           = 5'd24;
    localparam [4:0] ST_ACCESS_READ_WAIT      = 5'd25;
    localparam [4:0] ST_ACCESS_READ_RECOVERY  = 5'd26;
    localparam [4:0] ST_ACCESS_WRITE          = 5'd27;
    localparam [4:0] ST_ACCESS_WRITE_RECOVERY = 5'd28;
    localparam [4:0] ST_ACCESS_ACK            = 5'd29;

    reg [4:0]  state;
    reg [15:0] wait_count;
    reg [15:0] powerup_count;
    reg [15:0] refresh_count;
    reg        refresh_due;

    reg        saved_half_write;
    reg [25:0] saved_half_addr;
    reg [15:0] saved_half_wdata;
    reg  [1:0] saved_half_wstrb;
    reg [15:0] saved_read_data;

    // False means the next accepted halfword is the low half of a
    // new 32-bit Jupiter transaction. True means its second half is
    // still pending. Refresh is allowed only when this is false.
    reg logical_in_progress;

    reg [15:0] dq_out;
    reg        dq_oe;

    assign SDRAM_CKE = 1'b1;
    assign SDRAM_DQ = dq_oe ? dq_out : 16'hzzzz;

    // ------------------------------------------------------------
    // Physical command generation.
    //
    // The 128 MiB MiSTer arrangement uses the SDRAM_nCS level to
    // distinguish the two 64 MiB device selections. On smaller
    // configurations the second-chip initialization/refresh commands
    // are harmless because that selection is not populated.
    // ------------------------------------------------------------

    always @(*) begin
        SDRAM_A    = 13'd0;
        SDRAM_BA   = 2'b00;
        SDRAM_DQML = 1'b0;
        SDRAM_DQMH = 1'b0;

        dq_out = 16'd0;
        dq_oe  = 1'b0;

        half_rdata = saved_read_data;
        half_ready = (state == ST_ACCESS_ACK);

        SDRAM_nCS  = 1'b0;
        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = CMD_NOP;

        case (state)
            ST_INIT_PRE0: begin
                SDRAM_nCS  = 1'b0;
                SDRAM_A[10] = 1'b1;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_PRECHARGE;
            end

            ST_INIT_REF0_A,
            ST_INIT_REF0_B: begin
                SDRAM_nCS = 1'b0;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_AUTO_REFRESH;
            end

            ST_INIT_MRS0: begin
                SDRAM_nCS = 1'b0;
                SDRAM_A   = MODE_REGISTER;
                SDRAM_BA  = 2'b00;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_LOAD_MODE;
            end

            ST_INIT_PRE1: begin
                SDRAM_nCS   = 1'b1;
                SDRAM_A[10] = 1'b1;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_PRECHARGE;
            end

            ST_INIT_REF1_A,
            ST_INIT_REF1_B: begin
                SDRAM_nCS = 1'b1;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_AUTO_REFRESH;
            end

            ST_INIT_MRS1: begin
                SDRAM_nCS = 1'b1;
                SDRAM_A   = MODE_REGISTER;
                SDRAM_BA  = 2'b00;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_LOAD_MODE;
            end

            ST_REFRESH0: begin
                SDRAM_nCS = 1'b0;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_AUTO_REFRESH;
            end

            ST_REFRESH1: begin
                SDRAM_nCS = 1'b1;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_AUTO_REFRESH;
            end

            ST_ACCESS_ACTIVE: begin
                SDRAM_nCS = saved_half_addr[25];
                SDRAM_A   = saved_half_addr[16:4];
                SDRAM_BA  = saved_half_addr[3:2];
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_ACTIVE;
            end

            ST_ACCESS_READ: begin
                SDRAM_nCS    = saved_half_addr[25];
                SDRAM_A[9:0] =
                    {saved_half_addr[24:17], saved_half_addr[1:0]};
                SDRAM_A[10]  = 1'b1;
                SDRAM_BA     = saved_half_addr[3:2];
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_READ;
            end

            ST_ACCESS_WRITE: begin
                SDRAM_nCS    = saved_half_addr[25];
                SDRAM_A[9:0] =
                    {saved_half_addr[24:17], saved_half_addr[1:0]};
                SDRAM_A[10]  = 1'b1;
                SDRAM_BA     = saved_half_addr[3:2];

                SDRAM_DQML = ~saved_half_wstrb[0];
                SDRAM_DQMH = ~saved_half_wstrb[1];

                dq_out = saved_half_wdata;
                dq_oe  = 1'b1;

                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_WRITE;
            end

            default: begin
                SDRAM_nCS = 1'b0;
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} =
                    CMD_NOP;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Initialization and refresh sequencing.
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (reset) begin
            state          <= ST_POWERUP;
            initialized    <= 1'b0;
            wait_count     <= 16'd0;
            powerup_count  <= 16'd0;
            refresh_count       <= 16'd0;
            refresh_due         <= 1'b0;
            saved_half_write    <= 1'b0;
            saved_half_addr     <= 26'd0;
            saved_half_wdata    <= 16'd0;
            saved_half_wstrb    <= 2'b00;
            saved_read_data     <= 16'd0;
            logical_in_progress <= 1'b0;
        end else begin
            case (state)
                ST_POWERUP: begin
                    if (powerup_count >= POWERUP_CYCLES - 1) begin
                        powerup_count <= 16'd0;
                        state         <= ST_INIT_PRE0;
                    end else begin
                        powerup_count <= powerup_count + 16'd1;
                    end
                end

                ST_INIT_PRE0: begin
                    wait_count <= 16'd0;
                    state      <= ST_INIT_PRE0_WAIT;
                end

                ST_INIT_PRE0_WAIT: begin
                    if (wait_count >= TRP_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_INIT_REF0_A;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_INIT_REF0_A: begin
                    wait_count <= 16'd0;
                    state      <= ST_INIT_REF0_A_W;
                end

                ST_INIT_REF0_A_W: begin
                    if (wait_count >= TRFC_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_INIT_REF0_B;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_INIT_REF0_B: begin
                    wait_count <= 16'd0;
                    state      <= ST_INIT_REF0_B_W;
                end

                ST_INIT_REF0_B_W: begin
                    if (wait_count >= TRFC_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_INIT_MRS0;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_INIT_MRS0: begin
                    wait_count <= 16'd0;
                    state      <= ST_INIT_MRS0_WAIT;
                end

                ST_INIT_MRS0_WAIT: begin
                    if (wait_count >= TMRD_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_INIT_PRE1;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_INIT_PRE1: begin
                    wait_count <= 16'd0;
                    state      <= ST_INIT_PRE1_WAIT;
                end

                ST_INIT_PRE1_WAIT: begin
                    if (wait_count >= TRP_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_INIT_REF1_A;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_INIT_REF1_A: begin
                    wait_count <= 16'd0;
                    state      <= ST_INIT_REF1_A_W;
                end

                ST_INIT_REF1_A_W: begin
                    if (wait_count >= TRFC_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_INIT_REF1_B;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_INIT_REF1_B: begin
                    wait_count <= 16'd0;
                    state      <= ST_INIT_REF1_B_W;
                end

                ST_INIT_REF1_B_W: begin
                    if (wait_count >= TRFC_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_INIT_MRS1;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_INIT_MRS1: begin
                    wait_count <= 16'd0;
                    state      <= ST_INIT_MRS1_WAIT;
                end

                ST_INIT_MRS1_WAIT: begin
                    if (wait_count >= TMRD_CYCLES - 1) begin
                        wait_count    <= 16'd0;
                        initialized   <= 1'b1;
                        refresh_count <= 16'd0;
                        refresh_due   <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_IDLE: begin
                    if (refresh_due && !logical_in_progress) begin
                        state <= ST_REFRESH0;
                    end else if (half_valid) begin
                        saved_half_write <= half_write;
                        saved_half_addr  <= half_addr;
                        saved_half_wdata <= half_wdata;
                        saved_half_wstrb <= half_wstrb;
                        wait_count       <= 16'd0;
                        state            <= ST_ACCESS_ACTIVE;
                    end
                end

                ST_REFRESH0: begin
                    wait_count <= 16'd0;
                    state      <= ST_REFRESH0_WAIT;
                end

                ST_REFRESH0_WAIT: begin
                    if (wait_count >= TRFC_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_REFRESH1;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_REFRESH1: begin
                    wait_count <= 16'd0;
                    state      <= ST_REFRESH1_WAIT;
                end

                ST_REFRESH1_WAIT: begin
                    if (wait_count >= TRFC_CYCLES - 1) begin
                        wait_count    <= 16'd0;
                        refresh_count <= 16'd0;
                        refresh_due   <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_ACCESS_ACTIVE: begin
                    wait_count <= 16'd0;
                    state      <= ST_ACCESS_TRCD_WAIT;
                end

                ST_ACCESS_TRCD_WAIT: begin
                    if (wait_count >= TRCD_CYCLES - 1) begin
                        wait_count <= 16'd0;

                        if (saved_half_write)
                            state <= ST_ACCESS_WRITE;
                        else
                            state <= ST_ACCESS_READ;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_ACCESS_READ: begin
                    wait_count <= 16'd0;
                    state      <= ST_ACCESS_READ_WAIT;
                end

                ST_ACCESS_READ_WAIT: begin
                    if (wait_count >= CAS_CYCLES - 1) begin
                        saved_read_data <= SDRAM_DQ;
                        wait_count      <= 16'd0;
                        state           <= ST_ACCESS_READ_RECOVERY;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_ACCESS_READ_RECOVERY: begin
                    if (wait_count >= READ_RECOVERY_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_ACCESS_ACK;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_ACCESS_WRITE: begin
                    wait_count <= 16'd0;
                    state      <= ST_ACCESS_WRITE_RECOVERY;
                end

                ST_ACCESS_WRITE_RECOVERY: begin
                    if (wait_count >= WRITE_RECOVERY_CYCLES - 1) begin
                        wait_count <= 16'd0;
                        state      <= ST_ACCESS_ACK;
                    end else begin
                        wait_count <= wait_count + 16'd1;
                    end
                end

                ST_ACCESS_ACK: begin
                    logical_in_progress <= ~logical_in_progress;
                    state               <= ST_IDLE;
                end

                default: begin
                    state         <= ST_POWERUP;
                    initialized   <= 1'b0;
                    wait_count    <= 16'd0;
                    powerup_count <= 16'd0;
                    refresh_count       <= 16'd0;
                    refresh_due         <= 1'b0;
                    saved_half_write    <= 1'b0;
                    saved_half_addr     <= 26'd0;
                    saved_half_wdata    <= 16'd0;
                    saved_half_wstrb    <= 2'b00;
                    saved_read_data     <= 16'd0;
                    logical_in_progress <= 1'b0;
                end
            endcase

            // Begin counting refresh time only after initialization.
            // A pending refresh remains pending until the complete
            // two-selection refresh sequence has finished.
            if (initialized &&
                state != ST_REFRESH1_WAIT &&
                !refresh_due) begin
                if (refresh_count >= REFRESH_INTERVAL_CYCLES - 1) begin
                    refresh_due <= 1'b1;
                end else begin
                    refresh_count <= refresh_count + 16'd1;
                end
            end
        end
    end

endmodule
