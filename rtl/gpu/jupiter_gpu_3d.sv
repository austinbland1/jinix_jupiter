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

    // M10B-2 begins the renderer with the fixed 72-byte vertex fetch.
    //
    // One triangle contains eighteen consecutive aligned 32-bit words.
    // Rasterization is intentionally deferred until the next sub-checkpoint.
    localparam [1:0] FETCH_IDLE     = 2'd0;
    localparam [1:0] FETCH_WORD     = 2'd1;
    localparam [1:0] FETCH_VALIDATE = 2'd2;
    localparam [1:0] FETCH_RASTER   = 2'd3;

    reg [1:0] fetch_state;
    reg [4:0] vertex_word_index;
    reg [31:0] vertex_words [0:17];

    integer vertex_clear_index;

    wire fetched_one_over_w_valid =
        (vertex_words[5]  != 32'h00000000) &&
        (vertex_words[11] != 32'h00000000) &&
        (vertex_words[17] != 32'h00000000);

    // M10B-2c feeds the fetched post-transform X/Y words into the already
    // verified standalone raster engine. Covered samples are observable here
    // but do not generate framebuffer traffic until M10B-2d.
    wire raster_start =
        busy &&
        (fetch_state == FETCH_VALIDATE) &&
        fetched_one_over_w_valid;

    wire        raster_busy;
    wire        raster_done;
    wire        raster_covered_valid;
    wire [15:0] raster_covered_x;
    wire [15:0] raster_covered_y;
    wire [31:0] raster_coverage_count;
    wire [31:0] raster_sample_count;

    wire [31:0] framebuffer_pixel_index =
        (
            raster_covered_y *
            active_target_size[15:0]
        ) +
        raster_covered_x;

    wire [31:0] framebuffer_byte_offset =
        framebuffer_pixel_index << 1;

    wire framebuffer_upper_half =
        framebuffer_pixel_index[0];

    wire framebuffer_write_valid =
        busy &&
        (fetch_state == FETCH_RASTER) &&
        raster_busy &&
        raster_covered_valid;

    wire [31:0] framebuffer_write_addr =
        active_framebuffer_base +
        {
            framebuffer_byte_offset[31:2],
            2'b00
        };

    wire [31:0] framebuffer_write_data =
        framebuffer_upper_half ?
        {
            active_flat_color[15:0],
            16'h0000
        } :
        {
            16'h0000,
            active_flat_color[15:0]
        };

    wire [3:0] framebuffer_write_wstrb =
        framebuffer_upper_half ?
        4'b1100 :
        4'b0011;

    wire raster_covered_ready =
        framebuffer_write_valid &&
        sdram_ready;

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

    // Vertex fetches are aligned 32-bit reads. Covered flat fragments are
    // aligned 32-bit write transactions using byte strobes to select the
    // addressed RGB565 halfword.
    wire vertex_fetch_valid =
        busy &&
        (fetch_state == FETCH_WORD);

    assign sdram_valid =
        vertex_fetch_valid ||
        framebuffer_write_valid;

    assign sdram_write =
        framebuffer_write_valid;

    assign sdram_addr =
        vertex_fetch_valid ?
        (
            active_vertex_base +
            {25'd0, vertex_word_index, 2'b00}
        ) :
        framebuffer_write_valid ?
        framebuffer_write_addr :
        32'h00000000;

    assign sdram_wdata =
        framebuffer_write_valid ?
        framebuffer_write_data :
        32'h00000000;

    assign sdram_wstrb =
        framebuffer_write_valid ?
        framebuffer_write_wstrb :
        4'b0000;

    jupiter_gpu_3d_raster raster
    (
        .clk            (clk),
        .reset          (reset),

        .start          (raster_start),

        .target_width   (active_target_size[15:0]),
        .target_height  (active_target_size[31:16]),

        .v0_x           (vertex_words[0]),
        .v0_y           (vertex_words[1]),
        .v1_x           (vertex_words[6]),
        .v1_y           (vertex_words[7]),
        .v2_x           (vertex_words[12]),
        .v2_y           (vertex_words[13]),

        .busy           (raster_busy),
        .done           (raster_done),

        .covered_ready  (raster_covered_ready),
        .covered_valid  (raster_covered_valid),
        .covered_x      (raster_covered_x),
        .covered_y      (raster_covered_y),

        .coverage_count (raster_coverage_count),
        .sample_count   (raster_sample_count)
    );

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

            busy              <= 1'b0;
            done              <= 1'b0;
            error             <= 1'b0;
            fetch_state       <= FETCH_IDLE;
            vertex_word_index <= 5'd0;

            for (
                vertex_clear_index = 0;
                vertex_clear_index < 18;
                vertex_clear_index = vertex_clear_index + 1
            ) begin
                vertex_words[vertex_clear_index] <= 32'h00000000;
            end
        end else begin
            if (busy) begin
                case (fetch_state)
                    FETCH_WORD: begin
                        if (sdram_ready) begin
                            vertex_words[vertex_word_index] <=
                                sdram_rdata;

                            if (vertex_word_index == 5'd17) begin
                                fetch_state <= FETCH_VALIDATE;
                            end else begin
                                vertex_word_index <=
                                    vertex_word_index + 5'd1;
                            end
                        end
                    end

                    FETCH_VALIDATE: begin
                        if (!fetched_one_over_w_valid) begin
                            busy        <= 1'b0;
                            done        <= 1'b1;
                            error       <= 1'b1;
                            fetch_state <= FETCH_IDLE;
                        end else begin
                            // raster_start is asserted combinationally during
                            // this state, so the child snapshots target/X/Y at
                            // this same clock edge.
                            fetch_state <= FETCH_RASTER;
                        end
                    end

                    FETCH_RASTER: begin
                        if (raster_done) begin
                            busy        <= 1'b0;
                            done        <= 1'b1;
                            fetch_state <= FETCH_IDLE;
                        end
                    end

                    default: begin
                        busy              <= 1'b0;
                        done              <= 1'b1;
                        error             <= 1'b1;
                        fetch_state       <= FETCH_IDLE;
                        vertex_word_index <= 5'd0;
                    end
                endcase
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

                            done              <= 1'b0;
                            error             <= 1'b0;
                            fetch_state       <= FETCH_IDLE;
                            vertex_word_index <= 5'd0;

                            if (command_invalid) begin
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                error <= 1'b1;
                            end else begin
                                busy              <= 1'b1;
                                fetch_state       <= FETCH_WORD;
                                vertex_word_index <= 5'd0;
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
