`timescale 1ns/1ps

module jupiter_gpu_3d_mmio_tb;

    localparam [31:0] REG_2D_CONTROL      = 32'h00001100;
    localparam [31:0] REG_2D_STATUS       = 32'h00001104;
    localparam [31:0] REG_2D_TILEMAP_BASE = 32'h00001108;

    localparam [31:0] REG_3D_CONTROL          = 32'h00001140;
    localparam [31:0] REG_3D_STATUS           = 32'h00001144;
    localparam [31:0] REG_3D_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_3D_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_3D_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_3D_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_3D_FLAT_COLOR       = 32'h00001168;
    localparam [31:0] REG_3D_RESERVED         = 32'h0000116C;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        valid = 1'b0;
    reg        write = 1'b0;
    reg [31:0] addr  = 32'h00000000;
    reg [31:0] wdata = 32'h00000000;
    reg  [3:0] wstrb = 4'b0000;

    wire [31:0] rdata;
    wire        ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;

    reg [31:0] sdram_rdata = 32'h00000000;
    reg        sdram_ready = 1'b0;

    integer checks = 0;
    integer failures = 0;
    integer sdram_requests = 0;

    jupiter_gpu_2d dut
    (
        .clk         (clk),
        .reset       (reset),

        .valid       (valid),
        .write       (write),
        .addr        (addr),
        .wdata       (wdata),
        .wstrb       (wstrb),

        .rdata       (rdata),
        .ready       (ready),

        .sdram_valid (sdram_valid),
        .sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (sdram_valid)
            sdram_requests <= sdram_requests + 1;
    end

    task check;
        input condition;
        input [1023:0] message;
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

    task mmio_write;
        input [31:0] address;
        input [31:0] data;
        input  [3:0] strobes;
        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b1;
            addr  = address;
            wdata = data;
            wstrb = strobes;

            #1;

            check(
                ready === 1'b1,
                "wrapper MMIO write completes without wait"
            );

            @(posedge clk);
            #1;

            valid = 1'b0;
            write = 1'b0;
            addr  = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;
        end
    endtask

    task mmio_read;
        input [31:0] address;
        input [31:0] expected;
        input [1023:0] message;
        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b0;
            addr  = address;
            wstrb = 4'b0000;

            #1;

            check(
                ready === 1'b1,
                "wrapper MMIO read completes without wait"
            );

            check(
                rdata === expected,
                message
            );

            valid = 1'b0;
            addr  = 32'h00000000;

            #1;
        end
    endtask

    initial begin

        repeat (2)
            @(posedge clk);

        #1;

        check(
            !dut.busy &&
            !dut.done &&
            !dut.gpu3d.busy &&
            !dut.gpu3d.done &&
            !dut.gpu3d.error,
            "reset clears both 2D and 3D status"
        );

        @(negedge clk);
        reset = 1'b0;

        // ----------------------------------------------------
        // Existing M5 register path remains intact.
        // ----------------------------------------------------

        mmio_write(
            REG_2D_TILEMAP_BASE,
            32'h10004000,
            4'b1111
        );

        mmio_read(
            REG_2D_TILEMAP_BASE,
            32'h10004000,
            "M5 TILEMAP_BASE still reads back through wrapper"
        );

        mmio_read(
            REG_2D_STATUS,
            32'h00000000,
            "M5 STATUS remains independent from 3D state"
        );

        // ----------------------------------------------------
        // New 3D subrange routes to child.
        // ----------------------------------------------------

        mmio_write(
            REG_3D_VERTEX_BASE,
            32'h10000000,
            4'b1111
        );

        mmio_write(
            REG_3D_FRAMEBUFFER_BASE,
            32'h10001000,
            4'b1111
        );

        mmio_write(
            REG_3D_TARGET_SIZE,
            32'h00020002,
            4'b1111
        );

        mmio_write(
            REG_3D_BLEND_ALPHA,
            32'h00000010,
            4'b1111
        );

        mmio_write(
            REG_3D_FLAT_COLOR,
            32'h000007E0,
            4'b1111
        );

        mmio_read(
            REG_3D_VERTEX_BASE,
            32'h10000000,
            "3D VERTEX_BASE reads through existing GPU target"
        );

        mmio_read(
            REG_3D_FLAT_COLOR,
            32'h000007E0,
            "3D FLAT_COLOR reads through existing GPU target"
        );

        mmio_read(
            REG_3D_RESERVED,
            32'h00000000,
            "reserved 3D wrapper offset reads deterministic zero"
        );

        // ----------------------------------------------------
        // Valid shell command remains memory-idle.
        // ----------------------------------------------------

        mmio_write(
            REG_3D_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.gpu3d.busy &&
            !dut.gpu3d.done &&
            !dut.gpu3d.error,
            "3D START reaches child through wrapper"
        );

        check(
            !sdram_valid &&
            !dut.gpu3d_sdram_valid,
            "M10B-1 3D command emits no external SDRAM request"
        );

        @(posedge clk);
        #1;

        check(
            !dut.gpu3d.busy &&
            dut.gpu3d.done &&
            !dut.gpu3d.error,
            "3D child completes bounded shell command"
        );

        mmio_read(
            REG_3D_STATUS,
            32'h00000002,
            "3D DONE returns through wrapper MMIO mux"
        );

        mmio_read(
            REG_2D_STATUS,
            32'h00000000,
            "3D command does not alter M5 status"
        );

        // ----------------------------------------------------
        // Existing zero-dimension M5 START still works.
        // MAP_SIZE reset value is zero.
        // ----------------------------------------------------

        mmio_write(
            REG_2D_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            !dut.busy &&
            dut.done,
            "M5 zero-dimension START still completes immediately"
        );

        mmio_read(
            REG_2D_STATUS,
            32'h00000002,
            "M5 DONE still returns through original register"
        );

        mmio_read(
            REG_3D_STATUS,
            32'h00000002,
            "M5 operation does not disturb sticky 3D DONE"
        );

        check(
            sdram_requests == 0,
            "wrapper integration test observes zero SDRAM traffic"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "idle internal arbiter drives deterministic external values"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );
        end

        $display("==============================");

        if (failures != 0)
            $fatal(1);

        $finish;
    end

endmodule
