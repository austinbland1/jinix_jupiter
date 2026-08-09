`timescale 1ns/1ps

module jupiter_gpu_tiledata_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001100;
    localparam [31:0] REG_TILEMAP_BASE     = 32'h00001108;
    localparam [31:0] REG_TILEDATA_BASE    = 32'h0000110C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001110;
    localparam [31:0] REG_MAP_SIZE         = 32'h00001114;

    localparam [2:0] RENDER_TILEMAP_WAIT      = 3'd1;
    localparam [2:0] RENDER_TILE_DATA_PENDING = 3'd2;
    localparam [2:0] RENDER_TILE_DATA_WAIT    = 3'd3;
    localparam [2:0] RENDER_TILE_ROW_PENDING  = 3'd4;

    localparam [31:0] TILEMAP_BASE  = 32'h10008000;
    localparam [31:0] TILEDATA_BASE = 32'h1000A000;

    // Tile index 3:
    //   TILEDATA_BASE + (3 * 128) = 0x1000A180
    localparam [31:0] TILE3_BASE = 32'h1000A180;

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

    task complete_tiledata_read;
        input [31:0] expected_addr;
        input [31:0] return_data;
        begin
            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == expected_addr,
                "expected tile-data word address is presented"
            );

            check(
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000,
                "tile-data request remains read-only"
            );

            @(negedge clk);

            sdram_rdata = return_data;
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                sdram_addr == expected_addr,
                "tile-data request remains presented through completion"
            );

            @(posedge clk);
            #1;

            @(negedge clk);

            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;

        mmio_write(
            REG_TILEMAP_BASE,
            TILEMAP_BASE,
            4'b1111
        );

        mmio_write(
            REG_TILEDATA_BASE,
            TILEDATA_BASE,
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
            dut.renderer_state == RENDER_TILEMAP_WAIT &&
            sdram_valid &&
            sdram_addr == TILEMAP_BASE,
            "render begins with tilemap entry zero"
        );

        // Complete tilemap entry zero with tile index 3. Upper bits are
        // deliberately nonzero and must not participate in tile addressing.
        @(negedge clk);
        sdram_rdata = 32'hCAFE0003;
        sdram_ready = 1'b1;

        @(posedge clk);
        #1;

        check(
            dut.current_tile_index == 16'd3,
            "tilemap result supplies tile index three"
        );

        check(
            dut.renderer_state == RENDER_TILE_DATA_PENDING &&
            !sdram_valid,
            "tilemap completion retains one transaction-free pending state"
        );

        @(negedge clk);
        sdram_ready = 1'b0;
        sdram_rdata = 32'h00000000;

        // Change the live tile-data base while the active renderer moves
        // into its first tile-data request. The active snapshot must remain
        // the original base.
        mmio_write(
            REG_TILEDATA_BASE,
            32'h1000E000,
            4'b1111
        );

        #1;

        check(
            dut.renderer_state == RENDER_TILE_DATA_WAIT,
            "renderer advances from pending to tile-data read state"
        );

        check(
            dut.tiledata_base_reg == 32'h1000E000,
            "live TILEDATA_BASE remains writable while renderer is busy"
        );

        check(
            dut.active_tiledata_base == TILEDATA_BASE,
            "active TILEDATA_BASE snapshot remains unchanged"
        );

        check(
            dut.tile_word == 2'd0 &&
            sdram_valid &&
            sdram_addr == TILE3_BASE,
            "tile index three generates exact row-zero word-zero address"
        );

        // Explicitly prove the first tile-data request is stable under stall.
        held_addr  = sdram_addr;
        held_write = sdram_write;
        held_wdata = sdram_wdata;
        held_wstrb = sdram_wstrb;

        repeat (3) begin
            @(posedge clk);
            #1;

            check(
                sdram_valid &&
                sdram_addr == held_addr &&
                sdram_write == held_write &&
                sdram_wdata == held_wdata &&
                sdram_wstrb == held_wstrb,
                "tile-data word-zero request remains stable while stalled"
            );
        end

        complete_tiledata_read(
            TILE3_BASE + 32'd0,
            32'h11112222
        );

        check(
            dut.tile_row_word0 == 32'h11112222 &&
            dut.tile_word == 2'd1,
            "first tile-data word is captured and word index advances"
        );

        complete_tiledata_read(
            TILE3_BASE + 32'd4,
            32'h33334444
        );

        check(
            dut.tile_row_word1 == 32'h33334444 &&
            dut.tile_word == 2'd2,
            "second tile-data word is captured and word index advances"
        );

        complete_tiledata_read(
            TILE3_BASE + 32'd8,
            32'h55556666
        );

        check(
            dut.tile_row_word2 == 32'h55556666 &&
            dut.tile_word == 2'd3,
            "third tile-data word is captured and word index advances"
        );

        complete_tiledata_read(
            TILE3_BASE + 32'd12,
            32'h77778888
        );

        check(
            dut.tile_row_word3 == 32'h77778888,
            "fourth tile-data word is captured"
        );

        check(
            dut.renderer_state == RENDER_TILE_ROW_PENDING,
            "renderer stops at bounded post-row state after four reads"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "M5D-2 issues no framebuffer transaction"
        );

        check(
            dut.busy &&
            !dut.done,
            "M5D-2 does not fake nonzero render completion"
        );

        check(
            dut.tile_x == 8'd0 &&
            dut.tile_y == 8'd0,
            "M5D-2 does not advance tile coordinates"
        );

        // Reset must cancel the bounded in-progress operation.
        @(negedge clk);
        reset = 1'b1;

        repeat (2) @(posedge clk);
        #1;

        check(
            !dut.busy &&
            !dut.done &&
            !sdram_valid,
            "reset cancels bounded M5D-2 renderer state"
        );

        check(
            dut.tile_row_word0 == 32'h00000000 &&
            dut.tile_row_word1 == 32'h00000000 &&
            dut.tile_row_word2 == 32'h00000000 &&
            dut.tile_row_word3 == 32'h00000000,
            "reset clears captured tile-row words"
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
