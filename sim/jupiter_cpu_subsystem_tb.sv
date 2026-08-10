`timescale 1ns/1ps

module jupiter_cpu_subsystem_tb;

    reg  clk;
    reg  reset;

    wire halted;

    integer checks;
    integer failures;

    jupiter_cpu_subsystem dut
    (
        .clk    (clk),
        .reset  (reset),
        .sdram_sz (16'h0000),
        .halted (halted)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            checks = checks + 1;

            if (condition)
                $display("PASS: %0s", message);
            else begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    initial begin
        clk      = 1'b0;
        reset    = 1'b1;
        checks   = 0;
        failures = 0;

        // M3 simulation infrastructure may preload internal test RAM.
        // 0xFF000000 = HALT according to docs/ISA_SPEC.md.
        dut.ram.memory_b0[0] = (32'hFF000000);
        dut.ram.memory_b1[0] = ((32'hFF000000) >> 8);
        dut.ram.memory_b2[0] = ((32'hFF000000) >> 16);
        dut.ram.memory_b3[0] = ((32'hFF000000) >> 24);

        repeat (3) @(posedge clk);
        #1;

        check(!halted,
              "CPU is not halted while reset is asserted");
        check(dut.scratch.scratch_reg == 32'h00000000,
              "MMIO scratch register resets to zero");
        check(!dut.cpu_mem_valid,
              "CPU issues no memory request during reset");

        @(negedge clk);
        reset = 1'b0;
        #1;

        check(dut.cpu_mem_valid,
              "CPU begins instruction fetch after reset");
        check(!dut.cpu_mem_write,
              "instruction fetch is a read");
        check(dut.cpu_mem_addr == 32'h00000000,
              "first instruction fetch uses reset PC zero");
        check(dut.ram_valid,
              "interconnect routes address zero to internal RAM");
        check(!dut.mmio_valid,
              "instruction fetch does not select MMIO");
        check(dut.cpu_mem_ready,
              "RAM completion reaches CPU through interconnect");
        check(dut.cpu_mem_rdata == 32'hFF000000,
              "HALT instruction reaches CPU through RAM and interconnect");

        @(posedge clk);
        #1;

        check(dut.cpu.instruction_reg == 32'hFF000000,
              "CPU captures fetched HALT instruction");
        check(!dut.cpu_mem_valid,
              "fetch request ends while HALT is decoded");

        @(posedge clk);
        #1;

        check(halted,
              "CPU reaches halted state through integrated memory path");
        check(!dut.cpu_mem_valid,
              "halted CPU issues no further memory transaction");
        check(dut.scratch.scratch_reg == 32'h00000000,
              "instruction fetch leaves MMIO scratch register unchanged");

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("==============================");
            $finish;
        end else begin
            $display("RESULT: FAIL  (%0d failures / %0d checks)",
                     failures, checks);
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
