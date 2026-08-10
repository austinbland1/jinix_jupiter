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

    localparam [2:0] FRAGMENT_IDLE             = 3'd0;
    localparam [2:0] FRAGMENT_DEPTH_READ       = 3'd1;
    localparam [2:0] FRAGMENT_DEPTH_WRITE      = 3'd2;
    localparam [2:0] FRAGMENT_FRAMEBUFFER      = 3'd3;
    localparam [2:0] FRAGMENT_REJECT           = 3'd4;
    localparam [2:0] FRAGMENT_TEXTURE_READ     = 3'd5;
    localparam [2:0] FRAGMENT_FRAMEBUFFER_READ = 3'd6;

    reg [2:0] fragment_state;
    reg [15:0] fragment_source_color;
    reg [15:0] fragment_output_color;

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
    wire [15:0] raster_covered_z;

    wire signed [31:0] raster_covered_u_over_w;
    wire signed [31:0] raster_covered_v_over_w;
    wire        [31:0] raster_covered_one_over_w;
    wire signed [63:0] raster_covered_u_q16;
    wire signed [63:0] raster_covered_v_q16;

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

    wire active_texture_enabled =
        active_mode[0];

    wire active_depth_enabled =
        active_mode[1];

    wire active_blend_enabled =
        active_mode[2];

    // Reconstructed coordinates are signed Q16.16. M10D-2 selects one
    // nearest sample by taking the integer texel coordinate after the
    // documented perspective reconstruction, then clamps it to the
    // snapshotted texture rectangle.
    wire signed [63:0] texture_u_integer =
        raster_covered_u_q16 >>> 16;

    wire signed [63:0] texture_v_integer =
        raster_covered_v_q16 >>> 16;

    wire [15:0] texture_max_x =
        active_texture_size[15:0] - 16'd1;

    wire [15:0] texture_max_y =
        active_texture_size[31:16] - 16'd1;

    wire [15:0] texture_u_clamped =
        (texture_u_integer < 64'sd0) ?
        16'd0 :
        (
            texture_u_integer >=
            $signed(
                {
                    48'd0,
                    active_texture_size[15:0]
                }
            )
        ) ?
        texture_max_x :
        texture_u_integer[15:0];

    wire [15:0] texture_v_clamped =
        (texture_v_integer < 64'sd0) ?
        16'd0 :
        (
            texture_v_integer >=
            $signed(
                {
                    48'd0,
                    active_texture_size[31:16]
                }
            )
        ) ?
        texture_max_y :
        texture_v_integer[15:0];

    wire [31:0] texture_pixel_index =
        (
            texture_v_clamped *
            active_texture_size[15:0]
        ) +
        texture_u_clamped;

    wire [31:0] texture_byte_offset =
        texture_pixel_index << 1;

    wire texture_upper_half =
        texture_pixel_index[0];

    wire [31:0] texture_access_addr =
        active_texture_base +
        {
            texture_byte_offset[31:2],
            2'b00
        };

    wire [15:0] texture_read_value =
        texture_upper_half ?
        sdram_rdata[31:16] :
        sdram_rdata[15:0];

    wire direct_framebuffer_write_valid =
        busy &&
        (fetch_state == FETCH_RASTER) &&
        raster_busy &&
        raster_covered_valid &&
        !active_depth_enabled &&
        !active_texture_enabled &&
        !active_blend_enabled;

    wire texture_read_valid =
        busy &&
        (fetch_state == FETCH_RASTER) &&
        raster_busy &&
        raster_covered_valid &&
        active_texture_enabled &&
        (fragment_state == FRAGMENT_TEXTURE_READ);

    wire depth_read_valid =
        busy &&
        (fetch_state == FETCH_RASTER) &&
        raster_busy &&
        raster_covered_valid &&
        active_depth_enabled &&
        (fragment_state == FRAGMENT_DEPTH_READ);

    wire depth_write_valid =
        busy &&
        (fetch_state == FETCH_RASTER) &&
        raster_busy &&
        raster_covered_valid &&
        active_depth_enabled &&
        (fragment_state == FRAGMENT_DEPTH_WRITE);

    wire depth_framebuffer_write_valid =
        busy &&
        (fetch_state == FETCH_RASTER) &&
        raster_busy &&
        raster_covered_valid &&
        (
            active_depth_enabled ||
            active_texture_enabled ||
            active_blend_enabled
        ) &&
        (fragment_state == FRAGMENT_FRAMEBUFFER);

    wire framebuffer_write_valid =
        direct_framebuffer_write_valid ||
        depth_framebuffer_write_valid;

    wire framebuffer_read_valid =
        busy &&
        (fetch_state == FETCH_RASTER) &&
        raster_busy &&
        raster_covered_valid &&
        active_blend_enabled &&
        (fragment_state == FRAGMENT_FRAMEBUFFER_READ);

    wire [31:0] framebuffer_write_addr =
        active_framebuffer_base +
        {
            framebuffer_byte_offset[31:2],
            2'b00
        };

    function automatic [15:0] blend_rgb565;
        input [15:0] source_color;
        input [15:0] destination_color;
        input  [4:0] alpha;

        reg [4:0] inverse_alpha;

        reg [10:0] red_accum;
        reg [11:0] green_accum;
        reg [10:0] blue_accum;

        reg [4:0] red_result;
        reg [5:0] green_result;
        reg [4:0] blue_result;

        begin
            inverse_alpha =
                5'd16 - alpha;

            red_accum =
                (
                    source_color[15:11] *
                    alpha
                ) +
                (
                    destination_color[15:11] *
                    inverse_alpha
                ) +
                11'd8;

            green_accum =
                (
                    source_color[10:5] *
                    alpha
                ) +
                (
                    destination_color[10:5] *
                    inverse_alpha
                ) +
                12'd8;

            blue_accum =
                (
                    source_color[4:0] *
                    alpha
                ) +
                (
                    destination_color[4:0] *
                    inverse_alpha
                ) +
                11'd8;

            red_result =
                red_accum >> 4;

            green_result =
                green_accum >> 4;

            blue_result =
                blue_accum >> 4;

            blend_rgb565 =
            {
                red_result,
                green_result,
                blue_result
            };
        end
    endfunction

    wire [15:0] selected_fragment_color =
        active_texture_enabled ?
        fragment_source_color :
        active_flat_color[15:0];

    wire [15:0] framebuffer_read_value =
        framebuffer_upper_half ?
        sdram_rdata[31:16] :
        sdram_rdata[15:0];

    wire [15:0] framebuffer_output_color =
        active_blend_enabled ?
        fragment_output_color :
        selected_fragment_color;

    wire [31:0] framebuffer_write_data =
        framebuffer_upper_half ?
        {
            framebuffer_output_color,
            16'h0000
        } :
        {
            16'h0000,
            framebuffer_output_color
        };

    wire [3:0] framebuffer_write_wstrb =
        framebuffer_upper_half ?
        4'b1100 :
        4'b0011;

    wire [31:0] depth_access_addr =
        active_depth_base +
        {
            framebuffer_byte_offset[31:2],
            2'b00
        };

    wire [15:0] depth_read_value =
        framebuffer_upper_half ?
        sdram_rdata[31:16] :
        sdram_rdata[15:0];

    wire [31:0] depth_write_data =
        framebuffer_upper_half ?
        {
            raster_covered_z,
            16'h0000
        } :
        {
            16'h0000,
            raster_covered_z
        };

    wire [3:0] depth_write_wstrb =
        framebuffer_upper_half ?
        4'b1100 :
        4'b0011;

    wire raster_covered_ready =
        (
            direct_framebuffer_write_valid &&
            sdram_ready
        ) ||
        (
            raster_covered_valid &&
            (fragment_state == FRAGMENT_REJECT)
        ) ||
        (
            depth_framebuffer_write_valid &&
            sdram_ready
        );

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

    // Vertex fetches, depth tests, and texture samples are aligned
    // 32-bit reads. Texture traffic remains read-only. Depth and
    // framebuffer updates remain aligned 32-bit transactions selecting
    // one 16-bit destination with byte strobes.
    wire vertex_fetch_valid =
        busy &&
        (fetch_state == FETCH_WORD);

    assign sdram_valid =
        vertex_fetch_valid ||
        depth_read_valid ||
        depth_write_valid ||
        texture_read_valid ||
        framebuffer_read_valid ||
        framebuffer_write_valid;

    assign sdram_write =
        depth_write_valid ||
        framebuffer_write_valid;

    assign sdram_addr =
        vertex_fetch_valid ?
        (
            active_vertex_base +
            {25'd0, vertex_word_index, 2'b00}
        ) :
        depth_read_valid ?
        depth_access_addr :
        depth_write_valid ?
        depth_access_addr :
        texture_read_valid ?
        texture_access_addr :
        framebuffer_read_valid ?
        framebuffer_write_addr :
        framebuffer_write_valid ?
        framebuffer_write_addr :
        32'h00000000;

    assign sdram_wdata =
        depth_write_valid ?
        depth_write_data :
        framebuffer_write_valid ?
        framebuffer_write_data :
        32'h00000000;

    assign sdram_wstrb =
        depth_write_valid ?
        depth_write_wstrb :
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
        .v0_z           (vertex_words[2][15:0]),
        .v0_u_over_w    (vertex_words[3]),
        .v0_v_over_w    (vertex_words[4]),
        .v0_one_over_w  (vertex_words[5]),

        .v1_x           (vertex_words[6]),
        .v1_y           (vertex_words[7]),
        .v1_z           (vertex_words[8][15:0]),
        .v1_u_over_w    (vertex_words[9]),
        .v1_v_over_w    (vertex_words[10]),
        .v1_one_over_w  (vertex_words[11]),

        .v2_x           (vertex_words[12]),
        .v2_y           (vertex_words[13]),
        .v2_z           (vertex_words[14][15:0]),
        .v2_u_over_w    (vertex_words[15]),
        .v2_v_over_w    (vertex_words[16]),
        .v2_one_over_w  (vertex_words[17]),

        .busy           (raster_busy),
        .done           (raster_done),

        .covered_ready  (raster_covered_ready),
        .covered_valid      (raster_covered_valid),
        .covered_x          (raster_covered_x),
        .covered_y          (raster_covered_y),
        .covered_z          (raster_covered_z),
        .covered_u_over_w   (raster_covered_u_over_w),
        .covered_v_over_w   (raster_covered_v_over_w),
        .covered_one_over_w (raster_covered_one_over_w),
        .covered_u_q16      (raster_covered_u_q16),
        .covered_v_q16      (raster_covered_v_q16),

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

    // Covered fragments remain held by the raster valid/ready
    // interface through the selected transaction sequence.
    //
    // Flat:
    //   framebuffer write
    //
    // Blend:
    //   framebuffer read -> blend -> framebuffer write
    //
    // Texture:
    //   texture read -> framebuffer write
    //
    // Texture + blend:
    //   texture read -> framebuffer read -> blend -> framebuffer write
    //
    // Depth:
    //   depth read -> strict LESS -> depth write -> framebuffer write
    //
    // Combined:
    //   validate texture denominator
    //   depth read / strict LESS
    //   depth write on pass
    //   texture read if enabled
    //   framebuffer read / blend if enabled
    //   framebuffer write
    //
    // A zero interpolated 1/W rejects a texture-enabled fragment before
    // any depth or framebuffer state is modified.
    always @(posedge clk) begin
        if (reset) begin
            fragment_state        <= FRAGMENT_IDLE;
            fragment_source_color <= 16'h0000;
            fragment_output_color <= 16'h0000;
        end else if (
            !busy ||
            (fetch_state != FETCH_RASTER) ||
            (
                !active_depth_enabled &&
                !active_texture_enabled &&
                !active_blend_enabled
            )
        ) begin
            fragment_state <= FRAGMENT_IDLE;
        end else begin
            case (fragment_state)

                FRAGMENT_IDLE: begin
                    if (raster_covered_valid) begin
                        if (
                            active_texture_enabled &&
                            (
                                raster_covered_one_over_w ==
                                32'd0
                            )
                        ) begin
                            fragment_state <=
                                FRAGMENT_REJECT;
                        end else if (active_depth_enabled) begin
                            fragment_state <=
                                FRAGMENT_DEPTH_READ;
                        end else if (active_texture_enabled) begin
                            fragment_state <=
                                FRAGMENT_TEXTURE_READ;
                        end else if (active_blend_enabled) begin
                            fragment_state <=
                                FRAGMENT_FRAMEBUFFER_READ;
                        end
                    end
                end

                FRAGMENT_DEPTH_READ: begin
                    if (sdram_ready) begin
                        if (raster_covered_z < depth_read_value)
                            fragment_state <=
                                FRAGMENT_DEPTH_WRITE;
                        else
                            fragment_state <=
                                FRAGMENT_REJECT;
                    end
                end

                FRAGMENT_DEPTH_WRITE: begin
                    if (sdram_ready) begin
                        if (active_texture_enabled)
                            fragment_state <=
                                FRAGMENT_TEXTURE_READ;
                        else if (active_blend_enabled)
                            fragment_state <=
                                FRAGMENT_FRAMEBUFFER_READ;
                        else
                            fragment_state <=
                                FRAGMENT_FRAMEBUFFER;
                    end
                end

                FRAGMENT_TEXTURE_READ: begin
                    if (sdram_ready) begin
                        fragment_source_color <=
                            texture_read_value;

                        if (active_blend_enabled)
                            fragment_state <=
                                FRAGMENT_FRAMEBUFFER_READ;
                        else
                            fragment_state <=
                                FRAGMENT_FRAMEBUFFER;
                    end
                end

                FRAGMENT_FRAMEBUFFER_READ: begin
                    if (sdram_ready) begin
                        fragment_output_color <=
                            blend_rgb565(
                                selected_fragment_color,
                                framebuffer_read_value,
                                active_blend_alpha[4:0]
                            );

                        fragment_state <=
                            FRAGMENT_FRAMEBUFFER;
                    end
                end

                FRAGMENT_FRAMEBUFFER: begin
                    if (sdram_ready)
                        fragment_state <=
                            FRAGMENT_IDLE;
                end

                FRAGMENT_REJECT: begin
                    fragment_state <=
                        FRAGMENT_IDLE;
                end

                default: begin
                    fragment_state <=
                        FRAGMENT_IDLE;
                end
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
