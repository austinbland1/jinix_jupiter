`timescale 1ns/1ps

module jupiter_gpu_3d_texture_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_TEXTURE_BASE     = 32'h0000114C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_TEXTURE_SIZE     = 32'h0000115C;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;

    localparam [31:0] VERTEX_BASE      = 32'h10000000;
    localparam [31:0] TEXTURE_BASE     = 32'h10010000;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h10020000;

    localparam [2:0] FRAGMENT_FRAMEBUFFER  = 3'd3;
    localparam [2:0] FRAGMENT_TEXTURE_READ = 3'd5;

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
    integer watchdog = 0;
    integer i;

    integer vertex_reads = 0;
    integer texture_reads = 0;
    integer framebuffer_writes = 0;
    integer other_reads = 0;
    integer other_writes = 0;

    integer texture_stall_cycles = 0;
    integer framebuffer_stall_cycles = 0;

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
        if (sdram_valid && sdram_ready) begin
            if (!sdram_write) begin
                if (
                    (sdram_addr >= VERTEX_BASE) &&
                    (sdram_addr < (VERTEX_BASE + 32'd72))
                ) begin
                    vertex_reads <= vertex_reads + 1;
                end else if (
                    (sdram_addr >= TEXTURE_BASE) &&
                    (sdram_addr < (TEXTURE_BASE + 32'd32))
                ) begin
                    texture_reads <= texture_reads + 1;
                end else begin
                    other_reads <= other_reads + 1;
                end
            end else begin
                if (
                    (sdram_addr >= FRAMEBUFFER_BASE) &&
                    (sdram_addr < (FRAMEBUFFER_BASE + 32'd32))
                ) begin
                    framebuffer_writes <=
                        framebuffer_writes + 1;
                end else begin
                    other_writes <= other_writes + 1;
                end
            end
        end
    end

    function automatic [31:0] vertex_word;
        input integer index;

        begin
            case (index)
                // v0 = (0.25, 0.25), Z=0x4000
                // U=0, V=0, W=1
                0:  vertex_word = 32'h00004000;
                1:  vertex_word = 32'h00004000;
                2:  vertex_word = 32'h00004000;
                3:  vertex_word = 32'h00000000;
                4:  vertex_word = 32'h00000000;
                5:  vertex_word = 32'h00010000;

                // v1 = (3.25, 0.25), Z=0x4000
                // U=3, V=0, W=2
                6:  vertex_word = 32'h00034000;
                7:  vertex_word = 32'h00004000;
                8:  vertex_word = 32'h00004000;
                9:  vertex_word = 32'h00018000;
                10: vertex_word = 32'h00000000;
                11: vertex_word = 32'h00008000;

                // v2 = (0.25, 3.25), Z=0x4000
                // U=0, V=3, W=4
                12: vertex_word = 32'h00004000;
                13: vertex_word = 32'h00034000;
                14: vertex_word = 32'h00004000;
                15: vertex_word = 32'h00000000;
                16: vertex_word = 32'h0000C000;
                17: vertex_word = 32'h00004000;

                default:
                    vertex_word = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [15:0] expected_x;
        input integer index;

        begin
            case (index)
                0: expected_x = 16'd0;
                1: expected_x = 16'd1;
                2: expected_x = 16'd2;
                3: expected_x = 16'd0;
                4: expected_x = 16'd1;
                5: expected_x = 16'd0;
                default: expected_x = 16'hFFFF;
            endcase
        end
    endfunction

    function automatic [15:0] expected_y;
        input integer index;

        begin
            case (index)
                0, 1, 2: expected_y = 16'd0;
                3, 4:    expected_y = 16'd1;
                5:       expected_y = 16'd2;
                default: expected_y = 16'hFFFF;
            endcase
        end
    endfunction

    function automatic [15:0] expected_texel_x;
        input integer index;

        begin
            case (index)
                0: expected_texel_x = 16'd0;
                1: expected_texel_x = 16'd0;
                2: expected_texel_x = 16'd2;
                3: expected_texel_x = 16'd0;
                4: expected_texel_x = 16'd1;
                5: expected_texel_x = 16'd0;
                default: expected_texel_x = 16'hFFFF;
            endcase
        end
    endfunction

    function automatic [15:0] expected_texel_y;
        input integer index;

        begin
            case (index)
                0, 1, 2, 3, 4:
                    expected_texel_y = 16'd0;

                5:
                    expected_texel_y = 16'd1;

                default:
                    expected_texel_y = 16'hFFFF;
            endcase
        end
    endfunction

    function automatic [31:0] expected_texture_offset;
        input integer index;

        begin
            case (index)
                0, 1, 3, 4:
                    expected_texture_offset = 32'd0;

                2:
                    expected_texture_offset = 32'd4;

                5:
                    expected_texture_offset = 32'd8;

                default:
                    expected_texture_offset = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [31:0] texture_word;
        input integer index;

        begin
            case (index)
                0, 1, 3, 4:
                    // texel 0 = 0x1111
                    // texel 1 = 0x2222
                    texture_word = 32'h22221111;

                2:
                    // texel 2 = 0x3333
                    // texel 3 = 0x4444
                    texture_word = 32'h44443333;

                5:
                    // texel 4 = 0x5555
                    // texel 5 = 0x6666
                    texture_word = 32'h66665555;

                default:
                    texture_word = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [15:0] expected_source_color;
        input integer index;

        begin
            case (index)
                0, 1, 3:
                    expected_source_color = 16'h1111;

                2:
                    expected_source_color = 16'h3333;

                4:
                    expected_source_color = 16'h2222;

                5:
                    expected_source_color = 16'h5555;

                default:
                    expected_source_color = 16'hDEAD;
            endcase
        end
    endfunction

    function automatic [31:0] expected_framebuffer_offset;
        input integer index;

        begin
            case (index)
                0, 1:
                    expected_framebuffer_offset = 32'd0;

                2:
                    expected_framebuffer_offset = 32'd4;

                3, 4:
                    expected_framebuffer_offset = 32'd8;

                5:
                    expected_framebuffer_offset = 32'd16;

                default:
                    expected_framebuffer_offset = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [3:0] expected_framebuffer_wstrb;
        input integer index;

        begin
            case (index)
                1, 4:
                    expected_framebuffer_wstrb = 4'b1100;

                default:
                    expected_framebuffer_wstrb = 4'b0011;
            endcase
        end
    endfunction

    function automatic [31:0] expected_framebuffer_data;
        input integer index;

        reg [15:0] color;

        begin
            color = expected_source_color(index);

            if (
                expected_framebuffer_wstrb(index) ==
                4'b1100
            )
                expected_framebuffer_data =
                    {color, 16'h0000};
            else
                expected_framebuffer_data =
                    {16'h0000, color};
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

    task complete_vertex_word;
        input integer index;

        begin
            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        VERTEX_BASE +
                        (index * 4)
                    ),
                "expected vertex read is presented"
            );

            @(negedge clk);

            sdram_rdata = vertex_word(index);
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        VERTEX_BASE +
                        (index * 4)
                    ),
                "vertex read remains stable through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;
        end
    endtask

    task wait_for_texture_read;
        input integer index;

        begin
            watchdog = 0;

            while (
                !(
                    sdram_valid &&
                    !sdram_write &&
                    (
                        dut.fragment_state ==
                        FRAGMENT_TEXTURE_READ
                    )
                ) &&
                (watchdog < 120)
            ) begin
                @(posedge clk);
                #1;
                watchdog = watchdog + 1;
            end

            check(
                watchdog < 120,
                "fragment reaches texture-read state before watchdog"
            );

            check(
                dut.raster_covered_valid &&
                dut.raster_covered_x ==
                    expected_x(index) &&
                dut.raster_covered_y ==
                    expected_y(index),
                "held textured fragment X/Y matches raster reference"
            );

            check(
                dut.texture_u_clamped ==
                    expected_texel_x(index) &&
                dut.texture_v_clamped ==
                    expected_texel_y(index),
                "perspective reconstructed coordinates select expected texel"
            );

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        TEXTURE_BASE +
                        expected_texture_offset(index)
                    ) &&
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000,
                "texture fetch is exact aligned read-only transaction"
            );
        end
    endtask

    task complete_texture_read;
        input integer index;

        begin
            if (index == 0) begin
                repeat (3) begin
                    @(posedge clk);
                    #1;

                    texture_stall_cycles =
                        texture_stall_cycles + 1;

                    check(
                        sdram_valid &&
                        !sdram_write &&
                        sdram_addr == TEXTURE_BASE &&
                        dut.raster_covered_x == 16'd0 &&
                        dut.raster_covered_y == 16'd0 &&
                        dut.texture_u_clamped == 16'd0 &&
                        dut.texture_v_clamped == 16'd0,
                        "texture request and fragment remain stable while stalled"
                    );
                end
            end

            @(negedge clk);

            sdram_rdata =
                texture_word(index);

            sdram_ready =
                1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        TEXTURE_BASE +
                        expected_texture_offset(index)
                    ),
                "texture request remains exact through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready =
                1'b0;

            sdram_rdata =
                32'h00000000;

            #1;

            check(
                dut.fragment_source_color ==
                    expected_source_color(index),
                "selected RGB565 texture halfword is latched as source color"
            );
        end
    endtask

    task complete_framebuffer_write;
        input integer index;

        begin
            check(
                dut.fragment_state ==
                    FRAGMENT_FRAMEBUFFER &&
                sdram_valid &&
                sdram_write &&
                sdram_addr ==
                    (
                        FRAMEBUFFER_BASE +
                        expected_framebuffer_offset(index)
                    ) &&
                sdram_wdata ==
                    expected_framebuffer_data(index) &&
                sdram_wstrb ==
                    expected_framebuffer_wstrb(index),
                "textured fragment produces exact RGB565 framebuffer write"
            );

            check(
                !dut.raster_covered_ready,
                "textured fragment remains held before framebuffer completion"
            );

            if (index == 0) begin
                repeat (2) begin
                    @(posedge clk);
                    #1;

                    framebuffer_stall_cycles =
                        framebuffer_stall_cycles + 1;

                    check(
                        dut.fragment_state ==
                            FRAGMENT_FRAMEBUFFER &&
                        sdram_valid &&
                        sdram_write &&
                        sdram_addr ==
                            FRAMEBUFFER_BASE &&
                        sdram_wdata ==
                            32'h00001111 &&
                        sdram_wstrb ==
                            4'b0011 &&
                        dut.fragment_source_color ==
                            16'h1111,
                        "latched textured framebuffer request remains stable while stalled"
                    );
                end
            end

            @(negedge clk);

            sdram_ready =
                1'b1;

            #1;

            check(
                dut.raster_covered_ready &&
                sdram_valid &&
                sdram_write,
                "framebuffer completion releases textured fragment"
            );

            @(posedge clk);
            #1;

            sdram_ready =
                1'b0;

            #1;
        end
    endtask

    initial begin

        repeat (2)
            @(posedge clk);

        #1;

        check(
            !dut.busy &&
            !sdram_valid,
            "reset leaves textured renderer idle"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_write(
            REG_VERTEX_BASE,
            VERTEX_BASE
        );

        mmio_write(
            REG_TEXTURE_BASE,
            TEXTURE_BASE
        );

        mmio_write(
            REG_FRAMEBUFFER_BASE,
            FRAMEBUFFER_BASE
        );

        mmio_write(
            REG_TARGET_SIZE,
            32'h00040004
        );

        mmio_write(
            REG_TEXTURE_SIZE,
            32'h00040004
        );

        // Texture enabled. Depth and blending disabled.
        mmio_write(
            REG_MODE,
            32'h00000001
        );

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000010
        );

        // Distinct value proving texture data, not FLAT_COLOR,
        // becomes the fragment source.
        mmio_write(
            REG_FLAT_COLOR,
            32'h0000F81F
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001
        );

        check(
            dut.busy &&
            dut.active_mode == 32'h00000001 &&
            dut.active_texture_base ==
                TEXTURE_BASE &&
            dut.active_texture_size ==
                32'h00040004 &&
            dut.active_flat_color ==
                32'h0000F81F,
            "START snapshots textured command configuration"
        );

        for (i = 0; i < 18; i = i + 1)
            complete_vertex_word(i);

        for (i = 0; i < 6; i = i + 1) begin
            wait_for_texture_read(i);
            complete_texture_read(i);
            complete_framebuffer_write(i);
        end

        watchdog = 0;

        while (!dut.done && (watchdog < 100)) begin
            @(posedge clk);
            #1;
            watchdog = watchdog + 1;
        end

        check(
            watchdog < 100 &&
            dut.done &&
            !dut.busy &&
            !dut.error,
            "texture-only command completes normally"
        );

        check(
            vertex_reads == 18,
            "texture command performs exactly eighteen vertex reads"
        );

        check(
            texture_reads == 6,
            "texture command performs one texture read per covered fragment"
        );

        check(
            framebuffer_writes == 6,
            "texture command performs one framebuffer write per covered fragment"
        );

        check(
            other_reads == 0,
            "texture-only command performs no depth or unrelated reads"
        );

        check(
            other_writes == 0,
            "texture-only command writes only the selected framebuffer"
        );

        check(
            dut.raster_coverage_count == 32'd6 &&
            dut.raster_sample_count == 32'd16,
            "texturing preserves deterministic raster coverage"
        );

        check(
            texture_stall_cycles == 3,
            "first texture read survived three stall cycles"
        );

        check(
            framebuffer_stall_cycles == 2,
            "first textured framebuffer write survived two stall cycles"
        );

        // Perspective selection differs from affine coordinates for
        // multiple covered samples. For pixel (1,0), affine U would
        // select texel X=1, while the perspective result selects X=0.
        check(
            expected_texel_x(1) == 16'd0,
            "reference texture lookup is perspective-correct rather than affine"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "completed texture command returns SDRAM interface idle"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("TEXTURE_VERTEX_READS: %0d", vertex_reads);
            $display("TEXTURE_SAMPLE_READS: %0d", texture_reads);
            $display(
                "TEXTURE_FRAMEBUFFER_WRITES: %0d",
                framebuffer_writes
            );
            $display("TEXTURE_PERSPECTIVE_TEXEL_0: (0,0)");
            $display("TEXTURE_PERSPECTIVE_TEXEL_1: (0,0)");
            $display("TEXTURE_PERSPECTIVE_TEXEL_2: (2,0)");
            $display("TEXTURE_PERSPECTIVE_TEXEL_3: (0,0)");
            $display("TEXTURE_PERSPECTIVE_TEXEL_4: (1,0)");
            $display("TEXTURE_PERSPECTIVE_TEXEL_5: (0,1)");
            $display("TEXTURE_STALLED_READ_CYCLES: 3");
            $display("TEXTURE_STALLED_WRITE_CYCLES: 2");
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
