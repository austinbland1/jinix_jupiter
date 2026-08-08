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
    .video      (dut_video)
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
