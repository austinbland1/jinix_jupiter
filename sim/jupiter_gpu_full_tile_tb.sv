`timescale 1ns/1ps

module jupiter_gpu_full_tile_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001100;
    localparam [31:0] REG_TILEMAP_BASE     = 32'h00001108;
    localparam [31:0] REG_TILEDATA_BASE    = 32'h0000110C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001110;
    localparam [31:0] REG_MAP_SIZE         = 32'h00001114;

    localparam [2:0] RENDER_IDLE              = 3'd0;
    localparam [2:0] RENDER_TILEMAP_WAIT      = 3'd1;
    localparam [2:0] RENDER_TILE_DATA_PENDING = 3'd2;
    localparam [2:0] RENDER_TILE_DATA_WAIT    = 3'd3;
    localparam [2:0] RENDER_TILE_ROW_PENDING  = 3'd4;
    localparam [2:0] RENDER_FRAMEBUFFER_WAIT  = 3'd5;
    localparam [2:0] RENDER_ROW_WRITTEN       = 3'd6;
    localparam [2:0] RENDER_TILE_COMPLETE     = 3'd7;

    localparam [31:0] TILEMAP_BASE     = 32'h10008000;
    localparam [31:0] TILEDATA_BASE    = 32'h1000A000;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h1000C000;

    // Tile index 3 begins at +0x180.
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

    integer read_completions = 0;
    integer write_completions = 0;

    integer row_i;
    integer word_i;

    reg [31:0] held_addr;
    reg [31:0] held_data;
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

    always @(posedge clk) begin
        if (!reset && sdram_valid && sdram_ready) begin
            if (sdram_write)
                write_completions <= write_completions + 1;
            else
                read_completions <= read_completions + 1;
        end
    end

    function [31:0] row_word_data;
        input integer row_index;
        input integer word_index;
        begin
            row_word_data =
                32'hA5000000 +
                (row_index * 32'h00000100) +
                word_index;
        end
    endfunction

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

    task complete_read;
        input [31:0] expected_addr;
        input [31:0] return_data;
        begin
            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == expected_addr &&
                sdram_wstrb == 4'b0000,
                "expected tile or tilemap read is presented"
            );

            @(negedge clk);
            sdram_rdata = return_data;
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == expected_addr,
                "read request remains presented through completion"
            );

            @(posedge clk);
            #1;

            @(negedge clk);
            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;
        end
    endtask

    task complete_write;
        input [31:0] expected_addr;
        input [31:0] expected_data;
        begin
            #1;

            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr == expected_addr,
                "expected framebuffer write address is presented"
            );

            check(
                sdram_wdata == expected_data &&
                sdram_wstrb == 4'b1111,
                "framebuffer write carries expected row data and strobes"
            );

            @(negedge clk);
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr == expected_addr &&
                sdram_wdata == expected_data &&
                sdram_wstrb == 4'b1111,
                "framebuffer write remains stable through completion"
            );

            @(posedge clk);
            #1;

            @(negedge clk);
            sdram_ready = 1'b0;
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
            FRAMEBUFFER_BASE,
            4'b1111
        );

        // Deliberately use width 2 so the framebuffer stride is 32 bytes.
        // Height remains 2; D4 still renders only tile (0,0).
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
            dut.tile_row == 3'd0 &&
            dut.tile_x == 8'd0 &&
            dut.tile_y == 8'd0,
            "render begins at tile zero row zero"
        );

        complete_read(
            TILEMAP_BASE,
            32'hDEAD0003
        );

        check(
            dut.current_tile_index == 16'd3 &&
            dut.renderer_state == RENDER_TILE_DATA_PENDING,
            "tilemap fetch selects tile index three"
        );

        // Move through the intentional post-tilemap pending state.
        @(posedge clk);
        #1;

        for (row_i = 0; row_i < 8; row_i = row_i + 1) begin
            check(
                dut.renderer_state == RENDER_TILE_DATA_WAIT &&
                dut.tile_row == row_i,
                "renderer begins expected tile row"
            );

            for (word_i = 0; word_i < 4; word_i = word_i + 1) begin
                // Prove stability on a later row, not just the already-tested
                // row-zero request.
                if ((row_i == 3) && (word_i == 2)) begin
                    held_addr = sdram_addr;

                    repeat (2) begin
                        @(posedge clk);
                        #1;

                        check(
                            sdram_valid &&
                            !sdram_write &&
                            sdram_addr == held_addr,
                            "later-row tile-data request remains stable while stalled"
                        );
                    end
                end

                complete_read(
                    TILE3_BASE +
                    (row_i * 32'd16) +
                    (word_i * 32'd4),
                    row_word_data(row_i, word_i)
                );
            end

            check(
                dut.renderer_state == RENDER_TILE_ROW_PENDING,
                "four reads finish one tile row"
            );

            check(
                dut.tile_row_word0 == row_word_data(row_i, 0) &&
                dut.tile_row_word1 == row_word_data(row_i, 1) &&
                dut.tile_row_word2 == row_word_data(row_i, 2) &&
                dut.tile_row_word3 == row_word_data(row_i, 3),
                "all four words for current tile row are captured"
            );

            // Advance the transaction-free row-pending state.
            @(posedge clk);
            #1;

            check(
                dut.renderer_state == RENDER_FRAMEBUFFER_WAIT &&
                dut.tile_word == 2'd0,
                "captured tile row advances to framebuffer writes"
            );

            // With width_tiles == 2, each complete framebuffer scanline is
            // 32 bytes. Tile zero occupies the first sixteen bytes.
            check(
                sdram_addr ==
                    FRAMEBUFFER_BASE +
                    (row_i * 32'd32),
                "framebuffer row begins at full-image row stride"
            );

            for (word_i = 0; word_i < 4; word_i = word_i + 1) begin
                if ((row_i == 5) && (word_i == 1)) begin
                    held_addr  = sdram_addr;
                    held_data  = sdram_wdata;
                    held_wstrb = sdram_wstrb;

                    repeat (2) begin
                        @(posedge clk);
                        #1;

                        check(
                            sdram_valid &&
                            sdram_write &&
                            sdram_addr == held_addr &&
                            sdram_wdata == held_data &&
                            sdram_wstrb == held_wstrb,
                            "later-row framebuffer request remains stable while stalled"
                        );
                    end
                end

                complete_write(
                    FRAMEBUFFER_BASE +
                    (row_i * 32'd32) +
                    (word_i * 32'd4),
                    row_word_data(row_i, word_i)
                );
            end

            check(
                dut.renderer_state == RENDER_ROW_WRITTEN &&
                dut.tile_row == row_i,
                "four writes finish expected framebuffer row"
            );

            if (row_i < 7) begin
                @(posedge clk);
                #1;

                check(
                    dut.renderer_state == RENDER_TILE_DATA_WAIT &&
                    dut.tile_row == (row_i + 1),
                    "renderer advances to next row of same tile"
                );

                check(
                    dut.tile_x == 8'd0 &&
                    dut.tile_y == 8'd0,
                    "row traversal does not advance tile coordinates"
                );
            end
        end

        // Row seven is complete but still passes through ROW_WRITTEN before
        // entering the bounded single-tile completion state.
        @(posedge clk);
        #1;

        check(
            dut.renderer_state == RENDER_TILE_COMPLETE,
            "row seven completion reaches bounded full-tile state"
        );

        check(
            dut.tile_row == 3'd7 &&
            dut.tile_x == 8'd0 &&
            dut.tile_y == 8'd0,
            "M5D-4 stops after tile zero without tile-coordinate traversal"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "full-tile checkpoint leaves graphics-memory interface idle"
        );

        check(
            dut.busy &&
            !dut.done,
            "M5D-4 does not fake completion of the full map"
        );

        check(
            read_completions == 33,
            "one tilemap plus thirty-two tile-data reads complete"
        );

        check(
            write_completions == 32,
            "eight rows produce thirty-two framebuffer writes"
        );

        // Confirm a 2-tile-wide framebuffer used 32-byte row spacing.
        check(
            FRAMEBUFFER_BASE + (7 * 32) ==
            32'h1000C0E0,
            "row seven base reflects 32-byte framebuffer stride"
        );

        @(negedge clk);
        reset = 1'b1;

        repeat (2) @(posedge clk);
        #1;

        check(
            dut.renderer_state == RENDER_IDLE &&
            dut.tile_row == 3'd0 &&
            !dut.busy &&
            !dut.done &&
            !sdram_valid,
            "reset clears bounded full-tile renderer state"
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
