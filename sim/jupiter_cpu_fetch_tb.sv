`timescale 1ns/1ps

module jupiter_cpu_fetch_tb;

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
        input [8*96-1:0] message;
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
        // Synchronous active-high reset.
        repeat (3) @(posedge clk);
        #1;

        check(mem_valid === 1'b0,
              "no memory request is active while reset is asserted");

        check(dut.pc === 32'h00000000,
              "PC is zero during reset");

        // Release reset. The CPU should immediately present the fetch request.
        @(negedge clk);
        reset = 1'b0;
        #1;

        check(mem_valid === 1'b1,
              "instruction fetch becomes valid after reset");

        check(mem_write === 1'b0,
              "instruction fetch is a read");

        check(mem_addr === 32'h00000000,
              "first instruction fetch uses PC address zero");

        check(mem_wstrb === 4'b0000,
              "instruction fetch has no write strobes");

        // Stall the memory interface for several cycles. The documented
        // request must remain asserted and stable.
        repeat (3) begin
            @(posedge clk);
            #1;

            check(mem_valid === 1'b1 &&
                  mem_write === 1'b0 &&
                  mem_addr  === 32'h00000000 &&
                  mem_wstrb === 4'b0000,
                  "fetch request remains stable while mem_ready is low");
        end

        // Complete the transaction with a recognizable instruction word.
        @(negedge clk);
        mem_rdata = 32'h12345678;
        mem_ready = 1'b1;

        @(posedge clk);
        #1;

        check(dut.instruction_reg === 32'h12345678,
              "instruction word is captured on valid/ready completion");

        check(mem_valid === 1'b0,
              "fetch request deasserts after transaction completion");

        check(dut.state === dut.STATE_DECODE,
              "CPU enters decode state after instruction fetch");

        check(dut.pc === 32'h00000000,
              "PC remains at current instruction before execution exists");

        // Remove ready and prove no second transaction begins in the
        // intentionally-unimplemented decode state.
        @(negedge clk);
        mem_ready = 1'b0;
        mem_rdata = 32'h00000000;

        @(posedge clk);
        #1;

        check(mem_valid === 1'b0,
              "no second fetch begins before decode execution is implemented");

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
