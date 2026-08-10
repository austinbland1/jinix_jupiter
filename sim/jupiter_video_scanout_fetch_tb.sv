`timescale 1ns/1ps

module jupiter_video_scanout_fetch_tb;

    localparam [31:0] REG_DISPLAY_CONTROL = 32'h00001180;
    localparam [31:0] REG_DISPLAY_STATUS  = 32'h00001184;
    localparam [31:0] REG_DISPLAY_BASE    = 32'h00001188;
    localparam [31:0] REG_DISPLAY_SIZE    = 32'h0000118C;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg pal = 1'b0;
    reg scandouble = 1'b0;

    reg        valid = 1'b0;
    reg        write = 1'b0;
    reg [31:0] addr  = 32'h00000000;
    reg [31:0] wdata = 32'h00000000;
    reg  [3:0] wstrb = 4'b0000;

    wire [31:0] rdata;
    wire        ready;

    reg [31:0] sdram_max_addr = 32'h11FFFFFF;

    wire        sdram_valid;
    wire [31:0] sdram_addr;
    reg  [31:0] sdram_rdata = 32'h00000000;
    reg         sdram_ready = 1'b0;

    wire       ce_pix;
    wire       HBlank;
    wire       HSync;
    wire       VBlank;
    wire       VSync;

    wire [7:0] video_r;
    wire [7:0] video_g;
    wire [7:0] video_b;

    integer pass_count = 0;
    integer fail_count = 0;
    integer completed_reads = 0;
    integer i;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset &&
            sdram_valid &&
            sdram_ready)
            completed_reads =
                completed_reads + 1;
    end

    jupiter_video_scanout dut
    (
        .clk            (clk),
        .reset          (reset),

        .pal            (pal),
        .scandouble     (scandouble),

        .valid          (valid),
        .write          (write),
        .addr           (addr),
        .wdata          (wdata),
        .wstrb          (wstrb),
        .rdata          (rdata),
        .ready          (ready),

        .sdram_max_addr (sdram_max_addr),

        .sdram_valid    (sdram_valid),
        .sdram_addr     (sdram_addr),
        .sdram_rdata    (sdram_rdata),
        .sdram_ready    (sdram_ready),

        .ce_pix         (ce_pix),

        .HBlank         (HBlank),
        .HSync          (HSync),
        .VBlank         (VBlank),
        .VSync          (VSync),

        .video_r        (video_r),
        .video_g        (video_g),
        .video_b        (video_b)
    );

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display(
                    "PASS: %0s",
                    message
                );
            end else begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL: %0s",
                    message
                );
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task mmio_idle;
        begin
            valid = 1'b0;
            write = 1'b0;
            addr  = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;
            #1;
        end
    endtask

    task mmio_write;
        input [31:0] write_addr;
        input [31:0] write_data;
        input  [3:0] write_strobes;
        begin
            valid = 1'b1;
            write = 1'b1;
            addr  = write_addr;
            wdata = write_data;
            wstrb = write_strobes;

            #1;

            check(
                ready,
                "MMIO write completes without wait"
            );

            tick();
            mmio_idle();
        end
    endtask

    task reset_dut;
        begin
            reset = 1'b1;

            pal = 1'b0;
            scandouble = 1'b0;

            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;

            mmio_idle();

            tick();
            tick();

            reset = 1'b0;
            #1;
        end
    endtask

    task force_snapshot;
        begin
            dut.hc = 10'd637;

            if (scandouble)
                dut.vc = 10'd479;
            else
                dut.vc = 10'd239;

            dut.ce_pix = 1'b1;

            #1;
            tick();
        end
    endtask

    task force_frame_wrap;
        begin
            dut.hc = 10'd637;

            if (pal) begin
                if (scandouble)
                    dut.vc = 10'd623;
                else
                    dut.vc = 10'd311;
            end else begin
                if (scandouble)
                    dut.vc = 10'd523;
                else
                    dut.vc = 10'd261;
            end

            dut.ce_pix = 1'b1;

            #1;
            tick();
        end
    endtask

    task service_read;
        input [31:0] expected_addr;
        input [31:0] returned_data;
        input integer stall_cycles;

        integer stall_index;
        reg [31:0] held_addr;

        begin
            #1;

            check(
                sdram_valid &&
                sdram_addr == expected_addr,
                "expected aligned scanout read is presented"
            );

            held_addr = sdram_addr;

            for (
                stall_index = 0;
                stall_index < stall_cycles;
                stall_index = stall_index + 1
            ) begin
                sdram_ready = 1'b0;

                tick();

                check(
                    sdram_valid &&
                    sdram_addr == held_addr,
                    "scanout read remains stable under backpressure"
                );
            end

            sdram_rdata = returned_data;
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                sdram_addr == expected_addr,
                "scanout read remains exact through completion"
            );

            tick();

            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;

            #1;
        end
    endtask

    initial begin
        // ====================================================
        // Reset / disabled behavior
        // ====================================================

        reset_dut();

        check(
            !sdram_valid,
            "reset-disabled scanout emits no SDRAM request"
        );

        check(
            video_r == 8'h00 &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "reset-disabled active video is black"
        );

        // ====================================================
        // Narrow 4x2 framebuffer
        //
        // line 0:
        //   pixel 0 = F800 red
        //   pixel 1 = 07E0 green
        //   pixel 2 = 001F blue
        //   pixel 3 = FFFF white
        //
        // line 1:
        //   pixel 0 = FFE0 yellow
        // ====================================================

        completed_reads = 0;

        mmio_write(
            REG_DISPLAY_BASE,
            32'h10001000,
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd2, 16'd4},
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_CONTROL,
            32'h00000001,
            4'b0001
        );

        force_snapshot();

        check(
            dut.active_enable &&
            dut.active_base == 32'h10001000 &&
            dut.active_width == 16'd4 &&
            dut.active_height == 16'd2,
            "vertical blank activates exact narrow framebuffer"
        );

        check(
            dut.fetch_active &&
            dut.fetch_line == 16'd0 &&
            !dut.fetch_buffer_select &&
            dut.fetch_word_index == 16'd0,
            "snapshot starts source line zero in buffer zero"
        );

        service_read(
            32'h10001000,
            32'h07E0F800,
            3
        );

        check(
            !dut.buffer_0_valid,
            "partial source line is not marked displayable"
        );

        service_read(
            32'h10001004,
            32'hFFFF001F,
            0
        );

        check(
            dut.buffer_0_valid &&
            dut.buffer_0_line == 16'd0,
            "completed source line zero becomes valid atomically"
        );

        check(
            dut.line_buffer_0[0] == 16'hF800 &&
            dut.line_buffer_0[1] == 16'h07E0 &&
            dut.line_buffer_0[2] == 16'h001F &&
            dut.line_buffer_0[3] == 16'hFFFF,
            "32-bit reads unpack low/high RGB565 pixels exactly"
        );

        // One idle clock starts prefetch of line 1 during vertical blank.
        tick();

        check(
            sdram_valid &&
            dut.fetch_line == 16'd1 &&
            dut.fetch_buffer_select,
            "vertical blank prefetch advances to source line one"
        );

        service_read(
            32'h10001008,
            32'h0000FFE0,
            1
        );

        service_read(
            32'h1000100C,
            32'h8410001F,
            0
        );

        check(
            dut.buffer_1_valid &&
            dut.buffer_1_line == 16'd1,
            "completed source line one becomes valid in alternate buffer"
        );

        check(
            completed_reads == 4,
            "4x2 surface performs exactly four 32-bit source reads"
        );

        check(
            !sdram_valid,
            "two fully prefetched narrow lines leave SDRAM master idle"
        );

        // ====================================================
        // Frame start selects completed line zero
        // ====================================================

        force_frame_wrap();

        check(
            dut.vc == 10'd0 &&
            dut.hc == 10'd0 &&
            dut.display_line_valid &&
            !dut.display_buffer_select,
            "frame start selects completed buffer-zero source line"
        );

        #1;

        check(
            video_r == 8'hFF &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "RGB565 red expands exactly to RGB888"
        );

        dut.hc = 10'd1;
        #1;

        check(
            video_r == 8'h00 &&
            video_g == 8'hFF &&
            video_b == 8'h00,
            "RGB565 green expands exactly to RGB888"
        );

        dut.hc = 10'd2;
        #1;

        check(
            video_r == 8'h00 &&
            video_g == 8'h00 &&
            video_b == 8'hFF,
            "RGB565 blue expands exactly to RGB888"
        );

        dut.hc = 10'd3;
        #1;

        check(
            video_r == 8'hFF &&
            video_g == 8'hFF &&
            video_b == 8'hFF,
            "RGB565 white expands exactly to RGB888"
        );

        dut.hc = 10'd4;
        #1;

        check(
            video_r == 8'h00 &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "pixels beyond programmed source width are black"
        );

        // Move into physical/source line 1.
        dut.hc = 10'd637;
        dut.vc = 10'd0;
        dut.ce_pix = 1'b1;

        tick();

        check(
            dut.vc == 10'd1 &&
            dut.display_line_valid &&
            dut.display_buffer_select,
            "next source line switches to completed alternate buffer"
        );

        dut.hc = 10'd0;
        #1;

        check(
            video_r == 8'hFF &&
            video_g == 8'hFF &&
            video_b == 8'h00,
            "line-one yellow pixel expands exactly"
        );

        check(
            completed_reads == 4,
            "displaying prefetched lines performs no duplicate reads"
        );

        // ====================================================
        // Partial-line underflow
        // ====================================================

        reset_dut();
        completed_reads = 0;

        mmio_write(
            REG_DISPLAY_BASE,
            32'h10002000,
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd1, 16'd4},
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_CONTROL,
            32'h00000001,
            4'b0001
        );

        force_snapshot();

        service_read(
            32'h10002000,
            32'h07E0F800,
            0
        );

        check(
            sdram_valid &&
            sdram_addr == 32'h10002004 &&
            !dut.buffer_0_valid,
            "second word remains required before line is displayable"
        );

        // Start visible frame while final word remains stalled.
        force_frame_wrap();

        check(
            dut.display_line_valid == 1'b0,
            "incomplete required line is committed black at line start"
        );

        check(
            dut.underflow_sticky,
            "incomplete required line sets sticky underflow"
        );

        dut.hc = 10'd0;
        #1;

        check(
            video_r == 8'h00 &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "underflowed line begins black"
        );

        // Completing the source line in the middle of that display line must
        // not expose a partially displayed image.
        service_read(
            32'h10002004,
            32'hFFFF001F,
            0
        );

        check(
            dut.buffer_0_valid,
            "late final fetch still completes source buffer"
        );

        dut.hc = 10'd2;
        #1;

        check(
            video_r == 8'h00 &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "late completion cannot unblack an already underflowed line"
        );

        mmio_write(
            REG_DISPLAY_CONTROL,
            32'h00000003,
            4'b0001
        );

        check(
            !dut.underflow_sticky,
            "CLEAR_UNDERFLOW clears sticky underflow after late completion"
        );

        check(
            dut.enable_shadow,
            "CLEAR_UNDERFLOW may preserve ENABLE in the same control write"
        );

        // ====================================================
        // Full-width exact transaction count
        // ====================================================

        reset_dut();
        completed_reads = 0;

        mmio_write(
            REG_DISPLAY_BASE,
            32'h10010000,
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd1, 16'd320},
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_CONTROL,
            32'h00000001,
            4'b0001
        );

        force_snapshot();

        check(
            sdram_valid &&
            sdram_addr == 32'h10010000,
            "full-width line begins at exact framebuffer base"
        );

        sdram_ready = 1'b1;
        sdram_rdata = 32'h00000000;

        for (
            i = 0;
            i < 160;
            i = i + 1
        ) begin
            #1;

            check(
                sdram_valid &&
                sdram_addr ==
                    (32'h10010000 + (i * 4)),
                "full-width fetch presents exact sequential aligned address"
            );

            tick();
        end

        sdram_ready = 1'b0;
        sdram_rdata = 32'h00000000;

        #1;

        check(
            completed_reads == 160,
            "320-pixel line performs exactly 160 completed reads"
        );

        check(
            dut.buffer_0_valid &&
            dut.buffer_0_line == 16'd0,
            "full-width source line becomes valid only after read 160"
        );

        check(
            !sdram_valid,
            "one-line full-width framebuffer returns SDRAM master idle"
        );

        // ====================================================
        // Scandoubled source-line reuse
        // ====================================================

        reset_dut();
        completed_reads = 0;
        scandouble = 1'b1;

        mmio_write(
            REG_DISPLAY_BASE,
            32'h10020000,
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd2, 16'd4},
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_CONTROL,
            32'h00000001,
            4'b0001
        );

        force_snapshot();

        service_read(
            32'h10020000,
            32'h07E0F800,
            0
        );

        service_read(
            32'h10020004,
            32'hFFFF001F,
            0
        );

        tick();

        service_read(
            32'h10020008,
            32'h0000FFE0,
            0
        );

        service_read(
            32'h1002000C,
            32'h8410001F,
            0
        );

        check(
            completed_reads == 4,
            "scandoubled two-line source prefetches each source line once"
        );

        force_frame_wrap();

        check(
            dut.vc == 10'd0 &&
            dut.display_line_valid &&
            !dut.display_buffer_select,
            "scandoubled first physical row selects source line zero"
        );

        dut.hc = 10'd0;
        #1;

        check(
            video_r == 8'hFF &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "scandoubled first physical row displays source line zero"
        );

        // Advance from physical row 0 to row 1. Source line remains zero.
        dut.hc = 10'd637;
        dut.vc = 10'd0;

        tick();

        check(
            dut.vc == 10'd1 &&
            dut.display_line_valid &&
            !dut.display_buffer_select,
            "scandoubled second physical row reuses source line zero buffer"
        );

        dut.hc = 10'd0;
        #1;

        check(
            video_r == 8'hFF &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "scandoubled duplicate row reproduces exact source pixel"
        );

        check(
            completed_reads == 4,
            "scandoubled duplicate row performs no duplicate SDRAM fetch"
        );

        // Advance from physical row 1 to row 2: source line 1.
        dut.hc = 10'd637;
        dut.vc = 10'd1;

        tick();

        check(
            dut.vc == 10'd2 &&
            dut.display_line_valid &&
            dut.display_buffer_select,
            "scandoubled third physical row advances to source line one"
        );

        dut.hc = 10'd0;
        #1;

        check(
            video_r == 8'hFF &&
            video_g == 8'hFF &&
            video_b == 8'h00,
            "scandoubled source line one displays exact prefetched pixel"
        );

        check(
            completed_reads == 4,
            "display traversal itself adds no framebuffer transactions"
        );

        // ====================================================
        // Final result
        // ====================================================

        $display("");
        $display("==============================");

        if (fail_count == 0) begin
            $display(
                "RESULT: PASS  (%0d checks)",
                pass_count
            );
            $display(
                "SCANOUT_FINAL_COMPLETED_READS: %0d",
                completed_reads
            );
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                fail_count,
                pass_count + fail_count
            );
        end

        $display("==============================");

        if (fail_count != 0)
            $fatal(
                1,
                "M11B-2c framebuffer scanout regression failed"
            );

        $finish;
    end

endmodule
