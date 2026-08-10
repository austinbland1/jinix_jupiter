`timescale 1ns/1ps

module jupiter_gpu_2d3d_arbiter_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        gpu2d_valid = 1'b0;
    reg        gpu2d_write = 1'b0;
    reg [31:0] gpu2d_addr  = 32'h00000000;
    reg [31:0] gpu2d_wdata = 32'h00000000;
    reg  [3:0] gpu2d_wstrb = 4'b0000;

    wire [31:0] gpu2d_rdata;
    wire        gpu2d_ready;

    reg        gpu3d_valid = 1'b0;
    reg        gpu3d_write = 1'b0;
    reg [31:0] gpu3d_addr  = 32'h00000000;
    reg [31:0] gpu3d_wdata = 32'h00000000;
    reg  [3:0] gpu3d_wstrb = 4'b0000;

    wire [31:0] gpu3d_rdata;
    wire        gpu3d_ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;

    reg [31:0] sdram_rdata = 32'h00000000;
    reg        sdram_ready = 1'b0;

    integer checks = 0;
    integer failures = 0;

    jupiter_gpu_2d3d_arbiter dut
    (
        .clk          (clk),
        .reset        (reset),

        .gpu2d_valid  (gpu2d_valid),
        .gpu2d_write  (gpu2d_write),
        .gpu2d_addr   (gpu2d_addr),
        .gpu2d_wdata  (gpu2d_wdata),
        .gpu2d_wstrb  (gpu2d_wstrb),
        .gpu2d_rdata  (gpu2d_rdata),
        .gpu2d_ready  (gpu2d_ready),

        .gpu3d_valid  (gpu3d_valid),
        .gpu3d_write  (gpu3d_write),
        .gpu3d_addr   (gpu3d_addr),
        .gpu3d_wdata  (gpu3d_wdata),
        .gpu3d_wstrb  (gpu3d_wstrb),
        .gpu3d_rdata  (gpu3d_rdata),
        .gpu3d_ready  (gpu3d_ready),

        .sdram_valid  (sdram_valid),
        .sdram_write  (sdram_write),
        .sdram_addr   (sdram_addr),
        .sdram_wdata  (sdram_wdata),
        .sdram_wstrb  (sdram_wstrb),
        .sdram_rdata  (sdram_rdata),
        .sdram_ready  (sdram_ready)
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

        repeat (2)
            @(posedge clk);

        #1;

        check(
            dut.grant_state == 2'd0 &&
            dut.last_contested_winner == 2'd2,
            "reset establishes idle state and 2D-first contested history"
        );

        check(
            !sdram_valid &&
            !gpu2d_ready &&
            !gpu3d_ready,
            "reset presents no shared transaction"
        );

        @(negedge clk);
        reset = 1'b0;

        // ----------------------------------------------------
        // Uncontested 2D request
        // ----------------------------------------------------

        gpu2d_valid = 1'b1;
        gpu2d_write = 1'b0;
        gpu2d_addr  = 32'h10001000;

        #1;

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10001000,
            "uncontested 2D request is selected immediately"
        );

        check(
            !gpu2d_ready &&
            !gpu3d_ready,
            "requester waits while SDRAM ready is low"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd1,
            "uncompleted 2D transaction holds 2D grant"
        );

        // A new 3D request cannot preempt the held 2D transaction.
        gpu3d_valid = 1'b1;
        gpu3d_write = 1'b1;
        gpu3d_addr  = 32'h10002000;
        gpu3d_wdata = 32'hAABBCCDD;
        gpu3d_wstrb = 4'b1111;

        #1;

        check(
            sdram_addr == 32'h10001000 &&
            !sdram_write,
            "3D cannot preempt held 2D transaction"
        );

        sdram_rdata = 32'h11223344;
        sdram_ready = 1'b1;

        #1;

        check(
            gpu2d_ready &&
            !gpu3d_ready &&
            gpu2d_rdata == 32'h11223344,
            "held 2D transaction alone receives completion"
        );

        @(posedge clk);
        #1;

        sdram_ready = 1'b0;
        gpu2d_valid = 1'b0;

        check(
            dut.grant_state == 2'd0,
            "completed 2D transaction releases grant"
        );

        // ----------------------------------------------------
        // Uncontested 3D request
        // ----------------------------------------------------

        #1;

        check(
            sdram_valid &&
            sdram_write &&
            sdram_addr == 32'h10002000 &&
            sdram_wdata == 32'hAABBCCDD &&
            sdram_wstrb == 4'b1111,
            "uncontested 3D request is selected immediately"
        );

        sdram_ready = 1'b1;

        #1;

        check(
            gpu3d_ready &&
            !gpu2d_ready,
            "uncontested 3D completion returns only to 3D"
        );

        @(posedge clk);
        #1;

        gpu3d_valid = 1'b0;
        sdram_ready = 1'b0;

        // ----------------------------------------------------
        // First contested arbitration: 2D wins after reset
        // ----------------------------------------------------

        gpu2d_valid = 1'b1;
        gpu2d_write = 1'b0;
        gpu2d_addr  = 32'h10003000;

        gpu3d_valid = 1'b1;
        gpu3d_write = 1'b0;
        gpu3d_addr  = 32'h10004000;

        #1;

        check(
            sdram_addr == 32'h10003000,
            "2D wins first contested arbitration"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd1 &&
            dut.grant_contested,
            "contested 2D grant is held until completion"
        );

        sdram_ready = 1'b1;
        sdram_rdata = 32'h22222222;

        #1;

        check(
            gpu2d_ready &&
            !gpu3d_ready,
            "2D receives first contested completion"
        );

        @(posedge clk);
        #1;

        sdram_ready = 1'b0;

        check(
            dut.last_contested_winner == 2'd1,
            "completed contested 2D transaction updates history"
        );

        // Both requests are still asserted. Next transaction must rotate 3D.
        #1;

        check(
            sdram_addr == 32'h10004000,
            "next contested arbitration rotates to 3D"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd2 &&
            dut.grant_contested,
            "contested 3D transaction is held"
        );

        sdram_ready = 1'b1;
        sdram_rdata = 32'h33333333;

        #1;

        check(
            gpu3d_ready &&
            !gpu2d_ready &&
            gpu3d_rdata == 32'h33333333,
            "3D receives rotated contested completion"
        );

        @(posedge clk);
        #1;

        sdram_ready = 1'b0;

        check(
            dut.last_contested_winner == 2'd2,
            "completed contested 3D transaction updates history"
        );

        #1;

        check(
            sdram_addr == 32'h10003000,
            "continued contention rotates back to 2D"
        );

        // Complete the pending 2D request immediately at the free point.
        sdram_ready = 1'b1;
        sdram_rdata = 32'h44444444;

        #1;

        check(
            gpu2d_ready &&
            gpu2d_rdata == 32'h44444444,
            "free-point contested 2D transaction completes correctly"
        );

        @(posedge clk);
        #1;

        gpu2d_valid = 1'b0;
        gpu3d_valid = 1'b0;
        sdram_ready = 1'b0;

        check(
            dut.grant_state == 2'd0,
            "arbiter returns idle after final completion"
        );

        // ----------------------------------------------------
        // An uncontested completion must not alter contested history.
        // ----------------------------------------------------

        gpu3d_valid = 1'b1;
        gpu3d_addr  = 32'h10005000;
        sdram_ready = 1'b1;

        #1;

        check(
            gpu3d_ready,
            "uncontested 3D request can complete immediately"
        );

        @(posedge clk);
        #1;

        gpu3d_valid = 1'b0;
        sdram_ready = 1'b0;

        check(
            dut.last_contested_winner == 2'd1,
            "uncontested completion does not alter contested history"
        );

        // The final contested completion above was 2D, so 3D now wins.
        gpu2d_valid = 1'b1;
        gpu2d_addr  = 32'h10006000;

        gpu3d_valid = 1'b1;
        gpu3d_addr  = 32'h10007000;

        #1;

        check(
            sdram_addr == 32'h10007000,
            "round-robin history survives uncontested traffic"
        );

        // ----------------------------------------------------
        // Reset suppresses all transactions immediately.
        // ----------------------------------------------------

        reset = 1'b1;

        #1;

        check(
            !sdram_valid &&
            !gpu2d_ready &&
            !gpu3d_ready,
            "reset suppresses active requester outputs"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd0 &&
            dut.last_contested_winner == 2'd2,
            "reset restores deterministic arbitration history"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
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
