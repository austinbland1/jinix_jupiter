`timescale 1ns/1ps

module jupiter_gpu_3d_perspective_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg start = 1'b0;

    reg covered_ready = 1'b0;

    wire        busy;
    wire        done;

    wire        covered_valid;
    wire [15:0] covered_x;
    wire [15:0] covered_y;
    wire [15:0] covered_z;

    wire signed [31:0] covered_u_over_w;
    wire signed [31:0] covered_v_over_w;
    wire        [31:0] covered_one_over_w;

    wire signed [63:0] covered_u_q16;
    wire signed [63:0] covered_v_q16;

    wire [31:0] coverage_count;
    wire [31:0] sample_count;

    integer checks = 0;
    integer failures = 0;
    integer watchdog = 0;
    integer stalled_hold_cycles = 0;
    integer i;

    reg [15:0] expected_x [0:5];
    reg [15:0] expected_y [0:5];

    reg signed [31:0] expected_u_over_w [0:5];
    reg signed [31:0] expected_v_over_w [0:5];
    reg        [31:0] expected_one_over_w [0:5];

    reg signed [63:0] expected_u_q16 [0:5];
    reg signed [63:0] expected_v_q16 [0:5];

    reg [15:0] held_x;
    reg [15:0] held_y;
    reg [15:0] held_z;

    reg signed [31:0] held_u_over_w;
    reg signed [31:0] held_v_over_w;
    reg        [31:0] held_one_over_w;

    reg signed [63:0] held_u_q16;
    reg signed [63:0] held_v_q16;

    jupiter_gpu_3d_raster dut
    (
        .clk            (clk),
        .reset          (reset),

        .start          (start),

        .target_width   (16'd4),
        .target_height  (16'd4),

        // Reference geometry:
        // (0.25,0.25), (3.25,0.25), (0.25,3.25)
        //
        // Perspective attributes correspond to:
        //
        // v0: U=0, V=0, W=1
        //     U/W=0,    V/W=0,    1/W=1
        //
        // v1: U=3, V=0, W=2
        //     U/W=1.5,  V/W=0,    1/W=0.5
        //
        // v2: U=0, V=3, W=4
        //     U/W=0,    V/W=0.75, 1/W=0.25

        .v0_x           (32'sh00004000),
        .v0_y           (32'sh00004000),
        .v0_z           (16'h4000),
        .v0_u_over_w    (32'sh00000000),
        .v0_v_over_w    (32'sh00000000),
        .v0_one_over_w  (32'h00010000),

        .v1_x           (32'sh00034000),
        .v1_y           (32'sh00004000),
        .v1_z           (16'h4000),
        .v1_u_over_w    (32'sh00018000),
        .v1_v_over_w    (32'sh00000000),
        .v1_one_over_w  (32'h00008000),

        .v2_x           (32'sh00004000),
        .v2_y           (32'sh00034000),
        .v2_z           (16'h4000),
        .v2_u_over_w    (32'sh00000000),
        .v2_v_over_w    (32'sh0000C000),
        .v2_one_over_w  (32'h00004000),

        .busy           (busy),
        .done           (done),

        .covered_ready      (covered_ready),
        .covered_valid      (covered_valid),
        .covered_x          (covered_x),
        .covered_y          (covered_y),
        .covered_z          (covered_z),
        .covered_u_over_w   (covered_u_over_w),
        .covered_v_over_w   (covered_v_over_w),
        .covered_one_over_w (covered_one_over_w),
        .covered_u_q16      (covered_u_q16),
        .covered_v_q16      (covered_v_q16),

        .coverage_count (coverage_count),
        .sample_count   (sample_count)
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

    initial begin

        expected_x[0] = 16'd0;
        expected_y[0] = 16'd0;
        expected_u_over_w[0] = 32'sh00002000;
        expected_v_over_w[0] = 32'sh00001000;
        expected_one_over_w[0] = 32'h0000E555;
        expected_u_q16[0] = 64'h00000000000023B8;
        expected_v_q16[0] = 64'h00000000000011DC;

        expected_x[1] = 16'd1;
        expected_y[1] = 16'd0;
        expected_u_over_w[1] = 32'sh0000A000;
        expected_v_over_w[1] = 32'sh00001000;
        expected_one_over_w[1] = 32'h0000BAAA;
        expected_u_q16[1] = 64'h000000000000DB6E;
        expected_v_q16[1] = 64'h00000000000015F1;

        expected_x[2] = 16'd2;
        expected_y[2] = 16'd0;
        expected_u_over_w[2] = 32'sh00012000;
        expected_v_over_w[2] = 32'sh00001000;
        expected_one_over_w[2] = 32'h00009000;
        expected_u_q16[2] = 64'h0000000000020000;
        expected_v_q16[2] = 64'h0000000000001C71;

        expected_x[3] = 16'd0;
        expected_y[3] = 16'd1;
        expected_u_over_w[3] = 32'sh00002000;
        expected_v_over_w[3] = 32'sh00005000;
        expected_one_over_w[3] = 32'h0000A555;
        expected_u_q16[3] = 64'h000000000000318C;
        expected_v_q16[3] = 64'h0000000000007BDF;

        expected_x[4] = 16'd1;
        expected_y[4] = 16'd1;
        expected_u_over_w[4] = 32'sh0000A000;
        expected_v_over_w[4] = 32'sh00005000;
        expected_one_over_w[4] = 32'h00007AAA;
        expected_u_q16[4] = 64'h0000000000014DEB;
        expected_v_q16[4] = 64'h000000000000A6F5;

        expected_x[5] = 16'd0;
        expected_y[5] = 16'd2;
        expected_u_over_w[5] = 32'sh00002000;
        expected_v_over_w[5] = 32'sh00009000;
        expected_one_over_w[5] = 32'h00006555;
        expected_u_q16[5] = 64'h00000000000050D7;
        expected_v_q16[5] = 64'h0000000000016BCB;

        repeat (2)
            @(posedge clk);

        #1;

        check(
            !busy &&
            !done &&
            !covered_valid &&
            covered_u_over_w == 32'sd0 &&
            covered_v_over_w == 32'sd0 &&
            covered_one_over_w == 32'd0 &&
            covered_u_q16 == 64'sd0 &&
            covered_v_q16 == 64'sd0,
            "reset clears perspective fragment payload"
        );

        @(negedge clk);
        reset = 1'b0;
        start = 1'b1;

        @(posedge clk);
        #1;

        start = 1'b0;

        check(
            busy &&
            !done,
            "perspective reference triangle starts normally"
        );

        for (i = 0; i < 6; i = i + 1) begin

            watchdog = 0;

            while (
                !covered_valid &&
                !done &&
                (watchdog < 32768)
            ) begin
                @(posedge clk);
                #1;
                watchdog = watchdog + 1;
            end

            check(
                watchdog < 32768 &&
                covered_valid,
                "expected perspective fragment arrives before watchdog"
            );

            check(
                covered_x == expected_x[i] &&
                covered_y == expected_y[i] &&
                covered_z == 16'h4000,
                "perspective fragment coordinate/depth matches reference"
            );

            check(
                covered_u_over_w ==
                    expected_u_over_w[i] &&
                covered_v_over_w ==
                    expected_v_over_w[i] &&
                covered_one_over_w ==
                    expected_one_over_w[i],
                "linearly interpolated U/W V/W and 1/W match exact reference"
            );

            check(
                covered_u_q16 ==
                    expected_u_q16[i] &&
                covered_v_q16 ==
                    expected_v_q16[i],
                "perspective reconstructed U/V match exact Q16.16 reference"
            );

            check(
                covered_one_over_w > 32'd0,
                "covered reference has positive interpolated 1/W"
            );

            if (i == 0) begin

                held_x = covered_x;
                held_y = covered_y;
                held_z = covered_z;

                held_u_over_w =
                    covered_u_over_w;

                held_v_over_w =
                    covered_v_over_w;

                held_one_over_w =
                    covered_one_over_w;

                held_u_q16 =
                    covered_u_q16;

                held_v_q16 =
                    covered_v_q16;

                repeat (3) begin
                    @(posedge clk);
                    #1;

                    stalled_hold_cycles =
                        stalled_hold_cycles + 1;

                    check(
                        covered_valid &&
                        covered_x == held_x &&
                        covered_y == held_y &&
                        covered_z == held_z &&
                        covered_u_over_w ==
                            held_u_over_w &&
                        covered_v_over_w ==
                            held_v_over_w &&
                        covered_one_over_w ==
                            held_one_over_w &&
                        covered_u_q16 ==
                            held_u_q16 &&
                        covered_v_q16 ==
                            held_v_q16,
                        "complete perspective payload remains stable under backpressure"
                    );
                end
            end

            @(negedge clk);

            covered_ready = 1'b1;

            #1;

            check(
                covered_valid &&
                covered_x == expected_x[i] &&
                covered_y == expected_y[i] &&
                covered_u_over_w ==
                    expected_u_over_w[i] &&
                covered_v_over_w ==
                    expected_v_over_w[i] &&
                covered_one_over_w ==
                    expected_one_over_w[i] &&
                covered_u_q16 ==
                    expected_u_q16[i] &&
                covered_v_q16 ==
                    expected_v_q16[i],
                "perspective payload remains exact through acceptance"
            );

            @(posedge clk);
            #1;

            covered_ready = 1'b0;
        end

        watchdog = 0;

        while (!done && (watchdog < 32768)) begin
            @(posedge clk);
            #1;
            watchdog = watchdog + 1;
        end

        check(
            done &&
            !busy,
            "perspective interpolation command completes normally"
        );

        check(
            coverage_count == 32'd6,
            "perspective interpolation preserves six covered pixels"
        );

        check(
            sample_count == 32'd16,
            "perspective interpolation preserves sixteen scanned samples"
        );

        check(
            stalled_hold_cycles == 3,
            "perspective payload survived exactly three explicit stall cycles"
        );

        // At the first pixel, ordinary affine interpolation of U and V
        // would both produce 0.25 = 0x00004000. The perspective-correct
        // references deliberately differ.
        check(
            expected_u_q16[0] != 64'h0000000000004000 &&
            expected_v_q16[0] != 64'h0000000000004000,
            "reference distinguishes perspective reconstruction from affine U/V"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("PERSPECTIVE_COVERED_PIXELS: 6");
            $display("PERSPECTIVE_STALLED_HOLD_CYCLES: 3");
            $display("PERSPECTIVE_FIRST_U_OVER_W: 0x00002000");
            $display("PERSPECTIVE_FIRST_V_OVER_W: 0x00001000");
            $display("PERSPECTIVE_FIRST_ONE_OVER_W: 0x0000e555");
            $display("PERSPECTIVE_FIRST_U_Q16: 0x000023b8");
            $display("PERSPECTIVE_FIRST_V_Q16: 0x000011dc");
            $display("PERSPECTIVE_LAST_U_Q16: 0x000050d7");
            $display("PERSPECTIVE_LAST_V_Q16: 0x00016bcb");
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
