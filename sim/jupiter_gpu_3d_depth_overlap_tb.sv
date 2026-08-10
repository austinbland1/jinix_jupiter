`timescale 1ns/1ps

module jupiter_gpu_3d_depth_overlap_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_DEPTH_BASE       = 32'h00001154;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;

    localparam [31:0] VERTEX_BASE      = 32'h10000000;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h10010000;
    localparam [31:0] DEPTH_BASE       = 32'h10020000;

    localparam [31:0] FB_SENTINEL_BEFORE_ADDR =
        FRAMEBUFFER_BASE - 32'd4;

    localparam [31:0] FB_SENTINEL_AFTER_ADDR =
        FRAMEBUFFER_BASE + 32'd32;

    localparam [31:0] DEPTH_SENTINEL_BEFORE_ADDR =
        DEPTH_BASE - 32'd4;

    localparam [31:0] DEPTH_SENTINEL_AFTER_ADDR =
        DEPTH_BASE + 32'd32;

    localparam [31:0] UNRELATED_ADDR =
        32'h10030000;

    localparam [15:0] BACKGROUND_COLOR = 16'h1234;
    localparam [15:0] FAR_COLOR        = 16'hF800;
    localparam [15:0] NEAR_COLOR       = 16'h07E0;

    localparam [15:0] FAR_Z  = 16'h7000;
    localparam [15:0] NEAR_Z = 16'h2000;

    localparam [31:0] FB_SENTINEL_BEFORE_VALUE =
        32'hCAFEBABE;

    localparam [31:0] FB_SENTINEL_AFTER_VALUE =
        32'h0BADF00D;

    localparam [31:0] DEPTH_SENTINEL_BEFORE_VALUE =
        32'hDEADC0DE;

    localparam [31:0] DEPTH_SENTINEL_AFTER_VALUE =
        32'hFACEB00C;

    localparam [31:0] UNRELATED_VALUE =
        32'h5A5AA5A5;

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

    reg [31:0] sdram_rdata;
    reg        sdram_ready;

    reg [31:0] vertex_mem [0:17];
    reg [15:0] framebuffer_mem [0:15];
    reg [15:0] depth_mem [0:15];

    reg [31:0] fb_sentinel_before;
    reg [31:0] fb_sentinel_after;
    reg [31:0] depth_sentinel_before;
    reg [31:0] depth_sentinel_after;
    reg [31:0] unrelated_word;

    integer checks = 0;
    integer failures = 0;
    integer watchdog = 0;

    integer vertex_reads = 0;
    integer depth_reads = 0;
    integer framebuffer_reads = 0;

    integer depth_writes = 0;
    integer framebuffer_writes = 0;

    integer illegal_reads = 0;
    integer illegal_writes = 0;

    integer i;
    integer word_index;

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

    function automatic [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input  [3:0] strobe;

        reg [31:0] result;

        begin
            result = old_value;

            if (strobe[0])
                result[7:0] = new_value[7:0];

            if (strobe[1])
                result[15:8] = new_value[15:8];

            if (strobe[2])
                result[23:16] = new_value[23:16];

            if (strobe[3])
                result[31:24] = new_value[31:24];

            apply_wstrb = result;
        end
    endfunction

    function automatic [31:0] memory_read_word;
        input [31:0] address;

        integer index;

        begin
            memory_read_word = 32'hD15EA5ED;

            if (
                (address >= VERTEX_BASE) &&
                (address < (VERTEX_BASE + 32'd72))
            ) begin
                index =
                    (address - VERTEX_BASE) >> 2;

                memory_read_word =
                    vertex_mem[index];
            end else if (
                (address >= FRAMEBUFFER_BASE) &&
                (address < (FRAMEBUFFER_BASE + 32'd32))
            ) begin
                index =
                    (address - FRAMEBUFFER_BASE) >> 2;

                memory_read_word =
                {
                    framebuffer_mem[(index * 2) + 1],
                    framebuffer_mem[(index * 2)]
                };
            end else if (
                (address >= DEPTH_BASE) &&
                (address < (DEPTH_BASE + 32'd32))
            ) begin
                index =
                    (address - DEPTH_BASE) >> 2;

                memory_read_word =
                {
                    depth_mem[(index * 2) + 1],
                    depth_mem[(index * 2)]
                };
            end else if (
                address == FB_SENTINEL_BEFORE_ADDR
            ) begin
                memory_read_word =
                    fb_sentinel_before;
            end else if (
                address == FB_SENTINEL_AFTER_ADDR
            ) begin
                memory_read_word =
                    fb_sentinel_after;
            end else if (
                address == DEPTH_SENTINEL_BEFORE_ADDR
            ) begin
                memory_read_word =
                    depth_sentinel_before;
            end else if (
                address == DEPTH_SENTINEL_AFTER_ADDR
            ) begin
                memory_read_word =
                    depth_sentinel_after;
            end else if (
                address == UNRELATED_ADDR
            ) begin
                memory_read_word =
                    unrelated_word;
            end
        end
    endfunction

    function automatic is_covered_pixel;
        input integer index;

        begin
            case (index)
                0, 1, 2, 4, 5, 8:
                    is_covered_pixel = 1'b1;

                default:
                    is_covered_pixel = 1'b0;
            endcase
        end
    endfunction

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

    task load_triangle;
        input [15:0] depth_value;

        begin
            vertex_mem[0]  = 32'h00004000;
            vertex_mem[1]  = 32'h00004000;
            vertex_mem[2]  = {16'h0000, depth_value};
            vertex_mem[3]  = 32'h00000000;
            vertex_mem[4]  = 32'h00000000;
            vertex_mem[5]  = 32'h00010000;

            vertex_mem[6]  = 32'h00034000;
            vertex_mem[7]  = 32'h00004000;
            vertex_mem[8]  = {16'h0000, depth_value};
            vertex_mem[9]  = 32'h00010000;
            vertex_mem[10] = 32'h00000000;
            vertex_mem[11] = 32'h00010000;

            vertex_mem[12] = 32'h00004000;
            vertex_mem[13] = 32'h00034000;
            vertex_mem[14] = {16'h0000, depth_value};
            vertex_mem[15] = 32'h00000000;
            vertex_mem[16] = 32'h00010000;
            vertex_mem[17] = 32'h00010000;
        end
    endtask

    task reset_surfaces;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                framebuffer_mem[i] =
                    BACKGROUND_COLOR;

                depth_mem[i] =
                    16'hFFFF;
            end
        end
    endtask

    task reset_sentinels;
        begin
            fb_sentinel_before =
                FB_SENTINEL_BEFORE_VALUE;

            fb_sentinel_after =
                FB_SENTINEL_AFTER_VALUE;

            depth_sentinel_before =
                DEPTH_SENTINEL_BEFORE_VALUE;

            depth_sentinel_after =
                DEPTH_SENTINEL_AFTER_VALUE;

            unrelated_word =
                UNRELATED_VALUE;
        end
    endtask

    task mmio_write;
        input [31:0] address;
        input [31:0] data;

        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b1;
            addr  = address;
            wdata = data;
            wstrb = 4'b1111;

            #1;

            check(
                ready,
                "MMIO write completes without wait"
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

    task run_triangle;
        input [15:0] depth_value;
        input [15:0] color_value;
        input integer expected_depth_write_delta;
        input integer expected_framebuffer_write_delta;

        integer before_vertex_reads;
        integer before_depth_reads;
        integer before_depth_writes;
        integer before_framebuffer_writes;
        integer before_illegal_reads;
        integer before_illegal_writes;

        begin
            load_triangle(depth_value);

            before_vertex_reads =
                vertex_reads;

            before_depth_reads =
                depth_reads;

            before_depth_writes =
                depth_writes;

            before_framebuffer_writes =
                framebuffer_writes;

            before_illegal_reads =
                illegal_reads;

            before_illegal_writes =
                illegal_writes;

            mmio_write(
                REG_FLAT_COLOR,
                {16'h0000, color_value}
            );

            mmio_write(
                REG_CONTROL,
                32'h00000001
            );

            check(
                dut.busy &&
                dut.active_mode[1] &&
                dut.active_depth_base == DEPTH_BASE,
                "depth-enabled triangle command starts with snapshotted state"
            );

            watchdog = 0;

            while (!dut.done && (watchdog < 500)) begin
                @(posedge clk);
                #1;

                watchdog =
                    watchdog + 1;
            end

            check(
                watchdog < 500 &&
                dut.done &&
                !dut.busy &&
                !dut.error,
                "stateful depth command completes before watchdog"
            );

            check(
                (vertex_reads - before_vertex_reads) == 18,
                "command performs exactly eighteen vertex reads"
            );

            check(
                (depth_reads - before_depth_reads) == 6,
                "command performs one depth read for each covered pixel"
            );

            check(
                (depth_writes - before_depth_writes) ==
                    expected_depth_write_delta,
                "command performs expected strict-LESS depth writes"
            );

            check(
                (
                    framebuffer_writes -
                    before_framebuffer_writes
                ) ==
                    expected_framebuffer_write_delta,
                "command performs expected framebuffer writes"
            );

            check(
                illegal_reads == before_illegal_reads,
                "command performs no unrelated SDRAM reads"
            );

            check(
                illegal_writes == before_illegal_writes,
                "command performs no unrelated SDRAM writes"
            );

            check(
                dut.raster_coverage_count == 32'd6 &&
                dut.raster_sample_count == 32'd16,
                "command preserves deterministic six-pixel coverage"
            );

            check(
                !sdram_valid &&
                !sdram_write &&
                sdram_addr == 32'h00000000 &&
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000,
                "completed command returns SDRAM interface idle"
            );
        end
    endtask

    task check_surface;
        input [15:0] expected_color;
        input [15:0] expected_depth;
        input [1023:0] label;

        begin
            for (i = 0; i < 16; i = i + 1) begin
                if (is_covered_pixel(i)) begin
                    check(
                        framebuffer_mem[i] ==
                            expected_color,
                        label
                    );

                    check(
                        depth_mem[i] ==
                            expected_depth,
                        label
                    );
                end else begin
                    check(
                        framebuffer_mem[i] ==
                            BACKGROUND_COLOR,
                        "uncovered framebuffer pixels remain unchanged"
                    );

                    check(
                        depth_mem[i] ==
                            16'hFFFF,
                        "uncovered depth pixels remain at far clear value"
                    );
                end
            end
        end
    endtask

    task check_sentinels;
        begin
            check(
                fb_sentinel_before ==
                    FB_SENTINEL_BEFORE_VALUE,
                "framebuffer leading sentinel remains unchanged"
            );

            check(
                fb_sentinel_after ==
                    FB_SENTINEL_AFTER_VALUE,
                "framebuffer trailing sentinel remains unchanged"
            );

            check(
                depth_sentinel_before ==
                    DEPTH_SENTINEL_BEFORE_VALUE,
                "depth leading sentinel remains unchanged"
            );

            check(
                depth_sentinel_after ==
                    DEPTH_SENTINEL_AFTER_VALUE,
                "depth trailing sentinel remains unchanged"
            );

            check(
                unrelated_word ==
                    UNRELATED_VALUE,
                "unrelated SDRAM sentinel remains unchanged"
            );
        end
    endtask

    // Zero-wait-state deterministic SDRAM model. Every asserted logical
    // request completes on the next active edge while read data is supplied
    // combinationally from persistent memory.
    always @* begin
        sdram_ready =
            sdram_valid;

        sdram_rdata =
            memory_read_word(sdram_addr);
    end

    // Persistent SDRAM state and access accounting.
    always @(posedge clk) begin
        if (sdram_valid && sdram_ready) begin

            if (!sdram_write) begin

                if (
                    (sdram_addr >= VERTEX_BASE) &&
                    (sdram_addr < (VERTEX_BASE + 32'd72))
                ) begin
                    vertex_reads <=
                        vertex_reads + 1;
                end else if (
                    (sdram_addr >= DEPTH_BASE) &&
                    (sdram_addr < (DEPTH_BASE + 32'd32))
                ) begin
                    depth_reads <=
                        depth_reads + 1;
                end else if (
                    (sdram_addr >= FRAMEBUFFER_BASE) &&
                    (sdram_addr < (FRAMEBUFFER_BASE + 32'd32))
                ) begin
                    framebuffer_reads <=
                        framebuffer_reads + 1;

                    illegal_reads <=
                        illegal_reads + 1;
                end else begin
                    illegal_reads <=
                        illegal_reads + 1;
                end

            end else begin

                if (
                    (sdram_addr >= FRAMEBUFFER_BASE) &&
                    (sdram_addr < (FRAMEBUFFER_BASE + 32'd32))
                ) begin
                    word_index =
                        (sdram_addr - FRAMEBUFFER_BASE) >> 2;

                    if (sdram_wstrb == 4'b0011) begin
                        framebuffer_mem[word_index * 2] <=
                            sdram_wdata[15:0];
                    end else if (sdram_wstrb == 4'b1100) begin
                        framebuffer_mem[(word_index * 2) + 1] <=
                            sdram_wdata[31:16];
                    end else begin
                        illegal_writes <=
                            illegal_writes + 1;
                    end

                    framebuffer_writes <=
                        framebuffer_writes + 1;

                end else if (
                    (sdram_addr >= DEPTH_BASE) &&
                    (sdram_addr < (DEPTH_BASE + 32'd32))
                ) begin
                    word_index =
                        (sdram_addr - DEPTH_BASE) >> 2;

                    if (sdram_wstrb == 4'b0011) begin
                        depth_mem[word_index * 2] <=
                            sdram_wdata[15:0];
                    end else if (sdram_wstrb == 4'b1100) begin
                        depth_mem[(word_index * 2) + 1] <=
                            sdram_wdata[31:16];
                    end else begin
                        illegal_writes <=
                            illegal_writes + 1;
                    end

                    depth_writes <=
                        depth_writes + 1;

                end else if (
                    sdram_addr == FB_SENTINEL_BEFORE_ADDR
                ) begin
                    fb_sentinel_before <=
                        apply_wstrb(
                            fb_sentinel_before,
                            sdram_wdata,
                            sdram_wstrb
                        );

                    illegal_writes <=
                        illegal_writes + 1;

                end else if (
                    sdram_addr == FB_SENTINEL_AFTER_ADDR
                ) begin
                    fb_sentinel_after <=
                        apply_wstrb(
                            fb_sentinel_after,
                            sdram_wdata,
                            sdram_wstrb
                        );

                    illegal_writes <=
                        illegal_writes + 1;

                end else if (
                    sdram_addr == DEPTH_SENTINEL_BEFORE_ADDR
                ) begin
                    depth_sentinel_before <=
                        apply_wstrb(
                            depth_sentinel_before,
                            sdram_wdata,
                            sdram_wstrb
                        );

                    illegal_writes <=
                        illegal_writes + 1;

                end else if (
                    sdram_addr == DEPTH_SENTINEL_AFTER_ADDR
                ) begin
                    depth_sentinel_after <=
                        apply_wstrb(
                            depth_sentinel_after,
                            sdram_wdata,
                            sdram_wstrb
                        );

                    illegal_writes <=
                        illegal_writes + 1;

                end else if (
                    sdram_addr == UNRELATED_ADDR
                ) begin
                    unrelated_word <=
                        apply_wstrb(
                            unrelated_word,
                            sdram_wdata,
                            sdram_wstrb
                        );

                    illegal_writes <=
                        illegal_writes + 1;

                end else begin
                    illegal_writes <=
                        illegal_writes + 1;
                end
            end
        end
    end

    initial begin

        reset_surfaces();
        reset_sentinels();

        repeat (2)
            @(posedge clk);

        #1;

        check(
            !dut.busy &&
            !dut.done &&
            !sdram_valid,
            "reset leaves stateful depth renderer idle"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_write(
            REG_VERTEX_BASE,
            VERTEX_BASE
        );

        mmio_write(
            REG_FRAMEBUFFER_BASE,
            FRAMEBUFFER_BASE
        );

        mmio_write(
            REG_DEPTH_BASE,
            DEPTH_BASE
        );

        mmio_write(
            REG_TARGET_SIZE,
            32'h00040004
        );

        mmio_write(
            REG_MODE,
            32'h00000002
        );

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000010
        );

        // ====================================================
        // Scenario A:
        // FAR first, then NEAR.
        // Both commands initially pass, and NEAR replaces FAR.
        // ====================================================

        $display("");
        $display("=== OVERLAP SCENARIO A: FAR THEN NEAR ===");

        run_triangle(
            FAR_Z,
            FAR_COLOR,
            6,
            6
        );

        check_surface(
            FAR_COLOR,
            FAR_Z,
            "far-first covered pixels contain far result"
        );

        check_sentinels();

        run_triangle(
            NEAR_Z,
            NEAR_COLOR,
            6,
            6
        );

        check_surface(
            NEAR_COLOR,
            NEAR_Z,
            "near-second covered pixels replace farther result"
        );

        check_sentinels();

        // ====================================================
        // Scenario B:
        // NEAR first, then FAR.
        // FAR must fail strict LESS at every covered sample.
        // ====================================================

        $display("");
        $display("=== OVERLAP SCENARIO B: NEAR THEN FAR ===");

        reset_surfaces();

        run_triangle(
            NEAR_Z,
            NEAR_COLOR,
            6,
            6
        );

        check_surface(
            NEAR_COLOR,
            NEAR_Z,
            "near-first covered pixels contain near result"
        );

        check_sentinels();

        run_triangle(
            FAR_Z,
            FAR_COLOR,
            0,
            0
        );

        check_surface(
            NEAR_COLOR,
            NEAR_Z,
            "far-second triangle cannot overwrite nearer result"
        );

        check_sentinels();

        // ====================================================
        // Aggregate transaction/memory-safety references
        // ====================================================

        check(
            vertex_reads == 72,
            "four commands perform exactly seventy-two vertex reads"
        );

        check(
            depth_reads == 24,
            "four commands perform exactly twenty-four depth reads"
        );

        check(
            depth_writes == 18,
            "three passing draws perform exactly eighteen depth writes"
        );

        check(
            framebuffer_writes == 18,
            "three passing draws perform exactly eighteen framebuffer writes"
        );

        check(
            framebuffer_reads == 0,
            "depth-only unblended rendering never reads framebuffer"
        );

        check(
            illegal_reads == 0,
            "renderer performs no reads outside vertex/depth resources"
        );

        check(
            illegal_writes == 0,
            "renderer performs no writes outside framebuffer/depth resources"
        );

        check_sentinels();

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("OVERLAP_DRAW_ORDERS: 2");
            $display("OVERLAP_NEAR_WINS: 2");
            $display("OVERLAP_VERTEX_READS: %0d", vertex_reads);
            $display("OVERLAP_DEPTH_READS: %0d", depth_reads);
            $display("OVERLAP_DEPTH_WRITES: %0d", depth_writes);
            $display(
                "OVERLAP_FRAMEBUFFER_WRITES: %0d",
                framebuffer_writes
            );
            $display("OVERLAP_ILLEGAL_READS: %0d", illegal_reads);
            $display("OVERLAP_ILLEGAL_WRITES: %0d", illegal_writes);
            $display("OVERLAP_SENTINELS_INTACT: 5");
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
