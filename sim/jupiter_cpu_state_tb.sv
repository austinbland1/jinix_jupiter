`timescale 1ns/1ps

module jupiter_cpu_state_tb;

    reg clk   = 1'b0;
    reg reset = 1'b1;

    wire        mem_valid;
    wire        mem_write;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        halted;

    reg [31:0] mem_rdata = 32'h00000000;
    reg        mem_ready = 1'b0;

    integer checks = 0;
    integer failures = 0;

    always #5 clk = ~clk;

    jupiter_cpu dut
    (
        .clk       (clk),
        .reset     (reset),

        .mem_valid (mem_valid),
        .mem_write (mem_write),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),

        .mem_rdata (mem_rdata),
        .mem_ready (mem_ready),

        .halted    (halted)
    );

    task check;
        input condition;
        input [8*80-1:0] message;
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
        // Hold synchronous active-high reset for several rising edges.
        repeat (3) @(posedge clk);
        #1;

        check(dut.pc === 32'h00000000,
              "PC resets to 0x00000000");

        check(dut.regs[0] === 32'h00000000,
              "r0 resets to zero");

        check(dut.regs[1] === 32'h00000000,
              "r1 resets to zero");

        check(dut.regs[15] === 32'h00000000,
              "r15 resets to zero");

        check(dut.regs[31] === 32'h00000000,
              "r31 resets to zero");

        check(halted === 1'b0,
              "CPU leaves halted state on reset");

        check(mem_valid === 1'b0 &&
              mem_write === 1'b0 &&
              mem_addr  === 32'h00000000 &&
              mem_wdata === 32'h00000000 &&
              mem_wstrb === 4'b0000,
              "memory interface remains idle");

        // Release reset and confirm architectural state remains stable while
        // instruction execution has not yet been implemented.
        @(negedge clk);
        reset = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        check(dut.pc === 32'h00000000,
              "PC remains stable before fetch implementation");

        check(dut.regs[0] === 32'h00000000,
              "r0 remains hardwired to zero");

        check(halted === 1'b0,
              "CPU remains unhalted before execution implementation");

        if (failures == 0) begin
            $display("");
            $display("==============================");
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("==============================");
            $finish(0);
        end else begin
            $display("");
            $display("==============================");
            $display("RESULT: FAIL  (%0d failures)", failures);
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
