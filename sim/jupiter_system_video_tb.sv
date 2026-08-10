`timescale 1ns/1ps

module jupiter_system_video_tb;

reg clk = 1'b0;
reg reset = 1'b1;

wire       ce_pix;
wire       HBlank;
wire       HSync;
wire       VBlank;
wire       VSync;

wire [7:0] video_r;
wire [7:0] video_g;
wire [7:0] video_b;

integer checks = 0;

always #5 clk = ~clk;

jupiter_system dut
(
    .clk        (clk),
    .reset      (reset),

    .pal        (1'b0),
    .scandouble (1'b1),

    .ce_pix     (ce_pix),

    .HBlank     (HBlank),
    .HSync      (HSync),
    .VBlank     (VBlank),
    .VSync      (VSync),

    .video_r    (video_r),
    .video_g    (video_g),
    .video_b    (video_b),

    .sdram_sz   (16'h0000),

    .controller_0_state (32'h00000000),
    .controller_1_state (32'h00000000),
    .controller_2_state (32'h00000000),
    .controller_3_state (32'h00000000),
    .controller_4_state (32'h00000000),
    .controller_5_state (32'h00000000)
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

task select_pixel;
    input [9:0] x;
    begin
        force dut.cpu_subsystem.video_scanout.hc = x;
        #1;
    end
endtask

initial begin
    repeat (4)
        @(posedge clk);

    @(negedge clk);
    reset = 1'b0;

    @(posedge clk);
    #1;

    // Install a known completed source line directly into the already-tested
    // scanout line-buffer boundary. This test isolates propagation from
    // functional Jupiter scanout through jupiter_system.
    dut.cpu_subsystem.video_scanout.line_buffer_0[0] = 16'hF800;
    dut.cpu_subsystem.video_scanout.line_buffer_0[1] = 16'h07E0;
    dut.cpu_subsystem.video_scanout.line_buffer_0[2] = 16'h001F;
    dut.cpu_subsystem.video_scanout.line_buffer_0[3] = 16'hFFFF;

    force dut.cpu_subsystem.video_scanout.active_enable = 1'b1;
    force dut.cpu_subsystem.video_scanout.active_width = 16'd4;
    force dut.cpu_subsystem.video_scanout.active_height = 16'd1;

    force dut.cpu_subsystem.video_scanout.display_line_valid = 1'b1;
    force dut.cpu_subsystem.video_scanout.display_buffer_select = 1'b0;

    force dut.cpu_subsystem.video_scanout.vc = 10'd0;

    select_pixel(10'd0);

    check(
        video_r == 8'hFF &&
        video_g == 8'h00 &&
        video_b == 8'h00,
        "known RGB565 red propagates through production system boundary"
    );

    check(
        video_r == dut.scanout_video_r &&
        video_g == dut.scanout_video_g &&
        video_b == dut.scanout_video_b,
        "system RGB output is bit-exact scanout RGB"
    );

    select_pixel(10'd1);

    check(
        video_r == 8'h00 &&
        video_g == 8'hFF &&
        video_b == 8'h00,
        "known RGB565 green propagates through production system boundary"
    );

    select_pixel(10'd2);

    check(
        video_r == 8'h00 &&
        video_g == 8'h00 &&
        video_b == 8'hFF,
        "known RGB565 blue propagates through production system boundary"
    );

    select_pixel(10'd3);

    check(
        video_r == 8'hFF &&
        video_g == 8'hFF &&
        video_b == 8'hFF,
        "known RGB565 white propagates through production system boundary"
    );

    select_pixel(10'd4);

    check(
        video_r == 8'h00 &&
        video_g == 8'h00 &&
        video_b == 8'h00,
        "pixel outside programmed display width is black at system boundary"
    );

    force dut.cpu_subsystem.video_scanout.hc = 10'd320;
    #1;

    check(
        HBlank,
        "production system propagates scanout horizontal blanking"
    );

    check(
        video_r == 8'h00 &&
        video_g == 8'h00 &&
        video_b == 8'h00,
        "horizontal blanking region remains black"
    );

    force dut.cpu_subsystem.video_scanout.hc = 10'd0;
    force dut.cpu_subsystem.video_scanout.vc = 10'd480;
    #1;

    check(
        VBlank,
        "production system propagates scanout vertical blanking"
    );

    check(
        video_r == 8'h00 &&
        video_g == 8'h00 &&
        video_b == 8'h00,
        "vertical blanking region remains black"
    );

    check(
        ce_pix === dut.scanout_ce_pix &&
        HBlank === dut.scanout_hblank &&
        HSync === dut.scanout_hsync &&
        VBlank === dut.scanout_vblank &&
        VSync === dut.scanout_vsync,
        "all production system timing outputs are direct scanout timing"
    );

    release dut.cpu_subsystem.video_scanout.hc;
    release dut.cpu_subsystem.video_scanout.vc;

    release dut.cpu_subsystem.video_scanout.active_enable;
    release dut.cpu_subsystem.video_scanout.active_width;
    release dut.cpu_subsystem.video_scanout.active_height;

    release dut.cpu_subsystem.video_scanout.display_line_valid;
    release dut.cpu_subsystem.video_scanout.display_buffer_select;

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
