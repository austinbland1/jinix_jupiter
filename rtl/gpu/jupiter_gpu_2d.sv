module jupiter_gpu_2d
(
    input  wire        clk,
    input  wire        reset,

    // CPU-visible GPU MMIO target interface.
    input  wire        valid,
    input  wire        write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire  [3:0] wstrb,

    output reg  [31:0] rdata,
    output wire        ready,

    // GPU external-SDRAM master interface.
    //
    // M5C-2 establishes and integrates this interface. The M5D renderer
    // will become its first functional request producer.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    localparam [31:0] REG_CONTROL          = 32'h00001100;
    localparam [31:0] REG_STATUS           = 32'h00001104;
    localparam [31:0] REG_TILEMAP_BASE     = 32'h00001108;
    localparam [31:0] REG_TILEDATA_BASE    = 32'h0000110C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001110;
    localparam [31:0] REG_MAP_SIZE         = 32'h00001114;

    reg [31:0] tilemap_base_reg;
    reg [31:0] tiledata_base_reg;
    reg [31:0] framebuffer_base_reg;
    reg [15:0] map_size_reg;

    // Configuration snapshot for one render operation.
    //
    // Renderer memory traffic uses only these active values. Live CPU-visible
    // configuration may therefore change without altering an active render.
    reg [31:0] active_tilemap_base;
    reg [31:0] active_tiledata_base;
    reg [31:0] active_framebuffer_base;
    reg [15:0] active_map_size;

    reg busy;
    reg done;

    // M10 GPU-internal integration.
    //
    // The subsystem-visible jupiter_gpu_2d module remains the single GPU
    // target and the single external GPU SDRAM master. The new 3D child
    // occupies only its selected MMIO subrange and shares SDRAM through the
    // internal two-way arbiter.
    wire gpu3d_mmio_selected =
        valid &&
        (addr >= 32'h00001140) &&
        (addr <= 32'h0000117F);

    wire [31:0] gpu3d_mmio_rdata;
    wire        gpu3d_mmio_ready;

    wire        gpu2d_sdram_valid;
    wire        gpu2d_sdram_write;
    wire [31:0] gpu2d_sdram_addr;
    wire [31:0] gpu2d_sdram_wdata;
    wire  [3:0] gpu2d_sdram_wstrb;
    wire [31:0] gpu2d_sdram_rdata;
    wire        gpu2d_sdram_ready;

    wire        gpu3d_sdram_valid;
    wire        gpu3d_sdram_write;
    wire [31:0] gpu3d_sdram_addr;
    wire [31:0] gpu3d_sdram_wdata;
    wire  [3:0] gpu3d_sdram_wstrb;
    wire [31:0] gpu3d_sdram_rdata;
    wire        gpu3d_sdram_ready;

    // Renderer sequencing state.
    //
    // M5D-1 through M5D-4 established the complete per-tile path from
    // tilemap fetch through all eight RGB565 rows. M5D-5 extends that path
    // across tile X and tile Y in row-major order and completes the render
    // after the final configured tile.
    localparam [2:0] RENDER_IDLE               = 3'd0;
    localparam [2:0] RENDER_TILEMAP_WAIT       = 3'd1;
    localparam [2:0] RENDER_TILE_DATA_PENDING  = 3'd2;
    localparam [2:0] RENDER_TILE_DATA_WAIT     = 3'd3;
    localparam [2:0] RENDER_TILE_ROW_PENDING   = 3'd4;
    localparam [2:0] RENDER_FRAMEBUFFER_WAIT   = 3'd5;
    localparam [2:0] RENDER_ROW_WRITTEN        = 3'd6;
    localparam [2:0] RENDER_TILE_COMPLETE      = 3'd7;

    reg [2:0] renderer_state;
    reg [7:0] tile_x;
    reg [7:0] tile_y;
    reg [15:0] current_tile_index;

    // Tile row zero consists of four 32-bit words, each containing two
    // adjacent RGB565 pixels.
    reg [2:0] tile_row;
    reg [1:0] tile_word;
    reg [31:0] tile_row_word0;
    reg [31:0] tile_row_word1;
    reg [31:0] tile_row_word2;
    reg [31:0] tile_row_word3;

    wire [15:0] tilemap_linear_index =
        (tile_y * active_map_size[7:0]) + tile_x;

    wire [31:0] tilemap_request_addr =
        active_tilemap_base +
        {14'd0, tilemap_linear_index, 2'b00};

    // One tile occupies 128 bytes. Each of its eight rows occupies 16 bytes,
    // represented by four aligned 32-bit words.
    wire [31:0] tiledata_tile_base =
        active_tiledata_base +
        {9'd0, current_tile_index, 7'd0};

    wire [31:0] tiledata_request_addr =
        tiledata_tile_base +
        {25'd0, tile_row, 4'b0000} +
        {28'd0, tile_word, 2'b00};

    // Convert tile-space Y and the row within the current tile into the
    // framebuffer's absolute pixel-row number.
    wire [10:0] framebuffer_pixel_row =
        {tile_y, 3'b000} +
        {8'd0, tile_row};

    // Each tile contributes sixteen framebuffer bytes to a scanline.
    // Multiplying the pixel-row number by width_tiles and then by sixteen
    // produces the complete-image scanline offset.
    wire [18:0] framebuffer_row_tiles =
        framebuffer_pixel_row * active_map_size[7:0];

    wire [31:0] framebuffer_row_offset =
        {9'd0, framebuffer_row_tiles, 4'b0000};

    // A tile is sixteen framebuffer bytes wide.
    wire [31:0] framebuffer_tile_x_offset =
        {20'd0, tile_x, 4'b0000};

    wire [31:0] framebuffer_request_addr =
        active_framebuffer_base +
        framebuffer_row_offset +
        framebuffer_tile_x_offset +
        {28'd0, tile_word, 2'b00};

    reg [31:0] framebuffer_request_data;

    always @(*) begin
        case (tile_word)
            2'd0:
                framebuffer_request_data = tile_row_word0;

            2'd1:
                framebuffer_request_data = tile_row_word1;

            2'd2:
                framebuffer_request_data = tile_row_word2;

            default:
                framebuffer_request_data = tile_row_word3;
        endcase
    end

    // This first GPU MMIO target inserts no wait states.
    assign ready =
        gpu3d_mmio_selected ?
        gpu3d_mmio_ready :
        valid;

    // Graphics-memory transactions remain selected until completion.
    // Tilemap and tile-data transactions are read-only; framebuffer traffic
    // is the renderer's only write path.
    assign gpu2d_sdram_valid =
        (renderer_state == RENDER_TILEMAP_WAIT) ||
        (renderer_state == RENDER_TILE_DATA_WAIT) ||
        (renderer_state == RENDER_FRAMEBUFFER_WAIT);

    assign gpu2d_sdram_write =
        (renderer_state == RENDER_FRAMEBUFFER_WAIT);

    assign gpu2d_sdram_addr =
        (renderer_state == RENDER_TILEMAP_WAIT) ?
            tilemap_request_addr :
        (renderer_state == RENDER_TILE_DATA_WAIT) ?
            tiledata_request_addr :
        (renderer_state == RENDER_FRAMEBUFFER_WAIT) ?
            framebuffer_request_addr :
            32'h00000000;

    assign gpu2d_sdram_wdata =
        (renderer_state == RENDER_FRAMEBUFFER_WAIT) ?
            framebuffer_request_data :
            32'h00000000;

    assign gpu2d_sdram_wstrb =
        (renderer_state == RENDER_FRAMEBUFFER_WAIT) ?
            4'b1111 :
            4'b0000;

    jupiter_gpu_3d gpu3d
    (
        .clk         (clk),
        .reset       (reset),

        .valid       (gpu3d_mmio_selected),
        .write       (write),
        .addr        (addr),
        .wdata       (wdata),
        .wstrb       (wstrb),

        .rdata       (gpu3d_mmio_rdata),
        .ready       (gpu3d_mmio_ready),

        .sdram_valid (gpu3d_sdram_valid),
        .sdram_write (gpu3d_sdram_write),
        .sdram_addr  (gpu3d_sdram_addr),
        .sdram_wdata (gpu3d_sdram_wdata),
        .sdram_wstrb (gpu3d_sdram_wstrb),
        .sdram_rdata (gpu3d_sdram_rdata),
        .sdram_ready (gpu3d_sdram_ready)
    );

    jupiter_gpu_2d3d_arbiter gpu_sdram_arbiter
    (
        .clk          (clk),
        .reset        (reset),

        .gpu2d_valid  (gpu2d_sdram_valid),
        .gpu2d_write  (gpu2d_sdram_write),
        .gpu2d_addr   (gpu2d_sdram_addr),
        .gpu2d_wdata  (gpu2d_sdram_wdata),
        .gpu2d_wstrb  (gpu2d_sdram_wstrb),
        .gpu2d_rdata  (gpu2d_sdram_rdata),
        .gpu2d_ready  (gpu2d_sdram_ready),

        .gpu3d_valid  (gpu3d_sdram_valid),
        .gpu3d_write  (gpu3d_sdram_write),
        .gpu3d_addr   (gpu3d_sdram_addr),
        .gpu3d_wdata  (gpu3d_sdram_wdata),
        .gpu3d_wstrb  (gpu3d_sdram_wstrb),
        .gpu3d_rdata  (gpu3d_sdram_rdata),
        .gpu3d_ready  (gpu3d_sdram_ready),

        .sdram_valid  (sdram_valid),
        .sdram_write  (sdram_write),
        .sdram_addr   (sdram_addr),
        .sdram_wdata  (sdram_wdata),
        .sdram_wstrb  (sdram_wstrb),
        .sdram_rdata  (sdram_rdata),
        .sdram_ready  (sdram_ready)
    );

    // Reads are deterministic. CONTROL is write-only and therefore reads
    // as zero. Reserved/unimplemented offsets also read as zero.
    always @(*) begin
        rdata = 32'h00000000;

        if (gpu3d_mmio_selected && !write) begin
            rdata = gpu3d_mmio_rdata;
        end else if (valid && !write) begin
            case (addr)
                REG_STATUS:
                    rdata = {30'd0, done, busy};

                REG_TILEMAP_BASE:
                    rdata = tilemap_base_reg;

                REG_TILEDATA_BASE:
                    rdata = tiledata_base_reg;

                REG_FRAMEBUFFER_BASE:
                    rdata = framebuffer_base_reg;

                REG_MAP_SIZE:
                    rdata = {16'd0, map_size_reg};

                default:
                    rdata = 32'h00000000;
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            tilemap_base_reg     <= 32'h00000000;
            tiledata_base_reg    <= 32'h00000000;
            framebuffer_base_reg <= 32'h00000000;
            map_size_reg         <= 16'h0000;

            active_tilemap_base     <= 32'h00000000;
            active_tiledata_base    <= 32'h00000000;
            active_framebuffer_base <= 32'h00000000;
            active_map_size         <= 16'h0000;

            renderer_state     <= RENDER_IDLE;
            tile_x             <= 8'd0;
            tile_y             <= 8'd0;
            current_tile_index <= 16'd0;

            tile_row       <= 3'd0;
            tile_word      <= 2'd0;
            tile_row_word0 <= 32'h00000000;
            tile_row_word1 <= 32'h00000000;
            tile_row_word2 <= 32'h00000000;
            tile_row_word3 <= 32'h00000000;

            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            // Renderer progress is independent of CPU MMIO writes. This is
            // required because live configuration registers remain writable
            // while a render is active.
            if ((renderer_state == RENDER_TILEMAP_WAIT) &&
                gpu2d_sdram_ready) begin
                current_tile_index <= gpu2d_sdram_rdata[15:0];
                renderer_state <= RENDER_TILE_DATA_PENDING;
            end else if (renderer_state == RENDER_TILE_DATA_PENDING) begin
                // Keep one transaction-free boundary between the tilemap
                // completion and the first tile-data request. This preserves
                // the bounded M5D-1 checkpoint behavior.
                tile_word <= 2'd0;
                renderer_state <= RENDER_TILE_DATA_WAIT;
            end else if ((renderer_state == RENDER_TILE_DATA_WAIT) &&
                         gpu2d_sdram_ready) begin
                case (tile_word)
                    2'd0:
                        tile_row_word0 <= gpu2d_sdram_rdata;

                    2'd1:
                        tile_row_word1 <= gpu2d_sdram_rdata;

                    2'd2:
                        tile_row_word2 <= gpu2d_sdram_rdata;

                    2'd3:
                        tile_row_word3 <= gpu2d_sdram_rdata;
                endcase

                if (tile_word == 2'd3) begin
                    renderer_state <= RENDER_TILE_ROW_PENDING;
                end else begin
                    tile_word <= tile_word + 2'd1;
                end
            end else if (renderer_state == RENDER_TILE_ROW_PENDING) begin
                // Keep a transaction-free checkpoint after the four reads,
                // then begin writing the captured row to the framebuffer.
                tile_word <= 2'd0;
                renderer_state <= RENDER_FRAMEBUFFER_WAIT;
            end else if ((renderer_state == RENDER_FRAMEBUFFER_WAIT) &&
                         gpu2d_sdram_ready) begin
                if (tile_word == 2'd3) begin
                    renderer_state <= RENDER_ROW_WRITTEN;
                end else begin
                    tile_word <= tile_word + 2'd1;
                end
            end else if (renderer_state == RENDER_ROW_WRITTEN) begin
                if (tile_row == 3'd7) begin
                    renderer_state <= RENDER_TILE_COMPLETE;
                end else begin
                    tile_row <= tile_row + 3'd1;
                    tile_word <= 2'd0;

                    tile_row_word0 <= 32'h00000000;
                    tile_row_word1 <= 32'h00000000;
                    tile_row_word2 <= 32'h00000000;
                    tile_row_word3 <= 32'h00000000;

                    renderer_state <= RENDER_TILE_DATA_WAIT;
                end
            end else if (renderer_state == RENDER_TILE_COMPLETE) begin
                // Zero-sized maps complete immediately at START, so both
                // active dimensions are nonzero while this state is reached.
                if ((tile_x == (active_map_size[7:0] - 8'd1)) &&
                    (tile_y == (active_map_size[15:8] - 8'd1))) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    renderer_state <= RENDER_IDLE;
                end else begin
                    if (tile_x == (active_map_size[7:0] - 8'd1)) begin
                        tile_x <= 8'd0;
                        tile_y <= tile_y + 8'd1;
                    end else begin
                        tile_x <= tile_x + 8'd1;
                    end

                    tile_row <= 3'd0;
                    tile_word <= 2'd0;
                    current_tile_index <= 16'd0;

                    tile_row_word0 <= 32'h00000000;
                    tile_row_word1 <= 32'h00000000;
                    tile_row_word2 <= 32'h00000000;
                    tile_row_word3 <= 32'h00000000;

                    renderer_state <= RENDER_TILEMAP_WAIT;
                end
            end

            if (valid && write) begin
                case (addr)
                    REG_CONTROL: begin
                        // CONTROL.START is bit 0 in the low byte.
                        if (wstrb[0] && wdata[0] && !busy) begin
                            active_tilemap_base     <= tilemap_base_reg;
                            active_tiledata_base    <= tiledata_base_reg;
                            active_framebuffer_base <= framebuffer_base_reg;
                            active_map_size         <= map_size_reg;

                            tile_x <= 8'd0;
                            tile_y <= 8'd0;
                            current_tile_index <= 16'd0;

                            tile_row       <= 3'd0;
                            tile_word      <= 2'd0;
                            tile_row_word0 <= 32'h00000000;
                            tile_row_word1 <= 32'h00000000;
                            tile_row_word2 <= 32'h00000000;
                            tile_row_word3 <= 32'h00000000;

                            done <= 1'b0;

                            // The architecture defines a zero-width or
                            // zero-height operation as immediately complete
                            // without graphics-memory traffic.
                            if ((map_size_reg[7:0] == 8'd0) ||
                                (map_size_reg[15:8] == 8'd0)) begin
                                busy <= 1'b0;
                                done <= 1'b1;
                                renderer_state <= RENDER_IDLE;
                            end else begin
                                busy <= 1'b1;
                                renderer_state <= RENDER_TILEMAP_WAIT;
                            end
                        end
                    end

                    REG_STATUS: begin
                        // Read-only.
                    end

                    REG_TILEMAP_BASE: begin
                        if (wstrb[0])
                            tilemap_base_reg[7:0] <= wdata[7:0];
                        if (wstrb[1])
                            tilemap_base_reg[15:8] <= wdata[15:8];
                        if (wstrb[2])
                            tilemap_base_reg[23:16] <= wdata[23:16];
                        if (wstrb[3])
                            tilemap_base_reg[31:24] <= wdata[31:24];
                    end

                    REG_TILEDATA_BASE: begin
                        if (wstrb[0])
                            tiledata_base_reg[7:0] <= wdata[7:0];
                        if (wstrb[1])
                            tiledata_base_reg[15:8] <= wdata[15:8];
                        if (wstrb[2])
                            tiledata_base_reg[23:16] <= wdata[23:16];
                        if (wstrb[3])
                            tiledata_base_reg[31:24] <= wdata[31:24];
                    end

                    REG_FRAMEBUFFER_BASE: begin
                        if (wstrb[0])
                            framebuffer_base_reg[7:0] <= wdata[7:0];
                        if (wstrb[1])
                            framebuffer_base_reg[15:8] <= wdata[15:8];
                        if (wstrb[2])
                            framebuffer_base_reg[23:16] <= wdata[23:16];
                        if (wstrb[3])
                            framebuffer_base_reg[31:24] <= wdata[31:24];
                    end

                    REG_MAP_SIZE: begin
                        if (wstrb[0])
                            map_size_reg[7:0] <= wdata[7:0];
                        if (wstrb[1])
                            map_size_reg[15:8] <= wdata[15:8];
                    end

                    default: begin
                        // Reserved/unimplemented offsets ignore writes.
                    end
                endcase
            end
        end
    end

endmodule
