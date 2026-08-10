`timescale 1ns/1ps

module jupiter_audio_mixer_tb;

    localparam [31:0] REG_SAMPLE_ADDR  = 32'h00001300;
    localparam [31:0] REG_SAMPLE_DATA  = 32'h00001304;
    localparam [31:0] REG_OUTPUT_L     = 32'h00001308;
    localparam [31:0] REG_OUTPUT_R     = 32'h0000130C;
    localparam [31:0] REG_SAMPLE_COUNT = 32'h00001310;

    localparam [31:0] V0_CONTROL  = 32'h00001320;
    localparam [31:0] V0_STATUS   = 32'h00001324;
    localparam [31:0] V0_BASE     = 32'h00001328;
    localparam [31:0] V0_LENGTH   = 32'h0000132C;
    localparam [31:0] V0_VOLUME_L = 32'h00001330;
    localparam [31:0] V0_VOLUME_R = 32'h00001334;
    localparam [31:0] V0_POSITION = 32'h00001338;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        valid = 1'b0;
    reg        write = 1'b0;
    reg [31:0] addr  = 32'h00000000;
    reg [31:0] wdata = 32'h00000000;
    reg  [3:0] wstrb = 4'b0000;

    wire [31:0] rdata;
    wire        ready;

    integer checks = 0;
    integer failures = 0;

    reg [31:0] read_value;

    reg signed [15:0] held_left;
    reg signed [15:0] held_right;

    integer guard;


    jupiter_audio dut
    (
        .clk   (clk),
        .reset (reset),

        .valid (valid),
        .write (write),
        .addr  (addr),
        .wdata (wdata),
        .wstrb (wstrb),

        .rdata (rdata),
        .ready (ready)
    );


    always #5 clk = ~clk;


    task automatic check;
        input condition;
        input [8*180-1:0] message;

        begin

            checks = checks + 1;

            if (condition)
                $display(
                    "PASS: %0s",
                    message
                );

            else begin

                failures = failures + 1;

                $display(
                    "FAIL: %0s",
                    message
                );

            end
        end
    endtask


    task automatic reset_dut;

        begin

            @(negedge clk);

            reset = 1'b1;

            valid = 1'b0;
            write = 1'b0;
            addr = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;


            repeat (3)
                @(posedge clk);

            #1;

            @(negedge clk);

            reset = 1'b0;

        end
    endtask


    task automatic mmio_write;
        input [31:0] write_addr;
        input [31:0] write_data;
        input  [3:0] write_strobes;

        begin

            @(negedge clk);

            valid = 1'b1;
            write = 1'b1;
            addr = write_addr;
            wdata = write_data;
            wstrb = write_strobes;

            #1;

            check(
                ready == 1'b1,
                "mixer setup MMIO write completes immediately"
            );


            @(posedge clk);
            #1;

            @(negedge clk);

            valid = 1'b0;
            write = 1'b0;
            addr = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

        end
    endtask


    task automatic mmio_read;
        input  [31:0] read_addr;
        output [31:0] read_data;

        begin

            @(negedge clk);

            valid = 1'b1;
            write = 1'b0;
            addr = read_addr;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;

            check(
                ready == 1'b1,
                "mixer MMIO read completes immediately outside RAM ownership"
            );

            read_data =
                rdata;


            @(negedge clk);

            valid = 1'b0;
            addr = 32'h00000000;

        end
    endtask


    task automatic write_sample;
        input [11:0] sample_index;
        input [15:0] sample_value;

        begin

            mmio_write(
                REG_SAMPLE_ADDR,
                {
                    20'd0,
                    sample_index
                },
                4'b0011
            );

            mmio_write(
                REG_SAMPLE_DATA,
                {
                    16'd0,
                    sample_value
                },
                4'b0011
            );

        end
    endtask


    task automatic configure_voice;
        input [1:0] voice_number;
        input [11:0] base_index;
        input [12:0] length;
        input [7:0] volume_l;
        input [7:0] volume_r;

        reg [31:0] voice_block;

        begin

            voice_block =
                32'h00001320 +
                (
                    {
                        30'd0,
                        voice_number
                    } << 5
                );


            mmio_write(
                voice_block + 32'h08,
                {
                    20'd0,
                    base_index
                },
                4'b0011
            );

            mmio_write(
                voice_block + 32'h0C,
                {
                    19'd0,
                    length
                },
                4'b0011
            );

            mmio_write(
                voice_block + 32'h10,
                {
                    24'd0,
                    volume_l
                },
                4'b0001
            );

            mmio_write(
                voice_block + 32'h14,
                {
                    24'd0,
                    volume_r
                },
                4'b0001
            );

        end
    endtask


    task automatic start_voice;
        input [1:0] voice_number;

        reg [31:0] voice_block;

        begin

            voice_block =
                32'h00001320 +
                (
                    {
                        30'd0,
                        voice_number
                    } << 5
                );


            mmio_write(
                voice_block,
                32'h00000001,
                4'b0001
            );

        end
    endtask


    task automatic force_output_update;

        begin : force_update_block

            // Put the fractional accumulator exactly one increment
            // below the modulus so the next clk edge emits a tick.
            @(negedge clk);

            dut.sample_phase_reg =
                25'd19952000;


            @(posedge clk);
            #1;


            check(
                dut.sample_tick,
                "forced phase boundary emits a sample tick"
            );

            check(
                dut.mix_busy,
                "sample tick starts serialized mixer ownership"
            );


            guard = 0;

            while (
                !dut.mix_commit &&
                guard < 16
            ) begin

                @(posedge clk);
                #1;

                guard = guard + 1;

            end


            check(
                dut.mix_commit,
                "serialized mixer commits before timeout"
            );

            check(
                !dut.mix_busy,
                "shared sample-RAM ownership ends at mixer commit"
            );

        end
    endtask


    initial begin

        // --------------------------------------------------------
        // Reset.
        // --------------------------------------------------------

        repeat (3)
            @(posedge clk);

        #1;


        check(
            dut.output_l_reg == 16'sd0 &&
            dut.output_r_reg == 16'sd0,
            "mixer outputs reset to signed zero"
        );

        check(
            dut.sample_count_reg == 32'd0,
            "mixer SAMPLE_COUNT resets to zero"
        );

        check(
            !dut.mix_busy &&
            !dut.mix_commit,
            "serialized mixer resets idle"
        );


        @(negedge clk);

        reset = 1'b0;


        // --------------------------------------------------------
        // One positive signed PCM voice.
        //
        // 1000 * 128 / 256 = 500
        // 1000 *  64 / 256 = 250
        // --------------------------------------------------------

        reset_dut();

        write_sample(
            12'd10,
            16'sd1000
        );

        configure_voice(
            2'd0,
            12'd10,
            13'd1,
            8'd128,
            8'd64
        );

        start_voice(
            2'd0
        );

        force_output_update();


        check(
            $signed(dut.output_l_reg) == 16'sd500,
            "single positive voice produces exact left PCM value"
        );

        check(
            $signed(dut.output_r_reg) == 16'sd250,
            "single positive voice produces exact right PCM value"
        );

        check(
            dut.voice_position[0] == 13'd1 &&
            !dut.voice_active[0] &&
            dut.voice_done[0],
            "single-sample voice contributes before natural completion"
        );

        check(
            dut.sample_count_reg == 32'd1,
            "SAMPLE_COUNT increments exactly once at mixed-output commit"
        );


        mmio_read(
            REG_OUTPUT_L,
            read_value
        );

        check(
            read_value == 32'd500,
            "OUTPUT_L MMIO exposes positive mixed result"
        );


        mmio_read(
            REG_OUTPUT_R,
            read_value
        );

        check(
            read_value == 32'd250,
            "OUTPUT_R MMIO exposes positive mixed result"
        );


        // --------------------------------------------------------
        // Negative PCM + arithmetic right shift.
        //
        // -1000 * 255 = -255000
        // -255000 >>> 8 = -997
        // --------------------------------------------------------

        reset_dut();

        write_sample(
            12'd20,
            -16'sd1000
        );

        configure_voice(
            2'd0,
            12'd20,
            13'd1,
            8'd255,
            8'd255
        );

        start_voice(
            2'd0
        );

        force_output_update();


        check(
            $signed(dut.output_l_reg) == -16'sd997 &&
            $signed(dut.output_r_reg) == -16'sd997,
            "negative product uses documented arithmetic right-shift behavior"
        );


        mmio_read(
            REG_OUTPUT_L,
            read_value
        );

        check(
            read_value == 32'hFFFFFC1B,
            "negative OUTPUT_L is sign-extended through MMIO"
        );


        // --------------------------------------------------------
        // BASE is snapshotted by START; volume remains live.
        // --------------------------------------------------------

        reset_dut();

        write_sample(
            12'd30,
            16'sd2000
        );

        write_sample(
            12'd31,
            16'sd2000
        );

        write_sample(
            12'd100,
            16'sd30000
        );


        configure_voice(
            2'd0,
            12'd30,
            13'd2,
            8'd128,
            8'd128
        );

        start_voice(
            2'd0
        );

        force_output_update();


        check(
            $signed(dut.output_l_reg) == 16'sd1000 &&
            $signed(dut.output_r_reg) == 16'sd1000,
            "first sample uses initial live stereo volume"
        );

        check(
            dut.voice_position[0] == 13'd1 &&
            dut.voice_active[0],
            "two-sample voice remains active after first committed sample"
        );


        // Change configured BASE after START. Active playback must still
        // use the original snapshot at index 31.
        mmio_write(
            V0_BASE,
            32'd100,
            4'b0011
        );

        // Change live volume before the next output tick.
        mmio_write(
            V0_VOLUME_L,
            32'd64,
            4'b0001
        );

        mmio_write(
            V0_VOLUME_R,
            32'd192,
            4'b0001
        );


        check(
            dut.voice_base_reg[0] == 12'd100 &&
            dut.active_base[0] == 12'd30,
            "configured BASE changes without altering active BASE snapshot"
        );


        force_output_update();


        check(
            $signed(dut.output_l_reg) == 16'sd500,
            "live left volume affects next source sample"
        );

        check(
            $signed(dut.output_r_reg) == 16'sd1500,
            "live right volume independently affects next source sample"
        );

        check(
            dut.voice_position[0] == 13'd2 &&
            !dut.voice_active[0] &&
            dut.voice_done[0],
            "second snapshotted source sample completes voice"
        );


        // Output must remain stable between committed updates.
        held_left =
            dut.output_l_reg;

        held_right =
            dut.output_r_reg;


        repeat (20)
            @(posedge clk);

        #1;


        check(
            dut.output_l_reg == held_left &&
            dut.output_r_reg == held_right,
            "mixed outputs remain stable between output updates"
        );


        // --------------------------------------------------------
        // Four-voice reference mix.
        //
        // Left product sum:
        //   1000*255 + -2000*128 + 3000*64 + -4000*32
        // = 63000
        // 63000 >>> 8 = 246
        //
        // Right product sum:
        //   1000*32 + -2000*64 + 3000*128 + -4000*255
        // = -732000
        // -732000 >>> 8 = -2860
        // --------------------------------------------------------

        reset_dut();


        write_sample(
            12'd110,
            16'sd1000
        );

        write_sample(
            12'd111,
            -16'sd2000
        );

        write_sample(
            12'd112,
            16'sd3000
        );

        write_sample(
            12'd113,
            -16'sd4000
        );


        configure_voice(
            2'd0,
            12'd110,
            13'd1,
            8'd255,
            8'd32
        );

        configure_voice(
            2'd1,
            12'd111,
            13'd1,
            8'd128,
            8'd64
        );

        configure_voice(
            2'd2,
            12'd112,
            13'd1,
            8'd64,
            8'd128
        );

        configure_voice(
            2'd3,
            12'd113,
            13'd1,
            8'd32,
            8'd255
        );


        start_voice(
            2'd0
        );

        start_voice(
            2'd1
        );

        start_voice(
            2'd2
        );

        start_voice(
            2'd3
        );


        force_output_update();


        check(
            $signed(dut.output_l_reg) == 16'sd246,
            "all four voices match left-channel reference accumulation"
        );

        check(
            $signed(dut.output_r_reg) == -16'sd2860,
            "all four voices match right-channel reference accumulation"
        );

        check(
            dut.voice_done[0] &&
            dut.voice_done[1] &&
            dut.voice_done[2] &&
            dut.voice_done[3],
            "all four one-sample voices complete after contributing once"
        );


        // --------------------------------------------------------
        // Positive saturation.
        // --------------------------------------------------------

        reset_dut();


        write_sample(
            12'd200,
            16'h7FFF
        );

        write_sample(
            12'd201,
            16'h7FFF
        );

        write_sample(
            12'd202,
            16'h7FFF
        );

        write_sample(
            12'd203,
            16'h7FFF
        );


        configure_voice(
            2'd0,
            12'd200,
            13'd1,
            8'd255,
            8'd255
        );

        configure_voice(
            2'd1,
            12'd201,
            13'd1,
            8'd255,
            8'd255
        );

        configure_voice(
            2'd2,
            12'd202,
            13'd1,
            8'd255,
            8'd255
        );

        configure_voice(
            2'd3,
            12'd203,
            13'd1,
            8'd255,
            8'd255
        );


        start_voice(
            2'd0
        );

        start_voice(
            2'd1
        );

        start_voice(
            2'd2
        );

        start_voice(
            2'd3
        );


        force_output_update();


        check(
            dut.output_l_reg == 16'sh7FFF &&
            dut.output_r_reg == 16'sh7FFF,
            "positive four-voice overflow saturates to +32767"
        );


        // --------------------------------------------------------
        // Negative saturation.
        // --------------------------------------------------------

        reset_dut();


        write_sample(
            12'd200,
            16'h8000
        );

        write_sample(
            12'd201,
            16'h8000
        );

        write_sample(
            12'd202,
            16'h8000
        );

        write_sample(
            12'd203,
            16'h8000
        );


        configure_voice(
            2'd0,
            12'd200,
            13'd1,
            8'd255,
            8'd255
        );

        configure_voice(
            2'd1,
            12'd201,
            13'd1,
            8'd255,
            8'd255
        );

        configure_voice(
            2'd2,
            12'd202,
            13'd1,
            8'd255,
            8'd255
        );

        configure_voice(
            2'd3,
            12'd203,
            13'd1,
            8'd255,
            8'd255
        );


        start_voice(
            2'd0
        );

        start_voice(
            2'd1
        );

        start_voice(
            2'd2
        );

        start_voice(
            2'd3
        );


        force_output_update();


        check(
            dut.output_l_reg == 16'sh8000 &&
            dut.output_r_reg == 16'sh8000,
            "negative four-voice overflow saturates to -32768"
        );


        // --------------------------------------------------------
        // Inactive voices contribute zero.
        // --------------------------------------------------------

        reset_dut();


        write_sample(
            12'd300,
            16'sd4096
        );

        write_sample(
            12'd301,
            16'h7FFF
        );


        configure_voice(
            2'd0,
            12'd300,
            13'd1,
            8'd128,
            8'd128
        );

        configure_voice(
            2'd1,
            12'd301,
            13'd1,
            8'd255,
            8'd255
        );


        start_voice(
            2'd0
        );


        force_output_update();


        check(
            $signed(dut.output_l_reg) == 16'sd2048 &&
            $signed(dut.output_r_reg) == 16'sd2048,
            "configured but inactive voice contributes zero"
        );

        check(
            !dut.voice_active[1] &&
            !dut.voice_done[1],
            "inactive voice state remains untouched by mixer"
        );


        // --------------------------------------------------------
        // Shared SAMPLE_DATA port collision.
        //
        // Playback owns the one RAM read path for four mixer cycles.
        // A CPU SAMPLE_DATA write must stall and must not mutate RAM
        // until ready rises after mixer commit.
        // --------------------------------------------------------

        reset_dut();


        write_sample(
            12'd400,
            16'sd1000
        );

        write_sample(
            12'd500,
            16'd1234
        );

        write_sample(
            12'd600,
            16'h55AA
        );


        configure_voice(
            2'd0,
            12'd400,
            13'd1,
            8'd255,
            8'd255
        );

        start_voice(
            2'd0
        );


        mmio_write(
            REG_SAMPLE_ADDR,
            32'd500,
            4'b0011
        );


        // Start an update, but do not use force_output_update because
        // this test intentionally inserts a CPU transaction mid-mix.
        @(negedge clk);

        dut.sample_phase_reg =
            25'd19952000;


        @(posedge clk);
        #1;


        check(
            dut.sample_tick &&
            dut.mix_busy,
            "collision test begins while playback owns sample RAM"
        );


        @(negedge clk);

        valid = 1'b1;
        write = 1'b1;
        addr = REG_SAMPLE_DATA;
        wdata = 32'd4321;
        wstrb = 4'b0011;

        #1;


        check(
            ready == 1'b0,
            "SAMPLE_DATA write stalls while playback owns shared RAM"
        );

        check(
            ({dut.sample_ram_hi[500], dut.sample_ram_lo[500]}) == 16'd1234,
            "stalled SAMPLE_DATA write does not mutate RAM prematurely"
        );


        guard = 0;

        while (
            !ready &&
            guard < 16
        ) begin

            @(posedge clk);
            #1;

            guard = guard + 1;

        end


        check(
            ready == 1'b1,
            "stalled SAMPLE_DATA request becomes ready after mixer releases RAM"
        );

        check(
            dut.mix_commit,
            "SAMPLE_DATA readiness resumes on mixer-release boundary"
        );

        check(
            ({dut.sample_ram_hi[500], dut.sample_ram_lo[500]}) == 16'd1234,
            "RAM remains unchanged until a ready clock edge accepts the write"
        );


        // Transaction is now ready; accept it on the next rising edge.
        @(posedge clk);
        #1;


        check(
            ({dut.sample_ram_hi[500], dut.sample_ram_lo[500]}) == 16'd4321,
            "previously stalled SAMPLE_DATA write commits after RAM release"
        );


        @(negedge clk);

        valid = 1'b0;
        write = 1'b0;
        addr = 32'h00000000;
        wdata = 32'h00000000;
        wstrb = 4'b0000;


        check(
            ({dut.sample_ram_hi[600], dut.sample_ram_lo[600]}) == 16'h55AA,
            "mixing and collision handling preserve unrelated sample RAM"
        );

        check(
            $signed(dut.output_l_reg) == 16'sd996 &&
            $signed(dut.output_r_reg) == 16'sd996,
            "playback output remains correct during stalled CPU SAMPLE_DATA access"
        );

        check(
            dut.sample_count_reg == 32'd1,
            "collision-handled update increments SAMPLE_COUNT exactly once"
        );


        // --------------------------------------------------------
        // Other audio MMIO remains available during RAM ownership.
        // --------------------------------------------------------

        @(negedge clk);

        dut.sample_phase_reg =
            25'd19952000;


        @(posedge clk);
        #1;


        check(
            dut.mix_busy,
            "second collision update begins sample-RAM ownership"
        );


        @(negedge clk);

        valid = 1'b1;
        write = 1'b0;
        addr = V0_STATUS;
        wdata = 32'h00000000;
        wstrb = 4'b0000;

        #1;


        check(
            ready == 1'b1,
            "voice control/status MMIO remains ready during sample-RAM ownership"
        );

        check(
            rdata == 32'h00000002,
            "voice STATUS remains readable while mixer owns sample RAM"
        );


        @(posedge clk);
        #1;

        @(negedge clk);

        valid = 1'b0;
        addr = 32'h00000000;


        guard = 0;

        while (
            !dut.mix_commit &&
            guard < 16
        ) begin

            @(posedge clk);
            #1;

            guard = guard + 1;

        end


        check(
            dut.mix_commit,
            "second serialized output update commits normally"
        );

        check(
            dut.sample_count_reg == 32'd2,
            "SAMPLE_COUNT advances once for each committed output update"
        );


        // No active voices remain, so this update must produce silence.
        check(
            dut.output_l_reg == 16'sd0 &&
            dut.output_r_reg == 16'sd0,
            "output update with no active voices commits deterministic silence"
        );


        // --------------------------------------------------------
        // CPU-visible final state.
        // --------------------------------------------------------

        mmio_read(
            REG_SAMPLE_COUNT,
            read_value
        );

        check(
            read_value == 32'd2,
            "CPU-visible SAMPLE_COUNT matches committed mixer updates"
        );


        $display("");
        $display("==============================");


        if (failures == 0) begin

            $display(
                "RESULT: PASS  (%0d checks)",
                checks
            );

            $display("==============================");

            $finish;

        end else begin

            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );

            $display("==============================");

            $fatal(1);

        end
    end

endmodule
