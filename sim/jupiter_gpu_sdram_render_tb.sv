`timescale 1ns/1ps

module jupiter_gpu_sdram_render_tb;

    localparam [31:0] SDRAM_BASE      = 32'h10000000;
    localparam [31:0] TILEMAP_BASE    = 32'h10000100;
    localparam [31:0] TILEDATA_BASE   = 32'h10000400;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h10000800;

    localparam [31:0] GUARD_LOW_ADDR  = 32'h10000000;
    localparam [31:0] GUARD_HIGH_ADDR = 32'h10000C00;

    localparam [31:0] GUARD_LOW_DATA  = 32'h11223344;
    localparam [31:0] GUARD_HIGH_DATA = 32'h55667788;

    localparam integer MODEL_SLOTS = 600;

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
    integer render_cycles = 0;

    integer cpu_gpu_store_count = 0;
    reg bad_gpu_selection = 1'b0;

    integer gpu_read_completions = 0;
    integer gpu_write_completions = 0;
    integer gpu_total_completions = 0;

    integer physical_active_count = 0;
    integer physical_read_count = 0;
    integer physical_write_count = 0;

    integer preload_slot = 0;

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

    task automatic check;
        input condition;
        input [8*128-1:0] message;
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

    // Testbench-only preload of the behavioral SDRAM model.
    //
    // mem_tag is the controller's H[25:0] halfword address, which is
    // (Jupiter byte address - 0x10000000) >> 1.
    task automatic preload_word;
        input [31:0] byte_addr;
        input [31:0] data;
        reg [25:0] half_tag;
        begin
            if ((preload_slot + 1) >= MODEL_SLOTS) begin
                $display("FAIL: behavioral SDRAM preload exceeded slots");
                $fatal(1);
            end

            half_tag = (byte_addr - SDRAM_BASE) >> 1;

            dram.mem_valid[preload_slot] = 1'b1;
            dram.mem_tag[preload_slot]   = half_tag;
            dram.mem_data[preload_slot]  = data[15:0];
            preload_slot = preload_slot + 1;

            dram.mem_valid[preload_slot] = 1'b1;
            dram.mem_tag[preload_slot]   = half_tag + 26'd1;
            dram.mem_data[preload_slot]  = data[31:16];
            preload_slot = preload_slot + 1;
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
            low_tag  = (byte_addr - SDRAM_BASE) >> 1;
            high_tag = low_tag + 26'd1;

            low_found  = 1'b0;
            high_found = 1'b0;

            low_data  = 16'h0000;
            high_data = 16'h0000;

            for (k = 0; k < MODEL_SLOTS; k = k + 1) begin
                if (dram.mem_valid[k] &&
                    dram.mem_tag[k] == low_tag) begin
                    low_found = 1'b1;
                    low_data = dram.mem_data[k];
                end

                if (dram.mem_valid[k] &&
                    dram.mem_tag[k] == high_tag) begin
                    high_found = 1'b1;
                    high_data = dram.mem_data[k];
                end
            end

            check(
                low_found &&
                high_found &&
                {high_data, low_data} == expected_data,
                message
            );
        end
    endtask

    // Count completed CPU->GPU MMIO stores and ensure the interconnect
    // selects only the GPU target for them.
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
                cpu_gpu_store_count <= cpu_gpu_store_count + 1;
        end
    end

    // Count logical GPU transactions before the arbiter.
    always @(posedge clk) begin
        if (!reset &&
            dut.gpu_sdram_valid &&
            dut.gpu_sdram_ready) begin

            gpu_total_completions <= gpu_total_completions + 1;

            if (dut.gpu_sdram_write)
                gpu_write_completions <=
                    gpu_write_completions + 1;
            else
                gpu_read_completions <=
                    gpu_read_completions + 1;
        end
    end

    // Count commands at the actual physical 16-bit SDRAM pins.
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
         * Real CPU launch program.
         *
         * r1  = 0x10000000 SDRAM base
         * r10 = 0x00001100 GPU MMIO base
         *
         * r2  = 0x10000100 TILEMAP_BASE
         * r3  = 0x10000400 TILEDATA_BASE
         * r4  = 0x10000800 FRAMEBUFFER_BASE
         * r5  = 0x00000202 MAP_SIZE: width=2, height=2
         * r6  = 1 CONTROL.START
         *
         * The CPU halts immediately after launching the GPU. The renderer
         * then performs the complete 2x2 operation through the production
         * arbiter/frontend/controller path.
         */

        dut.ram.memory_b0[0] = (enc_i(8'h10, 5'd1, 5'd0, 14'd4096));
        dut.ram.memory_b1[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4096)) >> 8);
        dut.ram.memory_b2[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4096)) >> 16);
        dut.ram.memory_b3[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4096)) >> 24);

        for (i = 1; i <= 16; i = i + 1) begin
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

        dut.ram.memory_b0[17] = (enc_i(8'h10, 5'd10, 5'd0, 14'd4352));
        dut.ram.memory_b1[17] = ((enc_i(8'h10, 5'd10, 5'd0, 14'd4352)) >> 8);
        dut.ram.memory_b2[17] = ((enc_i(8'h10, 5'd10, 5'd0, 14'd4352)) >> 16);
        dut.ram.memory_b3[17] = ((enc_i(8'h10, 5'd10, 5'd0, 14'd4352)) >> 24);

        dut.ram.memory_b0[18] = (enc_i(8'h10, 5'd2, 5'd1, 14'd256));
        dut.ram.memory_b1[18] = ((enc_i(8'h10, 5'd2, 5'd1, 14'd256)) >> 8);
        dut.ram.memory_b2[18] = ((enc_i(8'h10, 5'd2, 5'd1, 14'd256)) >> 16);
        dut.ram.memory_b3[18] = ((enc_i(8'h10, 5'd2, 5'd1, 14'd256)) >> 24);

        dut.ram.memory_b0[19] = (enc_i(8'h10, 5'd3, 5'd1, 14'd1024));
        dut.ram.memory_b1[19] = ((enc_i(8'h10, 5'd3, 5'd1, 14'd1024)) >> 8);
        dut.ram.memory_b2[19] = ((enc_i(8'h10, 5'd3, 5'd1, 14'd1024)) >> 16);
        dut.ram.memory_b3[19] = ((enc_i(8'h10, 5'd3, 5'd1, 14'd1024)) >> 24);

        dut.ram.memory_b0[20] = (enc_i(8'h10, 5'd4, 5'd1, 14'd2048));
        dut.ram.memory_b1[20] = ((enc_i(8'h10, 5'd4, 5'd1, 14'd2048)) >> 8);
        dut.ram.memory_b2[20] = ((enc_i(8'h10, 5'd4, 5'd1, 14'd2048)) >> 16);
        dut.ram.memory_b3[20] = ((enc_i(8'h10, 5'd4, 5'd1, 14'd2048)) >> 24);

        dut.ram.memory_b0[21] = (enc_i(8'h10, 5'd5, 5'd0, 14'd514));
        dut.ram.memory_b1[21] = ((enc_i(8'h10, 5'd5, 5'd0, 14'd514)) >> 8);
        dut.ram.memory_b2[21] = ((enc_i(8'h10, 5'd5, 5'd0, 14'd514)) >> 16);
        dut.ram.memory_b3[21] = ((enc_i(8'h10, 5'd5, 5'd0, 14'd514)) >> 24);

        dut.ram.memory_b0[22] = (enc_i(8'h10, 5'd6, 5'd0, 14'd1));
        dut.ram.memory_b1[22] = ((enc_i(8'h10, 5'd6, 5'd0, 14'd1)) >> 8);
        dut.ram.memory_b2[22] = ((enc_i(8'h10, 5'd6, 5'd0, 14'd1)) >> 16);
        dut.ram.memory_b3[22] = ((enc_i(8'h10, 5'd6, 5'd0, 14'd1)) >> 24);

        dut.ram.memory_b0[23] = (enc_s(8'h21, 5'd2, 5'd10, 14'd8));
        dut.ram.memory_b1[23] = ((enc_s(8'h21, 5'd2, 5'd10, 14'd8)) >> 8);
        dut.ram.memory_b2[23] = ((enc_s(8'h21, 5'd2, 5'd10, 14'd8)) >> 16);
        dut.ram.memory_b3[23] = ((enc_s(8'h21, 5'd2, 5'd10, 14'd8)) >> 24);

        dut.ram.memory_b0[24] = (enc_s(8'h21, 5'd3, 5'd10, 14'd12));
        dut.ram.memory_b1[24] = ((enc_s(8'h21, 5'd3, 5'd10, 14'd12)) >> 8);
        dut.ram.memory_b2[24] = ((enc_s(8'h21, 5'd3, 5'd10, 14'd12)) >> 16);
        dut.ram.memory_b3[24] = ((enc_s(8'h21, 5'd3, 5'd10, 14'd12)) >> 24);

        dut.ram.memory_b0[25] = (enc_s(8'h21, 5'd4, 5'd10, 14'd16));
        dut.ram.memory_b1[25] = ((enc_s(8'h21, 5'd4, 5'd10, 14'd16)) >> 8);
        dut.ram.memory_b2[25] = ((enc_s(8'h21, 5'd4, 5'd10, 14'd16)) >> 16);
        dut.ram.memory_b3[25] = ((enc_s(8'h21, 5'd4, 5'd10, 14'd16)) >> 24);

        dut.ram.memory_b0[26] = (enc_s(8'h21, 5'd5, 5'd10, 14'd20));
        dut.ram.memory_b1[26] = ((enc_s(8'h21, 5'd5, 5'd10, 14'd20)) >> 8);
        dut.ram.memory_b2[26] = ((enc_s(8'h21, 5'd5, 5'd10, 14'd20)) >> 16);
        dut.ram.memory_b3[26] = ((enc_s(8'h21, 5'd5, 5'd10, 14'd20)) >> 24);

        dut.ram.memory_b0[27] = (enc_s(8'h21, 5'd6, 5'd10, 14'd0));
        dut.ram.memory_b1[27] = ((enc_s(8'h21, 5'd6, 5'd10, 14'd0)) >> 8);
        dut.ram.memory_b2[27] = ((enc_s(8'h21, 5'd6, 5'd10, 14'd0)) >> 16);
        dut.ram.memory_b3[27] = ((enc_s(8'h21, 5'd6, 5'd10, 14'd0)) >> 24);

        dut.ram.memory_b0[28] = (enc_n(8'hFF));
        dut.ram.memory_b1[28] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[28] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[28] = ((enc_n(8'hFF)) >> 24);

        // Allow all reset-driven nonblocking assignments in the DUT/model
        // to settle before preload.
        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.gpu.busy &&
            !dut.gpu.done &&
            !dut.gpu_sdram_valid,
            "GPU begins idle before integrated render"
        );

        @(negedge clk);
        reset = 1'b0;

        // --------------------------------------------------------
        // Preload physical SDRAM after reset is released but before
        // the CPU reaches GPU launch.
        // --------------------------------------------------------

        preload_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA
        );

        preload_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA
        );

        // Four row-major tilemap entries selecting tiles 1..4.
        for (tile_linear_i = 0;
             tile_linear_i < 4;
             tile_linear_i = tile_linear_i + 1) begin

            preload_word(
                TILEMAP_BASE +
                    (tile_linear_i * 32'd4),
                32'hCAFE0000 +
                    (tile_linear_i + 1)
            );
        end

        // Four complete 8x8 tiles. Tile zero remains unused.
        for (tile_linear_i = 0;
             tile_linear_i < 4;
             tile_linear_i = tile_linear_i + 1) begin

            tile_index_i = tile_linear_i + 1;

            for (row_i = 0;
                 row_i < 8;
                 row_i = row_i + 1) begin

                for (word_i = 0;
                     word_i < 4;
                     word_i = word_i + 1) begin

                    preload_word(
                        TILEDATA_BASE +
                            (tile_index_i * 32'd128) +
                            (row_i * 32'd16) +
                            (word_i * 32'd4),
                        pattern_word(
                            tile_linear_i,
                            row_i,
                            word_i
                        )
                    );
                end
            end
        end

        // Seed the full 16x16 framebuffer with a sentinel so every expected
        // output word must actually be overwritten by GPU physical writes.
        for (fb_word_i = 0;
             fb_word_i < 128;
             fb_word_i = fb_word_i + 1) begin

            preload_word(
                FRAMEBUFFER_BASE +
                    (fb_word_i * 32'd4),
                32'h55AA55AA
            );
        end

        check(
            preload_slot == 524,
            "behavioral SDRAM contains expected 524 preloaded halfwords"
        );

        check_model_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA,
            "low unrelated-memory guard is present before render"
        );

        check_model_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA,
            "high unrelated-memory guard is present before render"
        );

        // --------------------------------------------------------
        // CPU configures and launches the real GPU.
        // --------------------------------------------------------

        while (!halted && cycles < 2000) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(
            halted,
            "CPU reaches HALT after configuring and launching GPU"
        );

        check(
            dut.cpu.pc == 32'h00000070,
            "CPU HALT occurs at expected final launch-program PC"
        );

        check(
            cpu_gpu_store_count == 5,
            "CPU completes exactly five GPU configuration/start stores"
        );

        check(
            !bad_gpu_selection,
            "CPU GPU-MMIO stores select only the GPU target"
        );

        check(
            dut.gpu.tilemap_base_reg == TILEMAP_BASE &&
            dut.gpu.tiledata_base_reg == TILEDATA_BASE &&
            dut.gpu.framebuffer_base_reg == FRAMEBUFFER_BASE,
            "CPU programs all three GPU memory-base registers"
        );

        check(
            dut.gpu.active_tilemap_base == TILEMAP_BASE &&
            dut.gpu.active_tiledata_base == TILEDATA_BASE &&
            dut.gpu.active_framebuffer_base == FRAMEBUFFER_BASE &&
            dut.gpu.active_map_size == 16'h0202,
            "GPU active render snapshot matches CPU configuration"
        );

        check(
            dut.gpu.busy &&
            !dut.gpu.done,
            "GPU remains busy after CPU halts"
        );

        check(
            !dut.cpu_mem_valid,
            "halted CPU issues no further memory transaction"
        );

        // --------------------------------------------------------
        // Let the complete renderer run through physical SDRAM.
        // --------------------------------------------------------

        while (!dut.gpu.done &&
               render_cycles < 100000) begin
            @(posedge clk);
            #1;
            render_cycles = render_cycles + 1;
        end

        check(
            dut.gpu.done &&
            !dut.gpu.busy,
            "integrated 2x2 GPU render reaches DONE"
        );

        check(
            dut.gpu.renderer_state == 3'd0,
            "completed integrated renderer returns to idle state"
        );

        check(
            !dut.gpu_sdram_valid &&
            !dut.shared_sdram_valid,
            "integrated memory path returns to idle after render"
        );

        check(
            dut.sdram_initialized,
            "physical SDRAM controller completed initialization"
        );

        // --------------------------------------------------------
        // Logical and physical transaction accounting.
        // --------------------------------------------------------

        check(
            gpu_read_completions == 132,
            "GPU completes four tilemap plus 128 tile-data reads"
        );

        check(
            gpu_write_completions == 128,
            "GPU completes 128 framebuffer writes"
        );

        check(
            gpu_total_completions == 260,
            "GPU completes exactly 260 logical SDRAM transactions"
        );

        check(
            physical_read_count == 264,
            "132 logical GPU reads produce 264 physical 16-bit READs"
        );

        check(
            physical_write_count == 256,
            "128 logical GPU writes produce 256 physical 16-bit WRITEs"
        );

        check(
            physical_active_count == 520,
            "260 logical GPU transactions produce 520 ACTIVE commands"
        );

        check(
            protocol_error == 1'b0,
            "behavioral SDRAM reports no protocol error during render"
        );

        // --------------------------------------------------------
        // Source regions must remain unchanged.
        // --------------------------------------------------------

        for (tile_linear_i = 0;
             tile_linear_i < 4;
             tile_linear_i = tile_linear_i + 1) begin

            check_model_word(
                TILEMAP_BASE +
                    (tile_linear_i * 32'd4),
                32'hCAFE0000 +
                    (tile_linear_i + 1),
                "tilemap source word remains unchanged"
            );
        end

        for (tile_linear_i = 0;
             tile_linear_i < 4;
             tile_linear_i = tile_linear_i + 1) begin

            tile_index_i = tile_linear_i + 1;

            for (row_i = 0;
                 row_i < 8;
                 row_i = row_i + 1) begin

                for (word_i = 0;
                     word_i < 4;
                     word_i = word_i + 1) begin

                    check_model_word(
                        TILEDATA_BASE +
                            (tile_index_i * 32'd128) +
                            (row_i * 32'd16) +
                            (word_i * 32'd4),
                        pattern_word(
                            tile_linear_i,
                            row_i,
                            word_i
                        ),
                        "tile-data source word remains unchanged"
                    );
                end
            end
        end

        // --------------------------------------------------------
        // Verify every word of the resulting 16x16 framebuffer.
        // --------------------------------------------------------

        for (tile_y_i = 0;
             tile_y_i < 2;
             tile_y_i = tile_y_i + 1) begin

            for (tile_x_i = 0;
                 tile_x_i < 2;
                 tile_x_i = tile_x_i + 1) begin

                tile_linear_i =
                    (tile_y_i * 2) + tile_x_i;

                for (row_i = 0;
                     row_i < 8;
                     row_i = row_i + 1) begin

                    for (word_i = 0;
                         word_i < 4;
                         word_i = word_i + 1) begin

                        check_model_word(
                            FRAMEBUFFER_BASE +
                                (((tile_y_i * 8) + row_i) *
                                    32'd32) +
                                (tile_x_i * 32'd16) +
                                (word_i * 32'd4),
                            pattern_word(
                                tile_linear_i,
                                row_i,
                                word_i
                            ),
                            "framebuffer word matches deterministic 2x2 image"
                        );
                    end
                end
            end
        end

        check_model_word(
            FRAMEBUFFER_BASE + 32'h000001FC,
            pattern_word(3, 7, 3),
            "final framebuffer word matches tile one-one row seven word three"
        );

        // --------------------------------------------------------
        // Unrelated memory guards prove the renderer stayed bounded.
        // --------------------------------------------------------

        check_model_word(
            GUARD_LOW_ADDR,
            GUARD_LOW_DATA,
            "low unrelated-memory guard survives complete render"
        );

        check_model_word(
            GUARD_HIGH_ADDR,
            GUARD_HIGH_DATA,
            "high unrelated-memory guard survives complete render"
        );

        check(
            dut.cpu.regs[0] == 32'h00000000,
            "r0 remains hardwired to zero"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("CPU_LAUNCH_CYCLES: %0d", cycles);
            $display("RENDER_WAIT_CYCLES: %0d", render_cycles);
            $display(
                "GPU_LOGICAL_READS: %0d",
                gpu_read_completions
            );
            $display(
                "GPU_LOGICAL_WRITES: %0d",
                gpu_write_completions
            );
            $display(
                "GPU_LOGICAL_TOTAL: %0d",
                gpu_total_completions
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
