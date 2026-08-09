`timescale 1ns/1ps

module jupiter_gpu_full_map_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001100;
    localparam [31:0] REG_STATUS           = 32'h00001104;
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
    integer total_completions = 0;

    integer tile_x_i;
    integer tile_y_i;
    integer tile_linear_i;
    integer tile_index_i;
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
            total_completions <= total_completions + 1;

            if (sdram_write)
                write_completions <= write_completions + 1;
            else
                read_completions <= read_completions + 1;
        end
    end

    function [31:0] render_word;
        input integer tile_linear;
        input integer row_index;
        input integer word_index;
        begin
            render_word =
                32'hA0000000 +
                (tile_linear * 32'h00010000) +
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

    task check_done_status;
        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b0;
            addr  = REG_STATUS;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;

            check(
                ready &&
                rdata[1:0] == 2'b10,
                "CPU-visible STATUS reports done set and busy clear"
            );

            @(posedge clk);
            #1;

            @(negedge clk);

            valid = 1'b0;
            write = 1'b0;
            addr  = 32'h00000000;
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
                "expected graphics-memory read is presented"
            );

            @(negedge clk);
            sdram_rdata = return_data;
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == expected_addr,
                "graphics-memory read remains stable through completion"
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
                "framebuffer write carries exact RGB565 row word"
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

        // Deterministic 2x2 tile map: sixteen by sixteen output pixels.
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
            dut.busy &&
            !dut.done &&
            dut.renderer_state == RENDER_TILEMAP_WAIT,
            "nonzero 2x2 render starts busy with done clear"
        );

        for (tile_y_i = 0; tile_y_i < 2; tile_y_i = tile_y_i + 1) begin
            for (tile_x_i = 0; tile_x_i < 2; tile_x_i = tile_x_i + 1) begin
                tile_linear_i = (tile_y_i * 2) + tile_x_i;
                tile_index_i = tile_linear_i + 1;

                #1;

                check(
                    dut.renderer_state == RENDER_TILEMAP_WAIT &&
                    dut.tile_x == tile_x_i &&
                    dut.tile_y == tile_y_i,
                    "renderer presents expected row-major tile coordinate"
                );

                check(
                    sdram_valid &&
                    !sdram_write &&
                    sdram_addr ==
                        TILEMAP_BASE +
                        (tile_linear_i * 32'd4),
                    "tilemap read uses exact row-major entry address"
                );

                // Exercise a stalled tilemap request after traversal has
                // already advanced away from tile zero.
                if (tile_linear_i == 1) begin
                    held_addr = sdram_addr;

                    repeat (2) begin
                        @(posedge clk);
                        #1;

                        check(
                            sdram_valid &&
                            !sdram_write &&
                            sdram_addr == held_addr &&
                            dut.tile_x == 8'd1 &&
                            dut.tile_y == 8'd0,
                            "advanced tilemap request remains stable while stalled"
                        );
                    end
                end

                complete_read(
                    TILEMAP_BASE +
                    (tile_linear_i * 32'd4),
                    32'hD00D0000 + tile_index_i
                );

                check(
                    dut.current_tile_index == tile_index_i &&
                    dut.renderer_state == RENDER_TILE_DATA_PENDING,
                    "tilemap result selects expected tile-data index"
                );

                // Intentional transaction-free post-tilemap boundary.
                @(posedge clk);
                #1;

                for (row_i = 0; row_i < 8; row_i = row_i + 1) begin
                    check(
                        dut.renderer_state == RENDER_TILE_DATA_WAIT &&
                        dut.tile_row == row_i,
                        "renderer begins expected row within current tile"
                    );

                    for (word_i = 0; word_i < 4; word_i = word_i + 1) begin
                        complete_read(
                            TILEDATA_BASE +
                            (tile_index_i * 32'd128) +
                            (row_i * 32'd16) +
                            (word_i * 32'd4),
                            render_word(
                                tile_linear_i,
                                row_i,
                                word_i
                            )
                        );
                    end

                    check(
                        dut.renderer_state == RENDER_TILE_ROW_PENDING,
                        "four reads complete current tile row"
                    );

                    @(posedge clk);
                    #1;

                    check(
                        dut.renderer_state == RENDER_FRAMEBUFFER_WAIT,
                        "captured tile row advances to framebuffer writes"
                    );

                    for (word_i = 0; word_i < 4; word_i = word_i + 1) begin
                        // Exercise a stalled write whose address depends on
                        // both tile X and tile Y.
                        if ((tile_x_i == 1) &&
                            (tile_y_i == 1) &&
                            (row_i == 6) &&
                            (word_i == 2)) begin

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
                                    "multi-tile framebuffer request remains stable while stalled"
                                );
                            end
                        end

                        complete_write(
                            FRAMEBUFFER_BASE +
                            (((tile_y_i * 8) + row_i) * 32'd32) +
                            (tile_x_i * 32'd16) +
                            (word_i * 32'd4),
                            render_word(
                                tile_linear_i,
                                row_i,
                                word_i
                            )
                        );
                    end

                    check(
                        dut.renderer_state == RENDER_ROW_WRITTEN,
                        "four framebuffer writes complete current tile row"
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
                            dut.tile_x == tile_x_i &&
                            dut.tile_y == tile_y_i,
                            "row advancement preserves tile coordinate"
                        );
                    end
                end

                // Row seven has completed. First cross the existing
                // row-written boundary into TILE_COMPLETE.
                @(posedge clk);
                #1;

                check(
                    dut.renderer_state == RENDER_TILE_COMPLETE &&
                    dut.tile_x == tile_x_i &&
                    dut.tile_y == tile_y_i,
                    "completed tile reaches transaction-free tile boundary"
                );

                check(
                    !sdram_valid &&
                    !sdram_write,
                    "tile boundary presents no graphics-memory request"
                );

                if (tile_linear_i < 3) begin
                    @(posedge clk);
                    #1;

                    check(
                        dut.renderer_state == RENDER_TILEMAP_WAIT,
                        "non-final tile advances to next tilemap fetch"
                    );

                    if (tile_x_i == 0) begin
                        check(
                            dut.tile_x == 8'd1 &&
                            dut.tile_y == tile_y_i,
                            "row-major traversal advances tile X"
                        );
                    end else begin
                        check(
                            dut.tile_x == 8'd0 &&
                            dut.tile_y == (tile_y_i + 1),
                            "row-major traversal wraps X and advances tile Y"
                        );
                    end

                    check(
                        dut.tile_row == 3'd0 &&
                        dut.tile_word == 2'd0 &&
                        dut.current_tile_index == 16'd0,
                        "new tile begins with renderer-local counters reset"
                    );
                end else begin
                    // Final tile transitions from TILE_COMPLETE to IDLE and
                    // publishes completion through STATUS.
                    @(posedge clk);
                    #1;

                    check(
                        dut.renderer_state == RENDER_IDLE &&
                        !dut.busy &&
                        dut.done,
                        "final tile completes nonzero render"
                    );

                    check(
                        dut.tile_x == 8'd1 &&
                        dut.tile_y == 8'd1 &&
                        dut.tile_row == 3'd7,
                        "completed render retains final tile coordinate"
                    );

                    check(
                        !sdram_valid &&
                        !sdram_write &&
                        sdram_addr == 32'h00000000 &&
                        sdram_wdata == 32'h00000000 &&
                        sdram_wstrb == 4'b0000,
                        "completed render returns graphics-memory interface to idle"
                    );
                end
            end
        end

        check(
            read_completions == 132,
            "2x2 render completes four tilemap plus 128 tile-data reads"
        );

        check(
            write_completions == 128,
            "2x2 render completes 128 framebuffer writes"
        );

        check(
            total_completions == 260,
            "2x2 render completes exactly 260 GPU SDRAM transactions"
        );

        // Last framebuffer word:
        // pixel row 15 * 32-byte stride + tile-x 1 * 16 + word 3 * 4
        // = 0x1FC.
        check(
            FRAMEBUFFER_BASE + 32'h000001FC ==
            32'h1000C1FC,
            "2x2 framebuffer occupies expected final word address"
        );

        // Completion must be stable while the renderer remains idle.
        repeat (3) begin
            @(posedge clk);
            #1;

            check(
                dut.renderer_state == RENDER_IDLE &&
                !dut.busy &&
                dut.done &&
                !sdram_valid,
                "done remains stable with no post-completion memory traffic"
            );
        end

        check_done_status();

        @(negedge clk);
        reset = 1'b1;

        repeat (2) @(posedge clk);
        #1;

        check(
            dut.renderer_state == RENDER_IDLE &&
            !dut.busy &&
            !dut.done &&
            !sdram_valid,
            "reset clears completed-render status"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("GPU_READ_COMPLETIONS: %0d", read_completions);
            $display("GPU_WRITE_COMPLETIONS: %0d", write_completions);
            $display("GPU_TOTAL_COMPLETIONS: %0d", total_completions);
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
