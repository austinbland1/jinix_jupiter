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


    // ------------------------------------------------------------
    // Internal PCM sample RAM
    // ------------------------------------------------------------

    // 4096 signed 16-bit PCM samples.
    //
    // Sample RAM is intentionally not reset.
    reg [11:0] sample_addr_reg;
    reg signed [15:0] sample_ram [0:4095];


    // ------------------------------------------------------------
    // CPU-visible per-voice configuration
    // ------------------------------------------------------------

    reg [11:0] voice_base_reg [0:3];
    reg [12:0] voice_length_reg [0:3];

    reg [7:0] voice_volume_l_reg [0:3];
    reg [7:0] voice_volume_r_reg [0:3];


    // ------------------------------------------------------------
    // Active playback snapshots/state
    // ------------------------------------------------------------

    reg [11:0] active_base [0:3];
    reg [12:0] active_length [0:3];
    reg [12:0] voice_position [0:3];

    reg voice_active [0:3];
    reg voice_done [0:3];


    // ------------------------------------------------------------
    // Mixed output state
    // ------------------------------------------------------------

    reg signed [15:0] output_l_reg;
    reg signed [15:0] output_r_reg;

    reg [31:0] sample_count_reg;


    // ------------------------------------------------------------
    // Exact-average 48 kHz sample tick
    // ------------------------------------------------------------

    localparam [24:0] SAMPLE_PHASE_INCREMENT =
        25'd48000;

    localparam [24:0] SAMPLE_PHASE_MODULUS =
        25'd20000000;

    reg [24:0] sample_phase_reg;
    reg        sample_tick;

    wire [24:0] sample_phase_sum =
        sample_phase_reg +
        SAMPLE_PHASE_INCREMENT;

    wire sample_tick_fire =
        sample_phase_sum >=
        SAMPLE_PHASE_MODULUS;


    // ------------------------------------------------------------
    // MMIO decode helpers
    // ------------------------------------------------------------

    wire voice_selected =
        (addr >= VOICE_BASE_ADDR) &&
        (addr <= VOICE_LAST_ADDR);

    wire [1:0] voice_index =
        (addr - VOICE_BASE_ADDR) >> 5;

    wire [4:0] voice_offset =
        addr[4:0];

    wire control_command_write =
        valid &&
        write &&
        voice_selected &&
        (voice_offset == VOICE_CONTROL) &&
        wstrb[0];

    // START or STOP changes playback sequencing state.
    // CLEAR_DONE by itself does not pause playback.
    wire playback_command_write =
        control_command_write &&
        (wdata[1:0] != 2'b00);

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


    // ------------------------------------------------------------
    // Serialized four-voice mixer state
    //
    // One output update begins on each 48 kHz sample tick.
    // Voice state/address/volume is captured at that boundary.
    //
    // The shared sample-RAM read port is then used once for each
    // voice over four clk cycles. Inactive voices contribute zero.
    //
    // OUTPUT_L / OUTPUT_R / SAMPLE_COUNT / POSITION are committed
    // together after voice three has been processed.
    // ------------------------------------------------------------

    reg        mix_busy;
    reg        mix_commit;
    reg  [1:0] mix_voice_index;

    reg signed [26:0] mix_left_accum;
    reg signed [26:0] mix_right_accum;

    reg        mix_voice_enabled [0:3];
    reg [11:0] mix_sample_addr [0:3];

    reg [7:0] mix_volume_l [0:3];
    reg [7:0] mix_volume_r [0:3];

    // A START/STOP arriving after the sample-tick snapshot prevents
    // the mixer commit from overwriting that newer command state.
    reg mix_control_seen [0:3];


    // ------------------------------------------------------------
    // Single shared sample-RAM read path
    // ------------------------------------------------------------

    wire [11:0] sample_ram_read_addr =
        mix_busy
        ? mix_sample_addr[mix_voice_index]
        : sample_addr_reg;

    wire signed [15:0] sample_ram_read_data =
        sample_ram[sample_ram_read_addr];


    // ------------------------------------------------------------
    // Current serialized voice arithmetic
    //
    // The unsigned 8-bit volume is extended with a leading zero and
    // interpreted as a positive signed 9-bit value. This keeps the
    // signed source-sample multiplication unambiguous.
    // ------------------------------------------------------------

    wire signed [15:0] mix_current_sample =
        sample_ram_read_data;

    wire signed [8:0] mix_current_volume_l =
        {
            1'b0,
            mix_volume_l[mix_voice_index]
        };

    wire signed [8:0] mix_current_volume_r =
        {
            1'b0,
            mix_volume_r[mix_voice_index]
        };

    wire signed [24:0] mix_current_product_l =
        mix_current_sample *
        mix_current_volume_l;

    wire signed [24:0] mix_current_product_r =
        mix_current_sample *
        mix_current_volume_r;

    wire signed [26:0] mix_current_contribution_l =
        mix_voice_enabled[mix_voice_index]
        ? {
            {2{mix_current_product_l[24]}},
            mix_current_product_l
        }
        : 27'sd0;

    wire signed [26:0] mix_current_contribution_r =
        mix_voice_enabled[mix_voice_index]
        ? {
            {2{mix_current_product_r[24]}},
            mix_current_product_r
        }
        : 27'sd0;

    wire signed [26:0] mix_left_sum_next =
        mix_left_accum +
        mix_current_contribution_l;

    wire signed [26:0] mix_right_sum_next =
        mix_right_accum +
        mix_current_contribution_r;

    // The architecture shifts AFTER summing all voice products.
    wire signed [26:0] mix_left_scaled_next =
        mix_left_sum_next >>> 8;

    wire signed [26:0] mix_right_scaled_next =
        mix_right_sum_next >>> 8;


    // ------------------------------------------------------------
    // Signed-16 saturation
    // ------------------------------------------------------------

    function automatic [15:0] saturate_s16;
        input signed [26:0] value;

        begin

            if (value > 27'sd32767)
                saturate_s16 =
                    16'h7FFF;

            else if (value < -27'sd32768)
                saturate_s16 =
                    16'h8000;

            else
                saturate_s16 =
                    value[15:0];

        end
    endfunction


    // ------------------------------------------------------------
    // Shared-RAM ownership / MMIO completion
    //
    // Only SAMPLE_DATA requires the RAM data port. All other audio
    // registers remain accessible while the four-cycle mixer runs.
    // ------------------------------------------------------------

    wire sample_data_access =
        valid &&
        (addr == REG_SAMPLE_DATA);

    assign ready =
        valid &&
        !(
            sample_data_access &&
            mix_busy
        );


    integer i;


    // ------------------------------------------------------------
    // Deterministic reads
    // ------------------------------------------------------------

    always @(*) begin

        rdata =
            32'h00000000;

        if (valid && !write) begin

            case (addr)

                REG_SAMPLE_ADDR:
                    rdata = {
                        20'd0,
                        sample_addr_reg
                    };


                REG_SAMPLE_DATA: begin

                    // rdata is meaningful only when ready is asserted.
                    // Suppress the CPU-side RAM value while playback owns
                    // the shared read path.
                    if (!mix_busy)
                        rdata = {
                            16'd0,
                            sample_ram_read_data
                        };
                    else
                        rdata =
                            32'h00000000;

                end


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
    // State / writes / mixer
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

            sample_phase_reg <=
                25'd0;

            sample_tick <=
                1'b0;


            mix_busy <=
                1'b0;

            mix_commit <=
                1'b0;

            mix_voice_index <=
                2'd0;

            mix_left_accum <=
                27'sd0;

            mix_right_accum <=
                27'sd0;


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


                mix_voice_enabled[i] <=
                    1'b0;

                mix_sample_addr[i] <=
                    12'h000;

                mix_volume_l[i] <=
                    8'h00;

                mix_volume_r[i] <=
                    8'h00;

                mix_control_seen[i] <=
                    1'b0;

            end

        end else begin

            // One-cycle observation pulses.
            sample_tick <=
                1'b0;

            mix_commit <=
                1'b0;


            // ----------------------------------------------------
            // 20 MHz -> exact-average 48 kHz phase accumulator.
            // ----------------------------------------------------

            if (sample_tick_fire) begin

                sample_phase_reg <=
                    sample_phase_sum -
                    SAMPLE_PHASE_MODULUS;

                sample_tick <=
                    1'b1;


                // Four mixer cycles are vastly shorter than the
                // 416/417-cycle output period, so a new tick cannot
                // normally arrive while the prior update is active.
                if (!mix_busy) begin

                    mix_busy <=
                        1'b1;

                    mix_voice_index <=
                        2'd0;

                    mix_left_accum <=
                        27'sd0;

                    mix_right_accum <=
                        27'sd0;


                    // Snapshot the state belonging to this output tick.
                    //
                    // A simultaneous START/STOP command wins and the old
                    // playback state does not contribute to this tick.
                    for (
                        i = 0;
                        i < 4;
                        i = i + 1
                    ) begin

                        mix_voice_enabled[i] <=
                            voice_active[i] &&
                            !(
                                playback_command_write &&
                                (voice_index == i)
                            );

                        mix_sample_addr[i] <=
                            active_base[i] +
                            voice_position[i][11:0];

                        mix_volume_l[i] <=
                            voice_volume_l_reg[i];

                        mix_volume_r[i] <=
                            voice_volume_r_reg[i];

                        mix_control_seen[i] <=
                            playback_command_write &&
                            (voice_index == i);

                    end
                end

            end else begin

                sample_phase_reg <=
                    sample_phase_sum;

            end


            // ----------------------------------------------------
            // Serialized PCM fetch / stereo accumulation.
            // ----------------------------------------------------

            if (mix_busy) begin

                if (
                    mix_voice_index ==
                    2'd3
                ) begin

                    // Voice three's current contribution has not yet
                    // been stored in the accumulator, so use the
                    // combinational "next" sum for final scaling.
                    output_l_reg <=
                        saturate_s16(
                            mix_left_scaled_next
                        );

                    output_r_reg <=
                        saturate_s16(
                            mix_right_scaled_next
                        );

                    sample_count_reg <=
                        sample_count_reg +
                        32'd1;

                    mix_busy <=
                        1'b0;

                    mix_commit <=
                        1'b1;


                    // The sample at the pre-increment POSITION has now
                    // contributed to the committed output.
                    for (
                        i = 0;
                        i < 4;
                        i = i + 1
                    ) begin

                        if (
                            mix_voice_enabled[i] &&
                            !mix_control_seen[i] &&
                            !(
                                playback_command_write &&
                                (voice_index == i)
                            )
                        ) begin

                            if (
                                (
                                    voice_position[i] +
                                    13'd1
                                ) >=
                                active_length[i]
                            ) begin

                                voice_position[i] <=
                                    active_length[i];

                                voice_active[i] <=
                                    1'b0;

                                voice_done[i] <=
                                    1'b1;

                            end else begin

                                voice_position[i] <=
                                    voice_position[i] +
                                    13'd1;

                            end
                        end
                    end

                end else begin

                    mix_left_accum <=
                        mix_left_sum_next;

                    mix_right_accum <=
                        mix_right_sum_next;

                    mix_voice_index <=
                        mix_voice_index +
                        2'd1;

                end
            end


            // ----------------------------------------------------
            // CPU MMIO writes.
            //
            // A stalled SAMPLE_DATA transaction does not mutate RAM.
            // Other registers remain immediately available.
            // ----------------------------------------------------

            if (
                valid &&
                write &&
                ready
            ) begin

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

                                        // If START or STOP arrives after a
                                        // tick snapshot, preserve that newer
                                        // command state at mixer commit.
                                        if (
                                            mix_busy &&
                                            (
                                                wdata[1] ||
                                                wdata[0]
                                            )
                                        )
                                            mix_control_seen[
                                                voice_index
                                            ] <=
                                                1'b1;


                                        // CLEAR_DONE first.
                                        if (wdata[2])
                                            voice_done[
                                                voice_index
                                            ] <=
                                                1'b0;


                                        // STOP has priority over START.
                                        if (wdata[1]) begin

                                            voice_active[
                                                voice_index
                                            ] <=
                                                1'b0;

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
                                                ] ==
                                                13'h0000
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
    end

endmodule
