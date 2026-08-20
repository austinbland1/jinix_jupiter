`timescale 1ns/1ps

module jupiter_core_reset_tb;

    reg         clk;
    reg         reset;
    reg         pal;
    reg         scandouble;
    reg  [15:0] sdram_sz;

    reg         ioctl_download;
    reg  [15:0] ioctl_index;
    reg         ioctl_wr;
    reg  [26:0] ioctl_addr;
    reg   [7:0] ioctl_dout;
    wire        ioctl_wait;

    reg  [31:0] controller_0_state;
    reg  [31:0] controller_1_state;
    reg  [31:0] controller_2_state;
    reg  [31:0] controller_3_state;
    reg  [31:0] controller_4_state;
    reg  [31:0] controller_5_state;

    wire        SDRAM_CKE;
    wire [12:0] SDRAM_A;
    wire  [1:0] SDRAM_BA;
    tri  [15:0] SDRAM_DQ;
    wire        SDRAM_DQML;
    wire        SDRAM_DQMH;
    wire        SDRAM_nCS;
    wire        SDRAM_nCAS;
    wire        SDRAM_nRAS;
    wire        SDRAM_nWE;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;

    wire        video_ce_pix;
    wire        video_hblank;
    wire        video_hsync;
    wire        video_vblank;
    wire        video_vsync;
    wire  [7:0] video_r;
    wire  [7:0] video_g;
    wire  [7:0] video_b;

    wire        halted;

    integer checks;
    integer failures;

    jupiter_cpu_subsystem dut
    (
        .clk                (clk),
        .reset              (reset),

        .pal                (pal),
        .scandouble         (scandouble),
        .sdram_sz           (sdram_sz),

        .ioctl_download     (ioctl_download),
        .ioctl_index        (ioctl_index),
        .ioctl_wr           (ioctl_wr),
        .ioctl_addr         (ioctl_addr),
        .ioctl_dout         (ioctl_dout),
        .ioctl_wait         (ioctl_wait),

        .controller_0_state (controller_0_state),
        .controller_1_state (controller_1_state),
        .controller_2_state (controller_2_state),
        .controller_3_state (controller_3_state),
        .controller_4_state (controller_4_state),
        .controller_5_state (controller_5_state),

        .SDRAM_CKE          (SDRAM_CKE),
        .SDRAM_A            (SDRAM_A),
        .SDRAM_BA           (SDRAM_BA),
        .SDRAM_DQ           (SDRAM_DQ),
        .SDRAM_DQML         (SDRAM_DQML),
        .SDRAM_DQMH         (SDRAM_DQMH),
        .SDRAM_nCS          (SDRAM_nCS),
        .SDRAM_nCAS         (SDRAM_nCAS),
        .SDRAM_nRAS         (SDRAM_nRAS),
        .SDRAM_nWE          (SDRAM_nWE),

        .audio_l            (audio_l),
        .audio_r            (audio_r),

        .video_ce_pix       (video_ce_pix),
        .video_hblank       (video_hblank),
        .video_hsync        (video_hsync),
        .video_vblank       (video_vblank),
        .video_vsync        (video_vsync),
        .video_r            (video_r),
        .video_g            (video_g),
        .video_b            (video_b),

        .halted             (halted)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*104-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        pal = 1'b0;
        scandouble = 1'b0;
        sdram_sz = 16'h8001;

        ioctl_download = 1'b0;
        ioctl_index = 16'd0;
        ioctl_wr = 1'b0;
        ioctl_addr = 27'd0;
        ioctl_dout = 8'd0;

        controller_0_state = 32'd0;
        controller_1_state = 32'd0;
        controller_2_state = 32'd0;
        controller_3_state = 32'd0;
        controller_4_state = 32'd0;
        controller_5_state = 32'd0;

        checks = 0;
        failures = 0;

        step;
        step;

        @(negedge clk);
        reset = 1'b0;
        step;

        // Revalidate the existing installed-capacity interpretation now shared
        // by scanout and loader.
        #1;
        check(dut.sdram_size_valid === 1'b1, "32 MiB size code must be valid");
        check(dut.sdram_max_addr == 32'h11FFFFFF, "32 MiB max address mismatch");

        sdram_sz = 16'h8002;
        #1;
        check(dut.sdram_size_valid === 1'b1, "64 MiB size code must be valid");
        check(dut.sdram_max_addr == 32'h13FFFFFF, "64 MiB max address mismatch");

        sdram_sz = 16'h8003;
        #1;
        check(dut.sdram_size_valid === 1'b1, "128 MiB size code must be valid");
        check(dut.sdram_max_addr == 32'h17FFFFFF, "128 MiB max address mismatch");

        sdram_sz = 16'h0000;
        #1;
        check(dut.sdram_size_valid === 1'b0, "no-SDRAM configuration must be invalid");
        check(dut.sdram_max_addr == 32'h00000000, "no-SDRAM max address must be zero");

        sdram_sz = 16'h8001;

        // Non-matching transfers do not enter the M12 core reset domain.
        @(negedge clk);
        ioctl_index = 16'h0002;
        ioctl_download = 1'b1;
        #1;
        check(dut.loader_active === 1'b0, "non-matching download must not assert loader_active");
        check(dut.core_reset === 1'b0, "non-matching download must not assert core_reset");

        @(negedge clk);
        ioctl_download = 1'b0;
        step;

        // Matching transfer immediately enters core_reset and, after clocked
        // reset propagation, all SDRAM-producing core masters are quiescent.
        @(negedge clk);
        ioctl_index = 16'h0001;
        ioctl_download = 1'b1;
        #1;
        check(dut.loader_active === 1'b1, "matching download must assert loader_active");
        check(dut.core_reset === 1'b1, "matching download must assert core_reset");
        step;
        step;

        check(dut.cpu_mem_valid === 1'b0, "CPU must issue no memory request during core_reset");
        check(dut.gpu_sdram_valid === 1'b0, "GPU must issue no SDRAM request during core_reset");
        check(dut.dma_sdram_valid === 1'b0, "DMA must issue no SDRAM request during core_reset");
        check(dut.scanout_sdram_valid === 1'b0, "video scanout must issue no SDRAM request during core_reset");

        // The ordinary memory-path reset must remain deasserted. The loader,
        // both pre-existing arbiters, new loader arbiter, frontend, controller,
        // and internal RAM are therefore not reset merely by loader_active.
        check(reset === 1'b0, "ordinary reset must remain low during matching download");

        @(negedge clk);
        ioctl_download = 1'b0;
        step;
        #1;
        check(dut.loader_active === 1'b0, "loader_active must release after empty matching download");
        check(dut.core_reset === 1'b0, "core_reset must release after matching download");

        // Loader DONE is sticky after completion; observe through its standard
        // MMIO read-data register by hierarchical reference.
        check(dut.loader.done === 1'b1, "loader DONE must set after matching download completion");

        if (failures == 0) begin
            $display("PASS: M12 core reset/capacity integration (%0d checks)", checks);
            $finish;
        end

        $display("FAIL: M12 core reset/capacity integration %0d/%0d checks failed", failures, checks);
        $fatal(1);
    end

endmodule
