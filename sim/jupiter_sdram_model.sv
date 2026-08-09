module jupiter_sdram_model #(
    parameter integer CAS_CYCLES = 3,
    parameter integer SLOTS      = 64
) (
    input  wire        clk,
    input  wire        reset,

    input  wire        SDRAM_CKE,
    input  wire [12:0] SDRAM_A,
    input  wire  [1:0] SDRAM_BA,
    inout  wire [15:0] SDRAM_DQ,
    input  wire        SDRAM_DQML,
    input  wire        SDRAM_DQMH,
    input  wire        SDRAM_nCS,
    input  wire        SDRAM_nCAS,
    input  wire        SDRAM_nRAS,
    input  wire        SDRAM_nWE,

    output reg         protocol_error
);

    localparam [2:0] CMD_NOP          = 3'b111;
    localparam [2:0] CMD_ACTIVE       = 3'b011;
    localparam [2:0] CMD_READ         = 3'b101;
    localparam [2:0] CMD_WRITE        = 3'b100;
    localparam [2:0] CMD_PRECHARGE    = 3'b010;
    localparam [2:0] CMD_AUTO_REFRESH = 3'b001;
    localparam [2:0] CMD_LOAD_MODE    = 3'b000;

    wire [2:0] command = {
        SDRAM_nRAS,
        SDRAM_nCAS,
        SDRAM_nWE
    };

    // One open-row slot for each MiSTer chip-selection/bank pair.
    reg [12:0] open_row   [0:7];
    reg        open_valid [0:7];

    // Sparse simulation storage. This is deliberately not a 128 MiB
    // simulation array. Only addresses actually written by a test need
    // storage.
    reg [25:0] mem_tag   [0:SLOTS-1];
    reg [15:0] mem_data  [0:SLOTS-1];
    reg        mem_valid [0:SLOTS-1];

    reg        read_pending;
    integer    read_countdown;
    reg [15:0] read_data;

    integer i;
    integer bank_index;
    integer slot_index;
    integer free_index;

    reg [25:0] access_addr;
    reg [15:0] merged_data;

    // The model drives DQ only for the cycle in which CAS latency has
    // expired. The controller owns DQ during writes.
    assign SDRAM_DQ =
        (read_pending && (read_countdown == 1))
            ? read_data
            : 16'hzzzz;

    always @(posedge clk) begin
        if (reset) begin
            protocol_error <= 1'b0;

            read_pending   <= 1'b0;
            read_countdown <= 0;
            read_data      <= 16'd0;

            for (i = 0; i < 8; i = i + 1) begin
                open_row[i]   <= 13'd0;
                open_valid[i] <= 1'b0;
            end

            for (i = 0; i < SLOTS; i = i + 1) begin
                mem_tag[i]   <= 26'd0;
                mem_data[i]  <= 16'd0;
                mem_valid[i] <= 1'b0;
            end
        end else begin
            // Advance any pending read toward its data-return cycle.
            if (read_pending) begin
                if (read_countdown > 1) begin
                    read_countdown <= read_countdown - 1;
                end else begin
                    read_pending   <= 1'b0;
                    read_countdown <= 0;
                end
            end

            // Maintenance commands do not alter stored test data.
            if (SDRAM_CKE) begin
                case (command)
                    CMD_ACTIVE: begin
                        bank_index = {
                            SDRAM_nCS,
                            SDRAM_BA
                        };

                        open_row[bank_index]   <= SDRAM_A;
                        open_valid[bank_index] <= 1'b1;
                    end

                    CMD_WRITE: begin
                        bank_index = {
                            SDRAM_nCS,
                            SDRAM_BA
                        };

                        if (!open_valid[bank_index]) begin
                            protocol_error <= 1'b1;
                        end else begin
                            // Reconstruct Jupiter's H[25:0]:
                            //
                            // H[25]    = chip selection
                            // H[24:17] = column[9:2]
                            // H[16:4]  = active row
                            // H[3:2]   = bank
                            // H[1:0]   = column[1:0]
                            access_addr = {
                                SDRAM_nCS,
                                SDRAM_A[9:2],
                                open_row[bank_index],
                                SDRAM_BA,
                                SDRAM_A[1:0]
                            };

                            slot_index = -1;
                            free_index = -1;

                            for (i = 0; i < SLOTS; i = i + 1) begin
                                if (mem_valid[i] &&
                                    mem_tag[i] == access_addr)
                                    slot_index = i;

                                if (!mem_valid[i] &&
                                    free_index < 0)
                                    free_index = i;
                            end

                            if (slot_index < 0)
                                slot_index = free_index;

                            if (slot_index < 0) begin
                                protocol_error <= 1'b1;
                            end else begin
                                if (mem_valid[slot_index])
                                    merged_data =
                                        mem_data[slot_index];
                                else
                                    merged_data = 16'd0;

                                if (!SDRAM_DQML)
                                    merged_data[7:0] =
                                        SDRAM_DQ[7:0];

                                if (!SDRAM_DQMH)
                                    merged_data[15:8] =
                                        SDRAM_DQ[15:8];

                                mem_tag[slot_index] <=
                                    access_addr;

                                mem_data[slot_index] <=
                                    merged_data;

                                mem_valid[slot_index] <=
                                    1'b1;
                            end

                            // Jupiter currently requests auto-precharge
                            // on each individual READ/WRITE command.
                            if (SDRAM_A[10])
                                open_valid[bank_index] <= 1'b0;
                        end
                    end

                    CMD_READ: begin
                        bank_index = {
                            SDRAM_nCS,
                            SDRAM_BA
                        };

                        if (!open_valid[bank_index]) begin
                            protocol_error <= 1'b1;
                        end else if (read_pending) begin
                            protocol_error <= 1'b1;
                        end else begin
                            access_addr = {
                                SDRAM_nCS,
                                SDRAM_A[9:2],
                                open_row[bank_index],
                                SDRAM_BA,
                                SDRAM_A[1:0]
                            };

                            slot_index = -1;

                            for (i = 0; i < SLOTS; i = i + 1) begin
                                if (mem_valid[i] &&
                                    mem_tag[i] == access_addr)
                                    slot_index = i;
                            end

                            if (slot_index >= 0)
                                read_data <=
                                    mem_data[slot_index];
                            else
                                read_data <= 16'd0;

                            read_pending   <= 1'b1;
                            read_countdown <= CAS_CYCLES;

                            if (SDRAM_A[10])
                                open_valid[bank_index] <= 1'b0;
                        end
                    end

                    CMD_PRECHARGE: begin
                        if (SDRAM_A[10]) begin
                            // PRECHARGE ALL applies to all banks of the
                            // currently selected MiSTer SDRAM device.
                            open_valid[
                                {SDRAM_nCS, 2'b00}
                            ] <= 1'b0;

                            open_valid[
                                {SDRAM_nCS, 2'b01}
                            ] <= 1'b0;

                            open_valid[
                                {SDRAM_nCS, 2'b10}
                            ] <= 1'b0;

                            open_valid[
                                {SDRAM_nCS, 2'b11}
                            ] <= 1'b0;
                        end else begin
                            open_valid[
                                {SDRAM_nCS, SDRAM_BA}
                            ] <= 1'b0;
                        end
                    end

                    CMD_AUTO_REFRESH,
                    CMD_LOAD_MODE,
                    CMD_NOP: begin
                        // No storage action is required for these
                        // commands in the functional simulation model.
                    end

                    default: begin
                        protocol_error <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
