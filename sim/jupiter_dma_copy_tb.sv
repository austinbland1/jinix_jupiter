`timescale 1ns/1ps

module jupiter_dma_copy_tb;

    localparam [31:0] SDRAM_BASE = 32'h10000000;

    localparam [31:0] SRC_BASE =
        32'h10000100;

    localparam [31:0] DST_BASE =
        32'h10000200;

    localparam [31:0] GUARD_LOW_ADDR =
        32'h10000080;

    localparam [31:0] GUARD_HIGH_ADDR =
        32'h10000300;

    localparam [31:0] GUARD_LOW_DATA =
        32'h13579BDF;

    localparam [31:0] GUARD_HIGH_DATA =
        32'h2468ACE0;

    localparam integer WORD_COUNT = 4;
    localparam integer MODEL_SLOTS = 64;

    localparam [2:0] CMD_ACTIVE = 3'b011;
    localparam [2:0] CMD_READ   = 3'b101;
    localparam [2:0] CMD_WRITE  = 3'b100;

    reg clk;
    reg reset;

    wire halted;

    wire        SDRAM_CKE;
    wire [12:0] SDRAM_A;
    wire  [1:0] SDRAM_BA;
    wire [15:0] SDRAM_DQ;
    wire        SDRAM_DQML;
    wire        SDRAM_DQMH;
    wire        SDRAM_nCS;
    wire        SDRAM_nCAS;
    wire        SDRAM_nRAS;
    wire        SDRAM_nWE;

    wire protocol_error;

    wire [2:0] sdram_command = {
        SDRAM_nRAS,
        SDRAM_nCAS,
        SDRAM_nWE
    };

    integer checks;
    integer failures;
    integer cycles;

    integer preload_slot;

    integer dma_logical_read_count;
    integer dma_logical_write_count;

    integer cpu_sdram_count;
    integer gpu_sdram_count;

    integer dma_mmio_store_count;
    integer dma_mmio_load_count;

    integer physical_active_count;
    integer physical_read_count;
    integer physical_write_count;

    reg bad_dma_sequence;
    reg bad_dma_mmio_selection;

    integer i;

    jupiter_cpu_subsystem dut
    (
        .clk        (clk),
        .reset      (reset),

        // Valid MiSTer report: 128 MiB SDRAM installed.
        .sdram_sz   (16'h8003),

        .SDRAM_CKE  (SDRAM_CKE),
        .SDRAM_A    (SDRAM_A),
        .SDRAM_BA   (SDRAM_BA),
        .SDRAM_DQ   (SDRAM_DQ),
        .SDRAM_DQML (SDRAM_DQML),
        .SDRAM_DQMH (SDRAM_DQMH),
        .SDRAM_nCS  (SDRAM_nCS),
        .SDRAM_nCAS (SDRAM_nCAS),
        .SDRAM_nRAS (SDRAM_nRAS),
        .SDRAM_nWE  (SDRAM_nWE),

        .halted     (halted)
    );

    jupiter_sdram_model #(
        .CAS_CYCLES (3),
        .SLOTS      (MODEL_SLOTS)
    ) dram (
        .clk            (clk),
        .reset          (reset),

        .SDRAM_CKE      (SDRAM_CKE),
        .SDRAM_A        (SDRAM_A),
        .SDRAM_BA       (SDRAM_BA),
        .SDRAM_DQ       (SDRAM_DQ),
        .SDRAM_DQML     (SDRAM_DQML),
        .SDRAM_DQMH     (SDRAM_DQMH),
        .SDRAM_nCS      (SDRAM_nCS),
        .SDRAM_nCAS     (SDRAM_nCAS),
        .SDRAM_nRAS     (SDRAM_nRAS),
        .SDRAM_nWE      (SDRAM_nWE),

        .protocol_error (protocol_error)
    );

    always #5 clk = ~clk;

    function [31:0] enc_r;
        input [7:0] opcode;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            enc_r = {
                opcode,
                rd,
                rs1,
                rs2,
                9'd0
            };
        end
    endfunction

    function [31:0] enc_i;
        input [7:0]  opcode;
        input [4:0]  rd;
        input [4:0]  rs1;
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
        input [7:0]  opcode;
        input [4:0]  rs2;
        input [4:0]  rs1;
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

    function [31:0] enc_b;
        input [7:0]  opcode;
        input [4:0]  rs1;
        input [4:0]  rs2;
        input [13:0] off14;
        begin
            enc_b = {
                opcode,
                rs1,
                rs2,
                off14
            };
        end
    endfunction

    function [31:0] enc_n;
        input [7:0] opcode;
        begin
            enc_n = {
                opcode,
                24'd0
            };
        end
    endfunction

    function [31:0] source_word;
        input integer index;
        begin
            case (index)
                0:
                    source_word =
                        32'h11223344;

                1:
                    source_word =
                        32'h89ABCDEF;

                2:
                    source_word =
                        32'hCAFEBABE;

                3:
                    source_word =
                        32'h0BADF00D;

                default:
                    source_word =
                        32'h00000000;
            endcase
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

    // Testbench-only preload of the behavioral SDRAM model.
    //
    // mem_tag is the controller's H[25:0] halfword address:
    //
    //     (Jupiter byte address - 0x10000000) >> 1
    task automatic preload_word;
        input [31:0] byte_addr;
        input [31:0] data;

        reg [25:0] half_tag;
        begin
            if ((preload_slot + 1) >=
                MODEL_SLOTS) begin

                $display(
                    "FAIL: behavioral SDRAM preload exceeded slots"
                );

                $fatal(1);
            end

            half_tag =
                (byte_addr - SDRAM_BASE) >> 1;

            dram.mem_valid[preload_slot] =
                1'b1;

            dram.mem_tag[preload_slot] =
                half_tag;

            dram.mem_data[preload_slot] =
                data[15:0];

            preload_slot =
                preload_slot + 1;

            dram.mem_valid[preload_slot] =
                1'b1;

            dram.mem_tag[preload_slot] =
                half_tag + 26'd1;

            dram.mem_data[preload_slot] =
                data[31:16];

            preload_slot =
                preload_slot + 1;
        end
    endtask

    task automatic check_model_word;
        input [31:0] byte_addr;
        input [31:0] expected_data;
        input [8*128-1:0] message;

        integer k;

        reg [25:0] low_tag;
        reg [25:0] high_tag;

        reg low_found;
        reg high_found;

        reg [15:0] low_data;
        reg [15:0] high_data;

        begin
            low_tag =
                (byte_addr - SDRAM_BASE) >> 1;

            high_tag =
                low_tag + 26'd1;

            low_found  = 1'b0;
            high_found = 1'b0;

            low_data  = 16'h0000;
            high_data = 16'h0000;

            for (k = 0;
                 k < MODEL_SLOTS;
                 k = k + 1) begin

                if (dram.mem_valid[k] &&
                    dram.mem_tag[k] ==
                    low_tag) begin

                    low_found = 1'b1;
                    low_data =
                        dram.mem_data[k];
                end

                if (dram.mem_valid[k] &&
                    dram.mem_tag[k] ==
                    high_tag) begin

                    high_found = 1'b1;
                    high_data =
                        dram.mem_data[k];
                end
            end

            check(
                low_found &&
                high_found &&
                ({high_data, low_data} ===
                 expected_data),
                message
            );
        end
    endtask

    always @(posedge clk) begin
        if (!reset) begin
            // --------------------------------------------
            // Physical SDRAM command accounting.
            // --------------------------------------------
            case (sdram_command)
                CMD_ACTIVE:
                    physical_active_count <=
                        physical_active_count + 1;

                CMD_READ:
                    physical_read_count <=
                        physical_read_count + 1;

                CMD_WRITE:
                    physical_write_count <=
                        physical_write_count + 1;

                default: begin
                end
            endcase

            // --------------------------------------------
            // Real DMA logical transaction accounting.
            // --------------------------------------------
            if (dut.dma_sdram_valid &&
                dut.dma_sdram_ready) begin

                if (dut.dma_sdram_write) begin
                    if (dma_logical_write_count >=
                        WORD_COUNT) begin

                        bad_dma_sequence <=
                            1'b1;
                    end else begin
                        if (dut.dma_sdram_addr !=
                            DST_BASE +
                            (dma_logical_write_count *
                             4))
                            bad_dma_sequence <=
                                1'b1;

                        if (dut.dma_sdram_wstrb !=
                            4'b1111)
                            bad_dma_sequence <=
                                1'b1;

                        if (dut.dma_sdram_wdata !=
                            source_word(
                                dma_logical_write_count
                            ))
                            bad_dma_sequence <=
                                1'b1;
                    end

                    dma_logical_write_count <=
                        dma_logical_write_count + 1;
                end else begin
                    if (dma_logical_read_count >=
                        WORD_COUNT) begin

                        bad_dma_sequence <=
                            1'b1;
                    end else if (
                        dut.dma_sdram_addr !=
                        SRC_BASE +
                        (dma_logical_read_count * 4)
                    ) begin

                        bad_dma_sequence <=
                            1'b1;
                    end

                    dma_logical_read_count <=
                        dma_logical_read_count + 1;
                end
            end

            // CPU and GPU must not touch external SDRAM
            // during this deliberately clean DMA-copy test.
            if (dut.sdram_valid &&
                dut.sdram_ready)
                cpu_sdram_count <=
                    cpu_sdram_count + 1;

            if (dut.gpu_sdram_valid &&
                dut.gpu_sdram_ready)
                gpu_sdram_count <=
                    gpu_sdram_count + 1;

            // CPU-visible DMA MMIO accounting.
            if (dut.cpu_mem_valid &&
                dut.cpu_mem_ready &&
                dut.cpu_mem_addr >=
                    32'h00001200 &&
                dut.cpu_mem_addr <=
                    32'h000012FF) begin

                if (!(dut.dma_valid &&
                      !dut.ram_valid &&
                      !dut.mmio_valid &&
                      !dut.gpu_valid &&
                      !dut.sdram_valid))
                    bad_dma_mmio_selection <=
                        1'b1;

                if (dut.cpu_mem_write)
                    dma_mmio_store_count <=
                        dma_mmio_store_count + 1;
                else
                    dma_mmio_load_count <=
                        dma_mmio_load_count + 1;
            end
        end
    end

    initial begin
        clk   = 1'b0;
        reset = 1'b1;

        checks   = 0;
        failures = 0;
        cycles   = 0;

        preload_slot = 0;

        dma_logical_read_count  = 0;
        dma_logical_write_count = 0;

        cpu_sdram_count = 0;
        gpu_sdram_count = 0;

        dma_mmio_store_count = 0;
        dma_mmio_load_count  = 0;

        physical_active_count = 0;
        physical_read_count   = 0;
        physical_write_count  = 0;

        bad_dma_sequence = 1'b0;
        bad_dma_mmio_selection = 1'b0;

        /*
         * Real Jupiter CPU program.
         *
         * 00-40:
         *     construct r1 = 0x10000000
         *
         * 44:
         *     r10 = 0x00001200 DMA MMIO base
         *
         * 48:
         *     r2 = 0x10000100 source
         *
         * 4C:
         *     r3 = 0x10000200 destination
         *
         * 50:
         *     r4 = 4 words
         *
         * 54:
         *     r5 = 1 START
         *
         * 58:
         *     r6 = 2 expected DONE status
         *
         * 5C-68:
         *     program SRC_BASE, DST_BASE,
         *     LENGTH_WORDS, CONTROL.START
         *
         * Poll loop at 6C:
         *
         *     LDW r7, 4(r10)
         *     BNE r7, r6, -2
         *
         * 74:
         *     HALT
         *
         * The CPU itself performs no external-SDRAM
         * load or store in this program.
         */

        dut.ram.memory_b0[0] = (enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4096
            ));
        dut.ram.memory_b1[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4096
            )) >> 8);
        dut.ram.memory_b2[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4096
            )) >> 16);
        dut.ram.memory_b3[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4096
            )) >> 24);

        for (i = 1;
             i <= 16;
             i = i + 1) begin

            dut.ram.memory_b0[i] = (enc_r(
                    8'h01,
                    5'd1,
                    5'd1,
                    5'd1
                ));
            dut.ram.memory_b1[i] = ((enc_r(
                    8'h01,
                    5'd1,
                    5'd1,
                    5'd1
                )) >> 8);
            dut.ram.memory_b2[i] = ((enc_r(
                    8'h01,
                    5'd1,
                    5'd1,
                    5'd1
                )) >> 16);
            dut.ram.memory_b3[i] = ((enc_r(
                    8'h01,
                    5'd1,
                    5'd1,
                    5'd1
                )) >> 24);
        end

        dut.ram.memory_b0[17] = (enc_i(
                8'h10,
                5'd10,
                5'd0,
                14'd4608
            ));
        dut.ram.memory_b1[17] = ((enc_i(
                8'h10,
                5'd10,
                5'd0,
                14'd4608
            )) >> 8);
        dut.ram.memory_b2[17] = ((enc_i(
                8'h10,
                5'd10,
                5'd0,
                14'd4608
            )) >> 16);
        dut.ram.memory_b3[17] = ((enc_i(
                8'h10,
                5'd10,
                5'd0,
                14'd4608
            )) >> 24);

        dut.ram.memory_b0[18] = (enc_i(
                8'h10,
                5'd2,
                5'd1,
                14'd256
            ));
        dut.ram.memory_b1[18] = ((enc_i(
                8'h10,
                5'd2,
                5'd1,
                14'd256
            )) >> 8);
        dut.ram.memory_b2[18] = ((enc_i(
                8'h10,
                5'd2,
                5'd1,
                14'd256
            )) >> 16);
        dut.ram.memory_b3[18] = ((enc_i(
                8'h10,
                5'd2,
                5'd1,
                14'd256
            )) >> 24);

        dut.ram.memory_b0[19] = (enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd512
            ));
        dut.ram.memory_b1[19] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd512
            )) >> 8);
        dut.ram.memory_b2[19] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd512
            )) >> 16);
        dut.ram.memory_b3[19] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd512
            )) >> 24);

        dut.ram.memory_b0[20] = (enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd4
            ));
        dut.ram.memory_b1[20] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[20] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[20] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd4
            )) >> 24);

        dut.ram.memory_b0[21] = (enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd1
            ));
        dut.ram.memory_b1[21] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd1
            )) >> 8);
        dut.ram.memory_b2[21] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd1
            )) >> 16);
        dut.ram.memory_b3[21] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd1
            )) >> 24);

        dut.ram.memory_b0[22] = (enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd2
            ));
        dut.ram.memory_b1[22] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd2
            )) >> 8);
        dut.ram.memory_b2[22] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd2
            )) >> 16);
        dut.ram.memory_b3[22] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd2
            )) >> 24);

        dut.ram.memory_b0[23] = (enc_s(
                8'h21,
                5'd2,
                5'd10,
                14'd8
            ));
        dut.ram.memory_b1[23] = ((enc_s(
                8'h21,
                5'd2,
                5'd10,
                14'd8
            )) >> 8);
        dut.ram.memory_b2[23] = ((enc_s(
                8'h21,
                5'd2,
                5'd10,
                14'd8
            )) >> 16);
        dut.ram.memory_b3[23] = ((enc_s(
                8'h21,
                5'd2,
                5'd10,
                14'd8
            )) >> 24);

        dut.ram.memory_b0[24] = (enc_s(
                8'h21,
                5'd3,
                5'd10,
                14'd12
            ));
        dut.ram.memory_b1[24] = ((enc_s(
                8'h21,
                5'd3,
                5'd10,
                14'd12
            )) >> 8);
        dut.ram.memory_b2[24] = ((enc_s(
                8'h21,
                5'd3,
                5'd10,
                14'd12
            )) >> 16);
        dut.ram.memory_b3[24] = ((enc_s(
                8'h21,
                5'd3,
                5'd10,
                14'd12
            )) >> 24);

        dut.ram.memory_b0[25] = (enc_s(
                8'h21,
                5'd4,
                5'd10,
                14'd16
            ));
        dut.ram.memory_b1[25] = ((enc_s(
                8'h21,
                5'd4,
                5'd10,
                14'd16
            )) >> 8);
        dut.ram.memory_b2[25] = ((enc_s(
                8'h21,
                5'd4,
                5'd10,
                14'd16
            )) >> 16);
        dut.ram.memory_b3[25] = ((enc_s(
                8'h21,
                5'd4,
                5'd10,
                14'd16
            )) >> 24);

        dut.ram.memory_b0[26] = (enc_s(
                8'h21,
                5'd5,
                5'd10,
                14'd0
            ));
        dut.ram.memory_b1[26] = ((enc_s(
                8'h21,
                5'd5,
                5'd10,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[26] = ((enc_s(
                8'h21,
                5'd5,
                5'd10,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[26] = ((enc_s(
                8'h21,
                5'd5,
                5'd10,
                14'd0
            )) >> 24);

        // Poll DMA STATUS at index 27.
        dut.ram.memory_b0[27] = (enc_i(
                8'h20,
                5'd7,
                5'd10,
                14'd4
            ));
        dut.ram.memory_b1[27] = ((enc_i(
                8'h20,
                5'd7,
                5'd10,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[27] = ((enc_i(
                8'h20,
                5'd7,
                5'd10,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[27] = ((enc_i(
                8'h20,
                5'd7,
                5'd10,
                14'd4
            )) >> 24);

        // PC+4 at index 29; target index 27:
        // signed displacement = -2 words.
        dut.ram.memory_b0[28] = (enc_b(
                8'h31,
                5'd7,
                5'd6,
                14'h3FFE
            ));
        dut.ram.memory_b1[28] = ((enc_b(
                8'h31,
                5'd7,
                5'd6,
                14'h3FFE
            )) >> 8);
        dut.ram.memory_b2[28] = ((enc_b(
                8'h31,
                5'd7,
                5'd6,
                14'h3FFE
            )) >> 16);
        dut.ram.memory_b3[28] = ((enc_b(
                8'h31,
                5'd7,
                5'd6,
                14'h3FFE
            )) >> 24);

        dut.ram.memory_b0[29] = (enc_n(8'hFF));
        dut.ram.memory_b1[29] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[29] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[29] = ((enc_n(8'hFF)) >> 24);

        // Let reset-driven nonblocking assignments settle.
        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.dma.busy &&
            !dut.dma.done &&
            !dut.dma_sdram_valid,
            "production DMA begins idle before real copy"
        );

        check(
            !dut.shared_sdram_valid,
            "shared SDRAM path begins idle during reset"
        );

        @(negedge clk);
        reset = 1'b0;

        // ------------------------------------------------
        // Preload physical modeled SDRAM after reset is
        // released but before the CPU reaches START.
        // ------------------------------------------------

        preload_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA
        );

        preload_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA
        );

        for (i = 0;
             i < WORD_COUNT;
             i = i + 1) begin

            preload_word(
                SRC_BASE + (i * 4),
                source_word(i)
            );
        end

        for (i = 0;
             i < WORD_COUNT;
             i = i + 1) begin

            preload_word(
                DST_BASE + (i * 4),
                32'hDEAD0000 + i
            );
        end

        check(
            preload_slot == 20,
            "behavioral SDRAM contains expected twenty preloaded halfwords"
        );

        check_model_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA,
            "low guard is present before DMA copy"
        );

        check_model_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA,
            "high guard is present before DMA copy"
        );

        for (i = 0;
             i < WORD_COUNT;
             i = i + 1) begin

            check_model_word(
                SRC_BASE + (i * 4),
                source_word(i),
                "source word is present before DMA copy"
            );

            check_model_word(
                DST_BASE + (i * 4),
                32'hDEAD0000 + i,
                "destination sentinel is present before DMA copy"
            );
        end

        // ------------------------------------------------
        // Run real CPU configuration + real DMA copy.
        // ------------------------------------------------

        while (!halted &&
               cycles < 30000) begin

            @(posedge clk);
            #1;

            cycles = cycles + 1;
        end

        check(
            halted,
            "CPU reaches HALT after polling real DMA DONE"
        );

        check(
            dut.cpu.pc == 32'h00000074,
            "CPU HALT occurs at expected final PC 0x74"
        );

        check(
            dut.cpu.regs[7] == 32'h00000002,
            "CPU polling observes DMA DONE status"
        );

        check(
            dut.dma.done &&
            !dut.dma.busy,
            "production DMA reaches DONE and clears BUSY"
        );

        check(
            dut.dma.src_base_reg == SRC_BASE &&
            dut.dma.dst_base_reg == DST_BASE &&
            dut.dma.length_words_reg ==
                WORD_COUNT,
            "CPU programs exact live DMA configuration"
        );

        check(
            dut.dma.active_src_base == SRC_BASE &&
            dut.dma.active_dst_base == DST_BASE &&
            dut.dma.active_length_words ==
                WORD_COUNT,
            "real START snapshots exact DMA configuration"
        );

        check(
            dut.dma.current_src_addr ==
                SRC_BASE + (WORD_COUNT * 4) &&
            dut.dma.current_dst_addr ==
                DST_BASE + (WORD_COUNT * 4) &&
            dut.dma.remaining_words ==
                32'h00000000,
            "integrated DMA finishes with exact progress state"
        );

        check(
            dma_mmio_store_count == 4,
            "CPU performs exactly four DMA configuration/start stores"
        );

        check(
            dma_mmio_load_count >= 1,
            "CPU performs DMA STATUS polling loads"
        );

        check(
            !bad_dma_mmio_selection,
            "CPU DMA MMIO accesses select only DMA control target"
        );

        check(
            cpu_sdram_count == 0,
            "CPU performs no external SDRAM transaction during DMA copy"
        );

        check(
            gpu_sdram_count == 0,
            "GPU performs no external SDRAM transaction during DMA copy"
        );

        check(
            dma_logical_read_count ==
                WORD_COUNT,
            "real DMA completes exactly four logical source reads"
        );

        check(
            dma_logical_write_count ==
                WORD_COUNT,
            "real DMA completes exactly four logical destination writes"
        );

        check(
            (dma_logical_read_count +
             dma_logical_write_count) == 8,
            "real DMA completes exactly eight logical SDRAM transactions"
        );

        check(
            !bad_dma_sequence,
            "real DMA logical addresses data and strobes follow exact sequence"
        );

        // ------------------------------------------------
        // Inspect physical modeled SDRAM after copy.
        // ------------------------------------------------

        for (i = 0;
             i < WORD_COUNT;
             i = i + 1) begin

            check_model_word(
                SRC_BASE + (i * 4),
                source_word(i),
                "source word remains unchanged after DMA copy"
            );

            check_model_word(
                DST_BASE + (i * 4),
                source_word(i),
                "destination word exactly matches source after DMA copy"
            );
        end

        check_model_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA,
            "low unrelated-memory guard survives DMA copy"
        );

        check_model_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA,
            "high unrelated-memory guard survives DMA copy"
        );

        check(
            physical_read_count == 8,
            "four logical DMA reads produce eight physical 16-bit READs"
        );

        check(
            physical_write_count == 8,
            "four logical DMA writes produce eight physical 16-bit WRITEs"
        );

        check(
            physical_active_count == 16,
            "eight logical DMA accesses produce sixteen ACTIVE commands"
        );

        check(
            dut.sdram_initialized,
            "physical SDRAM controller completed initialization"
        );

        check(
            protocol_error == 1'b0,
            "behavioral SDRAM reports no protocol error during real DMA copy"
        );

        check(
            !dut.dma_sdram_valid &&
            !dut.shared_sdram_valid,
            "production DMA and shared SDRAM paths return idle after copy"
        );

        check(
            !dut.cpu_mem_valid,
            "halted CPU issues no further memory transaction"
        );

        check(
            dut.scratch.scratch_reg ==
                32'h00000000,
            "DMA copy does not alter scratch MMIO state"
        );

        check(
            dut.gpu.tilemap_base_reg ==
                32'h00000000,
            "DMA copy does not alter GPU control state"
        );

        check(
            dut.cpu.regs[0] ==
                32'h00000000,
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

            $display(
                "DMA_LOGICAL_READS: %0d",
                dma_logical_read_count
            );

            $display(
                "DMA_LOGICAL_WRITES: %0d",
                dma_logical_write_count
            );

            $display(
                "DMA_LOGICAL_TOTAL: %0d",
                dma_logical_read_count +
                dma_logical_write_count
            );

            $display(
                "PHYSICAL_READS: %0d",
                physical_read_count
            );

            $display(
                "PHYSICAL_WRITES: %0d",
                physical_write_count
            );

            $display(
                "PHYSICAL_ACTIVES: %0d",
                physical_active_count
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
