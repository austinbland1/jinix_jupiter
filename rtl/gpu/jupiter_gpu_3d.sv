module jupiter_gpu_3d
(
    input  wire        clk,
    input  wire        reset,

    // CPU-visible 3D MMIO interface.
    input  wire        valid,
    input  wire        write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire  [3:0] wstrb,

    output reg  [31:0] rdata,
    output wire        ready,

    // 3D external-SDRAM master interface.
    //
    // M10B-1 intentionally produces no rendering traffic. The interface is
    // established now so later rasterization checkpoints do not change the
    // integration boundary.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_STATUS           = 32'h00001144;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_TEXTURE_BASE     = 32'h0000114C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_DEPTH_BASE       = 32'h00001154;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_TEXTURE_SIZE     = 32'h0000115C;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;

    localparam [31:0] SDRAM_START = 32'h10000000;
    localparam [31:0] SDRAM_END   = 32'h17FFFFFF;

    reg [31:0] vertex_base_reg;
    reg [31:0] texture_base_reg;
    reg [31:0] framebuffer_base_reg;
    reg [31:0] depth_base_reg;
    reg [31:0] target_size_reg;
    reg [31:0] texture_size_reg;
    reg [31:0] mode_reg;
    reg [31:0] blend_alpha_reg;
    reg [31:0] flat_color_reg;

    // Accepted START snapshots all configuration for the command.
    reg [31:0] active_vertex_base;
    reg [31:0] active_texture_base;
    reg [31:0] active_framebuffer_base;
    reg [31:0] active_depth_base;
    reg [31:0] active_target_size;
    reg [31:0] active_texture_size;
    reg [31:0] active_mode;
    reg [31:0] active_blend_alpha;
    reg [31:0] active_flat_color;

    reg busy;
    reg done;
    reg error;

    // M10B-1 contains no rasterizer. A valid command occupies the shell for
    // one bounded interval and then completes without SDRAM traffic.
    reg shell_pending;

    wire [15:0] target_width  = target_size_reg[15:0];
    wire [15:0] target_height = target_size_reg[31:16];

    wire [15:0] texture_width  = texture_size_reg[15:0];
    wire [15:0] texture_height = texture_size_reg[31:16];

    wire texture_enabled = mode_reg[0];
    wire depth_enabled   = mode_reg[1];

    wire target_dimensions_valid =
        (target_width  >= 16'd1) &&
        (target_width  <= 16'd1024) &&
        (target_height >= 16'd1) &&
        (target_height <= 16'd1024);

    wire texture_dimensions_valid =
        (texture_width  >= 16'd1) &&
        (texture_width  <= 16'd1024) &&
        (texture_height >= 16'd1) &&
        (texture_height <= 16'd1024);

    wire [31:0] target_pixels =
        target_width * target_height;

    wire [31:0] texture_pixels =
        texture_width * texture_height;

    wire [32:0] target_bytes =
        {1'b0, target_pixels} << 1;

    wire [32:0] texture_bytes =
        {1'b0, texture_pixels} << 1;

    wire [32:0] vertex_last =
        {1'b0, vertex_base_reg} + 33'd71;

    wire [32:0] framebuffer_last =
        {1'b0, framebuffer_base_reg} +
        target_bytes -
        33'd1;

    wire [32:0] depth_last =
        {1'b0, depth_base_reg} +
        target_bytes -
        33'd1;

    wire [32:0] texture_last =
        {1'b0, texture_base_reg} +
        texture_bytes -
        33'd1;

    wire vertex_range_valid =
        (vertex_base_reg[1:0] == 2'b00) &&
        (vertex_base_reg >= SDRAM_START) &&
        (vertex_last <= {1'b0, SDRAM_END});

    wire framebuffer_range_valid =
        target_dimensions_valid &&
        (framebuffer_base_reg[1:0] == 2'b00) &&
        (framebuffer_base_reg >= SDRAM_START) &&
        (framebuffer_last <= {1'b0, SDRAM_END});

    wire depth_range_valid =
        !depth_enabled ||
        (
            target_dimensions_valid &&
            (depth_base_reg[1:0] == 2'b00) &&
            (depth_base_reg >= SDRAM_START) &&
            (depth_last <= {1'b0, SDRAM_END})
        );

    wire texture_range_valid =
        !texture_enabled ||
        (
            texture_dimensions_valid &&
            (texture_base_reg[1:0] == 2'b00) &&
            (texture_base_reg >= SDRAM_START) &&
            (texture_last <= {1'b0, SDRAM_END})
        );

    wire blend_alpha_valid =
        (blend_alpha_reg <= 32'd16);

    // Validation requiring fetched vertex contents, including nonzero 1/W,
    // begins with the M10B-2 vertex-fetch implementation.
    wire command_invalid =
        !target_dimensions_valid ||
        !vertex_range_valid ||
        !framebuffer_range_valid ||
        !depth_range_valid ||
        !texture_range_valid ||
        !blend_alpha_valid;

    function automatic [31:0] masked_write;
        input [31:0] old_value;
        input [31:0] new_value;
        input  [3:0] strobe;
        begin
            masked_write = old_value;

            if (strobe[0])
                masked_write[7:0] = new_value[7:0];

            if (strobe[1])
                masked_write[15:8] = new_value[15:8];

            if (strobe[2])
                masked_write[23:16] = new_value[23:16];

            if (strobe[3])
                masked_write[31:24] = new_value[31:24];
        end
    endfunction

    // The selected GPU MMIO interface inserts no wait states.
    assign ready = valid;

    // M10B-1 establishes the future master interface but intentionally emits
    // no graphics-memory traffic.
    assign sdram_valid = 1'b0;
    assign sdram_write = 1'b0;
    assign sdram_addr  = 32'h00000000;
    assign sdram_wdata = 32'h00000000;
    assign sdram_wstrb = 4'b0000;

    always @(*) begin
        rdata = 32'h00000000;

        if (valid && !write) begin
            case (addr)
                REG_STATUS:
                    rdata = {29'd0, error, done, busy};

                REG_VERTEX_BASE:
                    rdata = vertex_base_reg;

                REG_TEXTURE_BASE:
                    rdata = texture_base_reg;

                REG_FRAMEBUFFER_BASE:
                    rdata = framebuffer_base_reg;

                REG_DEPTH_BASE:
                    rdata = depth_base_reg;

                REG_TARGET_SIZE:
                    rdata = target_size_reg;

                REG_TEXTURE_SIZE:
                    rdata = texture_size_reg;

                REG_MODE:
                    rdata = mode_reg;

                REG_BLEND_ALPHA:
                    rdata = blend_alpha_reg;

                REG_FLAT_COLOR:
                    rdata = flat_color_reg;

                default:
                    rdata = 32'h00000000;
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            vertex_base_reg      <= 32'h00000000;
            texture_base_reg     <= 32'h00000000;
            framebuffer_base_reg <= 32'h00000000;
            depth_base_reg       <= 32'h00000000;
            target_size_reg      <= 32'h00000000;
            texture_size_reg     <= 32'h00000000;
            mode_reg             <= 32'h00000000;
            blend_alpha_reg      <= 32'h00000000;
            flat_color_reg       <= 32'h00000000;

            active_vertex_base      <= 32'h00000000;
            active_texture_base     <= 32'h00000000;
            active_framebuffer_base <= 32'h00000000;
            active_depth_base       <= 32'h00000000;
            active_target_size      <= 32'h00000000;
            active_texture_size     <= 32'h00000000;
            active_mode             <= 32'h00000000;
            active_blend_alpha      <= 32'h00000000;
            active_flat_color       <= 32'h00000000;

            busy          <= 1'b0;
            done          <= 1'b0;
            error         <= 1'b0;
            shell_pending <= 1'b0;
        end else begin
            // A valid M10B-1 shell command completes without SDRAM traffic.
            if (busy && shell_pending) begin
                busy          <= 1'b0;
                done          <= 1'b1;
                shell_pending <= 1'b0;
            end

            if (valid && write) begin
                case (addr)
                    REG_CONTROL: begin
                        if (wstrb[0] && wdata[0] && !busy) begin
                            active_vertex_base      <= vertex_base_reg;
                            active_texture_base     <= texture_base_reg;
                            active_framebuffer_base <= framebuffer_base_reg;
                            active_depth_base       <= depth_base_reg;
                            active_target_size      <= target_size_reg;
                            active_texture_size     <= texture_size_reg;
                            active_mode             <= mode_reg;
                            active_blend_alpha      <= blend_alpha_reg;
                            active_flat_color       <= flat_color_reg;

                            done          <= 1'b0;
                            error         <= 1'b0;
                            shell_pending <= 1'b0;

                            if (command_invalid) begin
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                error <= 1'b1;
                            end else begin
                                busy          <= 1'b1;
                                shell_pending <= 1'b1;
                            end
                        end
                    end

                    REG_STATUS: begin
                        // Read-only.
                    end

                    REG_VERTEX_BASE:
                        vertex_base_reg <=
                            masked_write(
                                vertex_base_reg,
                                wdata,
                                wstrb
                            );

                    REG_TEXTURE_BASE:
                        texture_base_reg <=
                            masked_write(
                                texture_base_reg,
                                wdata,
                                wstrb
                            );

                    REG_FRAMEBUFFER_BASE:
                        framebuffer_base_reg <=
                            masked_write(
                                framebuffer_base_reg,
                                wdata,
                                wstrb
                            );

                    REG_DEPTH_BASE:
                        depth_base_reg <=
                            masked_write(
                                depth_base_reg,
                                wdata,
                                wstrb
                            );

                    REG_TARGET_SIZE:
                        target_size_reg <=
                            masked_write(
                                target_size_reg,
                                wdata,
                                wstrb
                            );

                    REG_TEXTURE_SIZE:
                        texture_size_reg <=
                            masked_write(
                                texture_size_reg,
                                wdata,
                                wstrb
                            );

                    REG_MODE:
                        mode_reg <=
                            masked_write(
                                mode_reg,
                                wdata,
                                wstrb
                            );

                    REG_BLEND_ALPHA:
                        blend_alpha_reg <=
                            masked_write(
                                blend_alpha_reg,
                                wdata,
                                wstrb
                            );

                    REG_FLAT_COLOR:
                        flat_color_reg <=
                            masked_write(
                                flat_color_reg,
                                wdata,
                                wstrb
                            );

                    default: begin
                        // Reserved offsets ignore writes.
                    end
                endcase
            end
        end
    end

endmodule
