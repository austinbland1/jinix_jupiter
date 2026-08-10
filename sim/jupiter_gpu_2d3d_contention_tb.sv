`timescale 1ns/1ps

module jupiter_gpu_2d3d_contention_tb;

    // --------------------------------------------------------
    // Existing 2D MMIO
    // --------------------------------------------------------

    localparam [31:0] REG_2D_CONTROL =
        32'h00001100;

    localparam [31:0] REG_2D_TILEMAP_BASE =
        32'h00001108;

    localparam [31:0] REG_2D_TILEDATA_BASE =
        32'h0000110C;

    localparam [31:0] REG_2D_FRAMEBUFFER_BASE =
        32'h00001110;

    localparam [31:0] REG_2D_MAP_SIZE =
        32'h00001114;

    // --------------------------------------------------------
    // 3D MMIO
    // --------------------------------------------------------

    localparam [31:0] REG_3D_CONTROL =
        32'h00001140;

    localparam [31:0] REG_3D_VERTEX_BASE =
        32'h00001148;

    localparam [31:0] REG_3D_FRAMEBUFFER_BASE =
        32'h00001150;

    localparam [31:0] REG_3D_TARGET_SIZE =
        32'h00001158;

    localparam [31:0] REG_3D_MODE =
        32'h00001160;

    localparam [31:0] REG_3D_FLAT_COLOR =
        32'h00001168;

    // --------------------------------------------------------
    // Disjoint graphics-memory resources
    // --------------------------------------------------------

    localparam [31:0] TILEMAP_BASE =
        32'h10001000;

    localparam [31:0] TILEDATA_BASE =
        32'h10002000;

    localparam [31:0] FB2D_BASE =
        32'h10003000;

    localparam [31:0] VERTEX_BASE =
        32'h10010000;

    localparam [31:0] FB3D_BASE =
        32'h10011000;

    localparam [15:0] FLAT_3D_COLOR =
        16'hBEEF;

    // Boundary sentinels.
    localparam [31:0] TILEMAP_LEAD =
        TILEMAP_BASE - 32'd4;

    localparam [31:0] TILEMAP_TRAIL =
        TILEMAP_BASE + 32'd4;

    localparam [31:0] TILEDATA_LEAD =
        TILEDATA_BASE - 32'd4;

    localparam [31:0] TILEDATA_TRAIL =
        TILEDATA_BASE + 32'd128;

    localparam [31:0] FB2D_LEAD =
        FB2D_BASE - 32'd4;

    localparam [31:0] FB2D_TRAIL =
        FB2D_BASE + 32'd128;

    localparam [31:0] VERTEX_LEAD =
        VERTEX_BASE - 32'd4;

    localparam [31:0] VERTEX_TRAIL =
        VERTEX_BASE + 32'd72;

    localparam [31:0] FB3D_LEAD =
        FB3D_BASE - 32'd4;

    localparam [31:0] FB3D_TRAIL =
        FB3D_BASE + 32'd32;

    localparam [31:0] UNRELATED_ADDR =
        32'h10020000;

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

    reg [31:0] framebuffer_2d [0:31];
    reg [31:0] framebuffer_2d_initial [0:31];

    reg [15:0] framebuffer_3d [0:15];
    reg [15:0] framebuffer_3d_initial [0:15];

    reg [31:0] tilemap_lead_sentinel =
        32'h11110001;

    reg [31:0] tilemap_trail_sentinel =
        32'h11110002;

    reg [31:0] tiledata_lead_sentinel =
        32'h22220001;

    reg [31:0] tiledata_trail_sentinel =
        32'h22220002;

    reg [31:0] fb2d_lead_sentinel =
        32'h33330001;

    reg [31:0] fb2d_trail_sentinel =
        32'h33330002;

    reg [31:0] vertex_lead_sentinel =
        32'h44440001;

    reg [31:0] vertex_trail_sentinel =
        32'h44440002;

    reg [31:0] fb3d_lead_sentinel =
        32'h55550001;

    reg [31:0] fb3d_trail_sentinel =
        32'h55550002;

    reg [31:0] unrelated_sentinel =
        32'h89ABCDEF;

    integer checks = 0;
    integer failures = 0;
    integer watchdog = 0;
    integer i;

    integer service_delay = 0;
    reg service_started = 1'b0;

    integer gpu2d_reads = 0;
    integer gpu2d_writes = 0;
    integer gpu3d_reads = 0;
    integer gpu3d_writes = 0;

    integer simultaneous_request_cycles = 0;

    integer contested_2d_completions = 0;
    integer contested_3d_completions = 0;

    integer completions_2d_while_3d_pending = 0;
    integer completions_3d_while_2d_pending = 0;

    integer routing_errors = 0;
    integer bad_transaction_shapes = 0;
    integer source_write_errors = 0;
    integer illegal_accesses = 0;
    integer sentinel_accesses = 0;

    integer memory_index = 0;

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

    function automatic [31:0] tile_word;
        input integer index;

        begin
            tile_word =
                32'hA5000000 + index;
        end
    endfunction

    function automatic [31:0] vertex_word;
        input integer index;

        begin
            case (index)
                // CCW six-pixel reference triangle.
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

    function automatic [31:0] memory_read_word;
        input [31:0] address;

        integer index;

        begin
            memory_read_word =
                32'hDEADBEEF;

            index = 0;

            if (address == TILEMAP_BASE) begin

                // Tile zero.
                memory_read_word =
                    32'h00000000;

            end else if (
                (address >= TILEDATA_BASE) &&
                (address < (TILEDATA_BASE + 32'd128))
            ) begin

                index =
                    (address - TILEDATA_BASE) >> 2;

                memory_read_word =
                    tile_word(index);

            end else if (
                (address >= VERTEX_BASE) &&
                (address < (VERTEX_BASE + 32'd72))
            ) begin

                index =
                    (address - VERTEX_BASE) >> 2;

                memory_read_word =
                    vertex_word(index);

            end else if (
                (address >= FB2D_BASE) &&
                (address < (FB2D_BASE + 32'd128))
            ) begin

                index =
                    (address - FB2D_BASE) >> 2;

                memory_read_word =
                    framebuffer_2d[index];

            end else if (
                (address >= FB3D_BASE) &&
                (address < (FB3D_BASE + 32'd32))
            ) begin

                index =
                    (address - FB3D_BASE) >> 1;

                memory_read_word =
                {
                    framebuffer_3d[index + 1],
                    framebuffer_3d[index]
                };

            end else begin
                case (address)
                    TILEMAP_LEAD:
                        memory_read_word =
                            tilemap_lead_sentinel;

                    TILEMAP_TRAIL:
                        memory_read_word =
                            tilemap_trail_sentinel;

                    TILEDATA_LEAD:
                        memory_read_word =
                            tiledata_lead_sentinel;

                    TILEDATA_TRAIL:
                        memory_read_word =
                            tiledata_trail_sentinel;

                    FB2D_LEAD:
                        memory_read_word =
                            fb2d_lead_sentinel;

                    FB2D_TRAIL:
                        memory_read_word =
                            fb2d_trail_sentinel;

                    VERTEX_LEAD:
                        memory_read_word =
                            vertex_lead_sentinel;

                    VERTEX_TRAIL:
                        memory_read_word =
                            vertex_trail_sentinel;

                    FB3D_LEAD:
                        memory_read_word =
                            fb3d_lead_sentinel;

                    FB3D_TRAIL:
                        memory_read_word =
                            fb3d_trail_sentinel;

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
                $display(
                    "PASS: %0s",
                    message
                );
            end else begin
                failures = failures + 1;

                $display(
                    "FAIL: %0s",
                    message
                );
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
    // Stateful shared SDRAM model.
    //
    // Service begins only after both real renderers are busy,
    // guaranteeing overlap. Once enabled it remains enabled so
    // either renderer can finish after the other completes.
    //
    // Every transaction is held for two clocks before READY.
    // --------------------------------------------------------

    always @(posedge clk) begin

        if (reset) begin

            sdram_ready <=
                1'b0;

            sdram_rdata <=
                32'h00000000;

            service_delay = 0;
            service_started = 1'b0;

            gpu2d_reads = 0;
            gpu2d_writes = 0;
            gpu3d_reads = 0;
            gpu3d_writes = 0;

            simultaneous_request_cycles = 0;

            contested_2d_completions = 0;
            contested_3d_completions = 0;

            completions_2d_while_3d_pending = 0;
            completions_3d_while_2d_pending = 0;

            routing_errors = 0;
            bad_transaction_shapes = 0;
            source_write_errors = 0;
            illegal_accesses = 0;
            sentinel_accesses = 0;

        end else begin

            if (
                !service_started &&
                dut.busy &&
                dut.gpu3d.busy
            ) begin
                service_started =
                    1'b1;
            end

            if (
                service_started &&
                dut.gpu2d_sdram_valid &&
                dut.gpu3d_sdram_valid
            ) begin
                simultaneous_request_cycles =
                    simultaneous_request_cycles + 1;
            end

            if (sdram_valid && sdram_ready) begin

                // Exactly one internal renderer must receive each
                // completion from the shared wrapper output.
                if (
                    dut.gpu2d_sdram_ready ==
                    dut.gpu3d_sdram_ready
                ) begin
                    routing_errors =
                        routing_errors + 1;
                end

                if (dut.gpu2d_sdram_ready) begin

                    if (
                        !dut.gpu2d_sdram_valid ||
                        sdram_addr !=
                            dut.gpu2d_sdram_addr ||
                        sdram_write !=
                            dut.gpu2d_sdram_write ||
                        sdram_wdata !=
                            dut.gpu2d_sdram_wdata ||
                        sdram_wstrb !=
                            dut.gpu2d_sdram_wstrb
                    ) begin
                        routing_errors =
                            routing_errors + 1;
                    end

                    if (dut.gpu3d_sdram_valid) begin
                        completions_2d_while_3d_pending =
                            completions_2d_while_3d_pending + 1;
                    end

                    if (
                        dut.gpu_sdram_arbiter.grant_contested
                    ) begin
                        contested_2d_completions =
                            contested_2d_completions + 1;
                    end

                end

                if (dut.gpu3d_sdram_ready) begin

                    if (
                        !dut.gpu3d_sdram_valid ||
                        sdram_addr !=
                            dut.gpu3d_sdram_addr ||
                        sdram_write !=
                            dut.gpu3d_sdram_write ||
                        sdram_wdata !=
                            dut.gpu3d_sdram_wdata ||
                        sdram_wstrb !=
                            dut.gpu3d_sdram_wstrb
                    ) begin
                        routing_errors =
                            routing_errors + 1;
                    end

                    if (dut.gpu2d_sdram_valid) begin
                        completions_3d_while_2d_pending =
                            completions_3d_while_2d_pending + 1;
                    end

                    if (
                        dut.gpu_sdram_arbiter.grant_contested
                    ) begin
                        contested_3d_completions =
                            contested_3d_completions + 1;
                    end

                end

                // --------------------------------------------
                // 2D tilemap source
                // --------------------------------------------

                if (sdram_addr == TILEMAP_BASE) begin

                    if (
                        sdram_write ||
                        sdram_wstrb != 4'b0000 ||
                        !dut.gpu2d_sdram_ready
                    ) begin
                        bad_transaction_shapes =
                            bad_transaction_shapes + 1;

                        if (sdram_write)
                            source_write_errors =
                                source_write_errors + 1;
                    end else begin
                        gpu2d_reads =
                            gpu2d_reads + 1;
                    end

                // --------------------------------------------
                // 2D tile-data source
                // --------------------------------------------

                end else if (
                    (sdram_addr >= TILEDATA_BASE) &&
                    (sdram_addr <
                        (TILEDATA_BASE + 32'd128))
                ) begin

                    if (
                        sdram_write ||
                        sdram_wstrb != 4'b0000 ||
                        sdram_addr[1:0] != 2'b00 ||
                        !dut.gpu2d_sdram_ready
                    ) begin
                        bad_transaction_shapes =
                            bad_transaction_shapes + 1;

                        if (sdram_write)
                            source_write_errors =
                                source_write_errors + 1;
                    end else begin
                        gpu2d_reads =
                            gpu2d_reads + 1;
                    end

                // --------------------------------------------
                // 2D framebuffer destination
                // --------------------------------------------

                end else if (
                    (sdram_addr >= FB2D_BASE) &&
                    (sdram_addr <
                        (FB2D_BASE + 32'd128))
                ) begin

                    if (
                        !sdram_write ||
                        sdram_wstrb != 4'b1111 ||
                        sdram_addr[1:0] != 2'b00 ||
                        !dut.gpu2d_sdram_ready
                    ) begin
                        bad_transaction_shapes =
                            bad_transaction_shapes + 1;
                    end else begin

                        gpu2d_writes =
                            gpu2d_writes + 1;

                        memory_index =
                            (sdram_addr - FB2D_BASE) >> 2;

                        framebuffer_2d[memory_index] =
                            sdram_wdata;
                    end

                // --------------------------------------------
                // 3D vertex source
                // --------------------------------------------

                end else if (
                    (sdram_addr >= VERTEX_BASE) &&
                    (sdram_addr <
                        (VERTEX_BASE + 32'd72))
                ) begin

                    if (
                        sdram_write ||
                        sdram_wstrb != 4'b0000 ||
                        sdram_addr[1:0] != 2'b00 ||
                        !dut.gpu3d_sdram_ready
                    ) begin
                        bad_transaction_shapes =
                            bad_transaction_shapes + 1;

                        if (sdram_write)
                            source_write_errors =
                                source_write_errors + 1;
                    end else begin
                        gpu3d_reads =
                            gpu3d_reads + 1;
                    end

                // --------------------------------------------
                // 3D RGB565 framebuffer destination
                // --------------------------------------------

                end else if (
                    (sdram_addr >= FB3D_BASE) &&
                    (sdram_addr <
                        (FB3D_BASE + 32'd32))
                ) begin

                    if (
                        !sdram_write ||
                        sdram_addr[1:0] != 2'b00 ||
                        !(
                            sdram_wstrb == 4'b0011 ||
                            sdram_wstrb == 4'b1100
                        ) ||
                        !dut.gpu3d_sdram_ready
                    ) begin
                        bad_transaction_shapes =
                            bad_transaction_shapes + 1;
                    end else begin

                        gpu3d_writes =
                            gpu3d_writes + 1;

                        memory_index =
                            (sdram_addr - FB3D_BASE) >> 1;

                        if (sdram_wstrb == 4'b0011)
                            framebuffer_3d[memory_index] =
                                sdram_wdata[15:0];

                        if (sdram_wstrb == 4'b1100)
                            framebuffer_3d[memory_index + 1] =
                                sdram_wdata[31:16];
                    end

                // --------------------------------------------
                // Boundary / unrelated guards
                // --------------------------------------------

                end else if (
                    sdram_addr == TILEMAP_LEAD ||
                    sdram_addr == TILEMAP_TRAIL ||
                    sdram_addr == TILEDATA_LEAD ||
                    sdram_addr == TILEDATA_TRAIL ||
                    sdram_addr == FB2D_LEAD ||
                    sdram_addr == FB2D_TRAIL ||
                    sdram_addr == VERTEX_LEAD ||
                    sdram_addr == VERTEX_TRAIL ||
                    sdram_addr == FB3D_LEAD ||
                    sdram_addr == FB3D_TRAIL ||
                    sdram_addr == UNRELATED_ADDR
                ) begin

                    sentinel_accesses =
                        sentinel_accesses + 1;

                    if (sdram_write) begin
                        case (sdram_addr)
                            TILEMAP_LEAD:
                                tilemap_lead_sentinel =
                                    sdram_wdata;

                            TILEMAP_TRAIL:
                                tilemap_trail_sentinel =
                                    sdram_wdata;

                            TILEDATA_LEAD:
                                tiledata_lead_sentinel =
                                    sdram_wdata;

                            TILEDATA_TRAIL:
                                tiledata_trail_sentinel =
                                    sdram_wdata;

                            FB2D_LEAD:
                                fb2d_lead_sentinel =
                                    sdram_wdata;

                            FB2D_TRAIL:
                                fb2d_trail_sentinel =
                                    sdram_wdata;

                            VERTEX_LEAD:
                                vertex_lead_sentinel =
                                    sdram_wdata;

                            VERTEX_TRAIL:
                                vertex_trail_sentinel =
                                    sdram_wdata;

                            FB3D_LEAD:
                                fb3d_lead_sentinel =
                                    sdram_wdata;

                            FB3D_TRAIL:
                                fb3d_trail_sentinel =
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

                sdram_ready <=
                    1'b0;

                sdram_rdata <=
                    32'h00000000;

                service_delay = 0;

            end else if (
                service_started &&
                sdram_valid
            ) begin

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

                sdram_ready <=
                    1'b0;

                sdram_rdata <=
                    32'h00000000;

                service_delay = 0;
            end
        end
    end

    initial begin

        for (i = 0; i < 32; i = i + 1) begin

            framebuffer_2d[i] =
                32'hD0000000 + i;

            framebuffer_2d_initial[i] =
                framebuffer_2d[i];
        end

        for (i = 0; i < 16; i = i + 1) begin

            framebuffer_3d[i] =
                16'h9000 + i;

            framebuffer_3d_initial[i] =
                framebuffer_3d[i];
        end

        repeat (3)
            @(posedge clk);

        #1;

        check(
            !dut.busy &&
            !dut.gpu3d.busy &&
            !sdram_valid,
            "reset leaves both real renderers and shared SDRAM idle"
        );

        @(negedge clk);
        reset = 1'b0;

        // ----------------------------------------------------
        // Configure 2D one-tile reference.
        // ----------------------------------------------------

        mmio_write(
            REG_2D_TILEMAP_BASE,
            TILEMAP_BASE
        );

        mmio_write(
            REG_2D_TILEDATA_BASE,
            TILEDATA_BASE
        );

        mmio_write(
            REG_2D_FRAMEBUFFER_BASE,
            FB2D_BASE
        );

        mmio_write(
            REG_2D_MAP_SIZE,
            32'h00000101
        );

        // ----------------------------------------------------
        // Configure flat 3D six-pixel reference.
        // ----------------------------------------------------

        mmio_write(
            REG_3D_VERTEX_BASE,
            VERTEX_BASE
        );

        mmio_write(
            REG_3D_FRAMEBUFFER_BASE,
            FB3D_BASE
        );

        mmio_write(
            REG_3D_TARGET_SIZE,
            32'h00040004
        );

        mmio_write(
            REG_3D_MODE,
            32'h00000000
        );

        mmio_write(
            REG_3D_FLAT_COLOR,
            {16'h0000, FLAT_3D_COLOR}
        );

        // Start 2D first. SDRAM service remains disabled until
        // 3D is also busy, so real requests necessarily overlap.
        mmio_write(
            REG_2D_CONTROL,
            32'h00000001
        );

        check(
            dut.busy,
            "real 2D renderer starts before contention"
        );

        mmio_write(
            REG_3D_CONTROL,
            32'h00000001
        );

        check(
            dut.gpu3d.busy,
            "real 3D renderer starts before shared SDRAM service"
        );

        watchdog = 0;

        while (
            !(
                dut.done &&
                dut.gpu3d.done
            ) &&
            (watchdog < 6000)
        ) begin
            @(posedge clk);
            #1;

            watchdog =
                watchdog + 1;
        end

        check(
            watchdog < 6000,
            "both real renderers finish before watchdog"
        );

        check(
            service_started,
            "shared SDRAM service began only after both renderers were busy"
        );

        check(
            dut.done &&
            !dut.busy,
            "2D one-tile render completes and returns idle"
        );

        check(
            dut.gpu3d.done &&
            !dut.gpu3d.busy &&
            !dut.gpu3d.error,
            "3D flat triangle completes and returns idle"
        );

        // ----------------------------------------------------
        // Exact traffic counts.
        //
        // 2D one tile:
        //   1 tilemap read
        //   32 tile-data reads
        //   32 framebuffer writes
        //
        // 3D flat triangle:
        //   18 vertex reads
        //   6 framebuffer halfword writes
        // ----------------------------------------------------

        check(
            gpu2d_reads == 33,
            "2D performs exactly thirty-three source reads"
        );

        check(
            gpu2d_writes == 32,
            "2D performs exactly thirty-two framebuffer writes"
        );

        check(
            gpu3d_reads == 18,
            "3D performs exactly eighteen vertex reads"
        );

        check(
            gpu3d_writes == 6,
            "3D performs exactly six framebuffer writes"
        );

        check(
            (
                gpu2d_reads +
                gpu2d_writes +
                gpu3d_reads +
                gpu3d_writes
            ) == 89,
            "combined wrapper completes exactly eighty-nine SDRAM transactions"
        );

        // ----------------------------------------------------
        // Real arbitration / overlap evidence.
        // ----------------------------------------------------

        check(
            simultaneous_request_cycles > 0,
            "real 2D and 3D masters present simultaneous SDRAM requests"
        );

        check(
            contested_2d_completions > 0,
            "real 2D wins completed contested wrapper transactions"
        );

        check(
            contested_3d_completions > 0,
            "real 3D wins completed contested wrapper transactions"
        );

        check(
            completions_2d_while_3d_pending > 0,
            "2D completes traffic while a real 3D request is pending"
        );

        check(
            completions_3d_while_2d_pending > 0,
            "3D completes traffic while a real 2D request is pending"
        );

        check(
            routing_errors == 0,
            "shared completions and payloads route only to the granted renderer"
        );

        check(
            bad_transaction_shapes == 0,
            "all integrated graphics transactions retain legal alignment and strobes"
        );

        check(
            source_write_errors == 0,
            "tilemap tile-data and vertex resources remain read-only"
        );

        check(
            illegal_accesses == 0,
            "integrated renderers access only selected graphics resources"
        );

        check(
            sentinel_accesses == 0,
            "integrated renderers never address boundary or unrelated sentinels"
        );

        // ----------------------------------------------------
        // Exact 2D render result.
        // ----------------------------------------------------

        for (i = 0; i < 32; i = i + 1) begin

            check(
                framebuffer_2d[i] ==
                    tile_word(i),
                "2D framebuffer word matches exact source tile reference"
            );
        end

        // ----------------------------------------------------
        // Exact 3D six-pixel flat result.
        // ----------------------------------------------------

        check(
            framebuffer_3d[0] == FLAT_3D_COLOR,
            "3D covered pixel zero matches flat reference"
        );

        check(
            framebuffer_3d[1] == FLAT_3D_COLOR,
            "3D covered pixel one matches flat reference"
        );

        check(
            framebuffer_3d[2] == FLAT_3D_COLOR,
            "3D covered pixel two matches flat reference"
        );

        check(
            framebuffer_3d[4] == FLAT_3D_COLOR,
            "3D covered pixel four matches flat reference"
        );

        check(
            framebuffer_3d[5] == FLAT_3D_COLOR,
            "3D covered pixel five matches flat reference"
        );

        check(
            framebuffer_3d[8] == FLAT_3D_COLOR,
            "3D covered pixel eight matches flat reference"
        );

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
                    framebuffer_3d[i] ==
                        framebuffer_3d_initial[i],
                    "uncovered 3D framebuffer halfword remains unchanged"
                );
            end
        end

        // ----------------------------------------------------
        // Boundary/unrelated memory integrity.
        // ----------------------------------------------------

        check(
            tilemap_lead_sentinel ==
                32'h11110001 &&
            tilemap_trail_sentinel ==
                32'h11110002,
            "2D tilemap boundary sentinels remain intact"
        );

        check(
            tiledata_lead_sentinel ==
                32'h22220001 &&
            tiledata_trail_sentinel ==
                32'h22220002,
            "2D tile-data boundary sentinels remain intact"
        );

        check(
            fb2d_lead_sentinel ==
                32'h33330001 &&
            fb2d_trail_sentinel ==
                32'h33330002,
            "2D framebuffer boundary sentinels remain intact"
        );

        check(
            vertex_lead_sentinel ==
                32'h44440001 &&
            vertex_trail_sentinel ==
                32'h44440002,
            "3D vertex boundary sentinels remain intact"
        );

        check(
            fb3d_lead_sentinel ==
                32'h55550001 &&
            fb3d_trail_sentinel ==
                32'h55550002,
            "3D framebuffer boundary sentinels remain intact"
        );

        check(
            unrelated_sentinel ==
                32'h89ABCDEF,
            "unrelated SDRAM sentinel remains intact"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "completed dual-render command returns shared SDRAM interface idle"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin

            $display(
                "RESULT: PASS  (%0d checks)",
                checks
            );

            $display(
                "2D3D_2D_READS: %0d",
                gpu2d_reads
            );

            $display(
                "2D3D_2D_WRITES: %0d",
                gpu2d_writes
            );

            $display(
                "2D3D_3D_READS: %0d",
                gpu3d_reads
            );

            $display(
                "2D3D_3D_WRITES: %0d",
                gpu3d_writes
            );

            $display(
                "2D3D_TOTAL_TRANSACTIONS: %0d",
                (
                    gpu2d_reads +
                    gpu2d_writes +
                    gpu3d_reads +
                    gpu3d_writes
                )
            );

            $display(
                "2D3D_SIMULTANEOUS_REQUEST_CYCLES: %0d",
                simultaneous_request_cycles
            );

            $display(
                "2D3D_CONTESTED_2D_COMPLETIONS: %0d",
                contested_2d_completions
            );

            $display(
                "2D3D_CONTESTED_3D_COMPLETIONS: %0d",
                contested_3d_completions
            );

            $display(
                "2D3D_ROUTING_ERRORS: %0d",
                routing_errors
            );

            $display(
                "2D3D_BAD_TRANSACTION_SHAPES: %0d",
                bad_transaction_shapes
            );

            $display(
                "2D3D_SOURCE_WRITE_ERRORS: %0d",
                source_write_errors
            );

            $display(
                "2D3D_ILLEGAL_ACCESSES: %0d",
                illegal_accesses
            );

            $display(
                "2D3D_SENTINEL_ACCESSES: %0d",
                sentinel_accesses
            );

            $display(
                "2D3D_SENTINELS_INTACT: 11"
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
