module jupiter_audio
(
    input  wire        clk,
    input  wire        reset,

    // CPU-visible audio MMIO target.
    input  wire        valid,
    input  wire        write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire  [3:0] wstrb,

    output reg  [31:0] rdata,
    output wire        ready
);

    localparam [31:0] REG_SAMPLE_ADDR  = 32'h00001300;
    localparam [31:0] REG_SAMPLE_DATA  = 32'h00001304;
    localparam [31:0] REG_OUTPUT_L     = 32'h00001308;
    localparam [31:0] REG_OUTPUT_R     = 32'h0000130C;
    localparam [31:0] REG_SAMPLE_COUNT = 32'h00001310;

    localparam [31:0] VOICE_BASE_ADDR = 32'h00001320;
    localparam [31:0] VOICE_LAST_ADDR = 32'h0000139F;

    localparam [4:0] VOICE_CONTROL  = 5'h00;
    localparam [4:0] VOICE_STATUS   = 5'h04;
    localparam [4:0] VOICE_BASE     = 5'h08;
    localparam [4:0] VOICE_LENGTH   = 5'h0C;
    localparam [4:0] VOICE_VOLUME_L = 5'h10;
    localparam [4:0] VOICE_VOLUME_R = 5'h14;
    localparam [4:0] VOICE_POSITION = 5'h18;

    // 4096 signed 16-bit PCM samples.
    //
    // Sample RAM is intentionally not reset. Reset requirements apply
    // to control/state, not clearing all 8 KiB of PCM storage.
    reg [11:0] sample_addr_reg;
    reg signed [15:0] sample_ram [0:4095];

    // Live CPU-visible voice configuration.
    reg [11:0] voice_base_reg [0:3];
    reg [12:0] voice_length_reg [0:3];
    reg  [7:0] voice_volume_l_reg [0:3];
    reg  [7:0] voice_volume_r_reg [0:3];

    // Playback snapshots/state.
    reg [11:0] active_base [0:3];
    reg [12:0] active_length [0:3];
    reg [12:0] voice_position [0:3];

    reg voice_active [0:3];
    reg voice_done [0:3];

    // No sample-tick/mixer producer exists yet in M7B-1.
    reg signed [15:0] output_l_reg;
    reg signed [15:0] output_r_reg;

    reg [31:0] sample_count_reg;

    wire voice_selected =
        (addr >= VOICE_BASE_ADDR) &&
        (addr <= VOICE_LAST_ADDR);

    wire [1:0] voice_index =
        (addr - VOICE_BASE_ADDR) >> 5;

    wire [4:0] voice_offset =
        addr[4:0];

    wire [12:0] selected_remaining =
        13'd4096 -
        {1'b0, voice_base_reg[voice_index]};

    wire [12:0] selected_effective_length =
        (
            voice_length_reg[voice_index] >
            selected_remaining
        )
        ? selected_remaining
        : voice_length_reg[voice_index];

    integer i;

    // No playback sequencer owns the sample RAM port yet.
    assign ready = valid;


    // ------------------------------------------------------------
    // Deterministic reads
    // ------------------------------------------------------------

    always @(*) begin

        rdata = 32'h00000000;

        if (valid && !write) begin

            case (addr)

                REG_SAMPLE_ADDR:
                    rdata = {
                        20'd0,
                        sample_addr_reg
                    };


                REG_SAMPLE_DATA:
                    rdata = {
                        16'd0,
                        sample_ram[sample_addr_reg]
                    };


                REG_OUTPUT_L:
                    rdata = {
                        {16{output_l_reg[15]}},
                        output_l_reg
                    };


                REG_OUTPUT_R:
                    rdata = {
                        {16{output_r_reg[15]}},
                        output_r_reg
                    };


                REG_SAMPLE_COUNT:
                    rdata =
                        sample_count_reg;


                default: begin

                    if (voice_selected) begin

                        case (voice_offset)

                            VOICE_STATUS:
                                rdata = {
                                    30'd0,
                                    voice_done[
                                        voice_index
                                    ],
                                    voice_active[
                                        voice_index
                                    ]
                                };


                            VOICE_BASE:
                                rdata = {
                                    20'd0,
                                    voice_base_reg[
                                        voice_index
                                    ]
                                };


                            VOICE_LENGTH:
                                rdata = {
                                    19'd0,
                                    voice_length_reg[
                                        voice_index
                                    ]
                                };


                            VOICE_VOLUME_L:
                                rdata = {
                                    24'd0,
                                    voice_volume_l_reg[
                                        voice_index
                                    ]
                                };


                            VOICE_VOLUME_R:
                                rdata = {
                                    24'd0,
                                    voice_volume_r_reg[
                                        voice_index
                                    ]
                                };


                            VOICE_POSITION:
                                rdata = {
                                    19'd0,
                                    voice_position[
                                        voice_index
                                    ]
                                };


                            default:
                                rdata =
                                    32'h00000000;

                        endcase
                    end
                end

            endcase
        end
    end


    // ------------------------------------------------------------
    // State / writes
    // ------------------------------------------------------------

    always @(posedge clk) begin

        if (reset) begin

            sample_addr_reg <=
                12'h000;

            output_l_reg <=
                16'sh0000;

            output_r_reg <=
                16'sh0000;

            sample_count_reg <=
                32'h00000000;


            for (
                i = 0;
                i < 4;
                i = i + 1
            ) begin

                voice_base_reg[i] <=
                    12'h000;

                voice_length_reg[i] <=
                    13'h0000;

                voice_volume_l_reg[i] <=
                    8'h00;

                voice_volume_r_reg[i] <=
                    8'h00;


                active_base[i] <=
                    12'h000;

                active_length[i] <=
                    13'h0000;

                voice_position[i] <=
                    13'h0000;


                voice_active[i] <=
                    1'b0;

                voice_done[i] <=
                    1'b0;

            end

        end else if (valid && write) begin

            case (addr)

                REG_SAMPLE_ADDR: begin

                    if (wstrb[0])
                        sample_addr_reg[7:0] <=
                            wdata[7:0];

                    if (wstrb[1])
                        sample_addr_reg[11:8] <=
                            wdata[11:8];

                end


                REG_SAMPLE_DATA: begin

                    if (wstrb[0])
                        sample_ram[
                            sample_addr_reg
                        ][7:0] <=
                            wdata[7:0];

                    if (wstrb[1])
                        sample_ram[
                            sample_addr_reg
                        ][15:8] <=
                            wdata[15:8];

                end


                default: begin

                    if (voice_selected) begin

                        case (voice_offset)

                            VOICE_CONTROL: begin

                                if (wstrb[0]) begin

                                    // CLEAR_DONE first.
                                    if (wdata[2])
                                        voice_done[
                                            voice_index
                                        ] <= 1'b0;


                                    // STOP has priority over START.
                                    if (wdata[1]) begin

                                        voice_active[
                                            voice_index
                                        ] <= 1'b0;

                                    end else if (wdata[0]) begin

                                        active_base[
                                            voice_index
                                        ] <=
                                            voice_base_reg[
                                                voice_index
                                            ];

                                        active_length[
                                            voice_index
                                        ] <=
                                            selected_effective_length;

                                        voice_position[
                                            voice_index
                                        ] <=
                                            13'h0000;


                                        if (
                                            voice_length_reg[
                                                voice_index
                                            ] == 13'h0000
                                        ) begin

                                            voice_active[
                                                voice_index
                                            ] <=
                                                1'b0;

                                            voice_done[
                                                voice_index
                                            ] <=
                                                1'b1;

                                        end else begin

                                            voice_active[
                                                voice_index
                                            ] <=
                                                1'b1;

                                            voice_done[
                                                voice_index
                                            ] <=
                                                1'b0;

                                        end
                                    end
                                end
                            end


                            VOICE_BASE: begin

                                if (wstrb[0])
                                    voice_base_reg[
                                        voice_index
                                    ][7:0] <=
                                        wdata[7:0];

                                if (wstrb[1])
                                    voice_base_reg[
                                        voice_index
                                    ][11:8] <=
                                        wdata[11:8];

                            end


                            VOICE_LENGTH: begin

                                if (wstrb[0])
                                    voice_length_reg[
                                        voice_index
                                    ][7:0] <=
                                        wdata[7:0];

                                if (wstrb[1])
                                    voice_length_reg[
                                        voice_index
                                    ][12:8] <=
                                        wdata[12:8];

                            end


                            VOICE_VOLUME_L: begin

                                if (wstrb[0])
                                    voice_volume_l_reg[
                                        voice_index
                                    ] <=
                                        wdata[7:0];

                            end


                            VOICE_VOLUME_R: begin

                                if (wstrb[0])
                                    voice_volume_r_reg[
                                        voice_index
                                    ] <=
                                        wdata[7:0];

                            end


                            default: begin
                                // STATUS, POSITION, and reserved
                                // offsets ignore writes.
                            end

                        endcase
                    end
                end

            endcase
        end
    end

endmodule
