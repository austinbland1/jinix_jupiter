`timescale 1ns/1ps

module jupiter_gpu_3d_depth_tb;

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
    wire [31:0] coverage_count;
    wire [31:0] sample_count;

    integer checks = 0;
    integer failures = 0;
    integer watchdog = 0;
    integer i;
    integer stalled_hold_cycles = 0;

    reg [15:0] expected_x [0:5];
    reg [15:0] expected_y [0:5];
    reg [15:0] expected_z [0:5];

    reg [15:0] held_x;
    reg [15:0] held_y;
    reg [15:0] held_z;

    jupiter_gpu_3d_raster dut
    (
        .clk            (clk),
        .reset          (reset),

        .start          (start),

        .target_width   (16'd4),
        .target_height  (16'd4),

        // Same six-pixel M10B-2 reference triangle:
        // (0.25,0.25), (3.25,0.25), (0.25,3.25)
        .v0_x           (32'sh00004000),
        .v0_y           (32'sh00004000),
        .v0_z           (16'h1000),

        .v1_x           (32'sh00034000),
        .v1_y           (32'sh00004000),
        .v1_z           (16'h4000),

        .v2_x           (32'sh00004000),
        .v2_y           (32'sh00034000),
        .v2_z           (16'h7000),

        .busy           (busy),
        .done           (done),

        .covered_ready  (covered_ready),
        .covered_valid  (covered_valid),
        .covered_x      (covered_x),
        .covered_y      (covered_y),
        .covered_z      (covered_z),

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
        expected_z[0] = 16'h1C00;

        expected_x[1] = 16'd1;
        expected_y[1] = 16'd0;
        expected_z[1] = 16'h2C00;

        expected_x[2] = 16'd2;
        expected_y[2] = 16'd0;
        expected_z[2] = 16'h3C00;

        expected_x[3] = 16'd0;
        expected_y[3] = 16'd1;
        expected_z[3] = 16'h3C00;

        expected_x[4] = 16'd1;
        expected_y[4] = 16'd1;
        expected_z[4] = 16'h4C00;

        expected_x[5] = 16'd0;
        expected_y[5] = 16'd2;
        expected_z[5] = 16'h5C00;

        repeat (2)
            @(posedge clk);

        #1;

        check(
            !busy &&
            !done &&
            !covered_valid &&
            covered_z == 16'h0000,
            "reset clears raster depth output"
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
            "depth-reference triangle starts normally"
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
                "expected covered fragment arrives before watchdog"
            );

            check(
                covered_x == expected_x[i] &&
                covered_y == expected_y[i],
                "depth fragment coordinate matches coverage reference"
            );

            check(
                covered_z == expected_z[i],
                "screen-linear U0.16 depth matches exact reference"
            );

            if (i == 0) begin
                held_x = covered_x;
                held_y = covered_y;
                held_z = covered_z;

                repeat (3) begin
                    @(posedge clk);
                    #1;

                    stalled_hold_cycles =
                        stalled_hold_cycles + 1;

                    check(
                        covered_valid &&
                        covered_x == held_x &&
                        covered_y == held_y &&
                        covered_z == held_z,
                        "covered X/Y/Z remain stable under backpressure"
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
                covered_z == expected_z[i],
                "covered depth remains exact through acceptance"
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
            "depth interpolation command completes normally"
        );

        check(
            coverage_count == 32'd6,
            "depth interpolation preserves six covered pixels"
        );

        check(
            sample_count == 32'd16,
            "depth interpolation preserves sixteen scanned samples"
        );

        check(
            stalled_hold_cycles == 3,
            "depth output survived exactly three explicit stall cycles"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("DEPTH_INTERPOLATED_PIXELS: 6");
            $display(
                "DEPTH_STALLED_HOLD_CYCLES: %0d",
                stalled_hold_cycles
            );
            $display("DEPTH_REFERENCE_FIRST: 0x1c00");
            $display("DEPTH_REFERENCE_LAST: 0x5c00");
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
