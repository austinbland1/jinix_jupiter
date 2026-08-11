module jupiter_system
#(
    parameter RAM_INIT_B0 = "",
    parameter RAM_INIT_B1 = "",
    parameter RAM_INIT_B2 = "",
    parameter RAM_INIT_B3 = ""
)
(
    input  wire       clk,
    input  wire       reset,

    input  wire       pal,
    input  wire       scandouble,

    output wire       ce_pix,

    output wire       HBlank,
    output wire       HSync,
    output wire       VBlank,
    output wire       VSync,

    output wire [7:0] video_r,
    output wire [7:0] video_g,
    output wire [7:0] video_b,

    // MiSTer-facing Jupiter PCM audio boundary.
    output wire signed [15:0] AUDIO_L,
    output wire signed [15:0] AUDIO_R,
    output wire               AUDIO_S,
    output wire         [1:0] AUDIO_MIX,

    // MiSTer-reported external SDRAM configuration.
    input  wire [15:0] sdram_sz,

    // M8B-2 production digital controller boundary.
    input  wire [31:0] controller_0_state,
    input  wire [31:0] controller_1_state,
    input  wire [31:0] controller_2_state,
    input  wire [31:0] controller_3_state,
    input  wire [31:0] controller_4_state,
    input  wire [31:0] controller_5_state,

    // External SDR SDRAM interface.
    // SDRAM_CLK is intentionally deferred to top-level integration.
    output wire        SDRAM_CKE,
    output wire [12:0] SDRAM_A,
    output wire  [1:0] SDRAM_BA,
    inout  wire [15:0] SDRAM_DQ,
    output wire        SDRAM_DQML,
    output wire        SDRAM_DQMH,
    output wire        SDRAM_nCS,
    output wire        SDRAM_nCAS,
    output wire        SDRAM_nRAS,
    output wire        SDRAM_nWE
);

    // Milestone 1 Jupiter skeleton state.
    // These signals are intentionally internal for now.
    wire [7:0] jupiter_heartbeat;
    wire [3:0] jupiter_tick_cnt;
    wire       jupiter_done_pulse;

    jupiter_core jupiter
    (
        .clk        (clk),
        .reset      (reset),
        .heartbeat  (jupiter_heartbeat),
        .tick_cnt   (jupiter_tick_cnt),
        .done_pulse (jupiter_done_pulse)
    );


    wire jupiter_cpu_halted;

    // M11B-3a scanout is production-integrated inside the CPU subsystem.
    // The external wrapper remains on mycore until M11B-3b.
    wire       scanout_ce_pix;
    wire       scanout_hblank;
    wire       scanout_hsync;
    wire       scanout_vblank;
    wire       scanout_vsync;
    wire [7:0] scanout_video_r;
    wire [7:0] scanout_video_g;
    wire [7:0] scanout_video_b;


    jupiter_cpu_subsystem cpu_subsystem
    (
        .clk        (clk),
        .reset      (reset),

        .pal        (pal),
        .scandouble (scandouble),


        .sdram_sz   (sdram_sz),

        // M8B-2 production controller propagation.
        .controller_0_state (controller_0_state),
        .controller_1_state (controller_1_state),
        .controller_2_state (controller_2_state),
        .controller_3_state (controller_3_state),
        .controller_4_state (controller_4_state),
        .controller_5_state (controller_5_state),

        .audio_l    (AUDIO_L),
        .audio_r    (AUDIO_R),

        .video_ce_pix (scanout_ce_pix),
        .video_hblank (scanout_hblank),
        .video_hsync  (scanout_hsync),
        .video_vblank (scanout_vblank),
        .video_vsync  (scanout_vsync),
        .video_r      (scanout_video_r),
        .video_g      (scanout_video_g),
        .video_b      (scanout_video_b),


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

        .halted     (jupiter_cpu_halted)
    );

    defparam cpu_subsystem.RAM_INIT_B0 = RAM_INIT_B0;
    defparam cpu_subsystem.RAM_INIT_B1 = RAM_INIT_B1;
    defparam cpu_subsystem.RAM_INIT_B2 = RAM_INIT_B2;
    defparam cpu_subsystem.RAM_INIT_B3 = RAM_INIT_B3;

    // Selected MiSTer audio interpretation:
    // signed 16-bit stereo samples, with no framework mono mixing.
    assign AUDIO_S   = 1'b1;
    assign AUDIO_MIX = 2'b00;

    // M11B live display path.
    //
    // Timing and RGB now come directly from the framebuffer scanout engine.
    // The inherited mycore demo is no longer part of the production video
    // boundary.
    assign ce_pix = scanout_ce_pix;

    assign HBlank = scanout_hblank;
    assign HSync  = scanout_hsync;
    assign VBlank = scanout_vblank;
    assign VSync  = scanout_vsync;

    assign video_r = scanout_video_r;
    assign video_g = scanout_video_g;
    assign video_b = scanout_video_b;

endmodule
