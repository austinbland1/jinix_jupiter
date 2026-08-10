`timescale 1ns/1ps

module jupiter_cpu_dma_contention_tb;

    localparam [31:0] SDRAM_BASE =
        32'h10000000;

    localparam [31:0] GUARD_LOW_ADDR =
        32'h10000000;

    localparam [31:0] SRC_BASE =
        32'h10000100;

    localparam [31:0] DST_BASE =
        32'h10000300;

    localparam [31:0] GUARD_HIGH_ADDR =
        32'h10000500;

    localparam [31:0] CONTENTION_ADDR =
        32'h10000600;

    localparam [31:0] GUARD_LOW_DATA =
        32'h13579BDF;

    localparam [31:0] GUARD_HIGH_DATA =
        32'h2468ACE0;

    localparam integer WORD_COUNT = 64;
    localparam integer CPU_ITERATIONS = 64;
    localparam integer MODEL_SLOTS = 300;

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

    integer dma_mmio_store_count;
    integer dma_mmio_load_count;

    integer cpu_sdram_reads;
    integer cpu_sdram_writes;
    integer cpu_sdram_total;

    integer dma_sdram_reads;
    integer dma_sdram_writes;
    integer dma_sdram_total;

    integer contention_store_count;
    integer contention_load_count;

    integer cpu_completions_while_dma_busy;
    integer cpu_completions_while_dma_pending;
    integer dma_completions_while_cpu_pending;

    integer simultaneous_request_cycles;

    integer contested_cpu_completions;
    integer contested_dma_completions;

    integer physical_active_count;
    integer physical_read_count;
    integer physical_write_count;

    reg bad_dma_mmio_selection;
    reg bad_cpu_contention_readback;
    reg bad_dma_sequence;
    reg contested_grant_seen;

    reg [31:0] expected_contention_data;

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
            source_word =
                32'hA5000000 + index;
        end
    endfunction

    function [31:0] destination_sentinel;
        input integer index;
        begin
            destination_sentinel =
                32'hDEAD0000 + index;
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

    // Testbench-only preload of the sparse behavioral SDRAM.
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

    // --------------------------------------------------------
    // CPU-visible DMA MMIO accounting and target isolation.
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

    // --------------------------------------------------------
    // CPU external-SDRAM logical completions.
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

            if (dut.dma.busy)
                cpu_completions_while_dma_busy <=
                    cpu_completions_while_dma_busy + 1;

            if (dut.dma_sdram_valid)
                cpu_completions_while_dma_pending <=
                    cpu_completions_while_dma_pending + 1;

            if (dut.sdram_addr ==
                CONTENTION_ADDR) begin

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
    // DMA external-SDRAM logical completions.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset &&
            dut.dma_sdram_valid &&
            dut.dma_sdram_ready) begin

            dma_sdram_total <=
                dma_sdram_total + 1;

            if (dut.dma_sdram_write) begin
                if (dma_sdram_writes >=
                    WORD_COUNT) begin

                    bad_dma_sequence <=
                        1'b1;
                end else begin
                    // Each write must follow the corresponding read.
                    if (dma_sdram_reads !=
                        (dma_sdram_writes + 1))
                        bad_dma_sequence <=
                            1'b1;

                    if (dut.dma_sdram_addr !=
                        DST_BASE +
                        (dma_sdram_writes * 4))
                        bad_dma_sequence <=
                            1'b1;

                    if (dut.dma_sdram_wdata !=
                        source_word(
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
                    WORD_COUNT) begin

                    bad_dma_sequence <=
                        1'b1;
                end else begin
                    // A new read begins only after the previous write.
                    if (dma_sdram_reads !=
                        dma_sdram_writes)
                        bad_dma_sequence <=
                            1'b1;

                    if (dut.dma_sdram_addr !=
                        SRC_BASE +
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
        end
    end

    // --------------------------------------------------------
    // Explicit integrated contention observability.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!reset) begin
            if (dut.sdram_valid &&
                dut.dma_sdram_valid)
                simultaneous_request_cycles <=
                    simultaneous_request_cycles + 1;

            if (dut.sdram_arbiter.grant_contested)
                contested_grant_seen <=
                    1'b1;

            if (dut.sdram_arbiter.grant_contested &&
                dut.sdram_ready)
                contested_cpu_completions <=
                    contested_cpu_completions + 1;

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
        clk   = 1'b0;
        reset = 1'b1;

        checks   = 0;
        failures = 0;
        cycles   = 0;

        preload_slot = 0;

        dma_mmio_store_count = 0;
        dma_mmio_load_count  = 0;

        cpu_sdram_reads  = 0;
        cpu_sdram_writes = 0;
        cpu_sdram_total  = 0;

        dma_sdram_reads  = 0;
        dma_sdram_writes = 0;
        dma_sdram_total  = 0;

        contention_store_count = 0;
        contention_load_count  = 0;

        cpu_completions_while_dma_busy = 0;
        cpu_completions_while_dma_pending = 0;
        dma_completions_while_cpu_pending = 0;

        simultaneous_request_cycles = 0;

        contested_cpu_completions = 0;
        contested_dma_completions = 0;

        physical_active_count = 0;
        physical_read_count   = 0;
        physical_write_count  = 0;

        bad_dma_mmio_selection =
            1'b0;

        bad_cpu_contention_readback =
            1'b0;

        bad_dma_sequence =
            1'b0;

        contested_grant_seen =
            1'b0;

        expected_contention_data =
            32'h00000000;

        /*
         * Real CPU + DMA contention program.
         *
         * 00-40:
         *     construct r1 = 0x10000000
         *
         * 44:
         *     r10 = DMA MMIO base 0x1200
         *
         * 48:
         *     r2 = SRC_BASE = 0x10000100
         *
         * 4C:
         *     r3 = DST_BASE = 0x10000300
         *
         * 50:
         *     r4 = 64 DMA words
         *
         * 54:
         *     r5 = 1 START
         *
         * 58:
         *     r6 = 2 DONE
         *
         * 5C-68:
         *     configure and START real DMA
         *
         * 6C:
         *     r7 = CPU contention address 0x10000600
         *
         * 70:
         *     r8 = loop counter zero
         *
         * 74:
         *     r9 = 64 iterations
         *
         * CPU loop at 78:
         *
         *     ADDI r8, r8, 1
         *     STW  r8, 0(r7)
         *     LDW  r12, 0(r7)
         *     BNE  r8, r9, -4
         *
         * After 64 real CPU store/load pairs:
         *
         *     poll DMA STATUS until DONE=2
         *     HALT
         *
         * CPU and DMA operate on disjoint SDRAM regions.
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
                14'd768
            ));
        dut.ram.memory_b1[19] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd768
            )) >> 8);
        dut.ram.memory_b2[19] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd768
            )) >> 16);
        dut.ram.memory_b3[19] = ((enc_i(
                8'h10,
                5'd3,
                5'd1,
                14'd768
            )) >> 24);

        dut.ram.memory_b0[20] = (enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd64
            ));
        dut.ram.memory_b1[20] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd64
            )) >> 8);
        dut.ram.memory_b2[20] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd64
            )) >> 16);
        dut.ram.memory_b3[20] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd64
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

        dut.ram.memory_b0[27] = (enc_i(
                8'h10,
                5'd7,
                5'd1,
                14'd1536
            ));
        dut.ram.memory_b1[27] = ((enc_i(
                8'h10,
                5'd7,
                5'd1,
                14'd1536
            )) >> 8);
        dut.ram.memory_b2[27] = ((enc_i(
                8'h10,
                5'd7,
                5'd1,
                14'd1536
            )) >> 16);
        dut.ram.memory_b3[27] = ((enc_i(
                8'h10,
                5'd7,
                5'd1,
                14'd1536
            )) >> 24);

        dut.ram.memory_b0[28] = (enc_i(
                8'h10,
                5'd8,
                5'd0,
                14'd0
            ));
        dut.ram.memory_b1[28] = ((enc_i(
                8'h10,
                5'd8,
                5'd0,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[28] = ((enc_i(
                8'h10,
                5'd8,
                5'd0,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[28] = ((enc_i(
                8'h10,
                5'd8,
                5'd0,
                14'd0
            )) >> 24);

        dut.ram.memory_b0[29] = (enc_i(
                8'h10,
                5'd9,
                5'd0,
                14'd64
            ));
        dut.ram.memory_b1[29] = ((enc_i(
                8'h10,
                5'd9,
                5'd0,
                14'd64
            )) >> 8);
        dut.ram.memory_b2[29] = ((enc_i(
                8'h10,
                5'd9,
                5'd0,
                14'd64
            )) >> 16);
        dut.ram.memory_b3[29] = ((enc_i(
                8'h10,
                5'd9,
                5'd0,
                14'd64
            )) >> 24);

        // CPU contention loop begins at index 30 / PC 0x78.
        dut.ram.memory_b0[30] = (enc_i(
                8'h10,
                5'd8,
                5'd8,
                14'd1
            ));
        dut.ram.memory_b1[30] = ((enc_i(
                8'h10,
                5'd8,
                5'd8,
                14'd1
            )) >> 8);
        dut.ram.memory_b2[30] = ((enc_i(
                8'h10,
                5'd8,
                5'd8,
                14'd1
            )) >> 16);
        dut.ram.memory_b3[30] = ((enc_i(
                8'h10,
                5'd8,
                5'd8,
                14'd1
            )) >> 24);

        dut.ram.memory_b0[31] = (enc_s(
                8'h21,
                5'd8,
                5'd7,
                14'd0
            ));
        dut.ram.memory_b1[31] = ((enc_s(
                8'h21,
                5'd8,
                5'd7,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[31] = ((enc_s(
                8'h21,
                5'd8,
                5'd7,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[31] = ((enc_s(
                8'h21,
                5'd8,
                5'd7,
                14'd0
            )) >> 24);

        dut.ram.memory_b0[32] = (enc_i(
                8'h20,
                5'd12,
                5'd7,
                14'd0
            ));
        dut.ram.memory_b1[32] = ((enc_i(
                8'h20,
                5'd12,
                5'd7,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[32] = ((enc_i(
                8'h20,
                5'd12,
                5'd7,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[32] = ((enc_i(
                8'h20,
                5'd12,
                5'd7,
                14'd0
            )) >> 24);

        // PC+4 at index 34; target index 30 => -4 words.
        dut.ram.memory_b0[33] = (enc_b(
                8'h31,
                5'd8,
                5'd9,
                14'h3FFC
            ));
        dut.ram.memory_b1[33] = ((enc_b(
                8'h31,
                5'd8,
                5'd9,
                14'h3FFC
            )) >> 8);
        dut.ram.memory_b2[33] = ((enc_b(
                8'h31,
                5'd8,
                5'd9,
                14'h3FFC
            )) >> 16);
        dut.ram.memory_b3[33] = ((enc_b(
                8'h31,
                5'd8,
                5'd9,
                14'h3FFC
            )) >> 24);

        // DMA STATUS polling begins at index 34.
        dut.ram.memory_b0[34] = (enc_i(
                8'h20,
                5'd13,
                5'd10,
                14'd4
            ));
        dut.ram.memory_b1[34] = ((enc_i(
                8'h20,
                5'd13,
                5'd10,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[34] = ((enc_i(
                8'h20,
                5'd13,
                5'd10,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[34] = ((enc_i(
                8'h20,
                5'd13,
                5'd10,
                14'd4
            )) >> 24);

        // PC+4 at index 36; target index 34 => -2 words.
        dut.ram.memory_b0[35] = (enc_b(
                8'h31,
                5'd13,
                5'd6,
                14'h3FFE
            ));
        dut.ram.memory_b1[35] = ((enc_b(
                8'h31,
                5'd13,
                5'd6,
                14'h3FFE
            )) >> 8);
        dut.ram.memory_b2[35] = ((enc_b(
                8'h31,
                5'd13,
                5'd6,
                14'h3FFE
            )) >> 16);
        dut.ram.memory_b3[35] = ((enc_b(
                8'h31,
                5'd13,
                5'd6,
                14'h3FFE
            )) >> 24);

        dut.ram.memory_b0[36] = (enc_n(8'hFF));
        dut.ram.memory_b1[36] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[36] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[36] = ((enc_n(8'hFF)) >> 24);

        // Let reset-driven state settle before releasing reset.
        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.dma.busy &&
            !dut.dma.done &&
            !dut.dma_sdram_valid,
            "DMA begins idle before CPU/DMA contention"
        );

        check(
            !dut.gpu.busy &&
            !dut.gpu_sdram_valid,
            "GPU remains inactive for CPU/DMA-only contention"
        );

        @(negedge clk);
        reset = 1'b0;

        // --------------------------------------------------------
        // Behavioral SDRAM preload.
        //
        // 2 halfwords low guard
        // 2 halfwords high guard
        // 2 halfwords CPU contention word
        // 128 halfwords DMA source
        // 128 halfwords DMA destination
        // = 262 halfwords total.
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
            CONTENTION_ADDR,
            32'h00000000
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
                destination_sentinel(i)
            );
        end

        check(
            preload_slot == 262,
            "behavioral SDRAM contains expected 262 preloaded halfwords"
        );

        // --------------------------------------------------------
        // Run real CPU and real DMA concurrently.
        // --------------------------------------------------------

        while (!halted &&
               cycles < 60000) begin

            @(posedge clk);
            #1;

            cycles = cycles + 1;
        end

        check(
            halted,
            "CPU completes CPU/DMA contention and polling program"
        );

        check(
            dut.cpu.pc ==
                32'h00000090,
            "CPU HALT occurs at expected final PC 0x90"
        );

        check(
            dut.dma.done &&
            !dut.dma.busy,
            "real DMA completes before CPU HALT"
        );

        check(
            dut.cpu.regs[8] ==
                CPU_ITERATIONS &&
            dut.cpu.regs[12] ==
                CPU_ITERATIONS,
            "CPU completes all contention iterations with exact readback"
        );

        check(
            dut.cpu.regs[13] ==
                32'h00000002,
            "CPU STATUS polling observes DMA DONE"
        );

        check(
            dut.dma.active_src_base ==
                SRC_BASE &&
            dut.dma.active_dst_base ==
                DST_BASE &&
            dut.dma.active_length_words ==
                WORD_COUNT,
            "real DMA active snapshot matches CPU configuration"
        );

        check(
            dma_mmio_store_count == 4,
            "CPU performs exactly four DMA configuration/start stores"
        );

        check(
            dma_mmio_load_count >= 1,
            "CPU performs at least one DMA STATUS load"
        );

        check(
            !bad_dma_mmio_selection,
            "CPU DMA MMIO accesses select only DMA control target"
        );

        // --------------------------------------------------------
        // Exact CPU logical traffic.
        // --------------------------------------------------------

        check(
            cpu_sdram_writes ==
                CPU_ITERATIONS,
            "CPU completes exactly 64 contention SDRAM writes"
        );

        check(
            cpu_sdram_reads ==
                CPU_ITERATIONS,
            "CPU completes exactly 64 contention SDRAM reads"
        );

        check(
            cpu_sdram_total ==
                (CPU_ITERATIONS * 2),
            "CPU completes exactly 128 logical SDRAM transactions"
        );

        check(
            contention_store_count ==
                CPU_ITERATIONS,
            "CPU executes all 64 contention stores"
        );

        check(
            contention_load_count ==
                CPU_ITERATIONS,
            "CPU executes all 64 contention loads"
        );

        check(
            !bad_cpu_contention_readback,
            "every CPU contention load matches the most recent completed store"
        );

        // --------------------------------------------------------
        // Exact DMA logical traffic.
        // --------------------------------------------------------

        check(
            dma_sdram_reads ==
                WORD_COUNT,
            "DMA completes exactly 64 source reads"
        );

        check(
            dma_sdram_writes ==
                WORD_COUNT,
            "DMA completes exactly 64 destination writes"
        );

        check(
            dma_sdram_total ==
                (WORD_COUNT * 2),
            "DMA completes exactly 128 logical SDRAM transactions"
        );

        check(
            !bad_dma_sequence,
            "DMA read/write sequence addresses data and strobes remain exact"
        );

        // --------------------------------------------------------
        // Prove actual overlap, contention, and progress.
        // --------------------------------------------------------

        check(
            cpu_completions_while_dma_busy > 0,
            "CPU completes SDRAM traffic while DMA engine is busy"
        );

        check(
            cpu_completions_while_dma_pending > 0,
            "CPU completes SDRAM traffic while DMA request is pending"
        );

        check(
            dma_completions_while_cpu_pending > 0,
            "DMA completes SDRAM traffic while CPU request is pending"
        );

        check(
            simultaneous_request_cycles > 0,
            "CPU and DMA present simultaneous SDRAM requests"
        );

        check(
            contested_grant_seen,
            "integrated arbiter records a held CPU/DMA contested grant"
        );

        check(
            contested_cpu_completions > 0,
            "CPU wins at least one completed CPU/DMA contested transaction"
        );

        check(
            contested_dma_completions > 0,
            "DMA wins at least one completed CPU/DMA contested transaction"
        );

        // --------------------------------------------------------
        // Exact aggregate physical command accounting.
        //
        // CPU:
        //   64 reads + 64 writes = 128 logical
        //
        // DMA:
        //   64 reads + 64 writes = 128 logical
        //
        // Total:
        //   128 logical reads
        //   128 logical writes
        //   256 logical accesses
        //
        // Each logical access becomes two 16-bit physical accesses.
        // --------------------------------------------------------

        check(
            physical_read_count == 256,
            "128 logical reads produce 256 physical 16-bit READs"
        );

        check(
            physical_write_count == 256,
            "128 logical writes produce 256 physical 16-bit WRITEs"
        );

        check(
            physical_active_count == 512,
            "256 logical accesses produce 512 ACTIVE commands"
        );

        check(
            dut.sdram_initialized,
            "physical SDRAM controller completes initialization"
        );

        check(
            protocol_error == 1'b0,
            "behavioral SDRAM reports no protocol error under CPU/DMA contention"
        );

        // --------------------------------------------------------
        // DMA source and destination integrity.
        // --------------------------------------------------------

        for (i = 0;
             i < WORD_COUNT;
             i = i + 1) begin

            check_model_word(
                SRC_BASE + (i * 4),
                source_word(i),
                "DMA source word survives CPU/DMA contention"
            );

            check_model_word(
                DST_BASE + (i * 4),
                source_word(i),
                "DMA destination word matches source under CPU/DMA contention"
            );
        end

        check_model_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA,
            "low unrelated-memory guard survives CPU/DMA contention"
        );

        check_model_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA,
            "high unrelated-memory guard survives CPU/DMA contention"
        );

        check_model_word(
            CONTENTION_ADDR,
            32'd64,
            "CPU contention word contains final expected value 64"
        );

        check(
            !dut.cpu_mem_valid &&
            !dut.dma_sdram_valid &&
            !dut.gpu_sdram_valid &&
            !dut.shared_sdram_valid,
            "all production memory interfaces are idle after CPU/DMA completion"
        );

        check(
            dut.gpu.tilemap_base_reg ==
                32'h00000000,
            "CPU/DMA contention does not alter GPU control state"
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
                "SIMULTANEOUS_REQUEST_CYCLES: %0d",
                simultaneous_request_cycles
            );

            $display(
                "CONTESTED_CPU_COMPLETIONS: %0d",
                contested_cpu_completions
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
