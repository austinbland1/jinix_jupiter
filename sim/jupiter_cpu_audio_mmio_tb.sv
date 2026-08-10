`timescale 1ns/1ps

module jupiter_cpu_audio_mmio_tb;

    reg clk;
    reg reset;

    wire halted;

    integer checks;
    integer failures;
    integer cycles;

    integer audio_store_count;
    integer audio_load_count;

    reg bad_audio_selection;


    jupiter_cpu_subsystem dut
    (
        .clk      (clk),
        .reset    (reset),
        .sdram_sz (16'h0000),
        .halted   (halted)
    );


    always #5 clk = ~clk;


    function [31:0] enc_i;
        input [7:0] opcode;
        input [4:0] rd;
        input [4:0] rs1;
        input [13:0] imm14;
        begin

            enc_i = {
                opcode,
                rd,
                rs1,
                imm14
            };

        end
    endfunction


    function [31:0] enc_s;
        input [7:0] opcode;
        input [4:0] rs2;
        input [4:0] rs1;
        input [13:0] imm14;
        begin

            enc_s = {
                opcode,
                rs2,
                rs1,
                imm14
            };

        end
    endfunction


    function [31:0] enc_n;
        input [7:0] opcode;
        begin

            enc_n = {
                opcode,
                24'h000000
            };

        end
    endfunction


    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin

            checks = checks + 1;

            if (condition)
                $display(
                    "PASS: %0s",
                    message
                );
            else begin

                failures = failures + 1;

                $display(
                    "FAIL: %0s",
                    message
                );

            end
        end
    endtask


    always @(posedge clk) begin

        if (
            !reset &&
            dut.cpu_mem_valid &&
            dut.cpu_mem_ready &&
            dut.cpu_mem_addr >= 32'h00001300 &&
            dut.cpu_mem_addr <= 32'h000013FF
        ) begin

            if (!(
                dut.audio_valid &&
                !dut.ram_valid &&
                !dut.mmio_valid &&
                !dut.gpu_valid &&
                !dut.dma_valid &&
                !dut.sdram_valid
            ))
                bad_audio_selection <=
                    1'b1;


            if (dut.cpu_mem_write)
                audio_store_count <=
                    audio_store_count + 1;
            else
                audio_load_count <=
                    audio_load_count + 1;

        end
    end


    initial begin

        clk = 1'b0;
        reset = 1'b1;

        checks = 0;
        failures = 0;
        cycles = 0;

        audio_store_count = 0;
        audio_load_count = 0;

        bad_audio_selection = 1'b0;


        /*
         * M7B-1 CPU/audio integration program:
         *
         * 00 ADDI r1,r0,4864    r1 = 0x1300
         * 04 ADDI r2,r0,5
         * 08 STW  r2,0(r1)      SAMPLE_ADDR = 5
         * 0C ADDI r3,r0,42
         * 10 STW  r3,4(r1)      SAMPLE_DATA = 42
         * 14 LDW  r4,4(r1)      r4 = 42
         * 18 ADDI r5,r0,7
         * 1C STW  r5,40(r1)     voice 0 BASE = 7
         * 20 LDW  r6,40(r1)     r6 = 7
         * 24 STW  r0,44(r1)     LENGTH = 0
         * 28 ADDI r7,r0,1
         * 2C STW  r7,32(r1)     START
         * 30 LDW  r8,36(r1)     STATUS = DONE
         * 34 LDW  r9,20(r1)     reserved = 0
         * 38 HALT
         */


        dut.ram.memory_b0[0] = (enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4864
            ));
        dut.ram.memory_b1[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4864
            )) >> 8);
        dut.ram.memory_b2[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4864
            )) >> 16);
        dut.ram.memory_b3[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4864
            )) >> 24);


        dut.ram.memory_b0[1] = (enc_i(
                8'h10,
                5'd2,
                5'd0,
                14'd5
            ));
        dut.ram.memory_b1[1] = ((enc_i(
                8'h10,
                5'd2,
                5'd0,
                14'd5
            )) >> 8);
        dut.ram.memory_b2[1] = ((enc_i(
                8'h10,
                5'd2,
                5'd0,
                14'd5
            )) >> 16);
        dut.ram.memory_b3[1] = ((enc_i(
                8'h10,
                5'd2,
                5'd0,
                14'd5
            )) >> 24);


        dut.ram.memory_b0[2] = (enc_s(
                8'h21,
                5'd2,
                5'd1,
                14'd0
            ));
        dut.ram.memory_b1[2] = ((enc_s(
                8'h21,
                5'd2,
                5'd1,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[2] = ((enc_s(
                8'h21,
                5'd2,
                5'd1,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[2] = ((enc_s(
                8'h21,
                5'd2,
                5'd1,
                14'd0
            )) >> 24);


        dut.ram.memory_b0[3] = (enc_i(
                8'h10,
                5'd3,
                5'd0,
                14'd42
            ));
        dut.ram.memory_b1[3] = ((enc_i(
                8'h10,
                5'd3,
                5'd0,
                14'd42
            )) >> 8);
        dut.ram.memory_b2[3] = ((enc_i(
                8'h10,
                5'd3,
                5'd0,
                14'd42
            )) >> 16);
        dut.ram.memory_b3[3] = ((enc_i(
                8'h10,
                5'd3,
                5'd0,
                14'd42
            )) >> 24);


        dut.ram.memory_b0[4] = (enc_s(
                8'h21,
                5'd3,
                5'd1,
                14'd4
            ));
        dut.ram.memory_b1[4] = ((enc_s(
                8'h21,
                5'd3,
                5'd1,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[4] = ((enc_s(
                8'h21,
                5'd3,
                5'd1,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[4] = ((enc_s(
                8'h21,
                5'd3,
                5'd1,
                14'd4
            )) >> 24);


        dut.ram.memory_b0[5] = (enc_i(
                8'h20,
                5'd4,
                5'd1,
                14'd4
            ));
        dut.ram.memory_b1[5] = ((enc_i(
                8'h20,
                5'd4,
                5'd1,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[5] = ((enc_i(
                8'h20,
                5'd4,
                5'd1,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[5] = ((enc_i(
                8'h20,
                5'd4,
                5'd1,
                14'd4
            )) >> 24);


        dut.ram.memory_b0[6] = (enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd7
            ));
        dut.ram.memory_b1[6] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd7
            )) >> 8);
        dut.ram.memory_b2[6] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd7
            )) >> 16);
        dut.ram.memory_b3[6] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd7
            )) >> 24);


        dut.ram.memory_b0[7] = (enc_s(
                8'h21,
                5'd5,
                5'd1,
                14'd40
            ));
        dut.ram.memory_b1[7] = ((enc_s(
                8'h21,
                5'd5,
                5'd1,
                14'd40
            )) >> 8);
        dut.ram.memory_b2[7] = ((enc_s(
                8'h21,
                5'd5,
                5'd1,
                14'd40
            )) >> 16);
        dut.ram.memory_b3[7] = ((enc_s(
                8'h21,
                5'd5,
                5'd1,
                14'd40
            )) >> 24);


        dut.ram.memory_b0[8] = (enc_i(
                8'h20,
                5'd6,
                5'd1,
                14'd40
            ));
        dut.ram.memory_b1[8] = ((enc_i(
                8'h20,
                5'd6,
                5'd1,
                14'd40
            )) >> 8);
        dut.ram.memory_b2[8] = ((enc_i(
                8'h20,
                5'd6,
                5'd1,
                14'd40
            )) >> 16);
        dut.ram.memory_b3[8] = ((enc_i(
                8'h20,
                5'd6,
                5'd1,
                14'd40
            )) >> 24);


        dut.ram.memory_b0[9] = (enc_s(
                8'h21,
                5'd0,
                5'd1,
                14'd44
            ));
        dut.ram.memory_b1[9] = ((enc_s(
                8'h21,
                5'd0,
                5'd1,
                14'd44
            )) >> 8);
        dut.ram.memory_b2[9] = ((enc_s(
                8'h21,
                5'd0,
                5'd1,
                14'd44
            )) >> 16);
        dut.ram.memory_b3[9] = ((enc_s(
                8'h21,
                5'd0,
                5'd1,
                14'd44
            )) >> 24);


        dut.ram.memory_b0[10] = (enc_i(
                8'h10,
                5'd7,
                5'd0,
                14'd1
            ));
        dut.ram.memory_b1[10] = ((enc_i(
                8'h10,
                5'd7,
                5'd0,
                14'd1
            )) >> 8);
        dut.ram.memory_b2[10] = ((enc_i(
                8'h10,
                5'd7,
                5'd0,
                14'd1
            )) >> 16);
        dut.ram.memory_b3[10] = ((enc_i(
                8'h10,
                5'd7,
                5'd0,
                14'd1
            )) >> 24);


        dut.ram.memory_b0[11] = (enc_s(
                8'h21,
                5'd7,
                5'd1,
                14'd32
            ));
        dut.ram.memory_b1[11] = ((enc_s(
                8'h21,
                5'd7,
                5'd1,
                14'd32
            )) >> 8);
        dut.ram.memory_b2[11] = ((enc_s(
                8'h21,
                5'd7,
                5'd1,
                14'd32
            )) >> 16);
        dut.ram.memory_b3[11] = ((enc_s(
                8'h21,
                5'd7,
                5'd1,
                14'd32
            )) >> 24);


        dut.ram.memory_b0[12] = (enc_i(
                8'h20,
                5'd8,
                5'd1,
                14'd36
            ));
        dut.ram.memory_b1[12] = ((enc_i(
                8'h20,
                5'd8,
                5'd1,
                14'd36
            )) >> 8);
        dut.ram.memory_b2[12] = ((enc_i(
                8'h20,
                5'd8,
                5'd1,
                14'd36
            )) >> 16);
        dut.ram.memory_b3[12] = ((enc_i(
                8'h20,
                5'd8,
                5'd1,
                14'd36
            )) >> 24);


        dut.ram.memory_b0[13] = (enc_i(
                8'h20,
                5'd9,
                5'd1,
                14'd20
            ));
        dut.ram.memory_b1[13] = ((enc_i(
                8'h20,
                5'd9,
                5'd1,
                14'd20
            )) >> 8);
        dut.ram.memory_b2[13] = ((enc_i(
                8'h20,
                5'd9,
                5'd1,
                14'd20
            )) >> 16);
        dut.ram.memory_b3[13] = ((enc_i(
                8'h20,
                5'd9,
                5'd1,
                14'd20
            )) >> 24);


        dut.ram.memory_b0[14] = (enc_n(
                8'hFF
            ));
        dut.ram.memory_b1[14] = ((enc_n(
                8'hFF
            )) >> 8);
        dut.ram.memory_b2[14] = ((enc_n(
                8'hFF
            )) >> 16);
        dut.ram.memory_b3[14] = ((enc_n(
                8'hFF
            )) >> 24);


        repeat (3)
            @(posedge clk);

        #1;


        check(
            !halted,
            "CPU begins audio-MMIO integration program from reset state"
        );


        check(
            dut.audio.sample_addr_reg == 12'h000,
            "audio SAMPLE_ADDR begins at reset value"
        );


        check(
            !dut.audio.voice_active[0] &&
            !dut.audio.voice_done[0],
            "audio voice zero begins idle and not done"
        );


        check(
            dut.scratch.scratch_reg == 32'h00000000,
            "scratch MMIO begins unchanged"
        );


        check(
            dut.gpu.tilemap_base_reg == 32'h00000000,
            "GPU state begins unchanged"
        );


        check(
            dut.dma.src_base_reg == 32'h00000000,
            "DMA state begins unchanged"
        );


        @(negedge clk);

        reset = 1'b0;


        while (
            !halted &&
            cycles < 500
        ) begin

            @(posedge clk);
            #1;

            cycles = cycles + 1;

        end


        check(
            halted,
            "CPU reaches HALT before audio-MMIO test timeout"
        );


        check(
            dut.cpu.pc == 32'h00000038,
            "HALT occurs at expected final PC 0x38"
        );


        check(
            dut.cpu.regs[1] == 32'h00001300,
            "CPU constructs audio MMIO base address"
        );


        check(
            dut.audio.sample_addr_reg == 12'd5,
            "CPU store reaches SAMPLE_ADDR"
        );


        check(
            ({dut.audio.sample_ram_hi[5], dut.audio.sample_ram_lo[5]}) == 16'd42,
            "CPU store reaches PCM sample RAM through SAMPLE_DATA"
        );


        check(
            dut.cpu.regs[4] == 32'd42,
            "CPU reads PCM sample back through SAMPLE_DATA"
        );


        check(
            dut.audio.voice_base_reg[0] == 12'd7,
            "CPU store reaches voice zero BASE"
        );


        check(
            dut.cpu.regs[6] == 32'd7,
            "CPU reads voice zero BASE back"
        );


        check(
            dut.audio.voice_length_reg[0] == 13'd0,
            "CPU writes zero voice LENGTH"
        );


        check(
            !dut.audio.voice_active[0] &&
            dut.audio.voice_done[0],
            "zero-length CPU START leaves voice done and inactive"
        );


        check(
            dut.cpu.regs[8] == 32'h00000002,
            "CPU reads audio DONE status"
        );


        check(
            dut.cpu.regs[9] == 32'h00000000,
            "reserved audio MMIO offset returns deterministic zero"
        );


        check(
            audio_store_count == 5,
            "exactly five CPU stores complete in audio MMIO"
        );


        check(
            audio_load_count == 4,
            "exactly four CPU loads complete in audio MMIO"
        );


        check(
            !bad_audio_selection,
            "CPU audio-MMIO accesses select only the audio target"
        );


        check(
            dut.scratch.scratch_reg == 32'h00000000,
            "audio MMIO accesses do not modify scratch MMIO"
        );


        check(
            dut.gpu.tilemap_base_reg == 32'h00000000,
            "audio MMIO accesses do not modify GPU state"
        );


        check(
            dut.dma.src_base_reg == 32'h00000000,
            "audio MMIO accesses do not modify DMA state"
        );


        check(
            !dut.cpu_mem_valid,
            "halted CPU issues no further memory transaction"
        );


        check(
            dut.cpu.regs[0] == 32'h00000000,
            "r0 remains hardwired to zero"
        );


        $display("");
        $display("==============================");


        if (failures == 0) begin

            $display(
                "RESULT: PASS  (%0d checks)",
                checks
            );

            $display(
                "PROGRAM_CYCLES: %0d",
                cycles
            );

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
