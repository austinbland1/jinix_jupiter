`timescale 1ns/1ps

module jupiter_gpu_3d_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_STATUS           = 32'h00001144;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_TEXTURE_BASE     = 32'h0000114C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_DEPTH_BASE       = 32'h00001154;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_TEXTURE_SIZE     = 32'h0000115C;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;
    localparam [31:0] REG_RESERVED         = 32'h0000116C;

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

    reg [31:0] sdram_rdata = 32'hDEADBEEF;
    reg        sdram_ready = 1'b1;

    integer checks = 0;
    integer failures = 0;
    integer sdram_request_count = 0;

    jupiter_gpu_3d dut
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
            sdram_request_count <= sdram_request_count + 1;
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
                "MMIO write completes without wait state"
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
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;

            check(
                ready === 1'b1,
                "MMIO read completes without wait state"
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

        // ----------------------------------------------------
        // Reset behavior
        // ----------------------------------------------------

        repeat (2)
            @(posedge clk);

        #1;

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b0 &&
            dut.error === 1'b0 &&
            dut.shell_pending === 1'b0,
            "reset clears shell status"
        );

        check(
            sdram_valid === 1'b0 &&
            sdram_write === 1'b0 &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "reset shell presents no SDRAM transaction"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_read(
            REG_CONTROL,
            32'h00000000,
            "CONTROL reads deterministic zero"
        );

        mmio_read(
            REG_STATUS,
            32'h00000000,
            "STATUS begins clear"
        );

        mmio_read(
            REG_RESERVED,
            32'h00000000,
            "reserved 3D offset reads zero"
        );

        // ----------------------------------------------------
        // Byte-strobe behavior
        // ----------------------------------------------------

        mmio_write(
            REG_VERTEX_BASE,
            32'h11223344,
            4'b0001
        );

        mmio_read(
            REG_VERTEX_BASE,
            32'h00000044,
            "low-byte strobe updates only selected byte"
        );

        mmio_write(
            REG_VERTEX_BASE,
            32'hAABBCCDD,
            4'b1010
        );

        mmio_read(
            REG_VERTEX_BASE,
            32'hAA00CC44,
            "sparse byte strobes preserve unselected bytes"
        );

        mmio_write(
            REG_RESERVED,
            32'hDEADBEEF,
            4'b1111
        );

        mmio_read(
            REG_RESERVED,
            32'h00000000,
            "reserved 3D write has no effect"
        );

        mmio_read(
            REG_VERTEX_BASE,
            32'hAA00CC44,
            "reserved write does not corrupt live register"
        );

        // ----------------------------------------------------
        // Deterministic invalid-command failure
        // ----------------------------------------------------

        mmio_write(
            REG_VERTEX_BASE,
            32'h10000000,
            4'b1111
        );

        mmio_write(
            REG_FRAMEBUFFER_BASE,
            32'h10001000,
            4'b1111
        );

        // height = 1, width = 0 -> invalid target.
        mmio_write(
            REG_TARGET_SIZE,
            32'h00010000,
            4'b1111
        );

        mmio_write(
            REG_MODE,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.error === 1'b1 &&
            dut.shell_pending === 1'b0,
            "invalid target completes immediately with ERROR"
        );

        mmio_read(
            REG_STATUS,
            32'h00000006,
            "invalid command reports DONE and ERROR"
        );

        check(
            sdram_request_count == 0,
            "invalid command issues zero SDRAM requests"
        );

        // ----------------------------------------------------
        // Valid shell command
        // ----------------------------------------------------

        mmio_write(
            REG_TARGET_SIZE,
            32'h00020002,
            4'b1111
        );

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000010,
            4'b1111
        );

        mmio_write(
            REG_FLAT_COLOR,
            32'h0000F81F,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b1 &&
            dut.done === 1'b0 &&
            dut.error === 1'b0 &&
            dut.shell_pending === 1'b1,
            "valid START enters bounded BUSY shell state"
        );

        check(
            dut.active_vertex_base == 32'h10000000 &&
            dut.active_framebuffer_base == 32'h10001000 &&
            dut.active_target_size == 32'h00020002 &&
            dut.active_mode == 32'h00000000 &&
            dut.active_blend_alpha == 32'h00000010 &&
            dut.active_flat_color == 32'h0000F81F,
            "accepted START snapshots live configuration"
        );

        check(
            sdram_valid === 1'b0,
            "valid M10B-1 shell command still emits no SDRAM traffic"
        );

        // The shell is BUSY here. This second START reaches the next
        // posedge while old BUSY is still asserted and must be ignored.
        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.error === 1'b0 &&
            dut.shell_pending === 1'b0,
            "START while BUSY is ignored as first command completes"
        );

        check(
            dut.active_flat_color == 32'h0000F81F,
            "ignored START does not replace active snapshot"
        );

        mmio_read(
            REG_STATUS,
            32'h00000002,
            "successful shell command reports sticky DONE"
        );

        // ----------------------------------------------------
        // Live writes do not alter active command snapshot
        // ----------------------------------------------------

        mmio_write(
            REG_FLAT_COLOR,
            32'h00001234,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b1 &&
            dut.active_flat_color == 32'h00001234,
            "new command snapshots current flat color"
        );

        // This write lands while the old BUSY value is still asserted.
        mmio_write(
            REG_FLAT_COLOR,
            32'h00005678,
            4'b1111
        );

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.active_flat_color == 32'h00001234,
            "live write during BUSY does not mutate active snapshot"
        );

        mmio_read(
            REG_FLAT_COLOR,
            32'h00005678,
            "live write during BUSY is retained for next command"
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b1 &&
            dut.active_flat_color == 32'h00005678,
            "next START consumes updated live configuration"
        );

        @(posedge clk);
        #1;

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.error === 1'b0,
            "bounded shell command completes one interval later"
        );

        // ----------------------------------------------------
        // Alpha validation
        // ----------------------------------------------------

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000011,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.error === 1'b1,
            "alpha greater than 16 deterministically fails"
        );

        // ----------------------------------------------------
        // Texture validation only when texture mode is enabled
        // ----------------------------------------------------

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000010,
            4'b1111
        );

        mmio_write(
            REG_TEXTURE_BASE,
            32'h10002000,
            4'b1111
        );

        mmio_write(
            REG_TEXTURE_SIZE,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_MODE,
            32'h00000001,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.error === 1'b1,
            "enabled texture with zero dimensions fails"
        );

        // Disable texture again. Zero texture size is then legal.
        mmio_write(
            REG_MODE,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b1 &&
            dut.error === 1'b0,
            "disabled texture does not require texture dimensions"
        );

        @(posedge clk);
        #1;

        check(
            dut.done === 1'b1 &&
            dut.busy === 1'b0 &&
            dut.error === 1'b0,
            "texture-disabled command completes successfully"
        );

        // ----------------------------------------------------
        // Global M10B-1 memory-boundary proof
        // ----------------------------------------------------

        check(
            sdram_request_count == 0,
            "entire standalone M10B-1 test observes zero SDRAM requests"
        );

        check(
            sdram_valid === 1'b0 &&
            sdram_write === 1'b0 &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "3D shell SDRAM outputs remain deterministic idle values"
        );

        check(
            ready === 1'b0,
            "MMIO ready deasserts when no request is present"
        );

        // ----------------------------------------------------
        // Result
        // ----------------------------------------------------

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
