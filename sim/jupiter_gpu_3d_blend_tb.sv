`timescale 1ns/1ps

module jupiter_gpu_3d_blend_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;

    localparam [31:0] VERTEX_BASE      = 32'h10000000;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h10010000;

    localparam [2:0] FRAGMENT_FRAMEBUFFER      = 3'd3;
    localparam [2:0] FRAGMENT_FRAMEBUFFER_READ = 3'd6;

    localparam [15:0] SOURCE_COLOR = 16'h07E0;

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
    integer framebuffer_reads = 0;
    integer framebuffer_writes = 0;
    integer other_reads = 0;
    integer other_writes = 0;

    integer read_stall_cycles = 0;
    integer write_stall_cycles = 0;

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
                    (sdram_addr >= FRAMEBUFFER_BASE) &&
                    (sdram_addr < (FRAMEBUFFER_BASE + 32'd32))
                ) begin
                    framebuffer_reads <=
                        framebuffer_reads + 1;
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
                0:  vertex_word = 32'h00004000;
                1:  vertex_word = 32'h00004000;
                2:  vertex_word = 32'h00004000;
                3:  vertex_word = 32'h00000000;
                4:  vertex_word = 32'h00000000;
                5:  vertex_word = 32'h00010000;

                6:  vertex_word = 32'h00034000;
                7:  vertex_word = 32'h00004000;
                8:  vertex_word = 32'h00004000;
                9:  vertex_word = 32'h00000000;
                10: vertex_word = 32'h00000000;
                11: vertex_word = 32'h00010000;

                12: vertex_word = 32'h00004000;
                13: vertex_word = 32'h00034000;
                14: vertex_word = 32'h00004000;
                15: vertex_word = 32'h00000000;
                16: vertex_word = 32'h00000000;
                17: vertex_word = 32'h00010000;

                default:
                    vertex_word = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [31:0] framebuffer_offset;
        input integer index;

        begin
            case (index)
                0, 1: framebuffer_offset = 32'd0;
                2:    framebuffer_offset = 32'd4;
                3, 4: framebuffer_offset = 32'd8;
                5:    framebuffer_offset = 32'd16;
                default: framebuffer_offset = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [3:0] framebuffer_strobe;
        input integer index;

        begin
            case (index)
                1, 4:
                    framebuffer_strobe = 4'b1100;

                default:
                    framebuffer_strobe = 4'b0011;
            endcase
        end
    endfunction

    function automatic [15:0] expected_blend;
        input integer index;

        begin
            case (index)
                0: expected_blend = 16'h8400;
                1: expected_blend = 16'h0410;
                2: expected_blend = 16'h87F0;
                3: expected_blend = 16'h0400;
                4: expected_blend = 16'h07E0;
                5: expected_blend = 16'h87E0;
                default: expected_blend = 16'hDEAD;
            endcase
        end
    endfunction

    function automatic [31:0] framebuffer_read_word;
        input integer index;

        begin
            case (index)
                0: framebuffer_read_word = 32'hAAAAF800;
                1: framebuffer_read_word = 32'h001FAAAA;
                2: framebuffer_read_word = 32'hAAAAFFFF;
                3: framebuffer_read_word = 32'hAAAA0000;
                4: framebuffer_read_word = 32'h07E0AAAA;
                5: framebuffer_read_word = 32'hAAAAFFE0;
                default: framebuffer_read_word = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [31:0] expected_write_data;
        input integer index;

        reg [15:0] color;

        begin
            color = expected_blend(index);

            if (framebuffer_strobe(index) == 4'b1100)
                expected_write_data =
                    {color, 16'h0000};
            else
                expected_write_data =
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

    task wait_for_framebuffer_read;
        input integer index;

        begin
            watchdog = 0;

            while (
                !(
                    dut.fragment_state ==
                        FRAGMENT_FRAMEBUFFER_READ &&
                    sdram_valid &&
                    !sdram_write
                ) &&
                (watchdog < 32768)
            ) begin
                @(posedge clk);
                #1;
                watchdog = watchdog + 1;
            end

            check(
                watchdog < 32768,
                "fragment reaches framebuffer-read state before watchdog"
            );

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        FRAMEBUFFER_BASE +
                        framebuffer_offset(index)
                    ) &&
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000,
                "blend destination fetch is exact aligned read"
            );

            check(
                !dut.raster_covered_ready,
                "blend destination read keeps fragment held"
            );
        end
    endtask

    task complete_framebuffer_read;
        input integer index;

        begin
            if (index == 0) begin
                repeat (3) begin
                    @(posedge clk);
                    #1;

                    read_stall_cycles =
                        read_stall_cycles + 1;

                    check(
                        dut.fragment_state ==
                            FRAGMENT_FRAMEBUFFER_READ &&
                        sdram_valid &&
                        !sdram_write &&
                        sdram_addr ==
                            FRAMEBUFFER_BASE &&
                        dut.selected_fragment_color ==
                            SOURCE_COLOR,
                        "blend read and source remain stable while stalled"
                    );
                end
            end

            @(negedge clk);

            sdram_rdata =
                framebuffer_read_word(index);

            sdram_ready =
                1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        FRAMEBUFFER_BASE +
                        framebuffer_offset(index)
                    ),
                "blend destination read remains exact through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready =
                1'b0;

            sdram_rdata =
                32'h00000000;

            #1;

            check(
                dut.fragment_output_color ==
                    expected_blend(index),
                "RGB565 blend result matches exact per-channel reference"
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
                        framebuffer_offset(index)
                    ) &&
                sdram_wdata ==
                    expected_write_data(index) &&
                sdram_wstrb ==
                    framebuffer_strobe(index),
                "blended fragment produces exact RGB565 halfword write"
            );

            if (index == 0) begin
                repeat (2) begin
                    @(posedge clk);
                    #1;

                    write_stall_cycles =
                        write_stall_cycles + 1;

                    check(
                        dut.fragment_state ==
                            FRAGMENT_FRAMEBUFFER &&
                        sdram_valid &&
                        sdram_write &&
                        sdram_addr ==
                            FRAMEBUFFER_BASE &&
                        sdram_wdata ==
                            32'h00008400 &&
                        sdram_wstrb ==
                            4'b0011,
                        "blended framebuffer request remains stable while stalled"
                    );
                end
            end

            @(negedge clk);

            sdram_ready = 1'b1;

            #1;

            check(
                dut.raster_covered_ready &&
                sdram_valid &&
                sdram_write,
                "blended framebuffer completion releases fragment"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;

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
            "reset leaves blending renderer idle"
        );

        check(
            dut.blend_rgb565(
                16'h07E0,
                16'hF800,
                5'd0
            ) == 16'hF800,
            "alpha zero returns destination color"
        );

        check(
            dut.blend_rgb565(
                16'h07E0,
                16'hF800,
                5'd16
            ) == 16'h07E0,
            "alpha sixteen returns source color"
        );

        check(
            dut.blend_rgb565(
                16'h07E0,
                16'hF800,
                5'd8
            ) == 16'h8400,
            "alpha eight uses documented rounded half blend"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_write(REG_VERTEX_BASE, VERTEX_BASE);
        mmio_write(REG_FRAMEBUFFER_BASE, FRAMEBUFFER_BASE);
        mmio_write(REG_TARGET_SIZE, 32'h00040004);

        #1;

        mmio_write(REG_MODE, 32'h00000004);
        mmio_write(REG_BLEND_ALPHA, 32'h00000008);
        mmio_write(REG_FLAT_COLOR, {16'h0000, SOURCE_COLOR});
        mmio_write(REG_CONTROL, 32'h00000001);

        check(
            dut.busy &&
            dut.active_mode == 32'h00000004 &&
            dut.active_blend_alpha == 32'd8 &&
            dut.active_flat_color[15:0] ==
                SOURCE_COLOR,
            "START snapshots flat blending configuration"
        );

        for (i = 0; i < 18; i = i + 1)
            complete_vertex_word(i);

        for (i = 0; i < 6; i = i + 1) begin
            wait_for_framebuffer_read(i);
            complete_framebuffer_read(i);
            complete_framebuffer_write(i);
        end

        watchdog = 0;

        while (!dut.done && (watchdog < 32768)) begin
            @(posedge clk);
            #1;
            watchdog = watchdog + 1;
        end

        check(
            watchdog < 32768 &&
            dut.done &&
            !dut.busy &&
            !dut.error,
            "blend-only command completes normally"
        );

        check(
            vertex_reads == 18,
            "blend command performs exactly eighteen vertex reads"
        );

        check(
            framebuffer_reads == 6,
            "blend command reads destination framebuffer once per fragment"
        );

        check(
            framebuffer_writes == 6,
            "blend command writes framebuffer once per fragment"
        );

        check(
            other_reads == 0,
            "blend-only command performs no texture/depth/unrelated reads"
        );

        check(
            other_writes == 0,
            "blend-only command writes only selected framebuffer"
        );

        check(
            dut.raster_coverage_count == 32'd6 &&
            dut.raster_sample_count == 32'd16,
            "blending preserves deterministic raster coverage"
        );

        check(
            read_stall_cycles == 3,
            "first framebuffer blend read survived three stall cycles"
        );

        check(
            write_stall_cycles == 2,
            "first blended framebuffer write survived two stall cycles"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "completed blend command returns SDRAM interface idle"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("BLEND_VERTEX_READS: %0d", vertex_reads);
            $display(
                "BLEND_FRAMEBUFFER_READS: %0d",
                framebuffer_reads
            );
            $display(
                "BLEND_FRAMEBUFFER_WRITES: %0d",
                framebuffer_writes
            );
            $display("BLEND_ALPHA: 8");
            $display("BLEND_REFERENCE_0: 0x8400");
            $display("BLEND_REFERENCE_1: 0x0410");
            $display("BLEND_REFERENCE_2: 0x87f0");
            $display("BLEND_REFERENCE_3: 0x0400");
            $display("BLEND_REFERENCE_4: 0x07e0");
            $display("BLEND_REFERENCE_5: 0x87e0");
            $display("BLEND_STALLED_READ_CYCLES: 3");
            $display("BLEND_STALLED_WRITE_CYCLES: 2");
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
