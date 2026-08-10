`timescale 1ns/1ps

module jupiter_cpu_dma_mmio_tb;

    reg clk;
    reg reset;

    wire halted;

    integer checks;
    integer failures;
    integer cycles;

    integer dma_store_count;
    integer dma_load_count;
    reg bad_dma_selection;

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
            enc_n = {opcode, 24'h000000};
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
            dut.cpu_mem_addr >= 32'h00001200 &&
            dut.cpu_mem_addr <= 32'h000012FF) begin

            if (!(dut.dma_valid &&
                  !dut.ram_valid &&
                  !dut.mmio_valid &&
                  !dut.gpu_valid &&
                  !dut.sdram_valid))
                bad_dma_selection <= 1'b1;

            if (dut.cpu_mem_write)
                dma_store_count <= dma_store_count + 1;
            else
                dma_load_count <= dma_load_count + 1;
        end
    end

    initial begin
        clk      = 1'b0;
        reset    = 1'b1;

        checks   = 0;
        failures = 0;
        cycles   = 0;

        dma_store_count = 0;
        dma_load_count = 0;
        bad_dma_selection = 1'b0;

        /*
         * Deterministic M6B-2 CPU -> DMA-MMIO program:
         *
         * 00: ADDI r1, r0, 4608    DMA base = 0x1200
         * 04: ADDI r2, r0, 42
         * 08: STW  r2, 8(r1)       SRC_BASE = 42
         * 0C: LDW  r3, 8(r1)       r3 = 42
         * 10: ADDI r4, r0, 84
         * 14: STW  r4, 12(r1)      DST_BASE = 84
         * 18: LDW  r5, 12(r1)      r5 = 84
         * 1C: STW  r0, 16(r1)      LENGTH_WORDS = 0
         * 20: LDW  r9, 16(r1)      r9 = 0
         * 24: ADDI r6, r0, 1
         * 28: STW  r6, 0(r1)       CONTROL.START
         *                           zero length completes immediately
         * 2C: LDW  r7, 4(r1)       STATUS = DONE = 2
         * 30: LDW  r8, 32(r1)      reserved DMA offset -> 0
         * 34: HALT
         */

        dut.ram.memory_b0[0] = (enc_i(8'h10, 5'd1, 5'd0, 14'd4608));
        dut.ram.memory_b1[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4608)) >> 8);
        dut.ram.memory_b2[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4608)) >> 16);
        dut.ram.memory_b3[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4608)) >> 24);
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
        dut.ram.memory_b0[4] = (enc_i(8'h10, 5'd4, 5'd0, 14'd84));
        dut.ram.memory_b1[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd84)) >> 8);
        dut.ram.memory_b2[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd84)) >> 16);
        dut.ram.memory_b3[4] = ((enc_i(8'h10, 5'd4, 5'd0, 14'd84)) >> 24);
        dut.ram.memory_b0[5] = (enc_s(8'h21, 5'd4, 5'd1, 14'd12));
        dut.ram.memory_b1[5] = ((enc_s(8'h21, 5'd4, 5'd1, 14'd12)) >> 8);
        dut.ram.memory_b2[5] = ((enc_s(8'h21, 5'd4, 5'd1, 14'd12)) >> 16);
        dut.ram.memory_b3[5] = ((enc_s(8'h21, 5'd4, 5'd1, 14'd12)) >> 24);
        dut.ram.memory_b0[6] = (enc_i(8'h20, 5'd5, 5'd1, 14'd12));
        dut.ram.memory_b1[6] = ((enc_i(8'h20, 5'd5, 5'd1, 14'd12)) >> 8);
        dut.ram.memory_b2[6] = ((enc_i(8'h20, 5'd5, 5'd1, 14'd12)) >> 16);
        dut.ram.memory_b3[6] = ((enc_i(8'h20, 5'd5, 5'd1, 14'd12)) >> 24);
        dut.ram.memory_b0[7] = (enc_s(8'h21, 5'd0, 5'd1, 14'd16));
        dut.ram.memory_b1[7] = ((enc_s(8'h21, 5'd0, 5'd1, 14'd16)) >> 8);
        dut.ram.memory_b2[7] = ((enc_s(8'h21, 5'd0, 5'd1, 14'd16)) >> 16);
        dut.ram.memory_b3[7] = ((enc_s(8'h21, 5'd0, 5'd1, 14'd16)) >> 24);
        dut.ram.memory_b0[8] = (enc_i(8'h20, 5'd9, 5'd1, 14'd16));
        dut.ram.memory_b1[8] = ((enc_i(8'h20, 5'd9, 5'd1, 14'd16)) >> 8);
        dut.ram.memory_b2[8] = ((enc_i(8'h20, 5'd9, 5'd1, 14'd16)) >> 16);
        dut.ram.memory_b3[8] = ((enc_i(8'h20, 5'd9, 5'd1, 14'd16)) >> 24);
        dut.ram.memory_b0[9] = (enc_i(8'h10, 5'd6, 5'd0, 14'd1));
        dut.ram.memory_b1[9] = ((enc_i(8'h10, 5'd6, 5'd0, 14'd1)) >> 8);
        dut.ram.memory_b2[9] = ((enc_i(8'h10, 5'd6, 5'd0, 14'd1)) >> 16);
        dut.ram.memory_b3[9] = ((enc_i(8'h10, 5'd6, 5'd0, 14'd1)) >> 24);
        dut.ram.memory_b0[10] = (enc_s(8'h21, 5'd6, 5'd1, 14'd0));
        dut.ram.memory_b1[10] = ((enc_s(8'h21, 5'd6, 5'd1, 14'd0)) >> 8);
        dut.ram.memory_b2[10] = ((enc_s(8'h21, 5'd6, 5'd1, 14'd0)) >> 16);
        dut.ram.memory_b3[10] = ((enc_s(8'h21, 5'd6, 5'd1, 14'd0)) >> 24);
        dut.ram.memory_b0[11] = (enc_i(8'h20, 5'd7, 5'd1, 14'd4));
        dut.ram.memory_b1[11] = ((enc_i(8'h20, 5'd7, 5'd1, 14'd4)) >> 8);
        dut.ram.memory_b2[11] = ((enc_i(8'h20, 5'd7, 5'd1, 14'd4)) >> 16);
        dut.ram.memory_b3[11] = ((enc_i(8'h20, 5'd7, 5'd1, 14'd4)) >> 24);
        dut.ram.memory_b0[12] = (enc_i(8'h20, 5'd8, 5'd1, 14'd32));
        dut.ram.memory_b1[12] = ((enc_i(8'h20, 5'd8, 5'd1, 14'd32)) >> 8);
        dut.ram.memory_b2[12] = ((enc_i(8'h20, 5'd8, 5'd1, 14'd32)) >> 16);
        dut.ram.memory_b3[12] = ((enc_i(8'h20, 5'd8, 5'd1, 14'd32)) >> 24);
        dut.ram.memory_b0[13] = (enc_n(8'hFF));
        dut.ram.memory_b1[13] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[13] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[13] = ((enc_n(8'hFF)) >> 24);

        repeat (3) @(posedge clk);
        #1;

        check(!halted,
              "CPU begins DMA-MMIO integration program from reset state");

        check(dut.dma.src_base_reg == 32'h00000000,
              "DMA SRC_BASE begins at reset value");

        check(dut.dma.dst_base_reg == 32'h00000000,
              "DMA DST_BASE begins at reset value");

        check(dut.dma.length_words_reg == 32'h00000000,
              "DMA LENGTH_WORDS begins at reset value");

        check(!dut.dma.busy && !dut.dma.done,
              "DMA status begins idle and not done");

        check(dut.scratch.scratch_reg == 32'h00000000,
              "scratch MMIO begins unchanged");

        check(dut.gpu.tilemap_base_reg == 32'h00000000,
              "GPU control state begins unchanged");

        @(negedge clk);
        reset = 1'b0;

        while (!halted && cycles < 500) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(halted,
              "CPU reaches HALT before DMA-MMIO test timeout");

        check(dut.cpu.pc == 32'h00000034,
              "HALT occurs at expected final PC 0x34");

        check(dut.cpu.regs[1] == 32'h00001200,
              "CPU constructs DMA MMIO base address");

        check(dut.dma.src_base_reg == 32'd42,
              "CPU store reaches DMA SRC_BASE");

        check(dut.cpu.regs[3] == 32'd42,
              "CPU reads DMA SRC_BASE back");

        check(dut.dma.dst_base_reg == 32'd84,
              "CPU store reaches DMA DST_BASE");

        check(dut.cpu.regs[5] == 32'd84,
              "CPU reads DMA DST_BASE back");

        check(dut.dma.length_words_reg == 32'h00000000,
              "CPU writes zero DMA LENGTH_WORDS");

        check(dut.cpu.regs[9] == 32'h00000000,
              "CPU reads DMA LENGTH_WORDS back");

        check(dut.dma.active_src_base == 32'd42 &&
              dut.dma.active_dst_base == 32'd84 &&
              dut.dma.active_length_words == 32'd0,
              "CPU START snapshots DMA configuration");

        check(!dut.dma.busy && dut.dma.done,
              "zero-length CPU START leaves DMA done and not busy");

        check(dut.cpu.regs[7] == 32'h00000002,
              "CPU reads DMA DONE status");

        check(dut.cpu.regs[8] == 32'h00000000,
              "reserved DMA MMIO offset returns deterministic zero");

        check(dma_store_count == 4,
              "exactly four CPU stores complete in DMA MMIO");

        check(dma_load_count == 5,
              "exactly five CPU loads complete in DMA MMIO");

        check(!bad_dma_selection,
              "CPU DMA-MMIO accesses select only the DMA target");

        check(dut.scratch.scratch_reg == 32'h00000000,
              "DMA MMIO accesses do not modify scratch MMIO");

        check(dut.gpu.tilemap_base_reg == 32'h00000000,
              "DMA MMIO accesses do not modify GPU control state");

        check(!dut.dma_sdram_valid &&
              !dut.dma_sdram_write &&
              dut.dma_sdram_addr == 32'h00000000 &&
              dut.dma_sdram_wdata == 32'h00000000 &&
              dut.dma_sdram_wstrb == 4'b0000,
              "M6B-2 DMA data master remains deterministically idle");

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
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
