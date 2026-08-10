module jupiter_video_scanout
(
    input  wire        clk,
    input  wire        reset,

    input  wire        pal,
    input  wire        scandouble,

    // CPU-visible display MMIO target.
    input  wire        valid,
    input  wire        write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire  [3:0] wstrb,

    output reg  [31:0] rdata,
    output wire        ready,

    // Inclusive highest byte address of installed CPU-visible SDRAM.
    // Zero means no installed external SDRAM.
    input  wire [31:0] sdram_max_addr,

    // Read-only scanout SDRAM master.
    //
    // M11B-2b intentionally emits no requests yet. The line-buffer fetch
    // stage will become the first functional producer.
    output wire        sdram_valid,
    output wire [31:0] sdram_addr,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready,

    // MiSTer-facing logical video boundary.
    output reg         ce_pix,

    output wire        HBlank,
    output wire        HSync,
    output wire        VBlank,
    output wire        VSync,

    output wire  [7:0] video_r,
    output wire  [7:0] video_g,
    output wire  [7:0] video_b
);

    localparam [31:0] REG_DISPLAY_CONTROL = 32'h00001180;
    localparam [31:0] REG_DISPLAY_STATUS  = 32'h00001184;
    localparam [31:0] REG_DISPLAY_BASE    = 32'h00001188;
    localparam [31:0] REG_DISPLAY_SIZE    = 32'h0000118C;

    localparam [31:0] SDRAM_BASE = 32'h10000000;

    // Shadow software-visible configuration.
    reg        enable_shadow;
    reg [31:0] display_base_shadow;
    reg [31:0] display_size_shadow;

    // Active frame configuration, snapshotted at vertical blank.
    reg        active_enable;
    reg [31:0] active_base;
    reg [15:0] active_width;
    reg [15:0] active_height;

    // M11B line-fetch logic will set this sticky flag.
    // M11B-2b establishes reset/read/explicit-clear semantics.
    reg underflow_sticky;

    // Selected raster counters.
    reg [9:0] hc;
    reg [9:0] vc;

    wire [15:0] shadow_width =
        display_size_shadow[15:0];

    wire [15:0] shadow_height =
        display_size_shadow[31:16];

    // Width/height are tightly bounded, so this product cannot overflow
    // 32 bits for any valid selected configuration.
    wire [31:0] shadow_frame_bytes =
        shadow_width *
        shadow_height *
        32'd2;

    wire [32:0] shadow_frame_end_ext =
        {1'b0, display_base_shadow} +
        {1'b0, shadow_frame_bytes} -
        33'd1;

    wire shadow_dimensions_valid =
        (shadow_width >= 16'd2) &&
        (shadow_width <= 16'd320) &&
        (shadow_width[0] == 1'b0) &&
        (shadow_height >= 16'd1) &&
        (shadow_height <= 16'd240);

    wire shadow_base_valid =
        (display_base_shadow[1:0] == 2'b00) &&
        (display_base_shadow >= SDRAM_BASE);

    wire shadow_range_valid =
        shadow_dimensions_valid &&
        shadow_base_valid &&
        (sdram_max_addr >= SDRAM_BASE) &&
        !shadow_frame_end_ext[32] &&
        (shadow_frame_end_ext[31:0] <= sdram_max_addr);

    wire shadow_config_valid =
        enable_shadow &&
        shadow_range_valid;

    wire [9:0] raster_last_line =
        pal ?
            (scandouble ? 10'd623 : 10'd311) :
            (scandouble ? 10'd523 : 10'd261);

    wire [9:0] active_physical_lines =
        scandouble ?
            10'd480 :
            10'd240;

    // Preserve the inherited CE cadence.
    wire advance_pixel =
        scandouble ||
        ce_pix;

    wire vertical_blank_snapshot =
        advance_pixel &&
        (hc == 10'd637) &&
        (vc == (active_physical_lines - 10'd1));

    assign ready =
        valid;

    // H/V timing is combinational from the selected raster state.
    assign HBlank =
        (hc >= 10'd320);

    assign HSync =
        (hc >= 10'd544) &&
        (hc < 10'd590);

    assign VBlank =
        (vc >= active_physical_lines);

    assign VSync =
        pal ?
            scandouble ?
                ((vc >= 10'd609) &&
                 (vc < 10'd617)) :
                ((vc >= 10'd304) &&
                 (vc < 10'd308)) :
            scandouble ?
                ((vc >= 10'd490) &&
                 (vc < 10'd496)) :
                ((vc >= 10'd245) &&
                 (vc < 10'd248));

    // M11B-2b intentionally renders deterministic black.
    assign video_r = 8'h00;
    assign video_g = 8'h00;
    assign video_b = 8'h00;

    // M11B-2b line fetch is intentionally not active yet.
    assign sdram_valid = 1'b0;
    assign sdram_addr  = 32'h00000000;

    // Silence unused-input warnings conceptually until the fetch stage
    // consumes these target responses.
    wire unused_sdram_response =
        ^{sdram_rdata, sdram_ready};

    // CPU-visible reads.
    always @* begin
        rdata = 32'h00000000;

        if (valid) begin
            case (addr)
                REG_DISPLAY_CONTROL:
                    rdata = {
                        31'd0,
                        enable_shadow
                    };

                REG_DISPLAY_STATUS:
                    rdata = {
                        30'd0,
                        underflow_sticky,
                        active_enable
                    };

                REG_DISPLAY_BASE:
                    rdata =
                        display_base_shadow;

                REG_DISPLAY_SIZE:
                    rdata =
                        display_size_shadow;

                default:
                    rdata =
                        32'h00000000;
            endcase
        end
    end

    // Software configuration and raster state.
    always @(posedge clk) begin
        if (reset) begin
            enable_shadow      <= 1'b0;
            display_base_shadow <= 32'h00000000;
            display_size_shadow <= 32'h00000000;

            active_enable <= 1'b0;
            active_base   <= 32'h00000000;
            active_width  <= 16'd0;
            active_height <= 16'd0;

            underflow_sticky <= 1'b0;

            hc <= 10'd0;
            vc <= 10'd0;

            ce_pix <= 1'b0;
        end else begin
            // Existing template cadence:
            // non-scandoubled toggles CE; scandoubled advances every cycle.
            if (scandouble)
                ce_pix <= 1'b1;
            else
                ce_pix <= ~ce_pix;

            // MMIO writes.
            if (valid &&
                write) begin

                case (addr)
                    REG_DISPLAY_CONTROL: begin
                        if (wstrb[0]) begin
                            enable_shadow <=
                                wdata[0];

                            if (wdata[1])
                                underflow_sticky <=
                                    1'b0;
                        end
                    end

                    REG_DISPLAY_BASE: begin
                        if (wstrb[0])
                            display_base_shadow[7:0] <=
                                wdata[7:0];

                        if (wstrb[1])
                            display_base_shadow[15:8] <=
                                wdata[15:8];

                        if (wstrb[2])
                            display_base_shadow[23:16] <=
                                wdata[23:16];

                        if (wstrb[3])
                            display_base_shadow[31:24] <=
                                wdata[31:24];
                    end

                    REG_DISPLAY_SIZE: begin
                        if (wstrb[0])
                            display_size_shadow[7:0] <=
                                wdata[7:0];

                        if (wstrb[1])
                            display_size_shadow[15:8] <=
                                wdata[15:8];

                        if (wstrb[2])
                            display_size_shadow[23:16] <=
                                wdata[23:16];

                        if (wstrb[3])
                            display_size_shadow[31:24] <=
                                wdata[31:24];
                    end

                    default: begin
                        // STATUS and reserved addresses ignore writes.
                    end
                endcase
            end

            // Snapshot the complete shadow configuration exactly at the
            // transition into the selected 240-line vertical blank.
            if (vertical_blank_snapshot) begin
                if (shadow_config_valid) begin
                    active_enable <=
                        1'b1;

                    active_base <=
                        display_base_shadow;

                    active_width <=
                        shadow_width;

                    active_height <=
                        shadow_height;
                end else begin
                    active_enable <=
                        1'b0;

                    active_base <=
                        32'h00000000;

                    active_width <=
                        16'd0;

                    active_height <=
                        16'd0;
                end
            end

            // Raster advances only at the logical pixel cadence.
            if (advance_pixel) begin
                if (hc == 10'd637) begin
                    hc <= 10'd0;

                    if (vc == raster_last_line)
                        vc <= 10'd0;
                    else
                        vc <= vc + 10'd1;
                end else begin
                    hc <= hc + 10'd1;
                end
            end
        end
    end

endmodule
