module jupiter_sdram_frontend (
    input  wire        clk,
    input  wire        reset,

    // Jupiter 32-bit transaction interface.
    input  wire        m_valid,
    input  wire        m_write,
    input  wire [31:0] m_addr,
    input  wire [31:0] m_wdata,
    input  wire [3:0]  m_wstrb,
    output reg  [31:0] m_rdata,
    output reg         m_ready,

    // MiSTer-reported external SDRAM size.
    input  wire [15:0] sdram_sz,

    // Abstract 16-bit controller-side transaction interface.
    // M4B-1 intentionally stops here. A later checkpoint maps these
    // transactions to physical SDRAM row/bank/column commands.
    output reg         half_valid,
    output reg         half_write,
    output reg  [25:0] half_addr,
    output reg  [15:0] half_wdata,
    output reg  [1:0]  half_wstrb,
    input  wire [15:0] half_rdata,
    input  wire        half_ready
);

    localparam [31:0] SDRAM_BASE = 32'h10000000;

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_LOW  = 2'd1;
    localparam [1:0] STATE_HIGH = 2'd2;

    reg [1:0] state;

    reg        saved_write;
    reg [25:0] saved_half_addr;
    reg [31:0] saved_wdata;
    reg [3:0]  saved_wstrb;
    reg [15:0] saved_read_low;

    reg [31:0] capacity_bytes;

    wire size_valid = sdram_sz[15];

    always @(*) begin
        case (sdram_sz[1:0])
            2'd1: capacity_bytes = 32'h02000000; // 32 MiB
            2'd2: capacity_bytes = 32'h04000000; // 64 MiB
            2'd3: capacity_bytes = 32'h08000000; // 128 MiB
            default: capacity_bytes = 32'h00000000;
        endcase
    end

    wire [31:0] local_addr = m_addr - SDRAM_BASE;

    wire request_available =
        size_valid &&
        (capacity_bytes != 32'd0) &&
        (m_addr >= SDRAM_BASE) &&
        (m_addr[1:0] == 2'b00) &&
        (local_addr <= (capacity_bytes - 32'd4));

    always @(*) begin
        m_rdata    = 32'd0;
        m_ready    = 1'b0;

        half_valid = 1'b0;
        half_write = 1'b0;
        half_addr  = 26'd0;
        half_wdata = 16'd0;
        half_wstrb = 2'b00;

        case (state)
            STATE_IDLE: begin
                // Invalid, unavailable, misaligned, or out-of-range
                // transactions complete deterministically without reaching
                // the physical SDRAM controller.
                if (m_valid && !request_available) begin
                    m_ready = 1'b1;
                    m_rdata = 32'd0;
                end
            end

            STATE_LOW: begin
                half_valid = 1'b1;
                half_write = saved_write;
                half_addr  = saved_half_addr;
                half_wdata = saved_wdata[15:0];
                half_wstrb = saved_write ? saved_wstrb[1:0] : 2'b00;
            end

            STATE_HIGH: begin
                half_valid = 1'b1;
                half_write = saved_write;
                half_addr  = saved_half_addr + 26'd1;
                half_wdata = saved_wdata[31:16];
                half_wstrb = saved_write ? saved_wstrb[3:2] : 2'b00;

                if (half_ready) begin
                    m_ready = 1'b1;

                    if (!saved_write)
                        m_rdata = {half_rdata, saved_read_low};
                end
            end

            default: begin
                m_rdata    = 32'd0;
                m_ready    = 1'b0;
                half_valid = 1'b0;
            end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state           <= STATE_IDLE;
            saved_write     <= 1'b0;
            saved_half_addr <= 26'd0;
            saved_wdata     <= 32'd0;
            saved_wstrb     <= 4'd0;
            saved_read_low  <= 16'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (m_valid && request_available) begin
                        saved_write     <= m_write;
                        saved_half_addr <= local_addr[26:1];
                        saved_wdata     <= m_wdata;
                        saved_wstrb     <= m_wstrb;
                        state           <= STATE_LOW;
                    end
                end

                STATE_LOW: begin
                    if (half_ready) begin
                        if (!saved_write)
                            saved_read_low <= half_rdata;

                        state <= STATE_HIGH;
                    end
                end

                STATE_HIGH: begin
                    if (half_ready)
                        state <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
