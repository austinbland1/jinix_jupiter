`timescale 1ns/1ps

module jupiter_cpu_display_mmio_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;

    wire halted;

    wire       video_ce_pix;
    wire       video_hblank;
    wire       video_hsync;
    wire       video_vblank;
    wire       video_vsync;
    wire [7:0] video_r;
    wire [7:0] video_g;
    wire [7:0] video_b;

    integer checks = 0;
    integer failures = 0;
    integer cycles = 0;

    integer display_store_count = 0;
    integer display_load_count = 0;

    reg bad_display_selection = 1'b0;
    reg renderer_selected_for_display = 1'b0;
    reg unexpected_scanout_sdram = 1'b0;

    jupiter_cpu_subsystem dut
    (
        .clk        (clk),
        .reset      (reset),

        .pal        (1'b0),
        .scandouble (1'b0),

        // Valid MiSTer report: 32 MiB external SDRAM installed.
        .sdram_sz   (16'h8001),

        .controller_0_state (32'h00000000),
        .controller_1_state (32'h00000000),
        .controller_2_state (32'h00000000),
        .controller_3_state (32'h00000000),
        .controller_4_state (32'h00000000),
        .controller_5_state (32'h00000000),

        .video_ce_pix (video_ce_pix),
        .video_hblank (video_hblank),
        .video_hsync  (video_hsync),
        .video_vblank (video_vblank),
        .video_vsync  (video_vsync),
        .video_r      (video_r),
        .video_g      (video_g),
        .video_b      (video_b),

        .halted     (halted)
    );

    always #5 clk = ~clk;

    function [31:0] enc_i;
        input [7:0]  opcode;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [13:0] imm14;
        begin
            enc_i =
                {opcode, rd, rs1, imm14};
        end
    endfunction

    function [31:0] enc_s;
        input [7:0]  opcode;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [13:0] imm14;
        begin
            enc_s =
                {opcode, rs2, rs1, imm14};
        end
    endfunction

    function [31:0] enc_n;
        input [7:0] opcode;
        begin
            enc_n =
                {opcode, 24'd0};
        end
    endfunction

    task check;
        input condition;
        input [8*120-1:0] message;
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

    always @(posedge clk) begin
        if (!reset &&
            dut.cpu_mem_valid &&
            dut.cpu_mem_ready &&
            dut.cpu_mem_addr >= 32'h00001180 &&
            dut.cpu_mem_addr <= 32'h000011BF) begin

            if (!(dut.gpu_valid &&
                  dut.scanout_mmio_selected &&
                  !dut.gpu_render_valid &&
                  !dut.ram_valid &&
                  !dut.mmio_valid &&
                  !dut.dma_valid &&
                  !dut.audio_valid &&
                  !dut.controller_valid &&
                  !dut.sdram_valid))
                bad_display_selection <=
                    1'b1;

            if (dut.gpu_render_valid)
                renderer_selected_for_display <=
                    1'b1;

            if (dut.cpu_mem_write)
                display_store_count <=
                    display_store_count + 1;
            else
                display_load_count <=
                    display_load_count + 1;
        end

        if (dut.scanout_sdram_valid)
            unexpected_scanout_sdram <=
                1'b1;
    end

    initial begin
        /*
         * CPU -> display MMIO:
         *
         * r1 = 0x1180
         *
         * 0x1188 DISPLAY_BASE    <- 42
         * 0x1188 DISPLAY_BASE    -> r3
         * 0x118C DISPLAY_SIZE    <- 4
         * 0x118C DISPLAY_SIZE    -> r5
         * 0x1180 CONTROL.ENABLE  <- 1
         * 0x1180 CONTROL         -> r7
         * 0x1184 STATUS          -> r8
         * 0x1190 reserved        -> r9
         *
         * DISPLAY_BASE=42 and height=0 are deliberately invalid, so this
         * register-path test cannot generate framebuffer SDRAM traffic.
         */

        dut.ram.memory_b0[0] = (enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4480
            ));
        dut.ram.memory_b1[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4480
            )) >> 8);
        dut.ram.memory_b2[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4480
            )) >> 16);
        dut.ram.memory_b3[0] = ((enc_i(
                8'h10,
                5'd1,
                5'd0,
                14'd4480
            )) >> 24);

        dut.ram.memory_b0[1] = (enc_i(
                8'h10,
                5'd2,
                5'd0,
                14'd42
            ));
        dut.ram.memory_b1[1] = ((enc_i(
                8'h10,
                5'd2,
                5'd0,
                14'd42
            )) >> 8);
        dut.ram.memory_b2[1] = ((enc_i(
                8'h10,
                5'd2,
                5'd0,
                14'd42
            )) >> 16);
        dut.ram.memory_b3[1] = ((enc_i(
                8'h10,
                5'd2,
                5'd0,
                14'd42
            )) >> 24);

        dut.ram.memory_b0[2] = (enc_s(
                8'h21,
                5'd2,
                5'd1,
                14'd8
            ));
        dut.ram.memory_b1[2] = ((enc_s(
                8'h21,
                5'd2,
                5'd1,
                14'd8
            )) >> 8);
        dut.ram.memory_b2[2] = ((enc_s(
                8'h21,
                5'd2,
                5'd1,
                14'd8
            )) >> 16);
        dut.ram.memory_b3[2] = ((enc_s(
                8'h21,
                5'd2,
                5'd1,
                14'd8
            )) >> 24);

        dut.ram.memory_b0[3] = (enc_i(
                8'h20,
                5'd3,
                5'd1,
                14'd8
            ));
        dut.ram.memory_b1[3] = ((enc_i(
                8'h20,
                5'd3,
                5'd1,
                14'd8
            )) >> 8);
        dut.ram.memory_b2[3] = ((enc_i(
                8'h20,
                5'd3,
                5'd1,
                14'd8
            )) >> 16);
        dut.ram.memory_b3[3] = ((enc_i(
                8'h20,
                5'd3,
                5'd1,
                14'd8
            )) >> 24);

        dut.ram.memory_b0[4] = (enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd4
            ));
        dut.ram.memory_b1[4] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[4] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[4] = ((enc_i(
                8'h10,
                5'd4,
                5'd0,
                14'd4
            )) >> 24);

        dut.ram.memory_b0[5] = (enc_s(
                8'h21,
                5'd4,
                5'd1,
                14'd12
            ));
        dut.ram.memory_b1[5] = ((enc_s(
                8'h21,
                5'd4,
                5'd1,
                14'd12
            )) >> 8);
        dut.ram.memory_b2[5] = ((enc_s(
                8'h21,
                5'd4,
                5'd1,
                14'd12
            )) >> 16);
        dut.ram.memory_b3[5] = ((enc_s(
                8'h21,
                5'd4,
                5'd1,
                14'd12
            )) >> 24);

        dut.ram.memory_b0[6] = (enc_i(
                8'h20,
                5'd5,
                5'd1,
                14'd12
            ));
        dut.ram.memory_b1[6] = ((enc_i(
                8'h20,
                5'd5,
                5'd1,
                14'd12
            )) >> 8);
        dut.ram.memory_b2[6] = ((enc_i(
                8'h20,
                5'd5,
                5'd1,
                14'd12
            )) >> 16);
        dut.ram.memory_b3[6] = ((enc_i(
                8'h20,
                5'd5,
                5'd1,
                14'd12
            )) >> 24);

        dut.ram.memory_b0[7] = (enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd1
            ));
        dut.ram.memory_b1[7] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd1
            )) >> 8);
        dut.ram.memory_b2[7] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd1
            )) >> 16);
        dut.ram.memory_b3[7] = ((enc_i(
                8'h10,
                5'd6,
                5'd0,
                14'd1
            )) >> 24);

        dut.ram.memory_b0[8] = (enc_s(
                8'h21,
                5'd6,
                5'd1,
                14'd0
            ));
        dut.ram.memory_b1[8] = ((enc_s(
                8'h21,
                5'd6,
                5'd1,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[8] = ((enc_s(
                8'h21,
                5'd6,
                5'd1,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[8] = ((enc_s(
                8'h21,
                5'd6,
                5'd1,
                14'd0
            )) >> 24);

        dut.ram.memory_b0[9] = (enc_i(
                8'h20,
                5'd7,
                5'd1,
                14'd0
            ));
        dut.ram.memory_b1[9] = ((enc_i(
                8'h20,
                5'd7,
                5'd1,
                14'd0
            )) >> 8);
        dut.ram.memory_b2[9] = ((enc_i(
                8'h20,
                5'd7,
                5'd1,
                14'd0
            )) >> 16);
        dut.ram.memory_b3[9] = ((enc_i(
                8'h20,
                5'd7,
                5'd1,
                14'd0
            )) >> 24);

        dut.ram.memory_b0[10] = (enc_i(
                8'h20,
                5'd8,
                5'd1,
                14'd4
            ));
        dut.ram.memory_b1[10] = ((enc_i(
                8'h20,
                5'd8,
                5'd1,
                14'd4
            )) >> 8);
        dut.ram.memory_b2[10] = ((enc_i(
                8'h20,
                5'd8,
                5'd1,
                14'd4
            )) >> 16);
        dut.ram.memory_b3[10] = ((enc_i(
                8'h20,
                5'd8,
                5'd1,
                14'd4
            )) >> 24);

        dut.ram.memory_b0[11] = (enc_i(
                8'h20,
                5'd9,
                5'd1,
                14'd16
            ));
        dut.ram.memory_b1[11] = ((enc_i(
                8'h20,
                5'd9,
                5'd1,
                14'd16
            )) >> 8);
        dut.ram.memory_b2[11] = ((enc_i(
                8'h20,
                5'd9,
                5'd1,
                14'd16
            )) >> 16);
        dut.ram.memory_b3[11] = ((enc_i(
                8'h20,
                5'd9,
                5'd1,
                14'd16
            )) >> 24);

        dut.ram.memory_b0[12] = (enc_n(8'hFF));
        dut.ram.memory_b1[12] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[12] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[12] = ((enc_n(8'hFF)) >> 24);

        repeat (3)
            @(posedge clk);

        #1;

        check(
            dut.sdram_capacity_bytes ==
                32'h02000000,
            "32 MiB report decodes to exact frontend-compatible capacity"
        );

        check(
            dut.sdram_max_addr ==
                32'h11FFFFFF,
            "32 MiB report produces exact inclusive scanout final byte"
        );

        check(
            !dut.video_scanout.enable_shadow,
            "display scanout begins disabled"
        );

        check(
            dut.gpu.tilemap_base_reg ==
                32'h00000000,
            "existing renderer begins unchanged"
        );

        @(negedge clk);
        reset = 1'b0;

        while (!halted &&
               cycles < 500) begin
            @(posedge clk);
            #1;

            cycles = cycles + 1;
        end

        check(
            halted,
            "CPU display-MMIO program reaches HALT before timeout"
        );

        check(
            dut.cpu.pc ==
                32'h00000030,
            "display-MMIO program halts at expected PC 0x30"
        );

        check(
            dut.cpu.regs[1] ==
                32'h00001180,
            "CPU constructs exact display-MMIO base"
        );

        check(
            dut.video_scanout.display_base_shadow ==
                32'd42,
            "CPU store reaches DISPLAY_BASE"
        );

        check(
            dut.cpu.regs[3] ==
                32'd42,
            "CPU reads DISPLAY_BASE through production interconnect"
        );

        check(
            dut.video_scanout.display_size_shadow ==
                32'd4,
            "CPU store reaches DISPLAY_SIZE"
        );

        check(
            dut.cpu.regs[5] ==
                32'd4,
            "CPU reads DISPLAY_SIZE through production interconnect"
        );

        check(
            dut.video_scanout.enable_shadow,
            "CPU store reaches DISPLAY_CONTROL ENABLE"
        );

        check(
            dut.cpu.regs[7] ==
                32'h00000001,
            "CPU reads DISPLAY_CONTROL through production interconnect"
        );

        check(
            dut.cpu.regs[8] ==
                32'h00000000,
            "DISPLAY_STATUS remains inactive before valid snapshot"
        );

        check(
            dut.cpu.regs[9] ==
                32'h00000000,
            "reserved display MMIO returns zero"
        );

        check(
            display_store_count == 3,
            "exactly three CPU stores complete in display MMIO"
        );

        check(
            display_load_count == 5,
            "exactly five CPU loads complete in display MMIO"
        );

        check(
            !bad_display_selection,
            "display addresses select only scanout within GPU aperture"
        );

        check(
            !renderer_selected_for_display,
            "display MMIO never reaches existing renderer"
        );

        check(
            dut.gpu.tilemap_base_reg ==
                32'h00000000,
            "display MMIO leaves existing renderer registers unchanged"
        );

        check(
            !unexpected_scanout_sdram,
            "invalid display configuration emits no scanout SDRAM traffic"
        );

        check(
            !dut.cpu_mem_valid,
            "halted CPU issues no further memory transaction"
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
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );
        end

        $display("==============================");

        if (failures != 0)
            $fatal(
                1,
                "M11B-3a CPU display-MMIO integration failed"
            );

        $finish;
    end

endmodule
