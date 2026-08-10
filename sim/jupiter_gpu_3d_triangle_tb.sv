`timescale 1ns/1ps

module jupiter_gpu_3d_triangle_tb;

    localparam [1:0] RASTER_IDLE  = 2'd0;
    localparam [1:0] RASTER_SETUP = 2'd1;
    localparam [1:0] RASTER_SCAN  = 2'd2;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg start = 1'b0;

    reg [15:0] target_width  = 16'd0;
    reg [15:0] target_height = 16'd0;

    reg signed [31:0] v0_x = 32'sd0;
    reg signed [31:0] v0_y = 32'sd0;
    reg signed [31:0] v1_x = 32'sd0;
    reg signed [31:0] v1_y = 32'sd0;
    reg signed [31:0] v2_x = 32'sd0;
    reg signed [31:0] v2_y = 32'sd0;

    wire        busy;
    wire        done;
    wire        covered_valid;
    wire [15:0] covered_x;
    wire [15:0] covered_y;
    wire [31:0] coverage_count;
    wire [31:0] sample_count;

    integer checks = 0;
    integer failures = 0;

    integer observed_events = 0;
    integer observed_out_of_range = 0;
    integer watchdog = 0;

    reg [63:0] observed_bitmap = 64'd0;
    reg [63:0] bitmap_a = 64'd0;
    reg [63:0] bitmap_b = 64'd0;

    reg [31:0] count_a = 32'd0;
    reg [31:0] count_b = 32'd0;

    jupiter_gpu_3d_raster dut
    (
        .clk             (clk),
        .reset           (reset),

        .start           (start),

        .target_width    (target_width),
        .target_height   (target_height),

        .v0_x            (v0_x),
        .v0_y            (v0_y),
        .v0_z            (16'h0000),
        .v1_x            (v1_x),
        .v1_y            (v1_y),
        .v1_z            (16'h0000),
        .v2_x            (v2_x),
        .v2_y            (v2_y),
        .v2_z            (16'h0000),

        .busy            (busy),
        .done            (done),

        .covered_ready   (1'b1),
        .covered_valid   (covered_valid),
        .covered_x       (covered_x),
        .covered_y       (covered_y),
        .covered_z       (),

        .coverage_count  (coverage_count),
        .sample_count    (sample_count)
    );

    always #5 clk = ~clk;

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

    task launch;
        input [15:0] width;
        input [15:0] height;

        input signed [31:0] x0;
        input signed [31:0] y0;
        input signed [31:0] x1;
        input signed [31:0] y1;
        input signed [31:0] x2;
        input signed [31:0] y2;

        begin
            @(negedge clk);

            target_width  = width;
            target_height = height;

            v0_x = x0;
            v0_y = y0;
            v1_x = x1;
            v1_y = y1;
            v2_x = x2;
            v2_y = y2;

            observed_events = 0;
            observed_out_of_range = 0;
            observed_bitmap = 64'd0;

            start = 1'b1;

            @(posedge clk);
            #1;

            start = 1'b0;

            check(
                busy &&
                !done &&
                dut.raster_state == RASTER_SETUP,
                "accepted raster START enters setup state"
            );
        end
    endtask

    task collect_until_done;
        begin
            watchdog = 0;

            while (!done && (watchdog < 200)) begin
                @(posedge clk);
                #1;

                if (covered_valid) begin
                    observed_events =
                        observed_events + 1;

                    if (
                        (covered_x >= target_width) ||
                        (covered_y >= target_height)
                    ) begin
                        observed_out_of_range =
                            observed_out_of_range + 1;
                    end

                    if (
                        (covered_x < 16'd8) &&
                        (covered_y < 16'd8)
                    ) begin
                        observed_bitmap[
                            (covered_y * 8) + covered_x
                        ] = 1'b1;
                    end
                end

                watchdog = watchdog + 1;
            end

            check(
                done,
                "raster command completes before watchdog"
            );

            check(
                !busy &&
                dut.raster_state == RASTER_IDLE,
                "completed raster command returns idle"
            );

            check(
                observed_out_of_range == 0,
                "all covered samples stay inside target"
            );

            check(
                coverage_count == observed_events,
                "coverage counter matches emitted sample events"
            );
        end
    endtask

    initial begin

        repeat (2)
            @(posedge clk);

        #1;

        check(
            !busy &&
            !done &&
            !covered_valid &&
            coverage_count == 32'd0 &&
            sample_count == 32'd0 &&
            dut.raster_state == RASTER_IDLE,
            "reset clears raster state and counters"
        );

        @(negedge clk);
        reset = 1'b0;

        // ----------------------------------------------------
        // Reference triangle with no pixel-center edge ties.
        //
        // Vertices:
        //   (0.25, 0.25)
        //   (3.25, 0.25)
        //   (0.25, 3.25)
        //
        // Expected covered pixels:
        //   y=0: x=0,1,2
        //   y=1: x=0,1
        //   y=2: x=0
        // ----------------------------------------------------

        launch(
            16'd4,
            16'd4,

            32'sh00004000,
            32'sh00004000,

            32'sh00034000,
            32'sh00004000,

            32'sh00004000,
            32'sh00034000
        );

        collect_until_done();

        check(
            coverage_count == 32'd6,
            "reference triangle covers exactly six pixels"
        );

        check(
            sample_count == 32'd16,
            "reference triangle scans clipped 4x4 bounding box"
        );

        check(
            observed_bitmap == 64'h0000000000010307,
            "reference coverage bitmap matches deterministic pixel centers"
        );

        check(
            dut.scan_min_x == 16'd0 &&
            dut.scan_min_y == 16'd0 &&
            dut.scan_max_x == 16'd3 &&
            dut.scan_max_y == 16'd3,
            "reference bounding box matches expected integer limits"
        );

        // ----------------------------------------------------
        // Shared diagonal, triangle A.
        //
        // Square is split along (0,0) -> (2,2).
        // The top-left rule must assign exact diagonal samples to
        // exactly one of the two triangles.
        // ----------------------------------------------------

        launch(
            16'd2,
            16'd2,

            32'sh00000000,
            32'sh00000000,

            32'sh00020000,
            32'sh00000000,

            32'sh00020000,
            32'sh00020000
        );

        collect_until_done();

        bitmap_a = observed_bitmap;
        count_a = coverage_count;

        check(
            count_a == 32'd1,
            "shared-edge triangle A owns one square sample"
        );

        check(
            bitmap_a == 64'h0000000000000002,
            "triangle A owns the deterministic side of the diagonal"
        );

        check(
            sample_count == 32'd4,
            "triangle A scans exactly the clipped 2x2 square"
        );

        // ----------------------------------------------------
        // Shared diagonal, triangle B.
        // ----------------------------------------------------

        launch(
            16'd2,
            16'd2,

            32'sh00000000,
            32'sh00000000,

            32'sh00020000,
            32'sh00020000,

            32'sh00000000,
            32'sh00020000
        );

        collect_until_done();

        bitmap_b = observed_bitmap;
        count_b = coverage_count;

        check(
            count_b == 32'd3,
            "shared-edge triangle B owns three square samples"
        );

        check(
            bitmap_b == 64'h0000000000000301,
            "triangle B owns the complementary diagonal samples"
        );

        check(
            (bitmap_a & bitmap_b) == 64'd0,
            "adjacent triangles never double-fill shared-edge samples"
        );

        check(
            (bitmap_a | bitmap_b) == 64'h0000000000000303,
            "adjacent triangles cover the entire 2x2 square without cracks"
        );

        check(
            (count_a + count_b) == 32'd4,
            "shared-edge ownership preserves exactly four square samples"
        );

        // ----------------------------------------------------
        // Clockwise triangle is culled normally.
        // ----------------------------------------------------

        launch(
            16'd4,
            16'd4,

            32'sh00000000,
            32'sh00000000,

            32'sh00000000,
            32'sh00020000,

            32'sh00020000,
            32'sh00000000
        );

        collect_until_done();

        check(
            coverage_count == 32'd0 &&
            sample_count == 32'd0,
            "clockwise triangle generates no samples and no pixels"
        );

        check(
            dut.triangle_area < 67'sd0,
            "clockwise reference has negative signed area"
        );

        // ----------------------------------------------------
        // Zero-area triangle is culled normally.
        // ----------------------------------------------------

        launch(
            16'd4,
            16'd4,

            32'sh00000000,
            32'sh00000000,

            32'sh00010000,
            32'sh00010000,

            32'sh00020000,
            32'sh00020000
        );

        collect_until_done();

        check(
            coverage_count == 32'd0 &&
            sample_count == 32'd0,
            "degenerate triangle generates no samples and no pixels"
        );

        check(
            dut.triangle_area == 67'sd0,
            "degenerate reference has zero signed area"
        );

        // ----------------------------------------------------
        // Bounding-box clipping against target.
        //
        // Raw vertex extent:
        //   x = -1.75 .. 2.25
        //   y =  0.25 .. 4.25
        //
        // Target is only 2x3, so scan box must become:
        //   x = 0 .. 1
        //   y = 0 .. 2
        // ----------------------------------------------------

        launch(
            16'd2,
            16'd3,

            32'shFFFE4000,
            32'sh00004000,

            32'sh00024000,
            32'sh00004000,

            32'shFFFE4000,
            32'sh00044000
        );

        collect_until_done();

        check(
            dut.scan_min_x == 16'd0 &&
            dut.scan_min_y == 16'd0 &&
            dut.scan_max_x == 16'd1 &&
            dut.scan_max_y == 16'd2,
            "negative and oversized bounds clip exactly to target"
        );

        check(
            sample_count == 32'd6,
            "clipped triangle scans exactly six target samples"
        );

        check(
            coverage_count == 32'd3,
            "clipped triangle covers exactly three target pixels"
        );

        check(
            observed_bitmap == 64'h0000000000000103,
            "clipped coverage bitmap matches deterministic reference"
        );

        // ----------------------------------------------------
        // Completely offscreen triangle skips scan.
        // ----------------------------------------------------

        launch(
            16'd4,
            16'd4,

            -32'sh00030000,
            32'sh00000000,

            -32'sh00010000,
            32'sh00000000,

            -32'sh00030000,
            32'sh00020000
        );

        collect_until_done();

        check(
            coverage_count == 32'd0 &&
            sample_count == 32'd0,
            "fully offscreen triangle completes without scanning"
        );

        // ----------------------------------------------------
        // Zero-sized target also completes without scanning.
        // The integrated 3D command validator normally rejects this
        // before rasterization, but the standalone engine is bounded.
        // ----------------------------------------------------

        launch(
            16'd0,
            16'd4,

            32'sh00000000,
            32'sh00000000,

            32'sh00020000,
            32'sh00000000,

            32'sh00000000,
            32'sh00020000
        );

        collect_until_done();

        check(
            coverage_count == 32'd0 &&
            sample_count == 32'd0,
            "zero-width standalone target completes without scanning"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("REFERENCE_COVERED_PIXELS: 6");
            $display("SHARED_EDGE_TOTAL_PIXELS: 4");
            $display("CLIPPED_COVERED_PIXELS: 3");
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
