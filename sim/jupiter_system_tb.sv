`timescale 1ns/1ps

module jupiter_system_tb;

reg clk = 1'b0;
reg reset = 1'b1;
reg pal = 1'b0;
reg scandouble = 1'b1;

// M8B-2 controller inputs propagated by jupiter_system.
reg [31:0] controller_0_state = 32'h00000001;
reg [31:0] controller_1_state = 32'h80000000;
reg [31:0] controller_2_state = 32'hA5A55A5A;
reg [31:0] controller_3_state = 32'h13579BDF;
reg [31:0] controller_4_state = 32'h2468ACE0;
reg [31:0] controller_5_state = 32'h89ABCDEF;

always #5 clk = ~clk;

// Jupiter wrapper outputs.
wire       dut_ce_pix;
wire       dut_HBlank;
wire       dut_HSync;
wire       dut_VBlank;
wire       dut_VSync;
wire [7:0] dut_video_r;
wire [7:0] dut_video_g;
wire [7:0] dut_video_b;

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

integer checks = 0;
integer cycle;

reg saw_hblank = 1'b0;
reg saw_hsync  = 1'b0;
reg saw_vblank = 1'b0;
reg saw_vsync  = 1'b0;
reg saw_nonblack = 1'b0;

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

    .video_r    (dut_video_r),
    .video_g    (dut_video_g),
    .video_b    (dut_video_b),

    .AUDIO_L    (dut_AUDIO_L),
    .AUDIO_R    (dut_AUDIO_R),
    .AUDIO_S    (dut_AUDIO_S),
    .AUDIO_MIX  (dut_AUDIO_MIX),

    // Wrapper timing test runs without installed external SDRAM.
    .sdram_sz   (16'h0000),

    .controller_0_state (controller_0_state),
    .controller_1_state (controller_1_state),
    .controller_2_state (controller_2_state),
    .controller_3_state (controller_3_state),
    .controller_4_state (controller_4_state),
    .controller_5_state (controller_5_state),

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

task check;
    input condition;
    input [8*112-1:0] message;
    begin
        checks = checks + 1;

        if (!condition)
            $fatal(
                1,
                "FAIL: %0s",
                message
            );
        else
            $display(
                "PASS: %0s",
                message
            );
    end
endtask

initial begin
    // Hold reset through several rising edges.
    repeat (4)
        @(posedge clk);

    check(
        dut_SDRAM_CKE == 1'b1,
        "wrapper propagates SDRAM clock-enable from CPU subsystem"
    );

    check(
        dut_AUDIO_L == 16'sd0 &&
        dut_AUDIO_R == 16'sd0,
        "wrapper audio samples reset to signed silence"
    );

    check(
        dut_AUDIO_S == 1'b1,
        "wrapper marks Jupiter audio as signed PCM"
    );

    check(
        dut_AUDIO_MIX == 2'b00,
        "wrapper selects native stereo with no framework mono mix"
    );

    check(
        dut.cpu_subsystem.controller_0_state == controller_0_state,
        "wrapper propagates controller zero state"
    );

    check(
        dut.cpu_subsystem.controller_1_state == controller_1_state,
        "wrapper propagates controller one state"
    );

    check(
        dut.cpu_subsystem.controller_2_state == controller_2_state,
        "wrapper propagates controller two state"
    );

    check(
        dut.cpu_subsystem.controller_3_state == controller_3_state,
        "wrapper propagates controller three state"
    );

    check(
        dut.cpu_subsystem.controller_4_state == controller_4_state,
        "wrapper propagates controller four state"
    );

    check(
        dut.cpu_subsystem.controller_5_state == controller_5_state,
        "wrapper propagates controller five state"
    );

    controller_3_state = 32'h55AA00FF;
    #1;

    check(
        dut.cpu_subsystem.controller_3_state == 32'h55AA00FF,
        "wrapper propagates controller changes without extra latch"
    );

    @(negedge clk);
    reset = 1'b0;

    @(posedge clk);
    #1;

    check(
        dut.jupiter.heartbeat == 8'hFF,
        "wrapper Jupiter heartbeat toggles after reset"
    );

    check(
        dut.jupiter.tick_cnt == 4'd1,
        "wrapper Jupiter tick counter reaches 1"
    );

    repeat (15)
        @(posedge clk);

    #1;

    check(
        dut.jupiter.tick_cnt == 4'd0,
        "wrapper Jupiter tick counter wraps after 16 cycles"
    );

    check(
        dut.jupiter.done_pulse == 1'b1,
        "wrapper Jupiter done pulse asserts at wrap"
    );

    // Verify the stable mixer samples propagate bit-exactly.
    force dut.cpu_subsystem.audio.output_l_reg = -16'sd1234;
    force dut.cpu_subsystem.audio.output_r_reg =  16'sd2345;

    #1;

    check(
        $signed(dut_AUDIO_L) == -16'sd1234,
        "production wrapper propagates signed left mixer sample"
    );

    check(
        $signed(dut_AUDIO_R) == 16'sd2345,
        "production wrapper propagates signed right mixer sample"
    );

    release dut.cpu_subsystem.audio.output_l_reg;
    release dut.cpu_subsystem.audio.output_r_reg;

    // Run long enough to exercise complete horizontal/vertical timing.
    //
    // The framebuffer is intentionally disabled because sdram_sz is invalid,
    // so active pixels must remain deterministic black while timing continues.
    for (
        cycle = 0;
        cycle < 320000;
        cycle = cycle + 1
    ) begin
        @(posedge clk);
        #1;

        if (dut_ce_pix !== dut.scanout_ce_pix ||
            dut_HBlank !== dut.scanout_hblank ||
            dut_HSync  !== dut.scanout_hsync ||
            dut_VBlank !== dut.scanout_vblank ||
            dut_VSync  !== dut.scanout_vsync ||
            dut_video_r !== dut.scanout_video_r ||
            dut_video_g !== dut.scanout_video_g ||
            dut_video_b !== dut.scanout_video_b) begin

            $fatal(
                1,
                "FAIL: wrapper/scanout mismatch at cycle %0d",
                cycle
            );
        end

        if (dut_HBlank === 1'b1)
            saw_hblank = 1'b1;

        if (dut_HSync === 1'b1)
            saw_hsync = 1'b1;

        if (dut_VBlank === 1'b1)
            saw_vblank = 1'b1;

        if (dut_VSync === 1'b1)
            saw_vsync = 1'b1;

        if (dut_video_r !== 8'h00 ||
            dut_video_g !== 8'h00 ||
            dut_video_b !== 8'h00)
            saw_nonblack = 1'b1;
    end

    check(
        1'b1,
        "wrapper timing and RGB outputs follow integrated scanout for 320000 cycles"
    );

    check(
        !saw_nonblack,
        "disabled framebuffer scanout remains deterministic black"
    );

    check(
        saw_hblank,
        "horizontal blanking became active"
    );

    check(
        saw_hsync,
        "horizontal sync became active"
    );

    check(
        saw_vblank,
        "vertical blanking became active"
    );

    check(
        saw_vsync,
        "vertical sync became active"
    );

    $display("");
    $display("==============================");
    $display(
        "RESULT: PASS  (%0d checks)",
        checks
    );
    $display("==============================");

    $finish(0);
end

endmodule
