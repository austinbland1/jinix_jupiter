module jupiter_gpu_3d_raster
(
    input  wire               clk,
    input  wire               reset,

    input  wire               start,

    input  wire        [15:0] target_width,
    input  wire        [15:0] target_height,

    input  wire signed [31:0] v0_x,
    input  wire signed [31:0] v0_y,
    input  wire        [15:0] v0_z,
    input  wire signed [31:0] v0_u_over_w,
    input  wire signed [31:0] v0_v_over_w,
    input  wire        [31:0] v0_one_over_w,

    input  wire signed [31:0] v1_x,
    input  wire signed [31:0] v1_y,
    input  wire        [15:0] v1_z,
    input  wire signed [31:0] v1_u_over_w,
    input  wire signed [31:0] v1_v_over_w,
    input  wire        [31:0] v1_one_over_w,

    input  wire signed [31:0] v2_x,
    input  wire signed [31:0] v2_y,
    input  wire        [15:0] v2_z,
    input  wire signed [31:0] v2_u_over_w,
    input  wire signed [31:0] v2_v_over_w,
    input  wire        [31:0] v2_one_over_w,

    output reg                busy,
    output reg                done,

    // Covered-sample valid/ready handshake. A covered sample and its
    // coordinates remain stable until covered_ready is observed.
    input  wire               covered_ready,
    output reg                covered_valid,
    output reg         [15:0] covered_x,
    output reg         [15:0] covered_y,
    output reg         [15:0] covered_z,

    output reg signed [31:0] covered_u_over_w,
    output reg signed [31:0] covered_v_over_w,
    output reg        [31:0] covered_one_over_w,

    // Perspective reconstructed Q16.16 coordinates. These remain
    // unclamped until the texture stage applies the selected rectangle.
    output reg signed [63:0] covered_u_q16,
    output reg signed [63:0] covered_v_q16,

    // Deterministic command-local counters.
    output reg         [31:0] coverage_count,
    output reg         [31:0] sample_count
);

    localparam [2:0] RASTER_IDLE   = 3'd0;
    localparam [2:0] RASTER_SETUP  = 3'd1;
    localparam [2:0] RASTER_SCAN   = 3'd2;
    localparam [2:0] RASTER_INTERP = 3'd3;
    localparam [2:0] RASTER_DIVIDE = 3'd4;
    localparam [2:0] RASTER_PERSPECTIVE_SETUP = 3'd6;
    localparam [2:0] RASTER_EMIT   = 3'd5;

    localparam [1:0] INTERP_DEPTH = 2'd0;
    localparam [1:0] INTERP_U     = 2'd1;
    localparam [1:0] INTERP_V     = 2'd2;
    localparam [1:0] INTERP_OOW   = 2'd3;

    localparam [1:0] DIVIDE_BARYCENTRIC    = 2'd0;
    localparam [1:0] DIVIDE_PERSPECTIVE_U  = 2'd1;
    localparam [1:0] DIVIDE_PERSPECTIVE_V  = 2'd2;

    reg [2:0] raster_state;

    reg [15:0] active_target_width;
    reg [15:0] active_target_height;

    reg signed [31:0] active_v0_x;
    reg signed [31:0] active_v0_y;
    reg        [15:0] active_v0_z;
    reg signed [31:0] active_v0_u_over_w;
    reg signed [31:0] active_v0_v_over_w;
    reg        [31:0] active_v0_one_over_w;

    reg signed [31:0] active_v1_x;
    reg signed [31:0] active_v1_y;
    reg        [15:0] active_v1_z;
    reg signed [31:0] active_v1_u_over_w;
    reg signed [31:0] active_v1_v_over_w;
    reg        [31:0] active_v1_one_over_w;

    reg signed [31:0] active_v2_x;
    reg signed [31:0] active_v2_y;
    reg        [15:0] active_v2_z;
    reg signed [31:0] active_v2_u_over_w;
    reg signed [31:0] active_v2_v_over_w;
    reg        [31:0] active_v2_one_over_w;

    reg [15:0] raster_x;
    reg [15:0] raster_y;

    // Retained after completion for deterministic verification.
    reg [15:0] scan_min_x;
    reg [15:0] scan_min_y;
    reg [15:0] scan_max_x;
    reg [15:0] scan_max_y;

    // Shared barycentric interpolation engine.
    //
    // One attribute is evaluated per clock:
    //   depth -> U/W -> V/W -> 1/W.
    //
    // The three vertex products remain parallel, but those three
    // multipliers are reused across all four attributes.
    reg [1:0] interp_attr;

    reg        [15:0] interp_depth_result;
    reg signed [31:0] interp_u_result;
    reg signed [31:0] interp_v_result;
    reg        [31:0] interp_oow_result;

    // Sequential 101/67-bit restoring divider.
    //
    // The previous hardware implementation unrolled all 32 quotient-bit
    // steps combinationally. TimeQuest measured that path at more than
    // 260 ns. This engine performs exactly one compare/subtract step per
    // clock while preserving the identical quotient.
    reg [100:0] divider_remainder;
    reg [100:0] divider_shifted_denominator;
    reg  [47:0] divider_quotient;
    reg   [5:0] divider_bit_index;

    reg divider_negative;
    reg divider_domain_valid;

    reg [1:0] divider_mode;

    reg signed [63:0] perspective_u_result;
    reg signed [63:0] perspective_v_result;

    // --------------------------------------------------------
    // Signed fixed-point helpers
    // --------------------------------------------------------

    function automatic signed [31:0] min3;
        input signed [31:0] a;
        input signed [31:0] b;
        input signed [31:0] c;

        reg signed [31:0] m;

        begin
            m = a;

            if (b < m)
                m = b;

            if (c < m)
                m = c;

            min3 = m;
        end
    endfunction

    function automatic signed [31:0] max3;
        input signed [31:0] a;
        input signed [31:0] b;
        input signed [31:0] c;

        reg signed [31:0] m;

        begin
            m = a;

            if (b > m)
                m = b;

            if (c > m)
                m = c;

            max3 = m;
        end
    endfunction

    // Edge convention:
    //
    //     E(A,B,P) =
    //         (Bx-Ax)*(Py-Ay) -
    //         (By-Ay)*(Px-Ax)
    //
    // A counter-clockwise triangle therefore has positive signed area and
    // interior samples have nonnegative values on all three directed edges.
    //
    // Coordinates are signed Q16.16. A difference requires 33 signed bits.
    // Each product requires 66 bits and their subtraction requires 67 bits.
    function automatic signed [66:0] edge_value;
        input signed [31:0] ax;
        input signed [31:0] ay;
        input signed [31:0] bx;
        input signed [31:0] by;
        input signed [31:0] px;
        input signed [31:0] py;

        reg signed [32:0] abx;
        reg signed [32:0] aby;
        reg signed [32:0] apx;
        reg signed [32:0] apy;

        reg signed [65:0] product0;
        reg signed [65:0] product1;

        begin
            abx =
                $signed({bx[31], bx}) -
                $signed({ax[31], ax});

            aby =
                $signed({by[31], by}) -
                $signed({ay[31], ay});

            apx =
                $signed({px[31], px}) -
                $signed({ax[31], ax});

            apy =
                $signed({py[31], py}) -
                $signed({ay[31], ay});

            product0 = abx * apy;
            product1 = aby * apx;

            edge_value =
                $signed({product0[65], product0}) -
                $signed({product1[65], product1});
        end
    endfunction

    // With the positive-edge convention above, this deterministic ownership
    // predicate assigns every exact shared-edge sample to one orientation of
    // that directed edge and not to its reverse.
    function automatic edge_is_top_left;
        input signed [31:0] ax;
        input signed [31:0] ay;
        input signed [31:0] bx;
        input signed [31:0] by;

        reg signed [32:0] dx;
        reg signed [32:0] dy;

        begin
            dx =
                $signed({bx[31], bx}) -
                $signed({ax[31], ax});

            dy =
                $signed({by[31], by}) -
                $signed({ay[31], ay});

            edge_is_top_left =
                (dy > 33'sd0) ||
                (
                    (dy == 33'sd0) &&
                    (dx < 33'sd0)
                );
        end
    endfunction

    // Exact bounded restoring divider for barycentric interpolation.
    //
    // Covered-sample barycentric weights are nonnegative and sum to
    // triangle area. Therefore the interpolation quotient is bounded by
    // the 32-bit vertex attribute range. Computing quotient bits 31..0
    // is sufficient while retaining exact integer truncation semantics.
    //
    // This intentionally avoids a Verilog '/' wider than Quartus 17's
    // 64-bit lpm_divide operand limit.
    function automatic [31:0] divide_unsigned_101_by_67_q32;
        input [100:0] numerator;
        input  [66:0] denominator;

        reg [100:0] remainder;
        reg [100:0] shifted_denominator;
        reg  [31:0] quotient;
        integer bit_index;

        begin
            remainder = numerator;
            shifted_denominator = 101'd0;
            quotient = 32'd0;

            if (denominator != 67'd0) begin
                shifted_denominator =
                    {34'd0, denominator} << 31;

                for (
                    bit_index = 31;
                    bit_index >= 0;
                    bit_index = bit_index - 1
                ) begin
                    if (remainder >= shifted_denominator) begin
                        remainder =
                            remainder -
                            shifted_denominator;

                        quotient[bit_index] =
                            1'b1;
                    end

                    shifted_denominator =
                        shifted_denominator >> 1;
                end
            end

            divide_unsigned_101_by_67_q32 =
                quotient;
        end
    endfunction

    // Signed numerator, positive denominator. Magnitude division followed
    // by two's-complement sign restoration exactly matches truncation
    // toward zero for the valid barycentric domain.
    function automatic signed [31:0] divide_signed_101_by_67_q32;
        input signed [100:0] numerator;
        input        [66:0] denominator;

        reg [100:0] numerator_magnitude;
        reg  [31:0] quotient_magnitude;

        begin
            if (numerator[100])
                numerator_magnitude =
                    (~numerator) + 101'd1;
            else
                numerator_magnitude =
                    numerator;

            quotient_magnitude =
                divide_unsigned_101_by_67_q32(
                    numerator_magnitude,
                    denominator
                );

            if (numerator[100])
                divide_signed_101_by_67_q32 =
                    (~quotient_magnitude) + 32'd1;
            else
                divide_signed_101_by_67_q32 =
                    quotient_magnitude;
        end
    endfunction

    // Signed Q16.16 barycentric interpolation. Edge weights are
    // nonnegative for a covered CCW sample. Signed division therefore
    // provides the selected deterministic truncation toward zero.
    function automatic signed [31:0] interpolate_signed_q16;
        input signed [31:0] value0;
        input signed [31:0] value1;
        input signed [31:0] value2;
        input signed [66:0] weight0;
        input signed [66:0] weight1;
        input signed [66:0] weight2;
        input signed [66:0] area;

        reg signed [98:0] product0;
        reg signed [98:0] product1;
        reg signed [98:0] product2;
        reg signed [100:0] numerator;
        reg signed [31:0] quotient;

        begin
            product0 = 99'sd0;
            product1 = 99'sd0;
            product2 = 99'sd0;
            numerator = 101'sd0;
            quotient = 32'sd0;

            if (
                (area > 67'sd0) &&
                (weight0 >= 67'sd0) &&
                (weight1 >= 67'sd0) &&
                (weight2 >= 67'sd0)
            ) begin
                product0 =
                    $signed(value0) *
                    $signed(weight0);

                product1 =
                    $signed(value1) *
                    $signed(weight1);

                product2 =
                    $signed(value2) *
                    $signed(weight2);

                numerator =
                    {{2{product0[98]}}, product0} +
                    {{2{product1[98]}}, product1} +
                    {{2{product2[98]}}, product2};

                quotient =
                    divide_signed_101_by_67_q32(
                        numerator,
                        area[66:0]
                    );

                interpolate_signed_q16 =
                    quotient[31:0];
            end else begin
                interpolate_signed_q16 =
                    32'sd0;
            end
        end
    endfunction

    // Unsigned Q16.16 barycentric interpolation for 1/W.
    function automatic [31:0] interpolate_unsigned_q16;
        input        [31:0] value0;
        input        [31:0] value1;
        input        [31:0] value2;
        input signed [66:0] weight0;
        input signed [66:0] weight1;
        input signed [66:0] weight2;
        input signed [66:0] area;

        reg [98:0] product0;
        reg [98:0] product1;
        reg [98:0] product2;
        reg [100:0] numerator;
        reg [31:0] quotient;

        begin
            product0 = 99'd0;
            product1 = 99'd0;
            product2 = 99'd0;
            numerator = 101'd0;
            quotient = 32'd0;

            if (
                (area > 67'sd0) &&
                (weight0 >= 67'sd0) &&
                (weight1 >= 67'sd0) &&
                (weight2 >= 67'sd0)
            ) begin
                product0 =
                    value0 *
                    $unsigned(weight0);

                product1 =
                    value1 *
                    $unsigned(weight1);

                product2 =
                    value2 *
                    $unsigned(weight2);

                numerator =
                    {2'b00, product0} +
                    {2'b00, product1} +
                    {2'b00, product2};

                quotient =
                    divide_unsigned_101_by_67_q32(
                        numerator,
                        area[66:0]
                    );

                interpolate_unsigned_q16 =
                    quotient[31:0];
            end else begin
                interpolate_unsigned_q16 =
                    32'd0;
            end
        end
    endfunction

    // Screen-linear U0.16 depth interpolation.
    //
    // For the directed-edge convention used below:
    //
    //   vertex 0 weight = edge(v1,v2,p)
    //   vertex 1 weight = edge(v2,v0,p)
    //   vertex 2 weight = edge(v0,v1,p)
    //
    // Covered samples have nonnegative weights and positive area.
    // Division truncates toward zero; because all operands are unsigned
    // in this path, that is deterministic floor division.
    function automatic [15:0] interpolate_depth;
        input        [15:0] z0;
        input        [15:0] z1;
        input        [15:0] z2;
        input signed [66:0] weight0;
        input signed [66:0] weight1;
        input signed [66:0] weight2;
        input signed [66:0] area;

        reg [82:0] product0;
        reg [82:0] product1;
        reg [82:0] product2;
        reg [84:0] numerator;
        reg [31:0] quotient;

        begin
            product0 = 83'd0;
            product1 = 83'd0;
            product2 = 83'd0;
            numerator = 85'd0;
            quotient = 32'd0;

            if (
                (area > 67'sd0) &&
                (weight0 >= 67'sd0) &&
                (weight1 >= 67'sd0) &&
                (weight2 >= 67'sd0)
            ) begin
                product0 =
                    z0 * $unsigned(weight0);

                product1 =
                    z1 * $unsigned(weight1);

                product2 =
                    z2 * $unsigned(weight2);

                numerator =
                    {2'b00, product0} +
                    {2'b00, product1} +
                    {2'b00, product2};

                quotient =
                    divide_unsigned_101_by_67_q32(
                        {16'd0, numerator},
                        area[66:0]
                    );

                if (quotient > 32'd65535)
                    interpolate_depth = 16'hFFFF;
                else
                    interpolate_depth = quotient[15:0];
            end else begin
                interpolate_depth = 16'h0000;
            end
        end
    endfunction

    // --------------------------------------------------------
    // Integer bounding box
    // --------------------------------------------------------

    wire signed [31:0] v0_x_floor =
        $signed(active_v0_x) >>> 16;

    wire signed [31:0] v0_y_floor =
        $signed(active_v0_y) >>> 16;

    wire signed [31:0] v1_x_floor =
        $signed(active_v1_x) >>> 16;

    wire signed [31:0] v1_y_floor =
        $signed(active_v1_y) >>> 16;

    wire signed [31:0] v2_x_floor =
        $signed(active_v2_x) >>> 16;

    wire signed [31:0] v2_y_floor =
        $signed(active_v2_y) >>> 16;

    wire signed [31:0] bbox_min_x_raw =
        min3(
            v0_x_floor,
            v1_x_floor,
            v2_x_floor
        );

    wire signed [31:0] bbox_min_y_raw =
        min3(
            v0_y_floor,
            v1_y_floor,
            v2_y_floor
        );

    wire signed [31:0] bbox_max_x_raw =
        max3(
            v0_x_floor,
            v1_x_floor,
            v2_x_floor
        );

    wire signed [31:0] bbox_max_y_raw =
        max3(
            v0_y_floor,
            v1_y_floor,
            v2_y_floor
        );

    wire signed [31:0] target_last_x =
        $signed({16'd0, active_target_width}) -
        32'sd1;

    wire signed [31:0] target_last_y =
        $signed({16'd0, active_target_height}) -
        32'sd1;

    wire target_empty =
        (active_target_width == 16'd0) ||
        (active_target_height == 16'd0);

    wire bbox_outside =
        (bbox_max_x_raw < 32'sd0) ||
        (bbox_max_y_raw < 32'sd0) ||
        (bbox_min_x_raw > target_last_x) ||
        (bbox_min_y_raw > target_last_y);

    wire [15:0] clipped_min_x =
        (bbox_min_x_raw < 32'sd0) ?
        16'd0 :
        bbox_min_x_raw[15:0];

    wire [15:0] clipped_min_y =
        (bbox_min_y_raw < 32'sd0) ?
        16'd0 :
        bbox_min_y_raw[15:0];

    wire [15:0] clipped_max_x =
        (bbox_max_x_raw > target_last_x) ?
        (active_target_width - 16'd1) :
        bbox_max_x_raw[15:0];

    wire [15:0] clipped_max_y =
        (bbox_max_y_raw > target_last_y) ?
        (active_target_height - 16'd1) :
        bbox_max_y_raw[15:0];

    // --------------------------------------------------------
    // Pixel-center edge evaluation
    // --------------------------------------------------------

    wire signed [31:0] sample_x_q16 =
        $signed({raster_x, 16'h8000});

    wire signed [31:0] sample_y_q16 =
        $signed({raster_y, 16'h8000});

    wire signed [66:0] triangle_area =
        edge_value(
            active_v0_x,
            active_v0_y,
            active_v1_x,
            active_v1_y,
            active_v2_x,
            active_v2_y
        );

    wire signed [66:0] edge0 =
        edge_value(
            active_v0_x,
            active_v0_y,
            active_v1_x,
            active_v1_y,
            sample_x_q16,
            sample_y_q16
        );

    wire signed [66:0] edge1 =
        edge_value(
            active_v1_x,
            active_v1_y,
            active_v2_x,
            active_v2_y,
            sample_x_q16,
            sample_y_q16
        );

    wire signed [66:0] edge2 =
        edge_value(
            active_v2_x,
            active_v2_y,
            active_v0_x,
            active_v0_y,
            sample_x_q16,
            sample_y_q16
        );

    wire edge0_top_left =
        edge_is_top_left(
            active_v0_x,
            active_v0_y,
            active_v1_x,
            active_v1_y
        );

    wire edge1_top_left =
        edge_is_top_left(
            active_v1_x,
            active_v1_y,
            active_v2_x,
            active_v2_y
        );

    wire edge2_top_left =
        edge_is_top_left(
            active_v2_x,
            active_v2_y,
            active_v0_x,
            active_v0_y
        );

    wire edge0_pass =
        (edge0 > 67'sd0) ||
        (
            (edge0 == 67'sd0) &&
            edge0_top_left
        );

    wire edge1_pass =
        (edge1 > 67'sd0) ||
        (
            (edge1 == 67'sd0) &&
            edge1_top_left
        );

    wire edge2_pass =
        (edge2 > 67'sd0) ||
        (
            (edge2 == 67'sd0) &&
            edge2_top_left
        );

    wire sample_covered =
        (triangle_area > 67'sd0) &&
        edge0_pass &&
        edge1_pass &&
        edge2_pass;

    // --------------------------------------------------------
    // Shared barycentric attribute datapath
    // --------------------------------------------------------
    //
    // The original implementation evaluated depth, U/W, V/W and 1/W
    // concurrently. That created twelve wide attribute multipliers and
    // three copies of the restoring divider.
    //
    // This datapath evaluates one attribute per cycle and therefore
    // contains only three wide multipliers and one divider while keeping
    // the exact fixed-point arithmetic and truncation rules.

    reg [31:0] interp_value0_magnitude;
    reg [31:0] interp_value1_magnitude;
    reg [31:0] interp_value2_magnitude;

    reg interp_value0_negative;
    reg interp_value1_negative;
    reg interp_value2_negative;

    always @* begin
        interp_value0_magnitude = 32'd0;
        interp_value1_magnitude = 32'd0;
        interp_value2_magnitude = 32'd0;

        interp_value0_negative = 1'b0;
        interp_value1_negative = 1'b0;
        interp_value2_negative = 1'b0;

        case (interp_attr)
            INTERP_DEPTH: begin
                interp_value0_magnitude =
                    {16'd0, active_v0_z};

                interp_value1_magnitude =
                    {16'd0, active_v1_z};

                interp_value2_magnitude =
                    {16'd0, active_v2_z};
            end

            INTERP_U: begin
                interp_value0_negative =
                    active_v0_u_over_w[31];

                interp_value1_negative =
                    active_v1_u_over_w[31];

                interp_value2_negative =
                    active_v2_u_over_w[31];

                interp_value0_magnitude =
                    active_v0_u_over_w[31] ?
                    ((~$unsigned(active_v0_u_over_w)) + 32'd1) :
                    $unsigned(active_v0_u_over_w);

                interp_value1_magnitude =
                    active_v1_u_over_w[31] ?
                    ((~$unsigned(active_v1_u_over_w)) + 32'd1) :
                    $unsigned(active_v1_u_over_w);

                interp_value2_magnitude =
                    active_v2_u_over_w[31] ?
                    ((~$unsigned(active_v2_u_over_w)) + 32'd1) :
                    $unsigned(active_v2_u_over_w);
            end

            INTERP_V: begin
                interp_value0_negative =
                    active_v0_v_over_w[31];

                interp_value1_negative =
                    active_v1_v_over_w[31];

                interp_value2_negative =
                    active_v2_v_over_w[31];

                interp_value0_magnitude =
                    active_v0_v_over_w[31] ?
                    ((~$unsigned(active_v0_v_over_w)) + 32'd1) :
                    $unsigned(active_v0_v_over_w);

                interp_value1_magnitude =
                    active_v1_v_over_w[31] ?
                    ((~$unsigned(active_v1_v_over_w)) + 32'd1) :
                    $unsigned(active_v1_v_over_w);

                interp_value2_magnitude =
                    active_v2_v_over_w[31] ?
                    ((~$unsigned(active_v2_v_over_w)) + 32'd1) :
                    $unsigned(active_v2_v_over_w);
            end

            INTERP_OOW: begin
                interp_value0_magnitude =
                    active_v0_one_over_w;

                interp_value1_magnitude =
                    active_v1_one_over_w;

                interp_value2_magnitude =
                    active_v2_one_over_w;
            end

            default: begin
                interp_value0_magnitude = 32'd0;
                interp_value1_magnitude = 32'd0;
                interp_value2_magnitude = 32'd0;

                interp_value0_negative = 1'b0;
                interp_value1_negative = 1'b0;
                interp_value2_negative = 1'b0;
            end
        endcase
    end

    // Vertex 0, 1 and 2 barycentric weights respectively.
    wire [66:0] interp_weight0 =
        edge1[66:0];

    wire [66:0] interp_weight1 =
        edge2[66:0];

    wire [66:0] interp_weight2 =
        edge0[66:0];

    // These are the only three barycentric attribute multipliers in the
    // shared datapath.
    wire [98:0] interp_product0 =
        interp_value0_magnitude *
        interp_weight0;

    wire [98:0] interp_product1 =
        interp_value1_magnitude *
        interp_weight1;

    wire [98:0] interp_product2 =
        interp_value2_magnitude *
        interp_weight2;

    wire signed [100:0] interp_product0_extended =
        $signed({2'b00, interp_product0});

    wire signed [100:0] interp_product1_extended =
        $signed({2'b00, interp_product1});

    wire signed [100:0] interp_product2_extended =
        $signed({2'b00, interp_product2});

    wire signed [100:0] interp_term0 =
        interp_value0_negative ?
        -interp_product0_extended :
        interp_product0_extended;

    wire signed [100:0] interp_term1 =
        interp_value1_negative ?
        -interp_product1_extended :
        interp_product1_extended;

    wire signed [100:0] interp_term2 =
        interp_value2_negative ?
        -interp_product2_extended :
        interp_product2_extended;

    wire signed [100:0] interp_numerator =
        interp_term0 +
        interp_term1 +
        interp_term2;

    wire interp_domain_valid =
        (triangle_area > 67'sd0) &&
        (edge0 >= 67'sd0) &&
        (edge1 >= 67'sd0) &&
        (edge2 >= 67'sd0);

    wire [100:0] interp_numerator_magnitude =
        interp_numerator[100] ?
        ((~$unsigned(interp_numerator)) + 101'd1) :
        $unsigned(interp_numerator);

    // One restoring-divider step is performed during each
    // RASTER_DIVIDE clock.
    wire divider_take =
        (divider_remainder >= divider_shifted_denominator);

    // On the final iteration divider_bit_index is zero. Bits 31:1 have
    // already been accumulated in divider_quotient, while bit zero is
    // represented by the current compare result.
    wire [31:0] divider_final_magnitude =
        {
            divider_quotient[31:1],
            divider_take
        };

    wire [31:0] divider_final_signed_bits =
        divider_negative ?
        ((~divider_final_magnitude) + 32'd1) :
        divider_final_magnitude;


    // Perspective reconstruction shares the sequential restoring divider.
    wire signed [31:0] perspective_value =
        (divider_mode == DIVIDE_PERSPECTIVE_V) ?
        interp_v_result :
        interp_u_result;

    wire [31:0] perspective_value_magnitude =
        perspective_value[31] ?
        ((~$unsigned(perspective_value)) + 32'd1) :
        $unsigned(perspective_value);

    wire [47:0] perspective_numerator_magnitude =
        {
            perspective_value_magnitude,
            16'd0
        };

    wire [47:0] divider_final_perspective_magnitude =
        {
            divider_quotient[47:1],
            divider_take
        };

    wire [47:0] divider_final_perspective_signed_bits =
        divider_negative ?
        ((~divider_final_perspective_magnitude) + 48'd1) :
        divider_final_perspective_magnitude;

    wire signed [63:0] divider_final_perspective_signed =
        $signed(
            {
                {16{divider_final_perspective_signed_bits[47]}},
                divider_final_perspective_signed_bits
            }
        );

    // --------------------------------------------------------
    // Raster state machine
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (reset) begin
            raster_state <= RASTER_IDLE;

            active_target_width  <= 16'd0;
            active_target_height <= 16'd0;

            active_v0_x <= 32'sd0;
            active_v0_y <= 32'sd0;
            active_v0_z <= 16'd0;
            active_v0_u_over_w <= 32'sd0;
            active_v0_v_over_w <= 32'sd0;
            active_v0_one_over_w <= 32'd0;

            active_v1_x <= 32'sd0;
            active_v1_y <= 32'sd0;
            active_v1_z <= 16'd0;
            active_v1_u_over_w <= 32'sd0;
            active_v1_v_over_w <= 32'sd0;
            active_v1_one_over_w <= 32'd0;

            active_v2_x <= 32'sd0;
            active_v2_y <= 32'sd0;
            active_v2_z <= 16'd0;
            active_v2_u_over_w <= 32'sd0;
            active_v2_v_over_w <= 32'sd0;
            active_v2_one_over_w <= 32'd0;

            raster_x <= 16'd0;
            raster_y <= 16'd0;

            scan_min_x <= 16'd0;
            scan_min_y <= 16'd0;
            scan_max_x <= 16'd0;
            scan_max_y <= 16'd0;

            busy <= 1'b0;
            done <= 1'b0;

            covered_valid      <= 1'b0;
            covered_x          <= 16'd0;
            covered_y          <= 16'd0;
            covered_z          <= 16'd0;
            covered_u_over_w   <= 32'sd0;
            covered_v_over_w   <= 32'sd0;
            covered_one_over_w <= 32'd0;
            covered_u_q16      <= 64'sd0;
            covered_v_q16      <= 64'sd0;

            coverage_count <= 32'd0;
            sample_count   <= 32'd0;

            interp_attr <= INTERP_DEPTH;

            interp_depth_result <= 16'd0;
            interp_u_result     <= 32'sd0;
            interp_v_result     <= 32'sd0;
            interp_oow_result   <= 32'd0;

            divider_remainder           <= 101'd0;
            divider_shifted_denominator <= 101'd0;
            divider_quotient            <= 48'd0;
            divider_bit_index           <= 6'd0;
            divider_negative            <= 1'b0;
            divider_domain_valid        <= 1'b0;
            divider_mode                <= DIVIDE_BARYCENTRIC;

            perspective_u_result <= 64'sd0;
            perspective_v_result <= 64'sd0;
        end else begin
            done <= 1'b0;

            case (raster_state)
                RASTER_IDLE: begin
                    covered_valid <= 1'b0;

                    if (start && !busy) begin
                        active_target_width  <= target_width;
                        active_target_height <= target_height;

                        active_v0_x <= v0_x;
                        active_v0_y <= v0_y;
                        active_v0_z <= v0_z;
                        active_v0_u_over_w <= v0_u_over_w;
                        active_v0_v_over_w <= v0_v_over_w;
                        active_v0_one_over_w <= v0_one_over_w;

                        active_v1_x <= v1_x;
                        active_v1_y <= v1_y;
                        active_v1_z <= v1_z;
                        active_v1_u_over_w <= v1_u_over_w;
                        active_v1_v_over_w <= v1_v_over_w;
                        active_v1_one_over_w <= v1_one_over_w;

                        active_v2_x <= v2_x;
                        active_v2_y <= v2_y;
                        active_v2_z <= v2_z;
                        active_v2_u_over_w <= v2_u_over_w;
                        active_v2_v_over_w <= v2_v_over_w;
                        active_v2_one_over_w <= v2_one_over_w;

                        raster_x <= 16'd0;
                        raster_y <= 16'd0;

                        scan_min_x <= 16'd0;
                        scan_min_y <= 16'd0;
                        scan_max_x <= 16'd0;
                        scan_max_y <= 16'd0;

                        coverage_count <= 32'd0;
                        sample_count   <= 32'd0;

                        busy         <= 1'b1;
                        raster_state <= RASTER_SETUP;
                    end
                end

                RASTER_SETUP: begin
                    covered_valid <= 1'b0;

                    if (
                        target_empty ||
                        (triangle_area <= 67'sd0) ||
                        bbox_outside
                    ) begin
                        busy         <= 1'b0;
                        done         <= 1'b1;
                        raster_state <= RASTER_IDLE;
                    end else begin
                        scan_min_x <= clipped_min_x;
                        scan_min_y <= clipped_min_y;
                        scan_max_x <= clipped_max_x;
                        scan_max_y <= clipped_max_y;

                        raster_x <= clipped_min_x;
                        raster_y <= clipped_min_y;

                        raster_state <= RASTER_SCAN;
                    end
                end

                RASTER_SCAN: begin
                    if (covered_valid) begin
                        // Hold the accepted sample coordinates and all
                        // command-local scan state until the consumer
                        // completes the fragment transaction.
                        if (covered_ready) begin
                            covered_valid <= 1'b0;

                            sample_count <=
                                sample_count + 32'd1;

                            coverage_count <=
                                coverage_count + 32'd1;

                            if (
                                (raster_x == scan_max_x) &&
                                (raster_y == scan_max_y)
                            ) begin
                                busy         <= 1'b0;
                                done         <= 1'b1;
                                raster_state <= RASTER_IDLE;
                            end else if (raster_x == scan_max_x) begin
                                raster_x <= scan_min_x;
                                raster_y <= raster_y + 16'd1;
                            end else begin
                                raster_x <= raster_x + 16'd1;
                            end
                        end
                    end else if (sample_covered) begin
                        // Hold raster_x/y while the four attributes are
                        // generated over four clocks by the shared
                        // interpolation datapath.
                        interp_attr <= INTERP_DEPTH;
                        raster_state <= RASTER_INTERP;
                    end else begin
                        sample_count <=
                            sample_count + 32'd1;

                        if (
                            (raster_x == scan_max_x) &&
                            (raster_y == scan_max_y)
                        ) begin
                            busy         <= 1'b0;
                            done         <= 1'b1;
                            raster_state <= RASTER_IDLE;
                        end else if (raster_x == scan_max_x) begin
                            raster_x <= scan_min_x;
                            raster_y <= raster_y + 16'd1;
                        end else begin
                            raster_x <= raster_x + 16'd1;
                        end
                    end
                end

                RASTER_INTERP: begin
                    covered_valid <= 1'b0;

                    // Register the entire multiply/add result before
                    // beginning division. This creates a timing boundary
                    // between barycentric arithmetic and the iterative
                    // divider.
                    divider_mode <=
                        DIVIDE_BARYCENTRIC;

                    divider_remainder <=
                        interp_numerator_magnitude;

                    divider_shifted_denominator <=
                        {34'd0, triangle_area[66:0]} << 31;

                    divider_quotient <= 48'd0;
                    divider_bit_index <= 6'd31;

                    divider_negative <=
                        interp_numerator[100];

                    divider_domain_valid <=
                        interp_domain_valid;

                    raster_state <= RASTER_DIVIDE;
                end

                RASTER_DIVIDE: begin
                    covered_valid <= 1'b0;

                    if (divider_take) begin
                        divider_remainder <=
                            divider_remainder -
                            divider_shifted_denominator;

                        divider_quotient[
                            divider_bit_index
                        ] <= 1'b1;
                    end

                    divider_shifted_denominator <=
                        divider_shifted_denominator >> 1;

                    if (divider_bit_index == 6'd0) begin

                        if (
                            divider_mode ==
                            DIVIDE_BARYCENTRIC
                        ) begin

                            case (interp_attr)

                                INTERP_DEPTH: begin
                                    if (!divider_domain_valid)
                                        interp_depth_result <=
                                            16'd0;
                                    else if (
                                        divider_final_magnitude >
                                        32'd65535
                                    )
                                        interp_depth_result <=
                                            16'hFFFF;
                                    else
                                        interp_depth_result <=
                                            divider_final_magnitude[15:0];

                                    interp_attr <= INTERP_U;
                                    raster_state <= RASTER_INTERP;
                                end

                                INTERP_U: begin
                                    if (!divider_domain_valid)
                                        interp_u_result <=
                                            32'sd0;
                                    else
                                        interp_u_result <=
                                            $signed(
                                                divider_final_signed_bits
                                            );

                                    interp_attr <= INTERP_V;
                                    raster_state <= RASTER_INTERP;
                                end

                                INTERP_V: begin
                                    if (!divider_domain_valid)
                                        interp_v_result <=
                                            32'sd0;
                                    else
                                        interp_v_result <=
                                            $signed(
                                                divider_final_signed_bits
                                            );

                                    interp_attr <= INTERP_OOW;
                                    raster_state <= RASTER_INTERP;
                                end

                                INTERP_OOW: begin
                                    if (!divider_domain_valid)
                                        interp_oow_result <=
                                            32'd0;
                                    else
                                        interp_oow_result <=
                                            divider_final_magnitude;

                                    divider_mode <=
                                        DIVIDE_PERSPECTIVE_U;

                                    raster_state <=
                                        RASTER_PERSPECTIVE_SETUP;
                                end

                                default: begin
                                    interp_attr <= INTERP_DEPTH;
                                    divider_mode <=
                                        DIVIDE_BARYCENTRIC;
                                    raster_state <=
                                        RASTER_SCAN;
                                end

                            endcase

                        end else if (
                            divider_mode ==
                            DIVIDE_PERSPECTIVE_U
                        ) begin

                            if (!divider_domain_valid)
                                perspective_u_result <=
                                    64'sd0;
                            else
                                perspective_u_result <=
                                    divider_final_perspective_signed;

                            divider_mode <=
                                DIVIDE_PERSPECTIVE_V;

                            raster_state <=
                                RASTER_PERSPECTIVE_SETUP;

                        end else if (
                            divider_mode ==
                            DIVIDE_PERSPECTIVE_V
                        ) begin

                            if (!divider_domain_valid)
                                perspective_v_result <=
                                    64'sd0;
                            else
                                perspective_v_result <=
                                    divider_final_perspective_signed;

                            divider_mode <=
                                DIVIDE_BARYCENTRIC;

                            raster_state <=
                                RASTER_EMIT;

                        end else begin

                            divider_mode <=
                                DIVIDE_BARYCENTRIC;

                            raster_state <=
                                RASTER_SCAN;

                        end

                    end else begin

                        divider_bit_index <=
                            divider_bit_index - 6'd1;

                    end
                end

                RASTER_PERSPECTIVE_SETUP: begin
                    covered_valid <= 1'b0;

                    divider_remainder <=
                        {
                            53'd0,
                            perspective_numerator_magnitude
                        };

                    divider_shifted_denominator <=
                        (
                            {
                                69'd0,
                                interp_oow_result
                            }
                            << 47
                        );

                    divider_quotient <=
                        48'd0;

                    divider_bit_index <=
                        6'd47;

                    divider_negative <=
                        perspective_value[31];

                    divider_domain_valid <=
                        (interp_oow_result != 32'd0);

                    raster_state <=
                        RASTER_DIVIDE;
                end

                RASTER_EMIT: begin
                    // All four barycentric attributes are now registered.
                    // Publish them atomically and return to the ordinary
                    // valid/ready holding behavior in RASTER_SCAN.
                    covered_valid      <= 1'b1;
                    covered_x          <= raster_x;
                    covered_y          <= raster_y;
                    covered_z          <= interp_depth_result;
                    covered_u_over_w   <= interp_u_result;
                    covered_v_over_w   <= interp_v_result;
                    covered_one_over_w <= interp_oow_result;

                    covered_u_q16 <=
                        perspective_u_result;

                    covered_v_q16 <=
                        perspective_v_result;

                    raster_state <= RASTER_SCAN;
                end

                default: begin
                    busy          <= 1'b0;
                    done          <= 1'b1;
                    covered_valid <= 1'b0;
                    raster_state  <= RASTER_IDLE;
                end
            endcase
        end
    end

endmodule
