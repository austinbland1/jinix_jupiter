`timescale 1ns/1ps

module jupiter_gpu_3d_texture_blend_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_TEXTURE_BASE     = 32'h0000114C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_DEPTH_BASE       = 32'h00001154;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_TEXTURE_SIZE     = 32'h0000115C;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;

    localparam [31:0] VERTEX_BASE      = 32'h10000040;
    localparam [31:0] TEXTURE_BASE     = 32'h10001040;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h10002040;
    localparam [31:0] DEPTH_BASE       = 32'h10003040;

    localparam [31:0] VERTEX_LEAD      = VERTEX_BASE - 32'd4;
    localparam [31:0] VERTEX_TRAIL     = VERTEX_BASE + 32'd72;

    localparam [31:0] TEXTURE_LEAD     = TEXTURE_BASE - 32'd4;
    localparam [31:0] TEXTURE_TRAIL    = TEXTURE_BASE + 32'd32;

    localparam [31:0] FRAMEBUFFER_LEAD =
        FRAMEBUFFER_BASE - 32'd4;

    localparam [31:0] FRAMEBUFFER_TRAIL =
        FRAMEBUFFER_BASE + 32'd32;

    localparam [31:0] DEPTH_LEAD =
        DEPTH_BASE - 32'd4;

    localparam [31:0] DEPTH_TRAIL =
        DEPTH_BASE + 32'd32;

    localparam [31:0] UNRELATED_ADDR =
        32'h10004040;

    localparam [2:0] FRAGMENT_DEPTH_READ       = 3'd1;
    localparam [2:0] FRAGMENT_DEPTH_WRITE      = 3'd2;
    localparam [2:0] FRAGMENT_FRAMEBUFFER      = 3'd3;
    localparam [2:0] FRAGMENT_REJECT           = 3'd4;
    localparam [2:0] FRAGMENT_TEXTURE_READ     = 3'd5;
    localparam [2:0] FRAGMENT_FRAMEBUFFER_READ = 3'd6;

    localparam integer TXN_DEPTH_READ       = 1;
    localparam integer TXN_DEPTH_WRITE      = 2;
    localparam integer TXN_TEXTURE_READ     = 3;
    localparam integer TXN_FRAMEBUFFER_READ = 4;
    localparam integer TXN_FRAMEBUFFER_WRITE = 5;

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

    reg [15:0] texture_mem [0:15];
    reg [15:0] texture_initial [0:15];

    reg [15:0] framebuffer_mem [0:15];
    reg [15:0] framebuffer_initial [0:15];

    reg [15:0] depth_mem [0:15];
    reg [15:0] depth_initial [0:15];

    reg [31:0] vertex_lead_sentinel =
        32'h11112222;

    reg [31:0] vertex_trail_sentinel =
        32'h33334444;

    reg [31:0] texture_lead_sentinel =
        32'h55556666;

    reg [31:0] texture_trail_sentinel =
        32'h77778888;

    reg [31:0] framebuffer_lead_sentinel =
        32'h9999AAAA;

    reg [31:0] framebuffer_trail_sentinel =
        32'hBBBBCCCC;

    reg [31:0] depth_lead_sentinel =
        32'hDDDDEEEE;

    reg [31:0] depth_trail_sentinel =
        32'h13572468;

    reg [31:0] unrelated_sentinel =
        32'h89ABCDEF;

    integer checks = 0;
    integer failures = 0;
    integer watchdog = 0;
    integer i;

    integer service_delay = 0;

    integer vertex_reads = 0;
    integer depth_reads = 0;
    integer depth_writes = 0;
    integer texture_reads = 0;
    integer framebuffer_reads = 0;
    integer framebuffer_writes = 0;

    integer texture_word0_reads = 0;
    integer texture_word1_reads = 0;

    integer consumed_fragments = 0;
    integer rejected_fragments = 0;

    integer illegal_accesses = 0;
    integer sentinel_accesses = 0;
    integer bad_transaction_shapes = 0;
    integer sequence_errors = 0;

    integer graphics_transaction_index = 0;
    integer observed_code = 0;
    integer memory_index = 0;

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

    function automatic [31:0] vertex_word;
        input integer index;

        begin
            case (index)
                // v0 = (0.25,0.25), Z=0x4000
                // U=0, V=0, W=1.
                0:  vertex_word = 32'h00004000;
                1:  vertex_word = 32'h00004000;
                2:  vertex_word = 32'h00004000;
                3:  vertex_word = 32'h00000000;
                4:  vertex_word = 32'h00000000;
                5:  vertex_word = 32'h00010000;

                // v1 = (3.25,0.25), Z=0x4000
                // U=3, V=0, W=2.
                6:  vertex_word = 32'h00034000;
                7:  vertex_word = 32'h00004000;
                8:  vertex_word = 32'h00004000;
                9:  vertex_word = 32'h00018000;
                10: vertex_word = 32'h00000000;
                11: vertex_word = 32'h00008000;

                // v2 = (0.25,3.25), Z=0x4000
                // U=0, V=3, W=4.
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

    function automatic integer expected_graphics_code;
        input integer index;

        begin
            case (index)
                // Fragment 0: pass.
                0:  expected_graphics_code = TXN_DEPTH_READ;
                1:  expected_graphics_code = TXN_DEPTH_WRITE;
                2:  expected_graphics_code = TXN_TEXTURE_READ;
                3:  expected_graphics_code = TXN_FRAMEBUFFER_READ;
                4:  expected_graphics_code = TXN_FRAMEBUFFER_WRITE;

                // Fragment 1: equal-depth reject.
                5:  expected_graphics_code = TXN_DEPTH_READ;

                // Fragment 2: pass.
                6:  expected_graphics_code = TXN_DEPTH_READ;
                7:  expected_graphics_code = TXN_DEPTH_WRITE;
                8:  expected_graphics_code = TXN_TEXTURE_READ;
                9:  expected_graphics_code = TXN_FRAMEBUFFER_READ;
                10: expected_graphics_code = TXN_FRAMEBUFFER_WRITE;

                // Fragment 3: farther-depth reject.
                11: expected_graphics_code = TXN_DEPTH_READ;

                // Fragment 4: pass.
                12: expected_graphics_code = TXN_DEPTH_READ;
                13: expected_graphics_code = TXN_DEPTH_WRITE;
                14: expected_graphics_code = TXN_TEXTURE_READ;
                15: expected_graphics_code = TXN_FRAMEBUFFER_READ;
                16: expected_graphics_code = TXN_FRAMEBUFFER_WRITE;

                // Fragment 5: farther-depth reject.
                17: expected_graphics_code = TXN_DEPTH_READ;

                default:
                    expected_graphics_code = -1;
            endcase
        end
    endfunction

    function automatic [31:0] memory_read_word;
        input [31:0] address;

        integer index;

        begin
            memory_read_word = 32'hDEADBEEF;
            index = 0;

            if (
                (address >= VERTEX_BASE) &&
                (address < (VERTEX_BASE + 32'd72))
            ) begin
                index =
                    (address - VERTEX_BASE) >> 2;

                memory_read_word =
                    vertex_word(index);
            end else if (
                (address >= TEXTURE_BASE) &&
                (address < (TEXTURE_BASE + 32'd32))
            ) begin
                index =
                    (address - TEXTURE_BASE) >> 1;

                memory_read_word =
                {
                    texture_mem[index + 1],
                    texture_mem[index]
                };
            end else if (
                (address >= FRAMEBUFFER_BASE) &&
                (address < (FRAMEBUFFER_BASE + 32'd32))
            ) begin
                index =
                    (address - FRAMEBUFFER_BASE) >> 1;

                memory_read_word =
                {
                    framebuffer_mem[index + 1],
                    framebuffer_mem[index]
                };
            end else if (
                (address >= DEPTH_BASE) &&
                (address < (DEPTH_BASE + 32'd32))
            ) begin
                index =
                    (address - DEPTH_BASE) >> 1;

                memory_read_word =
                {
                    depth_mem[index + 1],
                    depth_mem[index]
                };
            end else begin
                case (address)
                    VERTEX_LEAD:
                        memory_read_word =
                            vertex_lead_sentinel;

                    VERTEX_TRAIL:
                        memory_read_word =
                            vertex_trail_sentinel;

                    TEXTURE_LEAD:
                        memory_read_word =
                            texture_lead_sentinel;

                    TEXTURE_TRAIL:
                        memory_read_word =
                            texture_trail_sentinel;

                    FRAMEBUFFER_LEAD:
                        memory_read_word =
                            framebuffer_lead_sentinel;

                    FRAMEBUFFER_TRAIL:
                        memory_read_word =
                            framebuffer_trail_sentinel;

                    DEPTH_LEAD:
                        memory_read_word =
                            depth_lead_sentinel;

                    DEPTH_TRAIL:
                        memory_read_word =
                            depth_trail_sentinel;

                    UNRELATED_ADDR:
                        memory_read_word =
                            unrelated_sentinel;

                    default:
                        memory_read_word =
                            32'hDEADBEEF;
                endcase
            end
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

    // --------------------------------------------------------
    // Deterministic stateful SDRAM model.
    //
    // Every request is held for two clocks before READY, which
    // exercises the composed pipeline under backpressure.
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (reset) begin
            sdram_ready <= 1'b0;
            sdram_rdata <= 32'h00000000;
            service_delay = 0;

            vertex_reads = 0;
            depth_reads = 0;
            depth_writes = 0;
            texture_reads = 0;
            framebuffer_reads = 0;
            framebuffer_writes = 0;

            texture_word0_reads = 0;
            texture_word1_reads = 0;

            consumed_fragments = 0;
            rejected_fragments = 0;

            illegal_accesses = 0;
            sentinel_accesses = 0;
            bad_transaction_shapes = 0;
            sequence_errors = 0;

            graphics_transaction_index = 0;
        end else begin

            if (
                dut.raster_covered_valid &&
                dut.raster_covered_ready
            ) begin
                consumed_fragments =
                    consumed_fragments + 1;

                if (
                    dut.fragment_state ==
                    FRAGMENT_REJECT
                ) begin
                    rejected_fragments =
                        rejected_fragments + 1;
                end
            end

            if (sdram_valid && sdram_ready) begin

                observed_code = 0;

                // --------------------------------------------
                // Vertex reads
                // --------------------------------------------

                if (
                    (sdram_addr >= VERTEX_BASE) &&
                    (sdram_addr <
                        (VERTEX_BASE + 32'd72))
                ) begin
                    if (
                        !sdram_write &&
                        sdram_wstrb == 4'b0000 &&
                        sdram_addr[1:0] == 2'b00
                    ) begin
                        vertex_reads =
                            vertex_reads + 1;
                    end else begin
                        bad_transaction_shapes =
                            bad_transaction_shapes + 1;
                    end

                // --------------------------------------------
                // Depth
                // --------------------------------------------

                end else if (
                    (sdram_addr >= DEPTH_BASE) &&
                    (sdram_addr <
                        (DEPTH_BASE + 32'd32))
                ) begin

                    if (!sdram_write) begin

                        observed_code =
                            TXN_DEPTH_READ;

                        depth_reads =
                            depth_reads + 1;

                        if (
                            dut.fragment_state !=
                            FRAGMENT_DEPTH_READ ||
                            sdram_wstrb != 4'b0000 ||
                            sdram_addr[1:0] != 2'b00
                        ) begin
                            bad_transaction_shapes =
                                bad_transaction_shapes + 1;
                        end

                    end else begin

                        observed_code =
                            TXN_DEPTH_WRITE;

                        depth_writes =
                            depth_writes + 1;

                        if (
                            dut.fragment_state !=
                            FRAGMENT_DEPTH_WRITE ||
                            sdram_addr[1:0] != 2'b00 ||
                            !(
                                sdram_wstrb == 4'b0011 ||
                                sdram_wstrb == 4'b1100
                            )
                        ) begin
                            bad_transaction_shapes =
                                bad_transaction_shapes + 1;
                        end

                        memory_index =
                            (sdram_addr - DEPTH_BASE) >> 1;

                        if (sdram_wstrb == 4'b0011)
                            depth_mem[memory_index] =
                                sdram_wdata[15:0];

                        if (sdram_wstrb == 4'b1100)
                            depth_mem[memory_index + 1] =
                                sdram_wdata[31:16];
                    end

                // --------------------------------------------
                // Texture: read-only
                // --------------------------------------------

                end else if (
                    (sdram_addr >= TEXTURE_BASE) &&
                    (sdram_addr <
                        (TEXTURE_BASE + 32'd32))
                ) begin

                    observed_code =
                        TXN_TEXTURE_READ;

                    texture_reads =
                        texture_reads + 1;

                    if (
                        sdram_write ||
                        dut.fragment_state !=
                            FRAGMENT_TEXTURE_READ ||
                        sdram_wstrb != 4'b0000 ||
                        sdram_addr[1:0] != 2'b00
                    ) begin
                        bad_transaction_shapes =
                            bad_transaction_shapes + 1;
                    end

                    if (sdram_addr == TEXTURE_BASE)
                        texture_word0_reads =
                            texture_word0_reads + 1;

                    if (
                        sdram_addr ==
                        (TEXTURE_BASE + 32'd4)
                    )
                        texture_word1_reads =
                            texture_word1_reads + 1;

                // --------------------------------------------
                // Framebuffer read / write
                // --------------------------------------------

                end else if (
                    (sdram_addr >= FRAMEBUFFER_BASE) &&
                    (sdram_addr <
                        (FRAMEBUFFER_BASE + 32'd32))
                ) begin

                    if (!sdram_write) begin

                        observed_code =
                            TXN_FRAMEBUFFER_READ;

                        framebuffer_reads =
                            framebuffer_reads + 1;

                        if (
                            dut.fragment_state !=
                                FRAGMENT_FRAMEBUFFER_READ ||
                            sdram_wstrb != 4'b0000 ||
                            sdram_addr[1:0] != 2'b00
                        ) begin
                            bad_transaction_shapes =
                                bad_transaction_shapes + 1;
                        end

                    end else begin

                        observed_code =
                            TXN_FRAMEBUFFER_WRITE;

                        framebuffer_writes =
                            framebuffer_writes + 1;

                        if (
                            dut.fragment_state !=
                                FRAGMENT_FRAMEBUFFER ||
                            sdram_addr[1:0] != 2'b00 ||
                            !(
                                sdram_wstrb == 4'b0011 ||
                                sdram_wstrb == 4'b1100
                            )
                        ) begin
                            bad_transaction_shapes =
                                bad_transaction_shapes + 1;
                        end

                        memory_index =
                            (
                                sdram_addr -
                                FRAMEBUFFER_BASE
                            ) >> 1;

                        if (sdram_wstrb == 4'b0011)
                            framebuffer_mem[memory_index] =
                                sdram_wdata[15:0];

                        if (sdram_wstrb == 4'b1100)
                            framebuffer_mem[memory_index + 1] =
                                sdram_wdata[31:16];
                    end

                // --------------------------------------------
                // Boundary/unrelated sentinels
                // --------------------------------------------

                end else if (
                    sdram_addr == VERTEX_LEAD ||
                    sdram_addr == VERTEX_TRAIL ||
                    sdram_addr == TEXTURE_LEAD ||
                    sdram_addr == TEXTURE_TRAIL ||
                    sdram_addr == FRAMEBUFFER_LEAD ||
                    sdram_addr == FRAMEBUFFER_TRAIL ||
                    sdram_addr == DEPTH_LEAD ||
                    sdram_addr == DEPTH_TRAIL ||
                    sdram_addr == UNRELATED_ADDR
                ) begin

                    sentinel_accesses =
                        sentinel_accesses + 1;

                    if (sdram_write) begin
                        case (sdram_addr)
                            VERTEX_LEAD:
                                vertex_lead_sentinel =
                                    sdram_wdata;

                            VERTEX_TRAIL:
                                vertex_trail_sentinel =
                                    sdram_wdata;

                            TEXTURE_LEAD:
                                texture_lead_sentinel =
                                    sdram_wdata;

                            TEXTURE_TRAIL:
                                texture_trail_sentinel =
                                    sdram_wdata;

                            FRAMEBUFFER_LEAD:
                                framebuffer_lead_sentinel =
                                    sdram_wdata;

                            FRAMEBUFFER_TRAIL:
                                framebuffer_trail_sentinel =
                                    sdram_wdata;

                            DEPTH_LEAD:
                                depth_lead_sentinel =
                                    sdram_wdata;

                            DEPTH_TRAIL:
                                depth_trail_sentinel =
                                    sdram_wdata;

                            UNRELATED_ADDR:
                                unrelated_sentinel =
                                    sdram_wdata;
                        endcase
                    end

                end else begin

                    illegal_accesses =
                        illegal_accesses + 1;
                end

                // Exact accepted graphics transaction sequence.
                if (observed_code != 0) begin
                    if (
                        graphics_transaction_index >= 18 ||
                        observed_code !=
                            expected_graphics_code(
                                graphics_transaction_index
                            )
                    ) begin
                        sequence_errors =
                            sequence_errors + 1;
                    end

                    graphics_transaction_index =
                        graphics_transaction_index + 1;
                end

                sdram_ready <= 1'b0;
                sdram_rdata <= 32'h00000000;
                service_delay = 0;

            end else if (sdram_valid) begin

                if (service_delay < 2) begin
                    service_delay =
                        service_delay + 1;
                end else begin
                    sdram_rdata <=
                        memory_read_word(sdram_addr);

                    sdram_ready <=
                        1'b1;
                end

            end else begin
                sdram_ready <= 1'b0;
                sdram_rdata <= 32'h00000000;
                service_delay = 0;
            end
        end
    end

    initial begin

        // ----------------------------------------------------
        // Initialize selected resources.
        // ----------------------------------------------------

        for (i = 0; i < 16; i = i + 1) begin
            texture_mem[i] =
                16'h6000 + i;

            framebuffer_mem[i] =
                16'hA000 + i;

            depth_mem[i] =
                16'h7777;
        end

        // Perspective-correct texture samples used by passing
        // fragments:
        //
        // fragment 0 -> texel 0 -> red
        // fragment 2 -> texel 2 -> blue
        // fragment 4 -> texel 1 -> green
        texture_mem[0] = 16'hF800;
        texture_mem[1] = 16'h07E0;
        texture_mem[2] = 16'h001F;
        texture_mem[4] = 16'hFFE0;

        // Selected covered framebuffer pixels.
        framebuffer_mem[0] = 16'h001F;
        framebuffer_mem[1] = 16'h1234;
        framebuffer_mem[2] = 16'hFFFF;
        framebuffer_mem[4] = 16'h5678;
        framebuffer_mem[5] = 16'hF800;
        framebuffer_mem[8] = 16'h9ABC;

        // Constant incoming depth is 0x4000.
        //
        // pass:  pixel 0  stored 0x5000
        // reject pixel 1  stored 0x4000 (equal)
        // pass:  pixel 2  stored 0x6000
        // reject pixel 4  stored 0x3000
        // pass:  pixel 5  stored 0xffff
        // reject pixel 8  stored 0x0000
        depth_mem[0] = 16'h5000;
        depth_mem[1] = 16'h4000;
        depth_mem[2] = 16'h6000;
        depth_mem[4] = 16'h3000;
        depth_mem[5] = 16'hFFFF;
        depth_mem[8] = 16'h0000;

        for (i = 0; i < 16; i = i + 1) begin
            texture_initial[i] =
                texture_mem[i];

            framebuffer_initial[i] =
                framebuffer_mem[i];

            depth_initial[i] =
                depth_mem[i];
        end

        repeat (3)
            @(posedge clk);

        #1;

        check(
            !dut.busy &&
            !sdram_valid,
            "reset leaves composed renderer idle"
        );

        @(negedge clk);
        reset = 1'b0;

        // ----------------------------------------------------
        // MODE=7: texture + depth + blending.
        // ----------------------------------------------------

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
            REG_DEPTH_BASE,
            DEPTH_BASE
        );

        mmio_write(
            REG_TARGET_SIZE,
            32'h00040004
        );

        mmio_write(
            REG_TEXTURE_SIZE,
            32'h00040004
        );

        mmio_write(
            REG_MODE,
            32'h00000007
        );

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000008
        );

        // Must not be used when texture is enabled.
        mmio_write(
            REG_FLAT_COLOR,
            32'h0000DEAD
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001
        );

        check(
            dut.busy &&
            dut.active_mode == 32'h00000007 &&
            dut.active_blend_alpha == 32'd8 &&
            dut.active_texture_base == TEXTURE_BASE &&
            dut.active_framebuffer_base == FRAMEBUFFER_BASE &&
            dut.active_depth_base == DEPTH_BASE,
            "START snapshots full texture/depth/blend configuration"
        );

        watchdog = 0;

        while (
            !dut.done &&
            (watchdog < 32768)
        ) begin
            @(posedge clk);
            #1;
            watchdog = watchdog + 1;
        end

        check(
            watchdog < 32768 &&
            dut.done &&
            !dut.busy &&
            !dut.error,
            "composed MODE=7 command completes normally"
        );

        // ----------------------------------------------------
        // Exact traffic counts.
        // ----------------------------------------------------

        check(
            vertex_reads == 18,
            "composition performs exactly eighteen vertex reads"
        );

        check(
            depth_reads == 6,
            "every covered fragment performs one depth read"
        );

        check(
            depth_writes == 3,
            "only three strict-LESS fragments write depth"
        );

        check(
            texture_reads == 3,
            "depth rejection suppresses texture reads"
        );

        check(
            framebuffer_reads == 3,
            "only passing textured fragments read blend destination"
        );

        check(
            framebuffer_writes == 3,
            "only passing textured fragments update framebuffer"
        );

        check(
            consumed_fragments == 6,
            "all six covered fragments are eventually consumed"
        );

        check(
            rejected_fragments == 3,
            "three covered fragments are rejected by depth"
        );

        check(
            graphics_transaction_index == 18 &&
            sequence_errors == 0,
            "combined graphics transaction order is exact"
        );

        check(
            texture_word0_reads == 2 &&
            texture_word1_reads == 1,
            "perspective texture fetches use expected aligned words"
        );

        check(
            illegal_accesses == 0,
            "renderer performs no access outside selected resources"
        );

        check(
            sentinel_accesses == 0,
            "renderer never addresses resource boundary sentinels"
        );

        check(
            bad_transaction_shapes == 0,
            "all composed SDRAM transactions use legal alignment and strobes"
        );

        check(
            dut.raster_coverage_count == 32'd6 &&
            dut.raster_sample_count == 32'd16,
            "composition preserves deterministic raster coverage"
        );

        // ----------------------------------------------------
        // Exact final passing pixels.
        //
        // alpha=8:
        // red  over blue  -> 0x8010
        // blue over white -> 0x841f
        // green over red  -> 0x8400
        // ----------------------------------------------------

        check(
            framebuffer_mem[0] == 16'h8010,
            "fragment 0 writes exact red-over-blue blended result"
        );

        check(
            framebuffer_mem[2] == 16'h841F,
            "fragment 2 writes exact blue-over-white blended result"
        );

        check(
            framebuffer_mem[5] == 16'h8400,
            "fragment 4 writes exact green-over-red blended result"
        );

        // Rejected covered pixels remain untouched.
        check(
            framebuffer_mem[1] ==
                framebuffer_initial[1],
            "equal-depth rejected fragment leaves framebuffer unchanged"
        );

        check(
            framebuffer_mem[4] ==
                framebuffer_initial[4],
            "nearer stored depth suppresses framebuffer change"
        );

        check(
            framebuffer_mem[8] ==
                framebuffer_initial[8],
            "zero stored depth suppresses framebuffer change"
        );

        // Exact depth results.
        check(
            depth_mem[0] == 16'h4000 &&
            depth_mem[2] == 16'h4000 &&
            depth_mem[5] == 16'h4000,
            "strict-LESS passing fragments update depth to incoming value"
        );

        check(
            depth_mem[1] == depth_initial[1] &&
            depth_mem[4] == depth_initial[4] &&
            depth_mem[8] == depth_initial[8],
            "rejected fragments do not alter depth"
        );

        // Entire texture allocation remains read-only.
        for (i = 0; i < 16; i = i + 1) begin
            check(
                texture_mem[i] ==
                    texture_initial[i],
                "texture allocation remains read-only"
            );
        end

        // Every uncovered framebuffer/depth halfword is unchanged.
        for (i = 0; i < 16; i = i + 1) begin
            if (
                i != 0 &&
                i != 1 &&
                i != 2 &&
                i != 4 &&
                i != 5 &&
                i != 8
            ) begin
                check(
                    framebuffer_mem[i] ==
                        framebuffer_initial[i],
                    "uncovered framebuffer halfword remains unchanged"
                );

                check(
                    depth_mem[i] ==
                        depth_initial[i],
                    "uncovered depth halfword remains unchanged"
                );
            end
        end

        // ----------------------------------------------------
        // Boundary and unrelated memory safety.
        // ----------------------------------------------------

        check(
            vertex_lead_sentinel ==
                32'h11112222 &&
            vertex_trail_sentinel ==
                32'h33334444,
            "vertex boundary sentinels remain unchanged"
        );

        check(
            texture_lead_sentinel ==
                32'h55556666 &&
            texture_trail_sentinel ==
                32'h77778888,
            "texture boundary sentinels remain unchanged"
        );

        check(
            framebuffer_lead_sentinel ==
                32'h9999AAAA &&
            framebuffer_trail_sentinel ==
                32'hBBBBCCCC,
            "framebuffer boundary sentinels remain unchanged"
        );

        check(
            depth_lead_sentinel ==
                32'hDDDDEEEE &&
            depth_trail_sentinel ==
                32'h13572468,
            "depth boundary sentinels remain unchanged"
        );

        check(
            unrelated_sentinel ==
                32'h89ABCDEF,
            "unrelated SDRAM sentinel remains unchanged"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "completed composed command returns SDRAM interface idle"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display(
                "RESULT: PASS  (%0d checks)",
                checks
            );

            $display(
                "COMPOSE_VERTEX_READS: %0d",
                vertex_reads
            );

            $display(
                "COMPOSE_DEPTH_READS: %0d",
                depth_reads
            );

            $display(
                "COMPOSE_DEPTH_WRITES: %0d",
                depth_writes
            );

            $display(
                "COMPOSE_TEXTURE_READS: %0d",
                texture_reads
            );

            $display(
                "COMPOSE_FRAMEBUFFER_READS: %0d",
                framebuffer_reads
            );

            $display(
                "COMPOSE_FRAMEBUFFER_WRITES: %0d",
                framebuffer_writes
            );

            $display(
                "COMPOSE_REJECTED_FRAGMENTS: %0d",
                rejected_fragments
            );

            $display(
                "COMPOSE_TRANSACTION_SEQUENCE_ERRORS: %0d",
                sequence_errors
            );

            $display(
                "COMPOSE_ILLEGAL_ACCESSES: %0d",
                illegal_accesses
            );

            $display(
                "COMPOSE_SENTINEL_ACCESSES: %0d",
                sentinel_accesses
            );

            $display(
                "COMPOSE_BAD_TRANSACTION_SHAPES: %0d",
                bad_transaction_shapes
            );

            $display(
                "COMPOSE_SENTINELS_INTACT: 9"
            );

            $display(
                "COMPOSE_FINAL_PIXEL_0: 0x8010"
            );

            $display(
                "COMPOSE_FINAL_PIXEL_2: 0x841f"
            );

            $display(
                "COMPOSE_FINAL_PIXEL_5: 0x8400"
            );
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
