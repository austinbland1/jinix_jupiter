`timescale 1ns/1ps

module jupiter_video_scanout_tb;

    localparam [31:0] REG_DISPLAY_CONTROL = 32'h00001180;
    localparam [31:0] REG_DISPLAY_STATUS  = 32'h00001184;
    localparam [31:0] REG_DISPLAY_BASE    = 32'h00001188;
    localparam [31:0] REG_DISPLAY_SIZE    = 32'h0000118C;
    localparam [31:0] REG_RESERVED        = 32'h00001190;

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

    always #5 clk = ~clk;

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

    task mmio_read_check;
        input [31:0] read_addr;
        input [31:0] expected_data;
        input [8*120-1:0] message;
        begin
            valid = 1'b1;
            write = 1'b0;
            addr  = read_addr;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;

            check(
                ready &&
                rdata == expected_data,
                message
            );

            mmio_idle();
        end
    endtask

    task force_snapshot_ntsc;
        begin
            // Snapshot occurs while leaving source/raster line 239.
            dut.hc = 10'd637;
            dut.vc = 10'd239;
            dut.ce_pix = 1'b1;

            #1;
            tick();
        end
    endtask

    initial begin
        // ====================================================
        // Reset state
        // ====================================================

        mmio_idle();

        tick();
        tick();

        check(
            dut.enable_shadow == 1'b0 &&
            dut.display_base_shadow == 32'h00000000 &&
            dut.display_size_shadow == 32'h00000000,
            "reset clears shadow display configuration"
        );

        check(
            dut.active_enable == 1'b0 &&
            dut.active_base == 32'h00000000 &&
            dut.active_width == 16'd0 &&
            dut.active_height == 16'd0,
            "reset clears active display configuration"
        );

        check(
            dut.underflow_sticky == 1'b0,
            "reset clears underflow status"
        );

        check(
            dut.hc == 10'd0 &&
            dut.vc == 10'd0 &&
            ce_pix == 1'b0,
            "reset initializes raster and pixel enable"
        );

        check(
            !sdram_valid &&
            sdram_addr == 32'h00000000,
            "M11B-2b emits no SDRAM traffic"
        );

        check(
            video_r == 8'h00 &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "M11B-2b video output is deterministic black"
        );

        reset = 1'b0;
        #1;

        // ====================================================
        // MMIO reset/read behavior
        // ====================================================

        mmio_read_check(
            REG_DISPLAY_CONTROL,
            32'h00000000,
            "CONTROL resets to disabled"
        );

        mmio_read_check(
            REG_DISPLAY_STATUS,
            32'h00000000,
            "STATUS resets inactive with no underflow"
        );

        mmio_read_check(
            REG_DISPLAY_BASE,
            32'h00000000,
            "DISPLAY_BASE resets to zero"
        );

        mmio_read_check(
            REG_DISPLAY_SIZE,
            32'h00000000,
            "DISPLAY_SIZE resets to zero"
        );

        mmio_read_check(
            REG_RESERVED,
            32'h00000000,
            "reserved display MMIO reads zero"
        );

        // Reserved writes do nothing.
        mmio_write(
            REG_RESERVED,
            32'hFFFFFFFF,
            4'b1111
        );

        mmio_read_check(
            REG_RESERVED,
            32'h00000000,
            "reserved display MMIO write remains ignored"
        );

        // ====================================================
        // Byte-strobe semantics
        // ====================================================

        mmio_write(
            REG_DISPLAY_BASE,
            32'h11223344,
            4'b0101
        );

        mmio_read_check(
            REG_DISPLAY_BASE,
            32'h00220044,
            "DISPLAY_BASE honors independent byte strobes"
        );

        mmio_write(
            REG_DISPLAY_BASE,
            32'hAABBCCDD,
            4'b1010
        );

        mmio_read_check(
            REG_DISPLAY_BASE,
            32'hAA22CC44,
            "later DISPLAY_BASE strobes preserve untouched bytes"
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            32'h12345678,
            4'b1001
        );

        mmio_read_check(
            REG_DISPLAY_SIZE,
            32'h12000078,
            "DISPLAY_SIZE honors independent byte strobes"
        );

        // Reprogram exact valid surface.
        mmio_write(
            REG_DISPLAY_BASE,
            32'h10001000,
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd240, 16'd320},
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_CONTROL,
            32'h00000001,
            4'b0001
        );

        mmio_read_check(
            REG_DISPLAY_CONTROL,
            32'h00000001,
            "CONTROL stores ENABLE only"
        );

        check(
            dut.active_enable == 1'b0,
            "shadow enable does not immediately alter active frame"
        );

        // ====================================================
        // Vertical-blank configuration snapshot
        // ====================================================

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b1,
            "valid enabled configuration activates at vertical blank"
        );

        check(
            dut.active_base == 32'h10001000 &&
            dut.active_width == 16'd320 &&
            dut.active_height == 16'd240,
            "vertical blank snapshots exact framebuffer configuration"
        );

        mmio_read_check(
            REG_DISPLAY_STATUS,
            32'h00000001,
            "STATUS reports valid active configuration"
        );

        check(
            dut.vc == 10'd240 &&
            VBlank,
            "snapshot transition enters selected NTSC vertical blank"
        );

        // Shadow writes after snapshot do not alter active state.
        mmio_write(
            REG_DISPLAY_BASE,
            32'h10020000,
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd120, 16'd160},
            4'b1111
        );

        check(
            dut.active_base == 32'h10001000 &&
            dut.active_width == 16'd320 &&
            dut.active_height == 16'd240,
            "mid-frame shadow writes leave active snapshot unchanged"
        );

        // ====================================================
        // Invalid configuration rejection
        // ====================================================

        // Odd width.
        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd120, 16'd159},
            4'b1111
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b0,
            "odd source width is rejected"
        );

        // Width above 320.
        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd120, 16'd322},
            4'b1111
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b0,
            "source width above 320 is rejected"
        );

        // Height above 240.
        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd241, 16'd320},
            4'b1111
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b0,
            "source height above 240 is rejected"
        );

        // Unaligned base.
        mmio_write(
            REG_DISPLAY_BASE,
            32'h10001002,
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd240, 16'd320},
            4'b1111
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b0,
            "unaligned framebuffer base is rejected"
        );

        // Below SDRAM aperture.
        mmio_write(
            REG_DISPLAY_BASE,
            32'h0FFFF000,
            4'b1111
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b0,
            "framebuffer below external SDRAM aperture is rejected"
        );

        // Frame extends beyond installed SDRAM limit.
        sdram_max_addr = 32'h1000FFFF;

        mmio_write(
            REG_DISPLAY_BASE,
            32'h1000F000,
            4'b1111
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b0,
            "framebuffer extending past installed SDRAM is rejected"
        );

        // No installed SDRAM.
        sdram_max_addr = 32'h00000000;

        mmio_write(
            REG_DISPLAY_BASE,
            32'h10001000,
            4'b1111
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b0,
            "enabled scanout is rejected when SDRAM is unavailable"
        );

        // Restore 32 MiB visible aperture and valid config.
        sdram_max_addr = 32'h11FFFFFF;

        mmio_write(
            REG_DISPLAY_BASE,
            32'h10001000,
            4'b1111
        );

        mmio_write(
            REG_DISPLAY_SIZE,
            {16'd240, 16'd320},
            4'b1111
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b1,
            "valid configuration reactivates after rejected snapshots"
        );

        // Disable is also deferred to snapshot.
        mmio_write(
            REG_DISPLAY_CONTROL,
            32'h00000000,
            4'b0001
        );

        check(
            dut.active_enable == 1'b1,
            "shadow disable does not change current active frame"
        );

        force_snapshot_ntsc();

        check(
            dut.active_enable == 1'b0,
            "shadow disable takes effect at vertical blank"
        );

        // ====================================================
        // CONTROL W1 underflow clear semantics
        // ====================================================

        // M11B-2b has no fetch engine to set the flag naturally yet.
        // Seed the implementation state to verify software clear behavior.
        dut.underflow_sticky = 1'b1;
        #1;

        mmio_read_check(
            REG_DISPLAY_STATUS,
            32'h00000002,
            "STATUS exposes sticky underflow bit"
        );

        mmio_write(
            REG_DISPLAY_CONTROL,
            32'h00000002,
            4'b0001
        );

        check(
            dut.underflow_sticky == 1'b0,
            "CONTROL CLEAR_UNDERFLOW clears sticky flag"
        );

        check(
            dut.enable_shadow == 1'b0,
            "CLEAR_UNDERFLOW write preserves requested disabled state"
        );

        // ====================================================
        // CE_PIXEL cadence
        // ====================================================

        reset = 1'b1;
        tick();
        reset = 1'b0;

        scandouble = 1'b0;

        check(
            dut.hc == 10'd0 &&
            ce_pix == 1'b0,
            "non-scandoubled cadence begins with CE low"
        );

        tick();

        check(
            ce_pix == 1'b1 &&
            dut.hc == 10'd0,
            "first non-scandoubled clock raises CE without raster advance"
        );

        tick();

        check(
            ce_pix == 1'b0 &&
            dut.hc == 10'd1,
            "second non-scandoubled clock advances one raster pixel"
        );

        scandouble = 1'b1;
        tick();

        check(
            ce_pix == 1'b1 &&
            dut.hc == 10'd2,
            "scandoubled mode advances raster every system clock"
        );

        tick();

        check(
            ce_pix == 1'b1 &&
            dut.hc == 10'd3,
            "scandoubled CE remains asserted continuously"
        );

        // ====================================================
        // Horizontal timing
        // ====================================================

        dut.hc = 10'd319;
        #1;

        check(
            !HBlank,
            "horizontal pixel 319 remains active"
        );

        dut.hc = 10'd320;
        #1;

        check(
            HBlank,
            "horizontal blank begins at count 320"
        );

        dut.hc = 10'd543;
        #1;

        check(
            !HSync,
            "HSync is inactive immediately before count 544"
        );

        dut.hc = 10'd544;
        #1;

        check(
            HSync,
            "HSync asserts at count 544"
        );

        dut.hc = 10'd589;
        #1;

        check(
            HSync,
            "HSync remains asserted through count 589"
        );

        dut.hc = 10'd590;
        #1;

        check(
            !HSync,
            "HSync deasserts at count 590"
        );

        // ====================================================
        // NTSC vertical timing
        // ====================================================

        pal = 1'b0;
        scandouble = 1'b0;

        dut.vc = 10'd239;
        #1;

        check(
            !VBlank,
            "NTSC non-scandoubled line 239 remains active"
        );

        dut.vc = 10'd240;
        #1;

        check(
            VBlank,
            "NTSC non-scandoubled vertical blank begins at line 240"
        );

        dut.vc = 10'd244;
        #1;

        check(
            !VSync,
            "NTSC non-scandoubled VSync inactive before line 245"
        );

        dut.vc = 10'd245;
        #1;

        check(
            VSync,
            "NTSC non-scandoubled VSync asserts at line 245"
        );

        dut.vc = 10'd247;
        #1;

        check(
            VSync,
            "NTSC non-scandoubled VSync remains active through line 247"
        );

        dut.vc = 10'd248;
        #1;

        check(
            !VSync,
            "NTSC non-scandoubled VSync deasserts at line 248"
        );

        // ====================================================
        // PAL vertical timing
        // ====================================================

        pal = 1'b1;
        scandouble = 1'b0;

        dut.vc = 10'd239;
        #1;

        check(
            !VBlank,
            "PAL selected Jupiter line 239 remains active"
        );

        dut.vc = 10'd240;
        #1;

        check(
            VBlank,
            "PAL remaining raster is blank after Jupiter line 239"
        );

        dut.vc = 10'd304;
        #1;

        check(
            VSync,
            "PAL non-scandoubled VSync asserts at line 304"
        );

        dut.vc = 10'd307;
        #1;

        check(
            VSync,
            "PAL non-scandoubled VSync remains active through line 307"
        );

        dut.vc = 10'd308;
        #1;

        check(
            !VSync,
            "PAL non-scandoubled VSync deasserts at line 308"
        );

        // ====================================================
        // Scandoubled vertical timing
        // ====================================================

        pal = 1'b0;
        scandouble = 1'b1;

        dut.vc = 10'd479;
        #1;

        check(
            !VBlank,
            "scandoubled NTSC line 479 remains active"
        );

        dut.vc = 10'd480;
        #1;

        check(
            VBlank,
            "scandoubled NTSC vertical blank begins at line 480"
        );

        dut.vc = 10'd490;
        #1;

        check(
            VSync,
            "scandoubled NTSC VSync asserts at line 490"
        );

        dut.vc = 10'd496;
        #1;

        check(
            !VSync,
            "scandoubled NTSC VSync deasserts at line 496"
        );

        pal = 1'b1;

        dut.vc = 10'd609;
        #1;

        check(
            VSync,
            "scandoubled PAL VSync asserts at line 609"
        );

        dut.vc = 10'd617;
        #1;

        check(
            !VSync,
            "scandoubled PAL VSync deasserts at line 617"
        );

        // ====================================================
        // Horizontal/vertical wrap
        // ====================================================

        reset = 1'b1;
        tick();
        reset = 1'b0;

        pal = 1'b0;
        scandouble = 1'b1;

        dut.hc = 10'd637;
        dut.vc = 10'd523;

        tick();

        check(
            dut.hc == 10'd0 &&
            dut.vc == 10'd0,
            "scandoubled NTSC raster wraps after line 523"
        );

        pal = 1'b1;

        dut.hc = 10'd637;
        dut.vc = 10'd623;

        tick();

        check(
            dut.hc == 10'd0 &&
            dut.vc == 10'd0,
            "scandoubled PAL raster wraps after line 623"
        );

        // ====================================================
        // Shell remains safely disconnected from SDRAM
        // ====================================================

        sdram_ready = 1'b1;
        sdram_rdata = 32'hDEADBEEF;

        repeat (8)
            tick();

        check(
            !sdram_valid &&
            sdram_addr == 32'h00000000,
            "scanout shell never issues SDRAM traffic"
        );

        check(
            video_r == 8'h00 &&
            video_g == 8'h00 &&
            video_b == 8'h00,
            "scanout shell remains deterministic black"
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
                "M11B-2b video scanout shell regression failed"
            );

        $finish;
    end

endmodule
