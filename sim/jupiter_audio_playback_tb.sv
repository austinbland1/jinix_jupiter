`timescale 1ns/1ps

module jupiter_audio_playback_tb;

    localparam [31:0] REG_OUTPUT_L     = 32'h00001308;
    localparam [31:0] REG_OUTPUT_R     = 32'h0000130C;
    localparam [31:0] REG_SAMPLE_COUNT = 32'h00001310;

    localparam [31:0] V0_CONTROL  = 32'h00001320;
    localparam [31:0] V0_STATUS   = 32'h00001324;
    localparam [31:0] V0_BASE     = 32'h00001328;
    localparam [31:0] V0_LENGTH   = 32'h0000132C;
    localparam [31:0] V0_POSITION = 32'h00001338;

    localparam [31:0] V1_CONTROL  = 32'h00001340;
    localparam [31:0] V1_STATUS   = 32'h00001344;
    localparam [31:0] V1_BASE     = 32'h00001348;
    localparam [31:0] V1_LENGTH   = 32'h0000134C;
    localparam [31:0] V1_POSITION = 32'h00001358;

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

    integer cycles_to_tick;

    integer absolute_cycles = 0;
    integer last_tick_cycle = 0;

    reg [31:0] read_value;


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


    // Absolute post-reset cycle counter used to measure sample-tick
    // spacing even though the helper waits several additional cycles
    // for the serialized mixer commit.
    always @(posedge clk) begin

        if (reset) begin

            absolute_cycles =
                0;

            last_tick_cycle =
                0;

        end else begin

            absolute_cycles =
                absolute_cycles + 1;

        end
    end


    task automatic check;
        input condition;
        input [8*160-1:0] message;
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
                "playback test MMIO write completes"
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
                "playback test MMIO read completes"
            );

            read_data = rdata;

            @(negedge clk);

            valid = 1'b0;
            addr = 32'h00000000;

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

            repeat (2)
                @(posedge clk);

            #1;

            @(negedge clk);

            reset = 1'b0;

        end
    endtask


    task automatic wait_for_sample_tick;
        output integer cycles_waited;

        begin : wait_tick_block

            cycles_waited = 0;

            while (1) begin

                @(posedge clk);
                #1;

                if (dut.sample_tick) begin

                    cycles_waited =
                        absolute_cycles -
                        last_tick_cycle;

                    last_tick_cycle =
                        absolute_cycles;


                    // M7B-3 serializes four sample-RAM voice reads.
                    // Wait until OUTPUT/POSITION/SAMPLE_COUNT commit
                    // before returning to the existing checks.
                    while (!dut.mix_commit) begin

                        @(posedge clk);
                        #1;

                    end


                    disable wait_tick_block;

                end
            end
        end
    endtask


    initial begin

        // --------------------------------------------------------
        // Reset and exact phase-accumulator cadence.
        // --------------------------------------------------------

        repeat (3)
            @(posedge clk);

        #1;


        check(
            dut.sample_phase_reg == 25'd0,
            "sample phase resets to zero"
        );


        check(
            dut.sample_tick == 1'b0,
            "sample tick resets low"
        );


        check(
            dut.sample_count_reg == 32'd0,
            "sample count resets to zero"
        );


        @(negedge clk);
        reset = 1'b0;


        wait_for_sample_tick(
            cycles_to_tick
        );

        check(
            cycles_to_tick == 417,
            "first 48 kHz tick occurs after 417 clk cycles"
        );


        check(
            dut.sample_count_reg == 32'd1,
            "first sample tick increments SAMPLE_COUNT once"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );

        check(
            cycles_to_tick == 417,
            "second 48 kHz tick occurs after 417 clk cycles"
        );


        check(
            dut.sample_count_reg == 32'd2,
            "second sample tick increments SAMPLE_COUNT once"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );

        check(
            cycles_to_tick == 416,
            "third 48 kHz tick occurs after 416 clk cycles"
        );


        check(
            dut.sample_count_reg == 32'd3,
            "third sample tick increments SAMPLE_COUNT once"
        );


        mmio_read(
            REG_OUTPUT_L,
            read_value
        );

        check(
            read_value == 32'h00000000,
            "M7B-2 leaves OUTPUT_L zero until mixer checkpoint"
        );


        mmio_read(
            REG_OUTPUT_R,
            read_value
        );

        check(
            read_value == 32'h00000000,
            "M7B-2 leaves OUTPUT_R zero until mixer checkpoint"
        );


        // --------------------------------------------------------
        // Basic three-sample voice progression.
        // --------------------------------------------------------

        reset_dut();


        check(
            dut.sample_count_reg == 32'd0 &&
            dut.sample_phase_reg == 25'd0,
            "reset restarts sample counter and phase accumulator"
        );


        mmio_write(
            V0_BASE,
            32'd10,
            4'b1111
        );


        mmio_write(
            V0_LENGTH,
            32'd3,
            4'b1111
        );


        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0001
        );


        check(
            dut.voice_active[0] &&
            !dut.voice_done[0] &&
            dut.voice_position[0] == 13'd0,
            "START begins three-sample voice at POSITION zero"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd1,
            "first voice tick advances POSITION from zero to one"
        );


        check(
            dut.voice_active[0] &&
            !dut.voice_done[0],
            "voice remains active after first of three samples"
        );


        check(
            dut.sample_count_reg == 32'd1,
            "SAMPLE_COUNT increments with first playback update"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd2,
            "second voice tick advances POSITION to two"
        );


        check(
            dut.voice_active[0] &&
            !dut.voice_done[0],
            "voice remains active before final sample"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd3,
            "final sample advances POSITION to effective length"
        );


        check(
            !dut.voice_active[0] &&
            dut.voice_done[0],
            "final sample clears ACTIVE and sets DONE"
        );


        check(
            dut.sample_count_reg == 32'd3,
            "three playback updates produce three sample-count increments"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd3 &&
            !dut.voice_active[0] &&
            dut.voice_done[0],
            "completed voice remains at final POSITION with sticky DONE"
        );


        check(
            dut.sample_count_reg == 32'd4,
            "SAMPLE_COUNT continues while no voice is active"
        );


        // --------------------------------------------------------
        // Truncated effective length must govern completion.
        // --------------------------------------------------------

        reset_dut();


        mmio_write(
            V0_BASE,
            32'h00000FFE,
            4'b1111
        );


        mmio_write(
            V0_LENGTH,
            32'd10,
            4'b1111
        );


        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0001
        );


        check(
            dut.active_base[0] == 12'hFFE,
            "truncated playback snapshots BASE 4094"
        );


        check(
            dut.active_length[0] == 13'd2,
            "truncated playback snapshots effective LENGTH two"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd1 &&
            dut.voice_active[0],
            "truncated voice consumes first valid sample"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd2 &&
            !dut.voice_active[0] &&
            dut.voice_done[0],
            "truncated voice completes exactly at end of sample RAM"
        );


        // --------------------------------------------------------
        // Multiple voices advance independently on the same tick.
        // --------------------------------------------------------

        reset_dut();


        mmio_write(
            V0_BASE,
            32'd100,
            4'b1111
        );


        mmio_write(
            V0_LENGTH,
            32'd2,
            4'b1111
        );


        mmio_write(
            V1_BASE,
            32'd200,
            4'b1111
        );


        mmio_write(
            V1_LENGTH,
            32'd4,
            4'b1111
        );


        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0001
        );


        mmio_write(
            V1_CONTROL,
            32'h00000001,
            4'b0001
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd1 &&
            dut.voice_position[1] == 13'd1,
            "two active voices advance together on one sample tick"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd2 &&
            !dut.voice_active[0] &&
            dut.voice_done[0],
            "short voice completes independently at length two"
        );


        check(
            dut.voice_position[1] == 13'd2 &&
            dut.voice_active[1] &&
            !dut.voice_done[1],
            "long voice remains active after short voice completes"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[1] == 13'd4 &&
            !dut.voice_active[1] &&
            dut.voice_done[1],
            "long voice completes independently at length four"
        );


        check(
            dut.sample_count_reg == 32'd4,
            "four global ticks increment SAMPLE_COUNT four times regardless of voice count"
        );


        // --------------------------------------------------------
        // STOP prevents subsequent POSITION advancement.
        // --------------------------------------------------------

        reset_dut();


        mmio_write(
            V0_BASE,
            32'd300,
            4'b1111
        );


        mmio_write(
            V0_LENGTH,
            32'd4,
            4'b1111
        );


        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0001
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd1 &&
            dut.voice_active[0],
            "voice advances once before STOP"
        );


        mmio_write(
            V0_CONTROL,
            32'h00000002,
            4'b0001
        );


        check(
            !dut.voice_active[0] &&
            !dut.voice_done[0],
            "STOP clears ACTIVE without setting DONE during playback"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd1,
            "stopped voice does not advance on later sample tick"
        );


        // --------------------------------------------------------
        // START after STOP restarts POSITION from zero.
        // --------------------------------------------------------

        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0001
        );


        check(
            dut.voice_position[0] == 13'd0 &&
            dut.voice_active[0] &&
            !dut.voice_done[0],
            "START after STOP deterministically restarts POSITION"
        );


        wait_for_sample_tick(
            cycles_to_tick
        );


        check(
            dut.voice_position[0] == 13'd1,
            "restarted voice advances from POSITION zero"
        );


        // --------------------------------------------------------
        // CPU-visible POSITION/STATUS agree with internal sequencing.
        // --------------------------------------------------------

        mmio_read(
            V0_POSITION,
            read_value
        );


        check(
            read_value == 32'd1,
            "CPU-visible POSITION reflects sequencer state"
        );


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000001,
            "CPU-visible STATUS reflects active restarted voice"
        );


        mmio_read(
            REG_SAMPLE_COUNT,
            read_value
        );


        check(
            read_value == dut.sample_count_reg,
            "CPU-visible SAMPLE_COUNT reflects phase-accumulator updates"
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
