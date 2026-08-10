module jupiter_gpu_3d_raster
(
    input  wire               clk,
    input  wire               reset,

    input  wire               start,

    input  wire        [15:0] target_width,
    input  wire        [15:0] target_height,

    input  wire signed [31:0] v0_x,
    input  wire signed [31:0] v0_y,
    input  wire signed [31:0] v1_x,
    input  wire signed [31:0] v1_y,
    input  wire signed [31:0] v2_x,
    input  wire signed [31:0] v2_y,

    output reg                busy,
    output reg                done,

    // Covered-sample valid/ready handshake. A covered sample and its
    // coordinates remain stable until covered_ready is observed.
    input  wire               covered_ready,
    output reg                covered_valid,
    output reg         [15:0] covered_x,
    output reg         [15:0] covered_y,

    // Deterministic command-local counters.
    output reg         [31:0] coverage_count,
    output reg         [31:0] sample_count
);

    localparam [1:0] RASTER_IDLE  = 2'd0;
    localparam [1:0] RASTER_SETUP = 2'd1;
    localparam [1:0] RASTER_SCAN  = 2'd2;

    reg [1:0] raster_state;

    reg [15:0] active_target_width;
    reg [15:0] active_target_height;

    reg signed [31:0] active_v0_x;
    reg signed [31:0] active_v0_y;
    reg signed [31:0] active_v1_x;
    reg signed [31:0] active_v1_y;
    reg signed [31:0] active_v2_x;
    reg signed [31:0] active_v2_y;

    reg [15:0] raster_x;
    reg [15:0] raster_y;

    // Retained after completion for deterministic verification.
    reg [15:0] scan_min_x;
    reg [15:0] scan_min_y;
    reg [15:0] scan_max_x;
    reg [15:0] scan_max_y;

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
    // Raster state machine
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (reset) begin
            raster_state <= RASTER_IDLE;

            active_target_width  <= 16'd0;
            active_target_height <= 16'd0;

            active_v0_x <= 32'sd0;
            active_v0_y <= 32'sd0;
            active_v1_x <= 32'sd0;
            active_v1_y <= 32'sd0;
            active_v2_x <= 32'sd0;
            active_v2_y <= 32'sd0;

            raster_x <= 16'd0;
            raster_y <= 16'd0;

            scan_min_x <= 16'd0;
            scan_min_y <= 16'd0;
            scan_max_x <= 16'd0;
            scan_max_y <= 16'd0;

            busy <= 1'b0;
            done <= 1'b0;

            covered_valid <= 1'b0;
            covered_x     <= 16'd0;
            covered_y     <= 16'd0;

            coverage_count <= 32'd0;
            sample_count   <= 32'd0;
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
                        active_v1_x <= v1_x;
                        active_v1_y <= v1_y;
                        active_v2_x <= v2_x;
                        active_v2_y <= v2_y;

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
                        // Publish the covered sample, but do not advance the
                        // scan until covered_ready accepts it.
                        covered_valid <= 1'b1;
                        covered_x     <= raster_x;
                        covered_y     <= raster_y;
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
