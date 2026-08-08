//============================================================================
//
//  jupiter_core_tb — Deterministic smoke-test for Milestone 1A
//
//  Verifies:
//    1. reset places the skeleton in its documented initial state
//    2. after reset is released, deterministic state/output changes occur
//    3. expected state/output is reached after a known number of clock cycles
//
//  Clock: TESTCLK = 10 ns period (100 MHz testbench clock)
//         This is NOT a final Jupiter hardware clock specification.
//
//============================================================================

`timescale 1ns / 1ps

module jupiter_core_tb;

    //--- Testbench clock -------------------------------------------
    localparam CLK_PERIOD = 10;       // 10 ns → 100 MHz testbench clock

    reg TESTCLK;
    reg RESET;

    wire [7:0] heartbeat;
    wire [3:0] tick_cnt;
    wire       done_pulse;

    int pass_count;
    int fail_count;

    // Instantiate Jupiter skeleton
    jupiter_core dut
    (
        .clk(TESTCLK),
        .reset(RESET),
        .heartbeat(heartbeat),
        .tick_cnt(tick_cnt),
        .done_pulse(done_pulse)
    );

    //--- Clock generation -------------------------------------------
    initial begin
        TESTCLK = 0;
        forever #((CLK_PERIOD/2)) TESTCLK = ~TESTCLK;
    end

    //--- Main test sequence -----------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;
        RESET      = 1'b1;

        // Hold RESET for at least 3 positive clock edges while DUT asserts reset
        wait_tick(3);

        // Release RESET on a negative clock edge (avoids race with DUT's posedge)
        @(negedge TESTCLK);
        RESET = 1'b0;

        // Cycle 1: heartbeat should be ~8'h00 → 8'hFF, tick_cnt should be 4'd1
        wait_tick(1);
        #1;   // allow DUT nonblocking assignments to complete before sampling

        if (heartbeat !== 8'hFF) begin
            $display("FAIL tick=%0d: heartbeat expected 8hFF got 8h%h", tick_cnt, heartbeat);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS tick=%0d: heartbeat == 8hFF (initial 8h00 toggled)", tick_cnt);
            pass_count = pass_count + 1;
        end

        if (tick_cnt !== 4'd1) begin
            $display("FAIL tick_cnt at cycle 1: expected 4'd1 got 4'h%0h", tick_cnt);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS tick_cnt == 4'd1 after 1 cycle post-reset");
            pass_count = pass_count + 1;
        end

        // Cycle 3 (tick_cnt should be 4'd3): verify known state at a known point
        wait_tick(2);
        #1;   // allow DUT nonblocking assignments to complete before sampling

        if (heartbeat !== 8'hFF) begin          // FF → 00 after cycle-2 toggle, then back to FF on cycle-3
            $display("FAIL tick=%0d: heartbeat expected 8hFF got 8h%h", tick_cnt, heartbeat);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS tick=%0d: heartbeat == 8hFF (FF → 00 in cycle-2, FF in cycle-3)", tick_cnt);
            pass_count = pass_count + 1;
        end

        if (tick_cnt !== 4'd3) begin
            $display("FAIL tick_cnt at cycle 3: expected 4'd3 got 4'h%0h", tick_cnt);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS tick_cnt == 4'd3 after 3 cycles post-reset");
            pass_count = pass_count + 1;
        end

        // Wait until wrap: tick_cnt should reach 4'd15 then done_pulse on cycle 16
        wait_tick(12);                          // now at cycle 15 total post-reset
        #1;   // allow DUT nonblocking assignments to complete before sampling

        if (tick_cnt !== 4'd15) begin
            $display("FAIL tick_cnt at cycle 15: expected 4'd15 got 4'h%0h", tick_cnt);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS tick_cnt == 4'd15 after 15 cycles (near wrap)");
            pass_count = pass_count + 1;
        end

        wait_tick(1);                           // cycle 16 → done_pulse asserted, counter wraps to 0
        #1;   // allow DUT nonblocking assignments to complete before sampling

        if (done_pulse !== 1'b1) begin
            $display("FAIL done_pulse at tick 4'd15+1: expected 1h1 got 1h%0h", done_pulse);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS done_pulse == 1 after 15 counts");
            pass_count = pass_count + 1;
        end

        if (tick_cnt !== 4'd0) begin
            $display("FAIL tick_cnt at cycle 16: expected 4'd0 got 4'h%0h", tick_cnt);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS tick_cnt == 4'd0 after 16 cycles (wraps to zero)");
            pass_count = pass_count + 1;
        end

        //--- Summary --------------------------------------------------
        $display("");
        $display("==============================");
        if (fail_count > 0) begin
            $display("RESULT: FAIL");
            $fatal(1, "Jupiter core smoke test failed");
        end else begin
            $display("RESULT: PASS  (%0d checks)", pass_count);
            $display("==============================");
            $finish(0);          // zero → exit code 0
        end
    end

    //--- Helper: wait N positive clock edges ------------------------
    task automatic wait_tick;
        input int n;
        begin
            repeat (n) @(posedge TESTCLK);
        end
    endtask

endmodule
