`timescale 1ns/1ps

module jupiter_gpu_tilemap_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001100;
    localparam [31:0] REG_STATUS           = 32'h00001104;
    localparam [31:0] REG_TILEMAP_BASE     = 32'h00001108;
    localparam [31:0] REG_TILEDATA_BASE    = 32'h0000110C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001110;
    localparam [31:0] REG_MAP_SIZE         = 32'h00001114;

    localparam [1:0] RENDER_IDLE              = 2'd0;
    localparam [1:0] RENDER_TILEMAP_WAIT      = 2'd1;
    localparam [1:0] RENDER_TILE_DATA_PENDING = 2'd2;

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

    reg [31:0] held_addr;
    reg        held_write;
    reg [31:0] held_wdata;
    reg  [3:0] held_wstrb;

    always #5 clk = ~clk;

    jupiter_gpu_2d dut
    (
        .clk   (clk),
        .reset (reset),

        .valid (valid),
        .write (write),
        .addr  (addr),
        .wdata (wdata),
        .wstrb (wstrb),

        .rdata (rdata),
        .ready (ready),

        .sdram_valid (sdram_valid),
        .sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );

    task check;
        input condition;
        input [8*128-1:0] message;
        begin
            checks = checks + 1;

            if (condition)
                $display("PASS: %0s", message);
            else begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task mmio_write;
        input [31:0] write_addr;
        input [31:0] write_data;
        input  [3:0] write_strobes;
        begin
            @(negedge clk);
            valid = 1'b1;
            write = 1'b1;
            addr  = write_addr;
            wdata = write_data;
            wstrb = write_strobes;

            #1;
            check(
                ready,
                "GPU MMIO write completes without wait state"
            );

            @(posedge clk);
            #1;

            @(negedge clk);
            valid = 1'b0;
            write = 1'b0;
            addr  = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1;

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "reset leaves renderer SDRAM request deterministically idle"
        );

        check(
            dut.renderer_state == RENDER_IDLE &&
            dut.tile_x == 8'd0 &&
            dut.tile_y == 8'd0 &&
            dut.current_tile_index == 16'd0,
            "reset clears renderer sequencing state"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_write(
            REG_TILEMAP_BASE,
            32'h10008000,
            4'b1111
        );

        mmio_write(
            REG_TILEDATA_BASE,
            32'h1000A000,
            4'b1111
        );

        mmio_write(
            REG_FRAMEBUFFER_BASE,
            32'h1000C000,
            4'b1111
        );

        // width = 2 tiles, height = 2 tiles.
        mmio_write(
            REG_MAP_SIZE,
            32'h00000202,
            4'b0011
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        #1;

        check(
            dut.busy && !dut.done,
            "nonzero render remains busy while first tilemap fetch is pending"
        );

        check(
            dut.renderer_state == RENDER_TILEMAP_WAIT,
            "nonzero start enters first tilemap-fetch state"
        );

        check(
            dut.tile_x == 8'd0 && dut.tile_y == 8'd0,
            "renderer begins at tile coordinate zero zero"
        );

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10008000,
            "first tilemap fetch reads exact snapshotted tilemap base"
        );

        check(
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "tilemap fetch is a deterministic read-only transaction"
        );

        held_addr  = sdram_addr;
        held_write = sdram_write;
        held_wdata = sdram_wdata;
        held_wstrb = sdram_wstrb;

        // Stall for multiple clocks. The complete request must stay stable.
        repeat (3) begin
            @(posedge clk);
            #1;

            check(
                sdram_valid &&
                sdram_addr == held_addr &&
                sdram_write == held_write &&
                sdram_wdata == held_wdata &&
                sdram_wstrb == held_wstrb,
                "tilemap request remains stable while SDRAM is stalled"
            );
        end

        // Change the live register while the renderer is stalled. The active
        // snapshot and memory request must not change.
        mmio_write(
            REG_TILEMAP_BASE,
            32'h1000E000,
            4'b1111
        );

        #1;

        check(
            dut.tilemap_base_reg == 32'h1000E000,
            "live TILEMAP_BASE remains writable while renderer is stalled"
        );

        check(
            dut.active_tilemap_base == 32'h10008000,
            "active TILEMAP_BASE snapshot is preserved while busy"
        );

        check(
            sdram_valid &&
            sdram_addr == 32'h10008000,
            "live configuration write does not alter active tilemap request"
        );

        // A second start while busy must also leave the active request alone.
        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        #1;

        check(
            dut.active_tilemap_base == 32'h10008000 &&
            sdram_addr == 32'h10008000,
            "start while busy does not replace active render state"
        );

        // Complete the first real graphics-memory transaction. Reserved high
        // bits must be ignored; low 16 bits are the unsigned tile index.
        @(negedge clk);
        sdram_rdata = 32'hA5A5BEEF;
        sdram_ready = 1'b1;

        #1;

        check(
            sdram_valid &&
            sdram_addr == 32'h10008000,
            "tilemap request remains presented through completion cycle"
        );

        @(posedge clk);
        #1;

        check(
            dut.current_tile_index == 16'hBEEF,
            "tilemap completion captures low sixteen bits as tile index"
        );

        check(
            dut.renderer_state == RENDER_TILE_DATA_PENDING,
            "renderer advances to bounded M5D-2 tile-data-pending state"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "M5D-1 issues no tile-data or framebuffer transaction yet"
        );

        check(
            dut.busy && !dut.done,
            "M5D-1 does not fake render completion after tilemap fetch"
        );

        @(negedge clk);
        sdram_ready = 1'b0;
        sdram_rdata = 32'h00000000;

        // Reset must cancel the bounded in-progress renderer state.
        reset = 1'b1;
        repeat (2) @(posedge clk);
        #1;

        check(
            dut.renderer_state == RENDER_IDLE &&
            !dut.busy &&
            !dut.done,
            "reset returns renderer to idle and clears status"
        );

        check(
            !sdram_valid &&
            sdram_addr == 32'h00000000,
            "reset leaves graphics-memory request idle"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("==============================");
            $finish;
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
