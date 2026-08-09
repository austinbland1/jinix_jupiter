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
    // M5B-1 establishes the register/control contract only. Later renderer
    // logic will consume these snapshot registers.
    reg [31:0] active_tilemap_base;
    reg [31:0] active_tiledata_base;
    reg [31:0] active_framebuffer_base;
    reg [15:0] active_map_size;

    reg busy;
    reg done;

    // This first GPU MMIO target inserts no wait states.
    assign ready = valid;

    // M5C-2 integrates the GPU's SDRAM-master interface without inventing
    // renderer traffic. Until M5D supplies the rendering state machine, the
    // GPU is a deterministic idle SDRAM master.
    assign sdram_valid = 1'b0;
    assign sdram_write = 1'b0;
    assign sdram_addr  = 32'h00000000;
    assign sdram_wdata = 32'h00000000;
    assign sdram_wstrb = 4'b0000;

    // Reads are deterministic. CONTROL is write-only and therefore reads
    // as zero. Reserved/unimplemented offsets also read as zero.
    always @(*) begin
        rdata = 32'h00000000;

        if (valid && !write) begin
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

            busy <= 1'b0;
            done <= 1'b0;
        end else if (valid && write) begin
            case (addr)
                REG_CONTROL: begin
                    // CONTROL.START is bit 0 in the low byte.
                    if (wstrb[0] && wdata[0] && !busy) begin
                        active_tilemap_base     <= tilemap_base_reg;
                        active_tiledata_base    <= tiledata_base_reg;
                        active_framebuffer_base <= framebuffer_base_reg;
                        active_map_size         <= map_size_reg;

                        done <= 1'b0;

                        // The architecture defines a zero-width or
                        // zero-height operation as immediately complete
                        // without graphics-memory traffic.
                        if ((map_size_reg[7:0] == 8'd0) ||
                            (map_size_reg[15:8] == 8'd0)) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            // M5B-1 deliberately does not fake renderer
                            // completion. The future rendering state
                            // machine will clear busy and assert done.
                            busy <= 1'b1;
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

endmodule
