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
    // Each accepted request fetches one aligned 32-bit word containing two
    // adjacent RGB565 framebuffer pixels.
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

    // Sticky display underflow state.
    reg underflow_sticky;

    // Two 320-pixel RGB565 line buffers. A buffer becomes visible only after
    // every word for its tagged source line has completed.
    (* ramstyle = "MLAB, no_rw_check" *)
    reg [15:0] line_buffer_0 [0:319];

    (* ramstyle = "MLAB, no_rw_check" *)
    reg [15:0] line_buffer_1 [0:319];

    reg        buffer_0_valid;
    reg        buffer_1_valid;
    reg [15:0] buffer_0_line;
    reg [15:0] buffer_1_line;

    // The currently displayed physical line is committed to one completed
    // buffer at its line boundary. If no completed source line exists at
    // that boundary, the entire affected physical line remains black.
    reg        display_line_valid;
    reg        display_buffer_select;

    // Sequential read-only line prefetch state.
    reg        fetch_active;
    reg        fetch_buffer_select;
    reg [15:0] fetch_line;
    reg [15:0] fetch_word_index;
    reg [15:0] next_fetch_line;

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

    wire line_boundary =
        advance_pixel &&
        (hc == 10'd637);

    wire [15:0] display_source_line =
        scandouble ?
            {7'd0, vc[9:1]} :
            {6'd0, vc};

    wire [9:0] next_raster_line =
        (vc == raster_last_line) ?
            10'd0 :
            (vc + 10'd1);

    wire [15:0] next_source_line =
        scandouble ?
            {7'd0, next_raster_line[9:1]} :
            {6'd0, next_raster_line};

    wire next_visible_source_needed =
        active_enable &&
        (next_raster_line < active_physical_lines) &&
        (next_source_line < active_height);

    wire [15:0] fetch_last_word_index =
        (active_width >> 1) -
        16'd1;

    wire fetch_last_word =
        fetch_active &&
        (fetch_word_index == fetch_last_word_index);

    wire fetch_completes_line =
        fetch_last_word &&
        sdram_ready;

    wire next_buffer_0_ready =
        (buffer_0_valid &&
         (buffer_0_line == next_source_line)) ||
        (fetch_completes_line &&
         !fetch_buffer_select &&
         (fetch_line == next_source_line));

    wire next_buffer_1_ready =
        (buffer_1_valid &&
         (buffer_1_line == next_source_line)) ||
        (fetch_completes_line &&
         fetch_buffer_select &&
         (fetch_line == next_source_line));

    wire next_source_buffer_ready =
        next_buffer_0_ready ||
        next_buffer_1_ready;

    // During vertical blank, prefetch at most the first two source lines.
    // During visible output, stay exactly one source line ahead.
    wire [15:0] prefetch_limit_line =
        VBlank ?
            16'd1 :
            (display_source_line + 16'd1);

    wire [31:0] fetch_line_pixels =
        {16'd0, fetch_line} *
        {16'd0, active_width};

    wire [31:0] fetch_line_byte_offset =
        fetch_line_pixels << 1;

    wire [31:0] fetch_word_byte_offset =
        {14'd0, fetch_word_index, 2'b00};

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

    // Functional read-only framebuffer fetch stream.
    assign sdram_valid =
        fetch_active;

    assign sdram_addr =
        active_base +
        fetch_line_byte_offset +
        fetch_word_byte_offset;

    function [7:0] expand_rgb5;
        input [4:0] value;
        begin
            expand_rgb5 =
                {value, value[4:2]};
        end
    endfunction

    function [7:0] expand_rgb6;
        input [5:0] value;
        begin
            expand_rgb6 =
                {value, value[5:4]};
        end
    endfunction

    reg [15:0] display_pixel;

    always @* begin
        display_pixel =
            16'h0000;

        if (active_enable &&
            display_line_valid &&
            !VBlank &&
            (hc < active_width) &&
            (hc < 10'd320) &&
            (display_source_line < active_height)) begin

            if (display_buffer_select)
                display_pixel =
                    line_buffer_1[hc];
            else
                display_pixel =
                    line_buffer_0[hc];
        end
    end

    assign video_r =
        expand_rgb5(
            display_pixel[15:11]
        );

    assign video_g =
        expand_rgb6(
            display_pixel[10:5]
        );

    assign video_b =
        expand_rgb5(
            display_pixel[4:0]
        );

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

            buffer_0_valid <= 1'b0;
            buffer_1_valid <= 1'b0;
            buffer_0_line  <= 16'd0;
            buffer_1_line  <= 16'd0;

            display_line_valid    <= 1'b0;
            display_buffer_select <= 1'b0;

            fetch_active        <= 1'b0;
            fetch_buffer_select <= 1'b0;
            fetch_line          <= 16'd0;
            fetch_word_index    <= 16'd0;
            next_fetch_line     <= 16'd0;

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

            // Select the complete source buffer for the next physical line.
            // A missing line is committed black for that entire physical
            // display line even if its fetch finishes later.
            if (line_boundary) begin
                if (next_visible_source_needed) begin
                    if (next_buffer_0_ready) begin
                        display_line_valid <=
                            1'b1;

                        display_buffer_select <=
                            1'b0;
                    end else if (next_buffer_1_ready) begin
                        display_line_valid <=
                            1'b1;

                        display_buffer_select <=
                            1'b1;
                    end else begin
                        display_line_valid <=
                            1'b0;

                        display_buffer_select <=
                            1'b0;

                        underflow_sticky <=
                            1'b1;
                    end
                end else begin
                    display_line_valid <=
                        1'b0;

                    display_buffer_select <=
                        1'b0;
                end
            end

            // Snapshot the complete shadow configuration exactly at the
            // transition into the selected 240-line vertical blank.
            //
            // A valid new frame always restarts prefetch from source line 0.
            if (vertical_blank_snapshot) begin
                buffer_0_valid <=
                    1'b0;

                buffer_1_valid <=
                    1'b0;

                display_line_valid <=
                    1'b0;

                display_buffer_select <=
                    1'b0;

                if (shadow_config_valid) begin
                    active_enable <=
                        1'b1;

                    active_base <=
                        display_base_shadow;

                    active_width <=
                        shadow_width;

                    active_height <=
                        shadow_height;

                    fetch_active <=
                        1'b1;

                    fetch_buffer_select <=
                        1'b0;

                    fetch_line <=
                        16'd0;

                    fetch_word_index <=
                        16'd0;

                    next_fetch_line <=
                        16'd1;
                end else begin
                    active_enable <=
                        1'b0;

                    active_base <=
                        32'h00000000;

                    active_width <=
                        16'd0;

                    active_height <=
                        16'd0;

                    fetch_active <=
                        1'b0;

                    fetch_buffer_select <=
                        1'b0;

                    fetch_line <=
                        16'd0;

                    fetch_word_index <=
                        16'd0;

                    next_fetch_line <=
                        16'd0;
                end
            end else begin
                // Capture two RGB565 pixels from each completed 32-bit word.
                if (fetch_active &&
                    sdram_ready) begin

                    if (fetch_buffer_select) begin
                        line_buffer_1[
                            (fetch_word_index << 1)
                        ] <=
                            sdram_rdata[15:0];

                        line_buffer_1[
                            (fetch_word_index << 1) +
                            16'd1
                        ] <=
                            sdram_rdata[31:16];
                    end else begin
                        line_buffer_0[
                            (fetch_word_index << 1)
                        ] <=
                            sdram_rdata[15:0];

                        line_buffer_0[
                            (fetch_word_index << 1) +
                            16'd1
                        ] <=
                            sdram_rdata[31:16];
                    end

                    if (fetch_last_word) begin
                        fetch_active <=
                            1'b0;

                        fetch_word_index <=
                            16'd0;

                        if (fetch_buffer_select) begin
                            buffer_1_valid <=
                                1'b1;

                            buffer_1_line <=
                                fetch_line;
                        end else begin
                            buffer_0_valid <=
                                1'b1;

                            buffer_0_line <=
                                fetch_line;
                        end
                    end else begin
                        fetch_word_index <=
                            fetch_word_index +
                            16'd1;
                    end
                end

                // Start one sequential source-line prefetch whenever the
                // current look-ahead policy permits it.
                if (!fetch_active &&
                    active_enable &&
                    (next_fetch_line < active_height) &&
                    (next_fetch_line <= prefetch_limit_line)) begin

                    fetch_active <=
                        1'b1;

                    fetch_buffer_select <=
                        next_fetch_line[0];

                    fetch_line <=
                        next_fetch_line;

                    fetch_word_index <=
                        16'd0;

                    next_fetch_line <=
                        next_fetch_line +
                        16'd1;

                    if (next_fetch_line[0])
                        buffer_1_valid <=
                            1'b0;
                    else
                        buffer_0_valid <=
                            1'b0;
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
