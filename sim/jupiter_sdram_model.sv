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

    localparam [12:0] EXPECTED_MODE =
        13'h233;

    wire [2:0] command = {
        SDRAM_nRAS,
        SDRAM_nCAS,
        SDRAM_nWE
    };

    /*
     * Preserve the legacy model's exact hierarchical storage
     * interface. Existing regressions directly preload and inspect
     * these arrays.
     */
    reg [25:0] mem_tag   [0:SLOTS-1];
    reg [15:0] mem_data  [0:SLOTS-1];
    reg        mem_valid [0:SLOTS-1];

    /*
     * One open row for each {selection,bank}.
     */
    reg [12:0] open_row   [0:7];
    reg        open_valid [0:7];

    integer i;
    integer bank_index;
    integer slot_index;
    integer free_index;

    reg [25:0] access_addr;
    reg [15:0] merged_data;

    /*
     * BL8 read-return state.
     */
    reg        read_pending;
    integer    read_start_cycle;
    integer    read_beat;
    integer    cycle_count;

    reg [25:0] read_base_addr;

    reg [15:0] dq_drive;
    reg        dq_drive_en;

    reg [15:0] lookup_data;

    assign SDRAM_DQ =
        dq_drive_en ?
            dq_drive :
            16'hzzzz;

    /*
     * Sparse-memory lookup.
     *
     * Unwritten storage remains zero, matching the old behavioral
     * model.
     */
    task automatic lookup_halfword;
        input  [25:0] address;
        output [15:0] value;

        integer k;

        begin

            value =
                16'd0;

            for (k = 0; k < SLOTS; k = k + 1)
                if (
                    mem_valid[k] &&
                    mem_tag[k] == address
                )
                    value =
                        mem_data[k];
        end
    endtask

    /*
     * Drive one beat on the falling edge so it is stable before
     * the controller captures it at the following rising edge.
     */
    always @(negedge clk) begin

        dq_drive_en =
            1'b0;

        dq_drive =
            16'd0;

        if (
            !reset &&
            read_pending &&
            cycle_count >=
                read_start_cycle + CAS_CYCLES - 1 &&
            read_beat < 8
        ) begin

            lookup_halfword(
                read_base_addr +
                    read_beat,
                lookup_data
            );

            dq_drive =
                lookup_data;

            dq_drive_en =
                1'b1;
        end
    end

    always @(posedge clk) begin

        if (reset) begin

            protocol_error =
                1'b0;

            read_pending =
                1'b0;

            read_start_cycle =
                0;

            read_beat =
                0;

            read_base_addr =
                26'd0;

            cycle_count =
                0;

            dq_drive_en =
                1'b0;

            dq_drive =
                16'd0;

            for (i = 0; i < 8; i = i + 1) begin

                open_row[i] =
                    13'd0;

                open_valid[i] =
                    1'b0;
            end

            for (i = 0; i < SLOTS; i = i + 1) begin

                mem_tag[i] =
                    26'd0;

                mem_data[i] =
                    16'd0;

                mem_valid[i] =
                    1'b0;
            end

        end else begin

            cycle_count =
                cycle_count + 1;

            /*
             * Advance the physical BL8 data burst.
             *
             * The controller aligns every miss to an eight-halfword
             * group, so simple sequential +0..+7 addressing exactly
             * matches the command stream.
             */
            if (
                read_pending &&
                cycle_count >=
                    read_start_cycle + CAS_CYCLES &&
                read_beat < 7
            ) begin

                read_beat =
                    read_beat + 1;
            end

            if (SDRAM_CKE) begin

                bank_index = {
                    SDRAM_nCS,
                    SDRAM_BA
                };

                case (command)

                    CMD_ACTIVE: begin

                        if (
                            open_valid[bank_index]
                        )
                            protocol_error =
                                1'b1;

                        open_row[bank_index] =
                            SDRAM_A;

                        open_valid[bank_index] =
                            1'b1;
                    end

                    CMD_WRITE: begin

                        if (
                            !open_valid[bank_index]
                        ) begin

                            protocol_error =
                                1'b1;

                        end else begin

                            /*
                             * Winning-controller H[25:0] mapping.
                             */
                            access_addr = {
                                SDRAM_nCS,
                                open_row[bank_index],
                                SDRAM_BA,
                                SDRAM_A[9:0]
                            };

                            slot_index =
                                -1;

                            free_index =
                                -1;

                            for (
                                i = 0;
                                i < SLOTS;
                                i = i + 1
                            ) begin

                                if (
                                    mem_valid[i] &&
                                    mem_tag[i] ==
                                        access_addr
                                )
                                    slot_index =
                                        i;

                                if (
                                    !mem_valid[i] &&
                                    free_index < 0
                                )
                                    free_index =
                                        i;
                            end

                            if (slot_index < 0)
                                slot_index =
                                    free_index;

                            if (slot_index < 0) begin

                                protocol_error =
                                    1'b1;

                            end else begin

                                if (
                                    mem_valid[
                                        slot_index
                                    ]
                                )
                                    merged_data =
                                        mem_data[
                                            slot_index
                                        ];
                                else
                                    merged_data =
                                        16'd0;

                                if (!SDRAM_DQML)
                                    merged_data[7:0] =
                                        SDRAM_DQ[7:0];

                                if (!SDRAM_DQMH)
                                    merged_data[15:8] =
                                        SDRAM_DQ[15:8];

                                mem_tag[slot_index] =
                                    access_addr;

                                mem_data[slot_index] =
                                    merged_data;

                                mem_valid[slot_index] =
                                    1'b1;
                            end

                            /*
                             * Candidate writes are single-location
                             * writes with A10 auto-precharge.
                             */
                            if (SDRAM_A[10])
                                open_valid[
                                    bank_index
                                ] =
                                    1'b0;
                        end
                    end

                    CMD_READ: begin

                        if (
                            !open_valid[bank_index]
                        ) begin

                            protocol_error =
                                1'b1;

                        end else if (
                            read_pending
                        ) begin

                            protocol_error =
                                1'b1;

                        end else begin

                            read_base_addr = {
                                SDRAM_nCS,
                                open_row[bank_index],
                                SDRAM_BA,
                                SDRAM_A[9:0]
                            };

                            /*
                             * The controller must issue aligned BL8
                             * reads. Catch any regression immediately.
                             */
                            if (
                                read_base_addr[2:0] !=
                                3'b000
                            )
                                protocol_error =
                                    1'b1;

                            if (!SDRAM_A[10])
                                protocol_error =
                                    1'b1;

                            read_pending =
                                1'b1;

                            read_start_cycle =
                                cycle_count;

                            read_beat =
                                0;

                            /*
                             * READ auto-precharge closes after the BL8
                             * burst. No overlapping access is legal
                             * while read_pending remains asserted.
                             */
                        end
                    end

                    CMD_PRECHARGE: begin

                        if (SDRAM_A[10]) begin

                            open_valid[
                                {SDRAM_nCS,2'b00}
                            ] = 1'b0;

                            open_valid[
                                {SDRAM_nCS,2'b01}
                            ] = 1'b0;

                            open_valid[
                                {SDRAM_nCS,2'b10}
                            ] = 1'b0;

                            open_valid[
                                {SDRAM_nCS,2'b11}
                            ] = 1'b0;

                        end else begin

                            open_valid[
                                bank_index
                            ] =
                                1'b0;
                        end
                    end

                    CMD_AUTO_REFRESH: begin

                        /*
                         * No bank of the selected SDRAM level may
                         * remain active at refresh.
                         */
                        if (
                            open_valid[
                                {SDRAM_nCS,2'b00}
                            ] ||
                            open_valid[
                                {SDRAM_nCS,2'b01}
                            ] ||
                            open_valid[
                                {SDRAM_nCS,2'b10}
                            ] ||
                            open_valid[
                                {SDRAM_nCS,2'b11}
                            ]
                        )
                            protocol_error =
                                1'b1;
                    end

                    CMD_LOAD_MODE: begin

                        if (
                            SDRAM_A !=
                            EXPECTED_MODE
                        )
                            protocol_error =
                                1'b1;

                        if (
                            SDRAM_BA !=
                            2'b00
                        )
                            protocol_error =
                                1'b1;
                    end

                    CMD_NOP: begin
                    end

                    default: begin

                        protocol_error =
                            1'b1;
                    end
                endcase
            end

            /*
             * Complete READ auto-precharge only once all eight
             * beats have actually been presented.
             */
            if (
                read_pending &&
                read_beat == 7 &&
                cycle_count >=
                    read_start_cycle +
                    CAS_CYCLES + 7
            ) begin

                open_valid[
                    {
                        read_base_addr[25],
                        read_base_addr[11:10]
                    }
                ] =
                    1'b0;

                /*
                 * The BL8 transfer and its modeled auto-precharge
                 * complete together.  Do not clear read_pending
                 * before this block or the bank never closes.
                 */
                read_pending =
                    1'b0;
            end
        end
    end

endmodule
