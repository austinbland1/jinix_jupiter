`timescale 1ns/1ps

module jupiter_cpu_gpu_mmio_tb;

    reg clk;
    reg reset;

    wire halted;

    integer checks;
    integer failures;
    integer cycles;

    integer gpu_store_count;
    integer gpu_load_count;
    reg bad_gpu_selection;

    jupiter_cpu_subsystem dut
    (
        .clk      (clk),
        .reset    (reset),
        .sdram_sz (16'h0000),
        .halted   (halted)
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
        input [8*120-1:0] message;
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

    always @(posedge clk) begin
        if (!reset &&
            dut.cpu_mem_valid &&
            dut.cpu_mem_ready &&
            dut.cpu_mem_addr >= 32'h00001100 &&
            dut.cpu_mem_addr <= 32'h000011FF) begin

            if (!(dut.gpu_valid &&
                  !dut.ram_valid &&
                  !dut.mmio_valid &&
                  !dut.sdram_valid))
                bad_gpu_selection <= 1'b1;

            if (dut.cpu_mem_write)
                gpu_store_count <= gpu_store_count + 1;
            else
                gpu_load_count <= gpu_load_count + 1;
        end
    end

    initial begin
        clk      = 1'b0;
        reset    = 1'b1;

        checks   = 0;
        failures = 0;
        cycles   = 0;

        gpu_store_count  = 0;
        gpu_load_count   = 0;
        bad_gpu_selection = 1'b0;

        /*
         * Deterministic M5B-2 CPU -> GPU-MMIO program:
         *
         * 00: ADDI r1, r0, 4352    GPU base = 0x1100
         * 04: ADDI r2, r0, 42
         * 08: STW  r2, 8(r1)       TILEMAP_BASE = 42
         * 0C: LDW  r3, 8(r1)       r3 = 42
         * 10: ADDI r4, r0, 1
         * 14: STW  r4, 0(r1)       CONTROL.START
         *                           MAP_SIZE is reset-zero, so operation
         *                           completes immediately without memory
         * 18: LDW  r5, 4(r1)       STATUS = DONE = 2
         * 1C: LDW  r6, 32(r1)      reserved GPU offset -> 0
         * 20: HALT
         */

        dut.ram.memory_b0[0] = (enc_i(8'h10, 5'd1, 5'd0, 14'd4352));
        dut.ram.memory_b1[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4352)) >> 8);
        dut.ram.memory_b2[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4352)) >> 16);
        dut.ram.memory_b3[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4352)) >> 24);
        dut.ram.memory_b0[1] = (enc_i(8'h10, 5'd2, 5'd0, 14'd42));
        dut.ram.memory_b1[1] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 8);
        dut.ram.memory_b2[1] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 16);
        dut.ram.memory_b3[1] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 24);
        dut.ram.memory_b0[2] = (enc_s(8'h21, 5'd2, 5'd1, 14'd8));
        dut.ram.memory_b1[2] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd8)) >> 8);
        dut.ram.memory_b2[2] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd8)) >> 16);
        dut.ram.memory_b3[2] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd8)) >> 24);
        dut.ram.memory_b0[3] = (enc_i(8'h20, 5'd3, 5'd1, 14'd8));
        dut.ram.memory_b1[3] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd8)) >> 8);
        dut.ram.memory_b2[3] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd8)) >> 16);
        dut.ram.memory_b3[3] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd8)) >> 24);
        dut.ram.memory_b0[4] = (enc_i(8'h10, 5'd4, 5'd0, 14'd1));
        dut.ram.memory_b1[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd1)) >> 8);
        dut.ram.memory_b2[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd1)) >> 16);
        dut.ram.memory_b3[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd1)) >> 24);
        dut.ram.memory_b0[5] = (enc_s(8'h21, 5'd4, 5'd1, 14'd0));
        dut.ram.memory_b1[5] = ((enc_s(8'h21, 5'd4, 5'd1, 14'd0)) >> 8);
        dut.ram.memory_b2[5] = ((enc_s(8'h21, 5'd4, 5'd1, 14'd0)) >> 16);
        dut.ram.memory_b3[5] = ((enc_s(8'h21, 5'd4, 5'd1, 14'd0)) >> 24);
        dut.ram.memory_b0[6] = (enc_i(8'h20, 5'd5, 5'd1, 14'd4));
        dut.ram.memory_b1[6] = ((enc_i(8'h20, 5'd5, 5'd1, 14'd4)) >> 8);
        dut.ram.memory_b2[6] = ((enc_i(8'h20, 5'd5, 5'd1, 14'd4)) >> 16);
        dut.ram.memory_b3[6] = ((enc_i(8'h20, 5'd5, 5'd1, 14'd4)) >> 24);
        dut.ram.memory_b0[7] = (enc_i(8'h20, 5'd6, 5'd1, 14'd32));
        dut.ram.memory_b1[7] = ((enc_i(8'h20, 5'd6, 5'd1, 14'd32)) >> 8);
        dut.ram.memory_b2[7] = ((enc_i(8'h20, 5'd6, 5'd1, 14'd32)) >> 16);
        dut.ram.memory_b3[7] = ((enc_i(8'h20, 5'd6, 5'd1, 14'd32)) >> 24);
        dut.ram.memory_b0[8] = (enc_n(8'hFF));
        dut.ram.memory_b1[8] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[8] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[8] = ((enc_n(8'hFF)) >> 24);

        repeat (3) @(posedge clk);
        #1;

        check(!halted,
              "CPU begins GPU-MMIO integration program from reset state");
        check(dut.gpu.tilemap_base_reg == 32'h00000000,
              "GPU TILEMAP_BASE begins at reset value");
        check(dut.gpu.busy == 1'b0 && dut.gpu.done == 1'b0,
              "GPU status begins idle and not done");
        check(dut.scratch.scratch_reg == 32'h00000000,
              "scratch MMIO begins unchanged");

        @(negedge clk);
        reset = 1'b0;

        while (!halted && cycles < 300) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(halted,
              "CPU reaches HALT before GPU-MMIO test timeout");
        check(dut.cpu.pc == 32'h00000020,
              "HALT occurs at expected final PC 0x20");

        check(dut.cpu.regs[1] == 32'h00001100,
              "CPU constructs GPU MMIO base address");
        check(dut.gpu.tilemap_base_reg == 32'd42,
              "CPU store reaches GPU TILEMAP_BASE");
        check(dut.cpu.regs[3] == 32'd42,
              "CPU reads GPU TILEMAP_BASE back");

        check(dut.cpu.regs[5] == 32'h00000002,
              "CPU reads DONE status after zero-dimension start");
        check(dut.gpu.busy == 1'b0 && dut.gpu.done == 1'b1,
              "zero-dimension CPU start leaves GPU done and not busy");

        check(dut.cpu.regs[6] == 32'h00000000,
              "reserved GPU MMIO offset returns deterministic zero");

        check(gpu_store_count == 2,
              "exactly two CPU stores complete in GPU MMIO");
        check(gpu_load_count == 3,
              "exactly three CPU loads complete in GPU MMIO");
        check(!bad_gpu_selection,
              "CPU GPU-MMIO accesses select only the GPU target");

        check(dut.scratch.scratch_reg == 32'h00000000,
              "GPU MMIO accesses do not modify scratch MMIO");
        check(!dut.cpu_mem_valid,
              "halted CPU issues no further memory transaction");
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
