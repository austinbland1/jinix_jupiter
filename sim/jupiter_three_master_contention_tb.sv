`timescale 1ns/1ps

module jupiter_three_master_contention_tb;

    localparam [31:0] SDRAM_BASE =
        32'h10000000;

    // GPU memory.
    localparam [31:0] TILEMAP_BASE =
        32'h10000100;

    localparam [31:0] TILEDATA_BASE =
        32'h10000400;

    localparam [31:0] FRAMEBUFFER_BASE =
        32'h10000800;

    // DMA memory.
    localparam [31:0] DMA_SRC_BASE =
        32'h10001000;

    localparam [31:0] DMA_DST_BASE =
        32'h10001200;

    // CPU-only contention word.
    localparam [31:0] CPU_CONTENTION_ADDR =
        32'h10001400;

    localparam [31:0] GUARD_LOW_ADDR =
        32'h10000000;

    localparam [31:0] GUARD_HIGH_ADDR =
        32'h10001500;

    localparam [31:0] GUARD_LOW_DATA =
        32'h13579BDF;

    localparam [31:0] GUARD_HIGH_DATA =
        32'h2468ACE0;

    localparam integer DMA_WORD_COUNT = 64;
    localparam integer CPU_ITERATIONS = 64;
    localparam integer MODEL_SLOTS = 900;

    localparam [2:0] CMD_ACTIVE = 3'b011;
    localparam [2:0] CMD_READ   = 3'b101;
    localparam [2:0] CMD_WRITE  = 3'b100;

    reg clk = 1'b0;
    reg reset = 1'b1;

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

    integer checks = 0;
    integer failures = 0;
    integer cycles = 0;

    integer preload_slot = 0;

    integer gpu_mmio_store_count = 0;
    integer gpu_mmio_load_count = 0;

    integer dma_mmio_store_count = 0;
    integer dma_mmio_load_count = 0;

    integer cpu_sdram_reads = 0;
    integer cpu_sdram_writes = 0;
    integer cpu_sdram_total = 0;

    integer gpu_sdram_reads = 0;
    integer gpu_sdram_writes = 0;
    integer gpu_sdram_total = 0;

    integer dma_sdram_reads = 0;
    integer dma_sdram_writes = 0;
    integer dma_sdram_total = 0;

    integer contention_store_count = 0;
    integer contention_load_count = 0;

    integer cpu_completions_while_gpu_pending = 0;
    integer cpu_completions_while_dma_pending = 0;

    integer gpu_completions_while_cpu_pending = 0;
    integer gpu_completions_while_dma_pending = 0;

    integer dma_completions_while_cpu_pending = 0;
    integer dma_completions_while_gpu_pending = 0;

    integer triple_request_cycles = 0;

    integer contested_cpu_completions = 0;
    integer contested_gpu_completions = 0;
    integer contested_dma_completions = 0;

    integer physical_active_count = 0;
    integer physical_read_count = 0;
    integer physical_write_count = 0;

    reg bad_gpu_mmio_selection = 1'b0;
    reg bad_dma_mmio_selection = 1'b0;

    reg bad_cpu_contention_readback = 1'b0;
    reg bad_dma_sequence = 1'b0;

    reg contested_grant_seen = 1'b0;

    reg [31:0] expected_contention_data =
        32'h00000000;

    integer i;
    integer tile_linear_i;
    integer tile_index_i;
    integer tile_x_i;
    integer tile_y_i;
    integer row_i;
    integer word_i;
    integer fb_word_i;

    jupiter_cpu_subsystem dut
    (
        .clk        (clk),
        .reset      (reset),
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

    function [31:0] enc_b;
        input [7:0] opcode;
        input [4:0] rs1;
        input [4:0] rs2;
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

    function [31:0] pattern_word;
        input integer tile_linear;
        input integer row_index;
        input integer word_index;
        begin
            pattern_word =
                32'hA0000000 +
                (tile_linear * 32'h00010000) +
                (row_index * 32'h00000100) +
                word_index;
        end
    endfunction

    function [31:0] dma_source_word;
        input integer index;
        begin
            dma_source_word =
                32'hD6000000 + index;
        end
    endfunction

    function [31:0] dma_destination_sentinel;
        input integer index;
        begin
            dma_destination_sentinel =
                32'hBEEF0000 + index;
        end
    endfunction

    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin
            checks = checks + 1;

            if (condition) begin
                $display(
                    "PASS: %0s",
                    message
                );
            end else begin
                failures = failures + 1;

                $display(
                    "FAIL: %0s",
                    message
                );
            end
        end
    endtask

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

            low_found = 1'b0;
            high_found = 1'b0;

            low_data = 16'h0000;
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

    // --------------------------------------------------------
    // CPU-visible GPU MMIO accounting.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset &&
            dut.cpu_mem_valid &&
            dut.cpu_mem_ready &&
            dut.cpu_mem_addr >=
                32'h00001100 &&
            dut.cpu_mem_addr <=
                32'h000011FF) begin

            if (!(dut.gpu_valid &&
                  !dut.dma_valid &&
                  !dut.ram_valid &&
                  !dut.mmio_valid &&
                  !dut.sdram_valid))
                bad_gpu_mmio_selection <=
                    1'b1;

            if (dut.cpu_mem_write)
                gpu_mmio_store_count <=
                    gpu_mmio_store_count + 1;
            else
                gpu_mmio_load_count <=
                    gpu_mmio_load_count + 1;
        end
    end

    // --------------------------------------------------------
    // CPU-visible DMA MMIO accounting.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset &&
            dut.cpu_mem_valid &&
            dut.cpu_mem_ready &&
            dut.cpu_mem_addr >=
                32'h00001200 &&
            dut.cpu_mem_addr <=
                32'h000012FF) begin

            if (!(dut.dma_valid &&
                  !dut.gpu_valid &&
                  !dut.ram_valid &&
                  !dut.mmio_valid &&
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

    // --------------------------------------------------------
    // CPU external-SDRAM completions.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset &&
            dut.sdram_valid &&
            dut.sdram_ready) begin

            cpu_sdram_total <=
                cpu_sdram_total + 1;

            if (dut.sdram_write)
                cpu_sdram_writes <=
                    cpu_sdram_writes + 1;
            else
                cpu_sdram_reads <=
                    cpu_sdram_reads + 1;

            if (dut.gpu_sdram_valid)
                cpu_completions_while_gpu_pending <=
                    cpu_completions_while_gpu_pending + 1;

            if (dut.dma_sdram_valid)
                cpu_completions_while_dma_pending <=
                    cpu_completions_while_dma_pending + 1;

            if (dut.sdram_addr ==
                CPU_CONTENTION_ADDR) begin

                if (dut.sdram_write) begin
                    contention_store_count <=
                        contention_store_count + 1;

                    expected_contention_data <=
                        dut.sdram_wdata;
                end else begin
                    contention_load_count <=
                        contention_load_count + 1;

                    if (dut.sdram_rdata !=
                        expected_contention_data)
                        bad_cpu_contention_readback <=
                            1'b1;
                end
            end
        end
    end

    // --------------------------------------------------------
    // GPU external-SDRAM completions.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset &&
            dut.gpu_sdram_valid &&
            dut.gpu_sdram_ready) begin

            gpu_sdram_total <=
                gpu_sdram_total + 1;

            if (dut.gpu_sdram_write)
                gpu_sdram_writes <=
                    gpu_sdram_writes + 1;
            else
                gpu_sdram_reads <=
                    gpu_sdram_reads + 1;

            if (dut.sdram_valid)
                gpu_completions_while_cpu_pending <=
                    gpu_completions_while_cpu_pending + 1;

            if (dut.dma_sdram_valid)
                gpu_completions_while_dma_pending <=
                    gpu_completions_while_dma_pending + 1;
        end
    end

    // --------------------------------------------------------
    // DMA external-SDRAM completions and exact sequencing.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset &&
            dut.dma_sdram_valid &&
            dut.dma_sdram_ready) begin

            dma_sdram_total <=
                dma_sdram_total + 1;

            if (dut.dma_sdram_write) begin
                if (dma_sdram_writes >=
                    DMA_WORD_COUNT) begin

                    bad_dma_sequence <=
                        1'b1;
                end else begin
                    if (dma_sdram_reads !=
                        (dma_sdram_writes + 1))
                        bad_dma_sequence <=
                            1'b1;

                    if (dut.dma_sdram_addr !=
                        DMA_DST_BASE +
                        (dma_sdram_writes * 4))
                        bad_dma_sequence <=
                            1'b1;

                    if (dut.dma_sdram_wdata !=
                        dma_source_word(
                            dma_sdram_writes
                        ))
                        bad_dma_sequence <=
                            1'b1;

                    if (dut.dma_sdram_wstrb !=
                        4'b1111)
                        bad_dma_sequence <=
                            1'b1;
                end

                dma_sdram_writes <=
                    dma_sdram_writes + 1;
            end else begin
                if (dma_sdram_reads >=
                    DMA_WORD_COUNT) begin

                    bad_dma_sequence <=
                        1'b1;
                end else begin
                    if (dma_sdram_reads !=
                        dma_sdram_writes)
                        bad_dma_sequence <=
                            1'b1;

                    if (dut.dma_sdram_addr !=
                        DMA_SRC_BASE +
                        (dma_sdram_reads * 4))
                        bad_dma_sequence <=
                            1'b1;
                end

                dma_sdram_reads <=
                    dma_sdram_reads + 1;
            end

            if (dut.sdram_valid)
                dma_completions_while_cpu_pending <=
                    dma_completions_while_cpu_pending + 1;

            if (dut.gpu_sdram_valid)
                dma_completions_while_gpu_pending <=
                    dma_completions_while_gpu_pending + 1;
        end
    end

    // --------------------------------------------------------
    // Three-master contention observability.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset) begin
            if (dut.sdram_valid &&
                dut.gpu_sdram_valid &&
                dut.dma_sdram_valid)
                triple_request_cycles <=
                    triple_request_cycles + 1;

            if (dut.sdram_arbiter.grant_contested)
                contested_grant_seen <=
                    1'b1;

            if (dut.sdram_arbiter.grant_contested &&
                dut.sdram_ready)
                contested_cpu_completions <=
                    contested_cpu_completions + 1;

            if (dut.sdram_arbiter.grant_contested &&
                dut.gpu_sdram_ready)
                contested_gpu_completions <=
                    contested_gpu_completions + 1;

            if (dut.sdram_arbiter.grant_contested &&
                dut.dma_sdram_ready)
                contested_dma_completions <=
                    contested_dma_completions + 1;
        end
    end

    // --------------------------------------------------------
    // Physical 16-bit SDRAM command accounting.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset) begin
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
        end
    end

    initial begin
        /*
         * Real three-master program.
         *
         * 00-40:
         *     construct r1 = 0x10000000
         *
         * r10 = GPU MMIO base 0x1100
         * r11 = DMA MMIO base 0x1200
         *
         * GPU:
         *     r2 = TILEMAP_BASE
         *     r3 = TILEDATA_BASE
         *     r4 = FRAMEBUFFER_BASE
         *     r5 = MAP_SIZE 0x0202
         *
         * Common:
         *     r6 = START = 1
         *
         * DMA:
         *     r7 = DMA_SRC_BASE
         *     r8 = DMA_DST_BASE
         *     r9 = 64 words
         *
         * CPU:
         *     r12 = CPU_CONTENTION_ADDR
         *     r13 = loop counter
         *     r14 = 64 iterations
         *
         * Status:
         *     r15 = expected DONE = 2
         *
         * Configure GPU and DMA first.
         * Start GPU.
         * Start DMA.
         *
         * Then execute 64 real CPU external-SDRAM
         * store/load pairs while both engines run.
         *
         * Finally poll GPU DONE, poll DMA DONE, and HALT.
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
                14'd4352
            ));
        dut.ram.memory_b1[17] = ((enc_i(
                8'h10,
                5'd10,
                5'd0,
                14'd4352
            )) >> 8);
        dut.ram.memory_b2[17] = ((enc_i(
                8'h10,
                5'd10,
                5'd0,
                14'd4352
            )) >> 16);
        dut.ram.memory_b3[17] = ((enc_i(
                8'h10,
                5'd10,
                5'd0,
                14'd4352
            )) >> 24);

        dut.ram.memory_b0[18] = (enc_i(
                8'h10,
                5'd11,
                5'd0,
                14'd4608
            ));
        dut.ram.memory_b1[18] = ((enc_i(
                8'h10,
                5'd11,
                5'd0,
                14'd4608
            )) >> 8);
        dut.ram.memory_b2[18] = ((enc_i(
                8'h10,
                5'd11,
                5'd0,
                14'd4608
            )) >> 16);
        dut.ram.memory_b3[18] = ((enc_i(
                8'h10,
                5'd11,
                5'd0,
                14'd4608
            )) >> 24);

        dut.ram.memory_b0[19] = (enc_i(
                8'h10,
                5'd2,
                5'd1,
                14'd256
            ));
        dut.ram.memory_b1[19] = ((enc_i(
                8'h10,
                5'd2,
                5'd1,
                14'd256
            )) >> 8);
        dut.ram.memory_b2[19] = ((enc_i(
                8'h10,
                5'd2,
                5'd1,
                14'd256
            )) >> 16);
        dut.ram.memory_b3[19] = ((enc_i(
                8'h10,
                5'd2,
                5'd1,
                14'd256
            )) >> 24);

        dut.ram.memory_b0[20] = (enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd1024
            ));
        dut.ram.memory_b1[20] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd1024
            )) >> 8);
        dut.ram.memory_b2[20] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd1024
            )) >> 16);
        dut.ram.memory_b3[20] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd1024
            )) >> 24);

        dut.ram.memory_b0[21] = (enc_i(
                8'h10,
                5'd4,
                5'd1,
                14'd2048
            ));
        dut.ram.memory_b1[21] = ((enc_i(
                8'h10,
                5'd4,
                5'd1,
                14'd2048
            )) >> 8);
        dut.ram.memory_b2[21] = ((enc_i(
                8'h10,
                5'd4,
                5'd1,
                14'd2048
            )) >> 16);
        dut.ram.memory_b3[21] = ((enc_i(
                8'h10,
                5'd4,
                5'd1,
                14'd2048
            )) >> 24);

        dut.ram.memory_b0[22] = (enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd514
            ));
        dut.ram.memory_b1[22] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd514
            )) >> 8);
        dut.ram.memory_b2[22] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd514
            )) >> 16);
        dut.ram.memory_b3[22] = ((enc_i(
                8'h10,
                5'd5,
                5'd0,
                14'd514
            )) >> 24);

        dut.ram.memory_b0[23] = (enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd1
            ));
        dut.ram.memory_b1[23] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd1
            )) >> 8);
        dut.ram.memory_b2[23] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd1
            )) >> 16);
        dut.ram.memory_b3[23] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd1
            )) >> 24);

        dut.ram.memory_b0[24] = (enc_i(
                8'h10,
                5'd7,
                5'd1,
                14'd4096
            ));
        dut.ram.memory_b1[24] = ((enc_i(
                8'h10,
                5'd7,
                5'd1,
                14'd4096
            )) >> 8);
        dut.ram.memory_b2[24] = ((enc_i(
                8'h10,
                5'd7,
                5'd1,
                14'd4096
            )) >> 16);
        dut.ram.memory_b3[24] = ((enc_i(
                8'h10,
                5'd7,
                5'd1,
                14'd4096
            )) >> 24);

        dut.ram.memory_b0[25] = (enc_i(
                8'h10,
                5'd8,
                5'd1,
                14'd4608
            ));
        dut.ram.memory_b1[25] = ((enc_i(
                8'h10,
                5'd8,
                5'd1,
                14'd4608
            )) >> 8);
        dut.ram.memory_b2[25] = ((enc_i(
                8'h10,
                5'd8,
                5'd1,
                14'd4608
            )) >> 16);
        dut.ram.memory_b3[25] = ((enc_i(
                8'h10,
                5'd8,
                5'd1,
                14'd4608
            )) >> 24);

        dut.ram.memory_b0[26] = (enc_i(
                8'h10,
                5'd9,
                5'd0,
                14'd64
            ));
        dut.ram.memory_b1[26] = ((enc_i(
                8'h10,
                5'd9,
                5'd0,
                14'd64
            )) >> 8);
        dut.ram.memory_b2[26] = ((enc_i(
                8'h10,
                5'd9,
                5'd0,
                14'd64
            )) >> 16);
        dut.ram.memory_b3[26] = ((enc_i(
                8'h10,
                5'd9,
                5'd0,
                14'd64
            )) >> 24);

        dut.ram.memory_b0[27] = (enc_i(
                8'h10,
                5'd12,
                5'd1,
                14'd5120
            ));
        dut.ram.memory_b1[27] = ((enc_i(
                8'h10,
                5'd12,
                5'd1,
                14'd5120
            )) >> 8);
        dut.ram.memory_b2[27] = ((enc_i(
                8'h10,
                5'd12,
                5'd1,
                14'd5120
            )) >> 16);
        dut.ram.memory_b3[27] = ((enc_i(
                8'h10,
                5'd12,
                5'd1,
                14'd5120
            )) >> 24);

        dut.ram.memory_b0[28] = (enc_i(
                8'h10,
                5'd13,
                5'd0,
                14'd0
            ));
        dut.ram.memory_b1[28] = ((enc_i(
                8'h10,
                5'd13,
                5'd0,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[28] = ((enc_i(
                8'h10,
                5'd13,
                5'd0,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[28] = ((enc_i(
                8'h10,
                5'd13,
                5'd0,
                14'd0
            )) >> 24);

        dut.ram.memory_b0[29] = (enc_i(
                8'h10,
                5'd14,
                5'd0,
                14'd64
            ));
        dut.ram.memory_b1[29] = ((enc_i(
                8'h10,
                5'd14,
                5'd0,
                14'd64
            )) >> 8);
        dut.ram.memory_b2[29] = ((enc_i(
                8'h10,
                5'd14,
                5'd0,
                14'd64
            )) >> 16);
        dut.ram.memory_b3[29] = ((enc_i(
                8'h10,
                5'd14,
                5'd0,
                14'd64
            )) >> 24);

        dut.ram.memory_b0[30] = (enc_i(
                8'h10,
                5'd15,
                5'd0,
                14'd2
            ));
        dut.ram.memory_b1[30] = ((enc_i(
                8'h10,
                5'd15,
                5'd0,
                14'd2
            )) >> 8);
        dut.ram.memory_b2[30] = ((enc_i(
                8'h10,
                5'd15,
                5'd0,
                14'd2
            )) >> 16);
        dut.ram.memory_b3[30] = ((enc_i(
                8'h10,
                5'd15,
                5'd0,
                14'd2
            )) >> 24);

        // GPU configuration.
        dut.ram.memory_b0[31] = (enc_s(
                8'h21,
                5'd2,
                5'd10,
                14'd8
            ));
        dut.ram.memory_b1[31] = ((enc_s(
                8'h21,
                5'd2,
                5'd10,
                14'd8
            )) >> 8);
        dut.ram.memory_b2[31] = ((enc_s(
                8'h21,
                5'd2,
                5'd10,
                14'd8
            )) >> 16);
        dut.ram.memory_b3[31] = ((enc_s(
                8'h21,
                5'd2,
                5'd10,
                14'd8
            )) >> 24);

        dut.ram.memory_b0[32] = (enc_s(
                8'h21,
                5'd3,
                5'd10,
                14'd12
            ));
        dut.ram.memory_b1[32] = ((enc_s(
                8'h21,
                5'd3,
                5'd10,
                14'd12
            )) >> 8);
        dut.ram.memory_b2[32] = ((enc_s(
                8'h21,
                5'd3,
                5'd10,
                14'd12
            )) >> 16);
        dut.ram.memory_b3[32] = ((enc_s(
                8'h21,
                5'd3,
                5'd10,
                14'd12
            )) >> 24);

        dut.ram.memory_b0[33] = (enc_s(
                8'h21,
                5'd4,
                5'd10,
                14'd16
            ));
        dut.ram.memory_b1[33] = ((enc_s(
                8'h21,
                5'd4,
                5'd10,
                14'd16
            )) >> 8);
        dut.ram.memory_b2[33] = ((enc_s(
                8'h21,
                5'd4,
                5'd10,
                14'd16
            )) >> 16);
        dut.ram.memory_b3[33] = ((enc_s(
                8'h21,
                5'd4,
                5'd10,
                14'd16
            )) >> 24);

        dut.ram.memory_b0[34] = (enc_s(
                8'h21,
                5'd5,
                5'd10,
                14'd20
            ));
        dut.ram.memory_b1[34] = ((enc_s(
                8'h21,
                5'd5,
                5'd10,
                14'd20
            )) >> 8);
        dut.ram.memory_b2[34] = ((enc_s(
                8'h21,
                5'd5,
                5'd10,
                14'd20
            )) >> 16);
        dut.ram.memory_b3[34] = ((enc_s(
                8'h21,
                5'd5,
                5'd10,
                14'd20
            )) >> 24);

        // DMA configuration.
        dut.ram.memory_b0[35] = (enc_s(
                8'h21,
                5'd7,
                5'd11,
                14'd8
            ));
        dut.ram.memory_b1[35] = ((enc_s(
                8'h21,
                5'd7,
                5'd11,
                14'd8
            )) >> 8);
        dut.ram.memory_b2[35] = ((enc_s(
                8'h21,
                5'd7,
                5'd11,
                14'd8
            )) >> 16);
        dut.ram.memory_b3[35] = ((enc_s(
                8'h21,
                5'd7,
                5'd11,
                14'd8
            )) >> 24);

        dut.ram.memory_b0[36] = (enc_s(
                8'h21,
                5'd8,
                5'd11,
                14'd12
            ));
        dut.ram.memory_b1[36] = ((enc_s(
                8'h21,
                5'd8,
                5'd11,
                14'd12
            )) >> 8);
        dut.ram.memory_b2[36] = ((enc_s(
                8'h21,
                5'd8,
                5'd11,
                14'd12
            )) >> 16);
        dut.ram.memory_b3[36] = ((enc_s(
                8'h21,
                5'd8,
                5'd11,
                14'd12
            )) >> 24);

        dut.ram.memory_b0[37] = (enc_s(
                8'h21,
                5'd9,
                5'd11,
                14'd16
            ));
        dut.ram.memory_b1[37] = ((enc_s(
                8'h21,
                5'd9,
                5'd11,
                14'd16
            )) >> 8);
        dut.ram.memory_b2[37] = ((enc_s(
                8'h21,
                5'd9,
                5'd11,
                14'd16
            )) >> 16);
        dut.ram.memory_b3[37] = ((enc_s(
                8'h21,
                5'd9,
                5'd11,
                14'd16
            )) >> 24);

        // Launch both hardware masters.
        dut.ram.memory_b0[38] = (enc_s(
                8'h21,
                5'd6,
                5'd10,
                14'd0
            ));
        dut.ram.memory_b1[38] = ((enc_s(
                8'h21,
                5'd6,
                5'd10,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[38] = ((enc_s(
                8'h21,
                5'd6,
                5'd10,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[38] = ((enc_s(
                8'h21,
                5'd6,
                5'd10,
                14'd0
            )) >> 24);

        dut.ram.memory_b0[39] = (enc_s(
                8'h21,
                5'd6,
                5'd11,
                14'd0
            ));
        dut.ram.memory_b1[39] = ((enc_s(
                8'h21,
                5'd6,
                5'd11,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[39] = ((enc_s(
                8'h21,
                5'd6,
                5'd11,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[39] = ((enc_s(
                8'h21,
                5'd6,
                5'd11,
                14'd0
            )) >> 24);

        // CPU SDRAM contention loop begins at index 40.
        dut.ram.memory_b0[40] = (enc_i(
                8'h10,
                5'd13,
                5'd13,
                14'd1
            ));
        dut.ram.memory_b1[40] = ((enc_i(
                8'h10,
                5'd13,
                5'd13,
                14'd1
            )) >> 8);
        dut.ram.memory_b2[40] = ((enc_i(
                8'h10,
                5'd13,
                5'd13,
                14'd1
            )) >> 16);
        dut.ram.memory_b3[40] = ((enc_i(
                8'h10,
                5'd13,
                5'd13,
                14'd1
            )) >> 24);

        dut.ram.memory_b0[41] = (enc_s(
                8'h21,
                5'd13,
                5'd12,
                14'd0
            ));
        dut.ram.memory_b1[41] = ((enc_s(
                8'h21,
                5'd13,
                5'd12,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[41] = ((enc_s(
                8'h21,
                5'd13,
                5'd12,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[41] = ((enc_s(
                8'h21,
                5'd13,
                5'd12,
                14'd0
            )) >> 24);

        dut.ram.memory_b0[42] = (enc_i(
                8'h20,
                5'd16,
                5'd12,
                14'd0
            ));
        dut.ram.memory_b1[42] = ((enc_i(
                8'h20,
                5'd16,
                5'd12,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[42] = ((enc_i(
                8'h20,
                5'd16,
                5'd12,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[42] = ((enc_i(
                8'h20,
                5'd16,
                5'd12,
                14'd0
            )) >> 24);

        // PC+4 at index 44; target index 40 => -4 words.
        dut.ram.memory_b0[43] = (enc_b(
                8'h31,
                5'd13,
                5'd14,
                14'h3FFC
            ));
        dut.ram.memory_b1[43] = ((enc_b(
                8'h31,
                5'd13,
                5'd14,
                14'h3FFC
            )) >> 8);
        dut.ram.memory_b2[43] = ((enc_b(
                8'h31,
                5'd13,
                5'd14,
                14'h3FFC
            )) >> 16);
        dut.ram.memory_b3[43] = ((enc_b(
                8'h31,
                5'd13,
                5'd14,
                14'h3FFC
            )) >> 24);

        // GPU STATUS polling begins at index 44.
        dut.ram.memory_b0[44] = (enc_i(
                8'h20,
                5'd17,
                5'd10,
                14'd4
            ));
        dut.ram.memory_b1[44] = ((enc_i(
                8'h20,
                5'd17,
                5'd10,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[44] = ((enc_i(
                8'h20,
                5'd17,
                5'd10,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[44] = ((enc_i(
                8'h20,
                5'd17,
                5'd10,
                14'd4
            )) >> 24);

        // PC+4 at index 46; target index 44 => -2 words.
        dut.ram.memory_b0[45] = (enc_b(
                8'h31,
                5'd17,
                5'd15,
                14'h3FFE
            ));
        dut.ram.memory_b1[45] = ((enc_b(
                8'h31,
                5'd17,
                5'd15,
                14'h3FFE
            )) >> 8);
        dut.ram.memory_b2[45] = ((enc_b(
                8'h31,
                5'd17,
                5'd15,
                14'h3FFE
            )) >> 16);
        dut.ram.memory_b3[45] = ((enc_b(
                8'h31,
                5'd17,
                5'd15,
                14'h3FFE
            )) >> 24);

        // DMA STATUS polling begins at index 46.
        dut.ram.memory_b0[46] = (enc_i(
                8'h20,
                5'd18,
                5'd11,
                14'd4
            ));
        dut.ram.memory_b1[46] = ((enc_i(
                8'h20,
                5'd18,
                5'd11,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[46] = ((enc_i(
                8'h20,
                5'd18,
                5'd11,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[46] = ((enc_i(
                8'h20,
                5'd18,
                5'd11,
                14'd4
            )) >> 24);

        // PC+4 at index 48; target index 46 => -2 words.
        dut.ram.memory_b0[47] = (enc_b(
                8'h31,
                5'd18,
                5'd15,
                14'h3FFE
            ));
        dut.ram.memory_b1[47] = ((enc_b(
                8'h31,
                5'd18,
                5'd15,
                14'h3FFE
            )) >> 8);
        dut.ram.memory_b2[47] = ((enc_b(
                8'h31,
                5'd18,
                5'd15,
                14'h3FFE
            )) >> 16);
        dut.ram.memory_b3[47] = ((enc_b(
                8'h31,
                5'd18,
                5'd15,
                14'h3FFE
            )) >> 24);

        dut.ram.memory_b0[48] = (enc_n(8'hFF));
        dut.ram.memory_b1[48] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[48] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[48] = ((enc_n(8'hFF)) >> 24);

        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.gpu.busy &&
            !dut.gpu.done &&
            !dut.gpu_sdram_valid,
            "GPU begins idle before three-master contention"
        );

        check(
            !dut.dma.busy &&
            !dut.dma.done &&
            !dut.dma_sdram_valid,
            "DMA begins idle before three-master contention"
        );

        @(negedge clk);
        reset = 1'b0;

        // --------------------------------------------------------
        // Behavioral SDRAM preload.
        //
        // 2 guard words
        // 1 CPU contention word
        // 4 GPU tilemap words
        // 128 GPU tile-data words
        // 128 framebuffer sentinels
        // 64 DMA source words
        // 64 DMA destination sentinels
        //
        // 391 32-bit logical words
        // 782 sparse 16-bit model entries.
        // --------------------------------------------------------

        preload_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA
        );

        preload_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA
        );

        preload_word(
            CPU_CONTENTION_ADDR,
            32'h00000000
        );

        for (tile_linear_i = 0;
             tile_linear_i < 4;
             tile_linear_i = tile_linear_i + 1) begin

            preload_word(
                TILEMAP_BASE +
                    (tile_linear_i * 4),
                32'hCAFE0000 +
                    (tile_linear_i + 1)
            );
        end

        for (tile_linear_i = 0;
             tile_linear_i < 4;
             tile_linear_i = tile_linear_i + 1) begin

            tile_index_i =
                tile_linear_i + 1;

            for (row_i = 0;
                 row_i < 8;
                 row_i = row_i + 1) begin

                for (word_i = 0;
                     word_i < 4;
                     word_i = word_i + 1) begin

                    preload_word(
                        TILEDATA_BASE +
                            (tile_index_i * 128) +
                            (row_i * 16) +
                            (word_i * 4),
                        pattern_word(
                            tile_linear_i,
                            row_i,
                            word_i
                        )
                    );
                end
            end
        end

        for (fb_word_i = 0;
             fb_word_i < 128;
             fb_word_i = fb_word_i + 1) begin

            preload_word(
                FRAMEBUFFER_BASE +
                    (fb_word_i * 4),
                32'h55AA55AA
            );
        end

        for (i = 0;
             i < DMA_WORD_COUNT;
             i = i + 1) begin

            preload_word(
                DMA_SRC_BASE +
                    (i * 4),
                dma_source_word(i)
            );
        end

        for (i = 0;
             i < DMA_WORD_COUNT;
             i = i + 1) begin

            preload_word(
                DMA_DST_BASE +
                    (i * 4),
                dma_destination_sentinel(i)
            );
        end

        check(
            preload_slot == 782,
            "behavioral SDRAM contains expected 782 preloaded halfwords"
        );

        // --------------------------------------------------------
        // Run all three real production masters.
        // --------------------------------------------------------

        while (!halted &&
               cycles < 150000) begin

            @(posedge clk);
            #1;

            cycles = cycles + 1;
        end

        check(
            halted,
            "CPU reaches HALT after three-master workload and DONE polling"
        );

        check(
            dut.cpu.pc ==
                32'h000000C0,
            "CPU HALT occurs at expected final PC 0xC0"
        );

        check(
            dut.cpu.regs[13] ==
                CPU_ITERATIONS &&
            dut.cpu.regs[16] ==
                CPU_ITERATIONS,
            "CPU completes all 64 external-SDRAM store/load iterations"
        );

        check(
            dut.cpu.regs[17] ==
                32'h00000002 &&
            dut.cpu.regs[18] ==
                32'h00000002,
            "CPU observes DONE from both GPU and DMA"
        );

        check(
            dut.gpu.done &&
            !dut.gpu.busy &&
            dut.gpu.renderer_state ==
                3'd0,
            "GPU render completes and returns idle"
        );

        check(
            dut.dma.done &&
            !dut.dma.busy &&
            dut.dma.remaining_words ==
                32'h00000000,
            "DMA copy completes and returns idle"
        );

        check(
            dut.gpu.active_tilemap_base ==
                TILEMAP_BASE &&
            dut.gpu.active_tiledata_base ==
                TILEDATA_BASE &&
            dut.gpu.active_framebuffer_base ==
                FRAMEBUFFER_BASE &&
            dut.gpu.active_map_size ==
                16'h0202,
            "GPU active snapshot matches CPU configuration"
        );

        check(
            dut.dma.active_src_base ==
                DMA_SRC_BASE &&
            dut.dma.active_dst_base ==
                DMA_DST_BASE &&
            dut.dma.active_length_words ==
                DMA_WORD_COUNT,
            "DMA active snapshot matches CPU configuration"
        );

        check(
            gpu_mmio_store_count == 5,
            "CPU performs exactly five GPU configuration/start stores"
        );

        check(
            dma_mmio_store_count == 4,
            "CPU performs exactly four DMA configuration/start stores"
        );

        check(
            gpu_mmio_load_count >= 1 &&
            dma_mmio_load_count >= 1,
            "CPU polls both GPU and DMA STATUS registers"
        );

        check(
            !bad_gpu_mmio_selection &&
            !bad_dma_mmio_selection,
            "GPU and DMA MMIO accesses select only intended targets"
        );

        // --------------------------------------------------------
        // Exact CPU logical traffic.
        // --------------------------------------------------------

        check(
            cpu_sdram_reads ==
                CPU_ITERATIONS,
            "CPU completes exactly 64 logical SDRAM reads"
        );

        check(
            cpu_sdram_writes ==
                CPU_ITERATIONS,
            "CPU completes exactly 64 logical SDRAM writes"
        );

        check(
            cpu_sdram_total ==
                (CPU_ITERATIONS * 2),
            "CPU completes exactly 128 logical SDRAM transactions"
        );

        check(
            contention_store_count ==
                CPU_ITERATIONS &&
            contention_load_count ==
                CPU_ITERATIONS,
            "CPU completes all contention stores and loads"
        );

        check(
            !bad_cpu_contention_readback,
            "every CPU read matches the most recently completed CPU store"
        );

        // --------------------------------------------------------
        // Exact GPU logical traffic.
        // --------------------------------------------------------

        check(
            gpu_sdram_reads == 132,
            "GPU completes exactly 132 logical SDRAM reads"
        );

        check(
            gpu_sdram_writes == 128,
            "GPU completes exactly 128 logical SDRAM writes"
        );

        check(
            gpu_sdram_total == 260,
            "GPU completes exactly 260 logical SDRAM transactions"
        );

        // --------------------------------------------------------
        // Exact DMA logical traffic.
        // --------------------------------------------------------

        check(
            dma_sdram_reads ==
                DMA_WORD_COUNT,
            "DMA completes exactly 64 logical source reads"
        );

        check(
            dma_sdram_writes ==
                DMA_WORD_COUNT,
            "DMA completes exactly 64 logical destination writes"
        );

        check(
            dma_sdram_total ==
                (DMA_WORD_COUNT * 2),
            "DMA completes exactly 128 logical SDRAM transactions"
        );

        check(
            !bad_dma_sequence,
            "DMA address data and strobe sequencing remains exact"
        );

        // --------------------------------------------------------
        // Explicit overlap and forward-progress evidence.
        // --------------------------------------------------------

        check(
            cpu_completions_while_gpu_pending > 0,
            "CPU makes progress while GPU request is pending"
        );

        check(
            cpu_completions_while_dma_pending > 0,
            "CPU makes progress while DMA request is pending"
        );

        check(
            gpu_completions_while_cpu_pending > 0,
            "GPU makes progress while CPU request is pending"
        );

        check(
            gpu_completions_while_dma_pending > 0,
            "GPU makes progress while DMA request is pending"
        );

        check(
            dma_completions_while_cpu_pending > 0,
            "DMA makes progress while CPU request is pending"
        );

        check(
            dma_completions_while_gpu_pending > 0,
            "DMA makes progress while GPU request is pending"
        );

        check(
            triple_request_cycles > 0,
            "CPU GPU and DMA are simultaneously requesting SDRAM"
        );

        check(
            contested_grant_seen,
            "production arbiter records held contested transactions"
        );

        check(
            contested_cpu_completions > 0,
            "CPU wins completed contested transactions"
        );

        check(
            contested_gpu_completions > 0,
            "GPU wins completed contested transactions"
        );

        check(
            contested_dma_completions > 0,
            "DMA wins completed contested transactions"
        );

        // --------------------------------------------------------
        // Exact physical command accounting.
        //
        // CPU:
        //    64 reads +  64 writes
        //
        // GPU:
        //   132 reads + 128 writes
        //
        // DMA:
        //    64 reads +  64 writes
        //
        // Aggregate:
        //   260 logical reads
        //   256 logical writes
        //   516 logical transactions
        //
        // Each logical transaction is two physical 16-bit halves.
        // --------------------------------------------------------

        check(
            physical_read_count == 520,
            "260 logical reads produce 520 physical 16-bit READs"
        );

        check(
            physical_write_count == 512,
            "256 logical writes produce 512 physical 16-bit WRITEs"
        );

        check(
            physical_active_count == 1032,
            "516 logical accesses produce 1032 ACTIVE commands"
        );

        check(
            dut.sdram_initialized,
            "physical SDRAM controller completes initialization"
        );

        check(
            protocol_error == 1'b0,
            "behavioral SDRAM reports no protocol error under three-master contention"
        );

        // --------------------------------------------------------
        // GPU source integrity.
        // --------------------------------------------------------

        for (tile_linear_i = 0;
             tile_linear_i < 4;
             tile_linear_i = tile_linear_i + 1) begin

            check_model_word(
                TILEMAP_BASE +
                    (tile_linear_i * 4),
                32'hCAFE0000 +
                    (tile_linear_i + 1),
                "tilemap source survives three-master contention"
            );
        end

        for (tile_linear_i = 0;
             tile_linear_i < 4;
             tile_linear_i = tile_linear_i + 1) begin

            tile_index_i =
                tile_linear_i + 1;

            for (row_i = 0;
                 row_i < 8;
                 row_i = row_i + 1) begin

                for (word_i = 0;
                     word_i < 4;
                     word_i = word_i + 1) begin

                    check_model_word(
                        TILEDATA_BASE +
                            (tile_index_i * 128) +
                            (row_i * 16) +
                            (word_i * 4),
                        pattern_word(
                            tile_linear_i,
                            row_i,
                            word_i
                        ),
                        "tile-data source survives three-master contention"
                    );
                end
            end
        end

        // --------------------------------------------------------
        // Complete GPU framebuffer integrity.
        // --------------------------------------------------------

        for (tile_y_i = 0;
             tile_y_i < 2;
             tile_y_i = tile_y_i + 1) begin

            for (tile_x_i = 0;
                 tile_x_i < 2;
                 tile_x_i = tile_x_i + 1) begin

                tile_linear_i =
                    (tile_y_i * 2) +
                    tile_x_i;

                for (row_i = 0;
                     row_i < 8;
                     row_i = row_i + 1) begin

                    for (word_i = 0;
                         word_i < 4;
                         word_i = word_i + 1) begin

                        check_model_word(
                            FRAMEBUFFER_BASE +
                                (((tile_y_i * 8) +
                                  row_i) * 32) +
                                (tile_x_i * 16) +
                                (word_i * 4),
                            pattern_word(
                                tile_linear_i,
                                row_i,
                                word_i
                            ),
                            "framebuffer word survives three-master contention"
                        );
                    end
                end
            end
        end

        // --------------------------------------------------------
        // DMA source and destination integrity.
        // --------------------------------------------------------

        for (i = 0;
             i < DMA_WORD_COUNT;
             i = i + 1) begin

            check_model_word(
                DMA_SRC_BASE +
                    (i * 4),
                dma_source_word(i),
                "DMA source survives three-master contention"
            );

            check_model_word(
                DMA_DST_BASE +
                    (i * 4),
                dma_source_word(i),
                "DMA destination matches source under three-master contention"
            );
        end

        // --------------------------------------------------------
        // CPU and unrelated-memory integrity.
        // --------------------------------------------------------

        check_model_word(
            CPU_CONTENTION_ADDR,
            32'd64,
            "CPU contention word contains final expected value 64"
        );

        check_model_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA,
            "low unrelated-memory guard survives three-master contention"
        );

        check_model_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA,
            "high unrelated-memory guard survives three-master contention"
        );

        check(
            !dut.cpu_mem_valid &&
            !dut.gpu_sdram_valid &&
            !dut.dma_sdram_valid &&
            !dut.shared_sdram_valid,
            "all production memory interfaces are idle after completion"
        );

        check(
            dut.scratch.scratch_reg ==
                32'h00000000,
            "three-master contention leaves scratch MMIO unchanged"
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
                "CPU_LOGICAL_READS: %0d",
                cpu_sdram_reads
            );

            $display(
                "CPU_LOGICAL_WRITES: %0d",
                cpu_sdram_writes
            );

            $display(
                "CPU_LOGICAL_TOTAL: %0d",
                cpu_sdram_total
            );

            $display(
                "GPU_LOGICAL_READS: %0d",
                gpu_sdram_reads
            );

            $display(
                "GPU_LOGICAL_WRITES: %0d",
                gpu_sdram_writes
            );

            $display(
                "GPU_LOGICAL_TOTAL: %0d",
                gpu_sdram_total
            );

            $display(
                "DMA_LOGICAL_READS: %0d",
                dma_sdram_reads
            );

            $display(
                "DMA_LOGICAL_WRITES: %0d",
                dma_sdram_writes
            );

            $display(
                "DMA_LOGICAL_TOTAL: %0d",
                dma_sdram_total
            );

            $display(
                "TRIPLE_REQUEST_CYCLES: %0d",
                triple_request_cycles
            );

            $display(
                "CONTESTED_CPU_COMPLETIONS: %0d",
                contested_cpu_completions
            );

            $display(
                "CONTESTED_GPU_COMPLETIONS: %0d",
                contested_gpu_completions
            );

            $display(
                "CONTESTED_DMA_COMPLETIONS: %0d",
                contested_dma_completions
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
