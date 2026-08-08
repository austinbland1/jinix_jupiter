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

    output wire [7:0] video
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
