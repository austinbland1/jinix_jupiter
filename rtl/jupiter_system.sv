module jupiter_system
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

    output wire [7:0] video,

    // MiSTer-facing Jupiter PCM audio boundary.
    output wire signed [15:0] AUDIO_L,
    output wire signed [15:0] AUDIO_R,
    output wire               AUDIO_S,
    output wire         [1:0] AUDIO_MIX,

    // MiSTer-reported external SDRAM configuration.
    input  wire [15:0] sdram_sz,

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

    jupiter_cpu_subsystem cpu_subsystem
    (
        .clk        (clk),
        .reset      (reset),

        .sdram_sz   (sdram_sz),

        .audio_l    (AUDIO_L),
        .audio_r    (AUDIO_R),

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

    // Selected MiSTer audio interpretation:
    // signed 16-bit stereo samples, with no framework mono mixing.
    assign AUDIO_S   = 1'b1;
    assign AUDIO_MIX = 2'b00;


    // Preserve the known-good MiSTer template demo-video path.
    mycore video_demo
    (
        .clk        (clk),
        .reset      (reset),

        .pal        (pal),
        .scandouble (scandouble),

        .ce_pix     (ce_pix),

        .HBlank     (HBlank),
        .HSync      (HSync),
        .VBlank     (VBlank),
        .VSync      (VSync),

        .video      (video)
    );

endmodule
