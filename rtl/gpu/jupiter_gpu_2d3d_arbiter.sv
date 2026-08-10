module jupiter_gpu_2d3d_arbiter
(
    input  wire        clk,
    input  wire        reset,

    // Existing 2D renderer master.
    input  wire        gpu2d_valid,
    input  wire        gpu2d_write,
    input  wire [31:0] gpu2d_addr,
    input  wire [31:0] gpu2d_wdata,
    input  wire  [3:0] gpu2d_wstrb,
    output wire [31:0] gpu2d_rdata,
    output wire        gpu2d_ready,

    // M10 3D renderer master.
    input  wire        gpu3d_valid,
    input  wire        gpu3d_write,
    input  wire [31:0] gpu3d_addr,
    input  wire [31:0] gpu3d_wdata,
    input  wire  [3:0] gpu3d_wstrb,
    output wire [31:0] gpu3d_rdata,
    output wire        gpu3d_ready,

    // One combined GPU master toward the existing system SDRAM arbiter.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    localparam [1:0] GRANT_NONE = 2'd0;
    localparam [1:0] GRANT_2D   = 2'd1;
    localparam [1:0] GRANT_3D   = 2'd2;

    reg [1:0] grant_state;

    // Only contested completions rotate priority.
    //
    // Reset history to 3D so the first contested transaction goes to 2D.
    reg [1:0] last_contested_winner;
    reg       grant_contested;

    wire contested_now =
        gpu2d_valid &&
        gpu3d_valid;

    reg [1:0] idle_grant;

    always @(*) begin
        idle_grant = GRANT_NONE;

        if (!reset &&
            (grant_state == GRANT_NONE)) begin

            case ({
                gpu2d_valid,
                gpu3d_valid
            })
                2'b00:
                    idle_grant = GRANT_NONE;

                2'b10:
                    idle_grant = GRANT_2D;

                2'b01:
                    idle_grant = GRANT_3D;

                2'b11: begin
                    if (last_contested_winner == GRANT_2D)
                        idle_grant = GRANT_3D;
                    else
                        idle_grant = GRANT_2D;
                end

                default:
                    idle_grant = GRANT_NONE;
            endcase
        end
    end

    wire idle_2d_selected =
        (idle_grant == GRANT_2D);

    wire idle_3d_selected =
        (idle_grant == GRANT_3D);

    wire gpu2d_selected =
        !reset &&
        (
            (grant_state == GRANT_2D) ||
            idle_2d_selected
        );

    wire gpu3d_selected =
        !reset &&
        (
            (grant_state == GRANT_3D) ||
            idle_3d_selected
        );

    assign sdram_valid =
        gpu2d_selected ? gpu2d_valid :
        gpu3d_selected ? gpu3d_valid :
                         1'b0;

    assign sdram_write =
        gpu2d_selected ? gpu2d_write :
        gpu3d_selected ? gpu3d_write :
                         1'b0;

    assign sdram_addr =
        gpu2d_selected ? gpu2d_addr :
        gpu3d_selected ? gpu3d_addr :
                         32'h00000000;

    assign sdram_wdata =
        gpu2d_selected ? gpu2d_wdata :
        gpu3d_selected ? gpu3d_wdata :
                         32'h00000000;

    assign sdram_wstrb =
        gpu2d_selected ? gpu2d_wstrb :
        gpu3d_selected ? gpu3d_wstrb :
                         4'b0000;

    assign gpu2d_ready =
        gpu2d_selected &&
        gpu2d_valid ?
        sdram_ready :
        1'b0;

    assign gpu3d_ready =
        gpu3d_selected &&
        gpu3d_valid ?
        sdram_ready :
        1'b0;

    assign gpu2d_rdata =
        gpu2d_selected &&
        gpu2d_valid ?
        sdram_rdata :
        32'h00000000;

    assign gpu3d_rdata =
        gpu3d_selected &&
        gpu3d_valid ?
        sdram_rdata :
        32'h00000000;

    always @(posedge clk) begin
        if (reset) begin
            grant_state           <= GRANT_NONE;
            grant_contested       <= 1'b0;
            last_contested_winner <= GRANT_3D;
        end else begin
            case (grant_state)
                GRANT_NONE: begin
                    if (idle_grant != GRANT_NONE) begin
                        if (sdram_ready) begin
                            grant_state     <= GRANT_NONE;
                            grant_contested <= 1'b0;

                            if (contested_now)
                                last_contested_winner <=
                                    idle_grant;
                        end else begin
                            grant_state <= idle_grant;
                            grant_contested <=
                                contested_now;
                        end
                    end
                end

                GRANT_2D: begin
                    if (gpu2d_valid &&
                        sdram_ready) begin

                        grant_state <= GRANT_NONE;

                        if (grant_contested)
                            last_contested_winner <=
                                GRANT_2D;

                        grant_contested <= 1'b0;
                    end
                end

                GRANT_3D: begin
                    if (gpu3d_valid &&
                        sdram_ready) begin

                        grant_state <= GRANT_NONE;

                        if (grant_contested)
                            last_contested_winner <=
                                GRANT_3D;

                        grant_contested <= 1'b0;
                    end
                end

                default: begin
                    grant_state           <= GRANT_NONE;
                    grant_contested       <= 1'b0;
                    last_contested_winner <= GRANT_3D;
                end
            endcase
        end
    end

endmodule
