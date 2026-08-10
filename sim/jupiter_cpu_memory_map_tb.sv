`timescale 1ns/1ps

module jupiter_cpu_memory_map_tb;

    reg clk;
    reg reset;

    wire halted;

    integer checks;
    integer failures;
    integer cycles;

    integer ram_store_count;
    integer ram_load_count;
    integer mmio_store_count;
    integer mmio_load_count;
    integer unmapped_store_count;
    integer unmapped_load_count;

    reg bad_ram_selection;
    reg bad_mmio_selection;
    reg bad_unmapped_selection;

    jupiter_cpu_subsystem dut
    (
        .clk    (clk),
        .reset  (reset),
        .sdram_sz (16'h0000),
        .halted (halted)
    );

    always #5 clk = ~clk;

    function [31:0] enc_i;
        input [7:0]  opcode;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [13:0] imm14;
        begin
            enc_i = {opcode, rd, rs1, imm14};
        end
    endfunction

    function [31:0] enc_s;
        input [7:0]  opcode;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [13:0] imm14;
        begin
            enc_s = {opcode, rs2, rs1, imm14};
        end
    endfunction

    function [31:0] enc_n;
        input [7:0] opcode;
        begin
            enc_n = {opcode, 24'd0};
        end
    endfunction

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

    // Observe completed CPU data transactions at the actual interconnect
    // boundary. Instruction fetches do not use the data addresses below.
    always @(posedge clk) begin
        if (!reset && dut.cpu_mem_valid && dut.cpu_mem_ready) begin

            if (dut.cpu_mem_addr == 32'h00000100) begin
                if (!(dut.ram_valid && !dut.mmio_valid))
                    bad_ram_selection <= 1'b1;

                if (dut.cpu_mem_write)
                    ram_store_count <= ram_store_count + 1;
                else
                    ram_load_count <= ram_load_count + 1;
            end

            if (dut.cpu_mem_addr == 32'h00001000) begin
                if (!(!dut.ram_valid && dut.mmio_valid))
                    bad_mmio_selection <= 1'b1;

                if (dut.cpu_mem_write)
                    mmio_store_count <= mmio_store_count + 1;
                else
                    mmio_load_count <= mmio_load_count + 1;
            end

            if (dut.cpu_mem_addr == 32'h00001004) begin
                if (dut.ram_valid || dut.mmio_valid)
                    bad_unmapped_selection <= 1'b1;

                if (dut.cpu_mem_write)
                    unmapped_store_count <= unmapped_store_count + 1;
                else
                    unmapped_load_count <= unmapped_load_count + 1;
            end
        end
    end

    initial begin
        clk      = 1'b0;
        reset    = 1'b1;

        checks   = 0;
        failures = 0;
        cycles   = 0;

        ram_store_count      = 0;
        ram_load_count       = 0;
        mmio_store_count     = 0;
        mmio_load_count      = 0;
        unmapped_store_count = 0;
        unmapped_load_count  = 0;

        bad_ram_selection      = 1'b0;
        bad_mmio_selection     = 1'b0;
        bad_unmapped_selection = 1'b0;

        /*
         * Deterministic Milestone 3 integration program:
         *
         * 00: ADDI r1, r0, 256
         * 04: ADDI r2, r0, 42
         * 08: STW  r2, 0(r1)       RAM[0x100] = 42
         * 0C: LDW  r3, 0(r1)       r3 = 42
         * 10: ADDI r4, r0, 4096    MMIO base = 0x1000
         * 14: STW  r3, 0(r4)       scratch = 42
         * 18: LDW  r5, 0(r4)       r5 = 42
         * 1C: ADDI r6, r4, 4       unmapped = 0x1004
         * 20: LDW  r7, 0(r6)       unmapped read -> 0
         * 24: ADDI r8, r0, 99
         * 28: STW  r8, 0(r6)       unmapped write -> ignored
         * 2C: LDW  r9, 0(r4)       scratch still 42
         * 30: HALT
         */

        dut.ram.memory_b0[0] = (enc_i(8'h10, 5'd1, 5'd0, 14'd256));
        dut.ram.memory_b1[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd256)) >> 8);
        dut.ram.memory_b2[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd256)) >> 16);
        dut.ram.memory_b3[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd256)) >> 24);
        dut.ram.memory_b0[1] = (enc_i(8'h10, 5'd2, 5'd0, 14'd42));
        dut.ram.memory_b1[1] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 8);
        dut.ram.memory_b2[1] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 16);
        dut.ram.memory_b3[1] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 24);
        dut.ram.memory_b0[2] = (enc_s(8'h21, 5'd2, 5'd1, 14'd0));
        dut.ram.memory_b1[2] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd0)) >> 8);
        dut.ram.memory_b2[2] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd0)) >> 16);
        dut.ram.memory_b3[2] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd0)) >> 24);
        dut.ram.memory_b0[3] = (enc_i(8'h20, 5'd3, 5'd1, 14'd0));
        dut.ram.memory_b1[3] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd0)) >> 8);
        dut.ram.memory_b2[3] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd0)) >> 16);
        dut.ram.memory_b3[3] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd0)) >> 24);
        dut.ram.memory_b0[4] = (enc_i(8'h10, 5'd4, 5'd0, 14'd4096));
        dut.ram.memory_b1[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd4096)) >> 8);
        dut.ram.memory_b2[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd4096)) >> 16);
        dut.ram.memory_b3[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd4096)) >> 24);
        dut.ram.memory_b0[5] = (enc_s(8'h21, 5'd3, 5'd4, 14'd0));
        dut.ram.memory_b1[5] = ((enc_s(8'h21, 5'd3, 5'd4, 14'd0)) >> 8);
        dut.ram.memory_b2[5] = ((enc_s(8'h21, 5'd3, 5'd4, 14'd0)) >> 16);
        dut.ram.memory_b3[5] = ((enc_s(8'h21, 5'd3, 5'd4, 14'd0)) >> 24);
        dut.ram.memory_b0[6] = (enc_i(8'h20, 5'd5, 5'd4, 14'd0));
        dut.ram.memory_b1[6] = ((enc_i(8'h20, 5'd5, 5'd4, 14'd0)) >> 8);
        dut.ram.memory_b2[6] = ((enc_i(8'h20, 5'd5, 5'd4, 14'd0)) >> 16);
        dut.ram.memory_b3[6] = ((enc_i(8'h20, 5'd5, 5'd4, 14'd0)) >> 24);
        dut.ram.memory_b0[7] = (enc_i(8'h10, 5'd6, 5'd4, 14'd4));
        dut.ram.memory_b1[7] = ((enc_i(8'h10, 5'd6, 5'd4, 14'd4)) >> 8);
        dut.ram.memory_b2[7] = ((enc_i(8'h10, 5'd6, 5'd4, 14'd4)) >> 16);
        dut.ram.memory_b3[7] = ((enc_i(8'h10, 5'd6, 5'd4, 14'd4)) >> 24);
        dut.ram.memory_b0[8] = (enc_i(8'h20, 5'd7, 5'd6, 14'd0));
        dut.ram.memory_b1[8] = ((enc_i(8'h20, 5'd7, 5'd6, 14'd0)) >> 8);
        dut.ram.memory_b2[8] = ((enc_i(8'h20, 5'd7, 5'd6, 14'd0)) >> 16);
        dut.ram.memory_b3[8] = ((enc_i(8'h20, 5'd7, 5'd6, 14'd0)) >> 24);
        dut.ram.memory_b0[9] = (enc_i(8'h10, 5'd8, 5'd0, 14'd99));
        dut.ram.memory_b1[9] = ((enc_i(8'h10, 5'd8, 5'd0, 14'd99)) >> 8);
        dut.ram.memory_b2[9] = ((enc_i(8'h10, 5'd8, 5'd0, 14'd99)) >> 16);
        dut.ram.memory_b3[9] = ((enc_i(8'h10, 5'd8, 5'd0, 14'd99)) >> 24);
        dut.ram.memory_b0[10] = (enc_s(8'h21, 5'd8, 5'd6, 14'd0));
        dut.ram.memory_b1[10] = ((enc_s(8'h21, 5'd8, 5'd6, 14'd0)) >> 8);
        dut.ram.memory_b2[10] = ((enc_s(8'h21, 5'd8, 5'd6, 14'd0)) >> 16);
        dut.ram.memory_b3[10] = ((enc_s(8'h21, 5'd8, 5'd6, 14'd0)) >> 24);
        dut.ram.memory_b0[11] = (enc_i(8'h20, 5'd9, 5'd4, 14'd0));
        dut.ram.memory_b1[11] = ((enc_i(8'h20, 5'd9, 5'd4, 14'd0)) >> 8);
        dut.ram.memory_b2[11] = ((enc_i(8'h20, 5'd9, 5'd4, 14'd0)) >> 16);
        dut.ram.memory_b3[11] = ((enc_i(8'h20, 5'd9, 5'd4, 14'd0)) >> 24);
        dut.ram.memory_b0[12] = (enc_n(8'hFF));
        dut.ram.memory_b1[12] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[12] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[12] = ((enc_n(8'hFF)) >> 24);

        repeat (3) @(posedge clk);
        #1;

        check(!halted,
              "CPU begins M3 program from reset state");
        check(dut.scratch.scratch_reg == 32'h00000000,
              "MMIO scratch begins at documented reset value");

        @(negedge clk);
        reset = 1'b0;

        while (!halted && cycles < 300) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(halted,
              "integrated M3 program reaches HALT before timeout");
        check(dut.cpu.pc == 32'h00000030,
              "HALT occurs at expected final PC 0x30");

        check(({dut.ram.memory_b3[64], dut.ram.memory_b2[64], dut.ram.memory_b1[64], dut.ram.memory_b0[64]}) == 32'd42,
              "CPU store writes 42 to internal RAM address 0x100");
        check(dut.cpu.regs[3] == 32'd42,
              "CPU loads RAM value back into r3");

        check(dut.scratch.scratch_reg == 32'd42,
              "CPU writes 42 to MMIO scratch register");
        check(dut.cpu.regs[5] == 32'd42,
              "CPU reads MMIO scratch value into r5");

        check(dut.cpu.regs[7] == 32'h00000000,
              "unmapped CPU read returns deterministic zero");

        check(dut.cpu.regs[8] == 32'd99,
              "unmapped-write source register contains expected value");
        check(dut.scratch.scratch_reg == 32'd42,
              "unmapped write does not modify MMIO state");
        check(dut.cpu.regs[9] == 32'd42,
              "MMIO read after unmapped write still returns 42");

        check(ram_store_count == 1,
              "exactly one CPU data store reaches RAM");
        check(ram_load_count == 1,
              "exactly one CPU data load reaches RAM");

        check(mmio_store_count == 1,
              "exactly one CPU store reaches MMIO");
        check(mmio_load_count == 2,
              "exactly two CPU loads reach MMIO");

        check(unmapped_store_count == 1,
              "exactly one unmapped CPU write completes");
        check(unmapped_load_count == 1,
              "exactly one unmapped CPU read completes");

        check(!bad_ram_selection,
              "RAM data access selects RAM only");
        check(!bad_mmio_selection,
              "MMIO accesses select MMIO only");
        check(!bad_unmapped_selection,
              "unmapped accesses select no implemented target");

        check(!dut.cpu_mem_valid,
              "halted integrated CPU issues no transaction");
        check(dut.cpu.regs[0] == 32'h00000000,
              "r0 remains hardwired to zero");

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("PROGRAM_CYCLES: %0d", cycles);
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
