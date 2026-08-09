`timescale 1ns/1ps

module jupiter_system_tb;

reg clk = 1'b0;
reg reset = 1'b1;
reg pal = 1'b0;
reg scandouble = 1'b1;

always #5 clk = ~clk;

// Jupiter wrapper outputs.
wire       dut_ce_pix;
wire       dut_HBlank;
wire       dut_HSync;
wire       dut_VBlank;
wire       dut_VSync;
wire [7:0] dut_video;

// Audio interface propagated by jupiter_system.
wire signed [15:0] dut_AUDIO_L;
wire signed [15:0] dut_AUDIO_R;
wire               dut_AUDIO_S;
wire         [1:0] dut_AUDIO_MIX;

// SDRAM interface propagated by jupiter_system.
wire        dut_SDRAM_CKE;
wire [12:0] dut_SDRAM_A;
wire  [1:0] dut_SDRAM_BA;
wire [15:0] dut_SDRAM_DQ;
wire        dut_SDRAM_DQML;
wire        dut_SDRAM_DQMH;
wire        dut_SDRAM_nCS;
wire        dut_SDRAM_nCAS;
wire        dut_SDRAM_nRAS;
wire        dut_SDRAM_nWE;

// Direct reference mycore outputs.
wire       ref_ce_pix;
wire       ref_HBlank;
wire       ref_HSync;
wire       ref_VBlank;
wire       ref_VSync;
wire [7:0] ref_video;

integer checks = 0;
integer cycle;
reg saw_hblank = 1'b0;
reg saw_hsync  = 1'b0;
reg saw_vblank = 1'b0;
reg saw_vsync  = 1'b0;

jupiter_system dut
(
    .clk        (clk),
    .reset      (reset),
    .pal        (pal),
    .scandouble (scandouble),
    .ce_pix     (dut_ce_pix),
    .HBlank     (dut_HBlank),
    .HSync      (dut_HSync),
    .VBlank     (dut_VBlank),
    .VSync      (dut_VSync),
    .video      (dut_video),

    .AUDIO_L    (dut_AUDIO_L),
    .AUDIO_R    (dut_AUDIO_R),
    .AUDIO_S    (dut_AUDIO_S),
    .AUDIO_MIX  (dut_AUDIO_MIX),

    // Existing wrapper regression runs without installed SDRAM.
    .sdram_sz   (16'h0000),

    .SDRAM_CKE  (dut_SDRAM_CKE),
    .SDRAM_A    (dut_SDRAM_A),
    .SDRAM_BA   (dut_SDRAM_BA),
    .SDRAM_DQ   (dut_SDRAM_DQ),
    .SDRAM_DQML (dut_SDRAM_DQML),
    .SDRAM_DQMH (dut_SDRAM_DQMH),
    .SDRAM_nCS  (dut_SDRAM_nCS),
    .SDRAM_nCAS (dut_SDRAM_nCAS),
    .SDRAM_nRAS (dut_SDRAM_nRAS),
    .SDRAM_nWE  (dut_SDRAM_nWE)
);

mycore reference_core
(
    .clk        (clk),
    .reset      (reset),
    .pal        (pal),
    .scandouble (scandouble),
    .ce_pix     (ref_ce_pix),
    .HBlank     (ref_HBlank),
    .HSync      (ref_HSync),
    .VBlank     (ref_VBlank),
    .VSync      (ref_VSync),
    .video      (ref_video)
);

task check;
    input condition;
    input [8*96-1:0] message;
    begin
        checks = checks + 1;
        if (!condition)
            $fatal(1, "FAIL: %0s", message);
        else
            $display("PASS: %0s", message);
    end
endtask

initial begin
    // Hold reset through several rising clock edges.
    repeat (4) @(posedge clk);

    check(dut_SDRAM_CKE == 1'b1,
          "wrapper propagates SDRAM clock-enable from CPU subsystem");

    check(dut_AUDIO_L == 16'sd0 &&
          dut_AUDIO_R == 16'sd0,
          "wrapper audio samples reset to signed silence");

    check(dut_AUDIO_S == 1'b1,
          "wrapper marks Jupiter audio as signed PCM");

    check(dut_AUDIO_MIX == 2'b00,
          "wrapper selects native stereo with no framework mono mix");

    // Release away from the active edge.
    @(negedge clk);
    reset = 1'b0;

    // Verify the Jupiter skeleton inside the wrapper still behaves
    // exactly as established by Milestone 1A.
    @(posedge clk);
    #1;
    check(dut.jupiter.heartbeat == 8'hFF,
          "wrapper Jupiter heartbeat toggles after reset");
    check(dut.jupiter.tick_cnt == 4'd1,
          "wrapper Jupiter tick counter reaches 1");

    repeat (15) @(posedge clk);
    #1;
    check(dut.jupiter.tick_cnt == 4'd0,
          "wrapper Jupiter tick counter wraps after 16 cycles");
    check(dut.jupiter.done_pulse == 1'b1,
          "wrapper Jupiter done pulse asserts at wrap");


    // Verify the stable mixer samples propagate bit-exactly through:
    //
    // jupiter_audio -> jupiter_cpu_subsystem -> jupiter_system.
    //
    // The mixer datapath itself is already exhaustively verified by
    // jupiter_audio_mixer_tb; this check isolates production wiring.
    force dut.cpu_subsystem.audio.output_l_reg = -16'sd1234;
    force dut.cpu_subsystem.audio.output_r_reg =  16'sd2345;

    #1;

    check($signed(dut_AUDIO_L) == -16'sd1234,
          "production wrapper propagates signed left mixer sample");

    check($signed(dut_AUDIO_R) == 16'sd2345,
          "production wrapper propagates signed right mixer sample");

    release dut.cpu_subsystem.audio.output_l_reg;
    release dut.cpu_subsystem.audio.output_r_reg;


    // Run long enough to exercise horizontal and vertical timing.
    // scandouble=1 means mycore advances its pixel timing every clk.
    for (cycle = 0; cycle < 320000; cycle = cycle + 1) begin
        @(posedge clk);
        #1;

        // Case comparison is intentional because the untouched template
        // has several signals which begin uninitialized in simulation.
        if (dut_ce_pix !== ref_ce_pix ||
            dut_HBlank !== ref_HBlank ||
            dut_HSync  !== ref_HSync  ||
            dut_VBlank !== ref_VBlank ||
            dut_VSync  !== ref_VSync  ||
            dut_video  !== ref_video) begin

            $fatal(1,
                "FAIL: wrapper/reference mismatch at cycle %0d",
                cycle);
        end

        if (dut_HBlank === 1'b1) saw_hblank = 1'b1;
        if (dut_HSync  === 1'b1) saw_hsync  = 1'b1;
        if (dut_VBlank === 1'b1) saw_vblank = 1'b1;
        if (dut_VSync  === 1'b1) saw_vsync  = 1'b1;
    end

    check(1'b1,
          "wrapper video outputs match direct mycore for 320000 cycles");
    check(saw_hblank,
          "horizontal blanking became active");
    check(saw_hsync,
          "horizontal sync became active");
    check(saw_vblank,
          "vertical blanking became active");
    check(saw_vsync,
          "vertical sync became active");

    $display("");
    $display("==============================");
    $display("RESULT: PASS  (%0d checks)", checks);
    $display("==============================");

    $finish(0);
end

endmodule
