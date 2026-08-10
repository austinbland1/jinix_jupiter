`timescale 1ns/1ps

module jupiter_gpu_3d_depth_integration_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_DEPTH_BASE       = 32'h00001154;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;

    localparam [31:0] VERTEX_BASE      = 32'h10000000;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h10010000;
    localparam [31:0] DEPTH_BASE       = 32'h10020000;

    localparam [2:0] FRAGMENT_IDLE        = 3'd0;
    localparam [2:0] FRAGMENT_DEPTH_READ  = 3'd1;
    localparam [2:0] FRAGMENT_DEPTH_WRITE = 3'd2;
    localparam [2:0] FRAGMENT_FRAMEBUFFER = 3'd3;
    localparam [2:0] FRAGMENT_REJECT      = 3'd4;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        valid = 1'b0;
    reg        write = 1'b0;
    reg [31:0] addr  = 32'h00000000;
    reg [31:0] wdata = 32'h00000000;
    reg  [3:0] wstrb = 4'b0000;

    wire [31:0] rdata;
    wire        ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;

    reg [31:0] sdram_rdata = 32'h00000000;
    reg        sdram_ready = 1'b0;

    integer checks = 0;
    integer failures = 0;
    integer watchdog = 0;
    integer i;

    integer vertex_reads = 0;
    integer depth_reads = 0;
    integer depth_writes = 0;
    integer framebuffer_writes = 0;

    integer depth_read_stall_cycles = 0;
    integer depth_write_stall_cycles = 0;

    jupiter_gpu_3d dut
    (
        .clk         (clk),
        .reset       (reset),

        .valid       (valid),
        .write       (write),
        .addr        (addr),
        .wdata       (wdata),
        .wstrb       (wstrb),

        .rdata       (rdata),
        .ready       (ready),

        .sdram_valid (sdram_valid),
        .sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (sdram_valid && sdram_ready) begin
            if (!sdram_write) begin
                if (
                    (sdram_addr >= VERTEX_BASE) &&
                    (sdram_addr < (VERTEX_BASE + 32'd72))
                ) begin
                    vertex_reads <= vertex_reads + 1;
                end else if (
                    (sdram_addr >= DEPTH_BASE) &&
                    (sdram_addr < (DEPTH_BASE + 32'd32))
                ) begin
                    depth_reads <= depth_reads + 1;
                end
            end else begin
                if (
                    (sdram_addr >= DEPTH_BASE) &&
                    (sdram_addr < (DEPTH_BASE + 32'd32))
                ) begin
                    depth_writes <= depth_writes + 1;
                end else if (
                    (sdram_addr >= FRAMEBUFFER_BASE) &&
                    (sdram_addr < (FRAMEBUFFER_BASE + 32'd32))
                ) begin
                    framebuffer_writes <=
                        framebuffer_writes + 1;
                end
            end
        end
    end

    function automatic [31:0] vertex_word;
        input integer index;

        begin
            case (index)
                0:  vertex_word = 32'h00004000;
                1:  vertex_word = 32'h00004000;
                2:  vertex_word = 32'h00001000;
                3:  vertex_word = 32'h00000000;
                4:  vertex_word = 32'h00000000;
                5:  vertex_word = 32'h00010000;

                6:  vertex_word = 32'h00034000;
                7:  vertex_word = 32'h00004000;
                8:  vertex_word = 32'h00004000;
                9:  vertex_word = 32'h00010000;
                10: vertex_word = 32'h00000000;
                11: vertex_word = 32'h00010000;

                12: vertex_word = 32'h00004000;
                13: vertex_word = 32'h00034000;
                14: vertex_word = 32'h00007000;
                15: vertex_word = 32'h00000000;
                16: vertex_word = 32'h00010000;
                17: vertex_word = 32'h00010000;

                default:
                    vertex_word = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [15:0] expected_x;
        input integer index;
        begin
            case (index)
                0: expected_x = 16'd0;
                1: expected_x = 16'd1;
                2: expected_x = 16'd2;
                3: expected_x = 16'd0;
                4: expected_x = 16'd1;
                5: expected_x = 16'd0;
                default: expected_x = 16'hFFFF;
            endcase
        end
    endfunction

    function automatic [15:0] expected_y;
        input integer index;
        begin
            case (index)
                0, 1, 2: expected_y = 16'd0;
                3, 4:    expected_y = 16'd1;
                5:       expected_y = 16'd2;
                default: expected_y = 16'hFFFF;
            endcase
        end
    endfunction

    function automatic [15:0] expected_z;
        input integer index;
        begin
            case (index)
                0: expected_z = 16'h1C00;
                1: expected_z = 16'h2C00;
                2: expected_z = 16'h3C00;
                3: expected_z = 16'h3C00;
                4: expected_z = 16'h4C00;
                5: expected_z = 16'h5C00;
                default: expected_z = 16'hFFFF;
            endcase
        end
    endfunction

    function automatic [31:0] expected_aligned_offset;
        input integer index;
        begin
            case (index)
                0: expected_aligned_offset = 32'd0;
                1: expected_aligned_offset = 32'd0;
                2: expected_aligned_offset = 32'd4;
                3: expected_aligned_offset = 32'd8;
                4: expected_aligned_offset = 32'd8;
                5: expected_aligned_offset = 32'd16;
                default: expected_aligned_offset = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [31:0] depth_read_word;
        input integer index;
        begin
            case (index)
                // PASS: 0x1c00 < 0x2000
                0: depth_read_word = 32'hA5A52000;

                // EQUAL: 0x2c00 == 0x2c00, must fail
                1: depth_read_word = 32'h2C00A5A5;

                // FARTHER: 0x3c00 > 0x3bff, must fail
                2: depth_read_word = 32'hA5A53BFF;

                // PASS: 0x3c00 < 0xffff
                3: depth_read_word = 32'hA5A5FFFF;

                // PASS: 0x4c00 < 0x4d00
                4: depth_read_word = 32'h4D00A5A5;

                // FARTHER: 0x5c00 > 0x1000, must fail
                5: depth_read_word = 32'hA5A51000;

                default:
                    depth_read_word = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic pass_expected;
        input integer index;
        begin
            case (index)
                0, 3, 4:
                    pass_expected = 1'b1;

                default:
                    pass_expected = 1'b0;
            endcase
        end
    endfunction

    function automatic [31:0] expected_depth_write_data;
        input integer index;
        begin
            case (index)
                0: expected_depth_write_data = 32'h00001C00;
                3: expected_depth_write_data = 32'h00003C00;
                4: expected_depth_write_data = 32'h4C000000;
                default:
                    expected_depth_write_data = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [3:0] expected_halfword_wstrb;
        input integer index;
        begin
            case (index)
                1, 4:
                    expected_halfword_wstrb = 4'b1100;

                default:
                    expected_halfword_wstrb = 4'b0011;
            endcase
        end
    endfunction

    function automatic [31:0] expected_fb_data;
        input integer index;
        begin
            case (index)
                4:
                    expected_fb_data = 32'hF8000000;

                default:
                    expected_fb_data = 32'h0000F800;
            endcase
        end
    endfunction

    task check;
        input condition;
        input [1023:0] message;

        begin
            checks = checks + 1;

            if (condition) begin
                $display("PASS: %0s", message);
            end else begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task mmio_write;
        input [31:0] address;
        input [31:0] data;

        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b1;
            addr  = address;
            wdata = data;
            wstrb = 4'b1111;

            #1;

            check(
                ready,
                "MMIO write completes without wait"
            );

            @(posedge clk);
            #1;

            valid = 1'b0;
            write = 1'b0;
            addr  = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;
        end
    endtask

    task complete_vertex_word;
        input integer index;

        begin
            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        VERTEX_BASE +
                        (index * 4)
                    ),
                "expected vertex read is presented"
            );

            @(negedge clk);

            sdram_rdata = vertex_word(index);
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        VERTEX_BASE +
                        (index * 4)
                    ),
                "vertex read remains stable through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;
        end
    endtask

    task wait_for_depth_read;
        input integer index;

        begin
            watchdog = 0;

            while (
                !(
                    sdram_valid &&
                    !sdram_write &&
                    (dut.fragment_state == FRAGMENT_DEPTH_READ)
                ) &&
                (watchdog < 32768)
            ) begin
                @(posedge clk);
                #1;
                watchdog = watchdog + 1;
            end

            check(
                watchdog < 32768,
                "fragment reaches depth-read state before watchdog"
            );

            check(
                dut.raster_covered_valid &&
                dut.raster_covered_x == expected_x(index) &&
                dut.raster_covered_y == expected_y(index) &&
                dut.raster_covered_z == expected_z(index),
                "held fragment X/Y/Z matches deterministic reference"
            );

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        DEPTH_BASE +
                        expected_aligned_offset(index)
                    ) &&
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000,
                "depth read uses exact aligned address and read strobes"
            );
        end
    endtask

    task complete_depth_read;
        input integer index;

        begin
            if (index == 0) begin
                repeat (3) begin
                    @(posedge clk);
                    #1;

                    depth_read_stall_cycles =
                        depth_read_stall_cycles + 1;

                    check(
                        sdram_valid &&
                        !sdram_write &&
                        sdram_addr == DEPTH_BASE &&
                        dut.raster_covered_x == 16'd0 &&
                        dut.raster_covered_y == 16'd0 &&
                        dut.raster_covered_z == 16'h1C00,
                        "depth read and fragment remain stable while stalled"
                    );
                end
            end

            @(negedge clk);

            sdram_rdata = depth_read_word(index);
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        DEPTH_BASE +
                        expected_aligned_offset(index)
                    ),
                "depth read remains exact through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;
        end
    endtask

    task complete_depth_write;
        input integer index;

        begin
            check(
                dut.fragment_state == FRAGMENT_DEPTH_WRITE &&
                sdram_valid &&
                sdram_write &&
                sdram_addr ==
                    (
                        DEPTH_BASE +
                        expected_aligned_offset(index)
                    ) &&
                sdram_wdata ==
                    expected_depth_write_data(index) &&
                sdram_wstrb ==
                    expected_halfword_wstrb(index),
                "passing fragment produces exact depth halfword write"
            );

            if (index == 0) begin
                repeat (2) begin
                    @(posedge clk);
                    #1;

                    depth_write_stall_cycles =
                        depth_write_stall_cycles + 1;

                    check(
                        dut.fragment_state == FRAGMENT_DEPTH_WRITE &&
                        sdram_valid &&
                        sdram_write &&
                        sdram_addr == DEPTH_BASE &&
                        sdram_wdata == 32'h00001C00 &&
                        sdram_wstrb == 4'b0011 &&
                        dut.raster_covered_z == 16'h1C00,
                        "depth write remains stable while SDRAM stalls"
                    );
                end
            end

            @(negedge clk);
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr ==
                    (
                        DEPTH_BASE +
                        expected_aligned_offset(index)
                    ) &&
                sdram_wdata ==
                    expected_depth_write_data(index) &&
                sdram_wstrb ==
                    expected_halfword_wstrb(index),
                "depth write remains exact through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;

            // sdram_ready feeds continuous DUT handshake logic. Allow
            // one simulation delay for raster_covered_ready and the
            // external SDRAM outputs to settle before the framebuffer
            // completion task samples them.
            #1;
        end
    endtask

    task complete_framebuffer_write;
        input integer index;

        begin
            check(
                dut.fragment_state == FRAGMENT_FRAMEBUFFER &&
                sdram_valid &&
                sdram_write &&
                sdram_addr ==
                    (
                        FRAMEBUFFER_BASE +
                        expected_aligned_offset(index)
                    ) &&
                sdram_wdata ==
                    expected_fb_data(index) &&
                sdram_wstrb ==
                    expected_halfword_wstrb(index),
                "depth-passing fragment produces exact framebuffer write"
            );

            check(
                !dut.raster_covered_ready,
                "passing fragment is not released before framebuffer completion"
            );

            @(negedge clk);
            sdram_ready = 1'b1;

            #1;

            check(
                dut.raster_covered_ready &&
                sdram_valid &&
                sdram_write,
                "framebuffer completion releases passing fragment"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;
        end
    endtask

    task complete_rejected_fragment;
        input integer index;

        begin
            check(
                dut.fragment_state == FRAGMENT_REJECT,
                "failed or equal depth compare enters reject state"
            );

            check(
                !sdram_valid &&
                !sdram_write &&
                dut.raster_covered_ready,
                "rejected fragment performs no write and is released"
            );

            check(
                dut.raster_covered_x == expected_x(index) &&
                dut.raster_covered_y == expected_y(index) &&
                dut.raster_covered_z == expected_z(index),
                "rejected fragment remains exact until release"
            );

            @(posedge clk);
            #1;

            check(
                dut.fragment_state == FRAGMENT_IDLE,
                "rejected fragment returns transaction sequencer idle"
            );
        end
    endtask

    initial begin

        repeat (2)
            @(posedge clk);

        #1;

        check(
            !dut.busy &&
            dut.fragment_state == FRAGMENT_IDLE &&
            !sdram_valid,
            "reset leaves depth transaction sequencer idle"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_write(REG_VERTEX_BASE, VERTEX_BASE);
        mmio_write(REG_FRAMEBUFFER_BASE, FRAMEBUFFER_BASE);
        mmio_write(REG_DEPTH_BASE, DEPTH_BASE);
        mmio_write(REG_TARGET_SIZE, 32'h00040004);

        // MODE bit 1 enables depth. Texture and blend remain disabled.
        mmio_write(REG_MODE, 32'h00000002);
        mmio_write(REG_BLEND_ALPHA, 32'h00000010);
        mmio_write(REG_FLAT_COLOR, 32'h0000F800);
        mmio_write(REG_CONTROL, 32'h00000001);

        check(
            dut.busy &&
            dut.active_mode[1] &&
            dut.active_depth_base == DEPTH_BASE,
            "START snapshots enabled depth configuration"
        );

        for (i = 0; i < 18; i = i + 1)
            complete_vertex_word(i);

        for (i = 0; i < 6; i = i + 1) begin
            wait_for_depth_read(i);
            complete_depth_read(i);

            if (pass_expected(i)) begin
                complete_depth_write(i);
                complete_framebuffer_write(i);
            end else begin
                complete_rejected_fragment(i);
            end
        end

        watchdog = 0;

        while (!dut.done && (watchdog < 32768)) begin
            @(posedge clk);
            #1;
            watchdog = watchdog + 1;
        end

        check(
            watchdog < 32768 &&
            dut.done &&
            !dut.busy &&
            !dut.error,
            "depth-enabled command completes normally"
        );

        check(
            vertex_reads == 18,
            "depth command performs exactly eighteen vertex reads"
        );

        check(
            depth_reads == 6,
            "every covered fragment performs exactly one depth read"
        );

        check(
            depth_writes == 3,
            "only strict-LESS passing fragments update depth"
        );

        check(
            framebuffer_writes == 3,
            "only strict-LESS passing fragments update framebuffer"
        );

        check(
            dut.raster_coverage_count == 32'd6,
            "all six covered fragments are eventually consumed"
        );

        check(
            dut.raster_sample_count == 32'd16,
            "depth pipeline preserves deterministic raster sample count"
        );

        check(
            depth_read_stall_cycles == 3,
            "first depth read survived three stall cycles"
        );

        check(
            depth_write_stall_cycles == 2,
            "first depth write survived two stall cycles"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "completed depth command returns SDRAM interface idle"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("DEPTH_VERTEX_READS: %0d", vertex_reads);
            $display("DEPTH_TEST_READS: %0d", depth_reads);
            $display("DEPTH_PASS_WRITES: %0d", depth_writes);
            $display(
                "DEPTH_FRAMEBUFFER_WRITES: %0d",
                framebuffer_writes
            );
            $display("DEPTH_STRICT_LESS_PASSES: 3");
            $display("DEPTH_REJECTED_FRAGMENTS: 3");
            $display("DEPTH_EQUAL_REJECTS: 1");
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );
        end

        $display("==============================");

        if (failures != 0)
            $fatal(1);

        $finish;
    end

endmodule
