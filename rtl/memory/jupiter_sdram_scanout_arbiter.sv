module jupiter_sdram_scanout_arbiter
(
    input  wire        clk,
    input  wire        reset,

    // Aggregate normal-memory master.
    //
    // This input is the already-arbitrated CPU/GPU/DMA stream from
    // jupiter_sdram_arbiter. M11B intentionally leaves that first-stage
    // arbitration policy unchanged.
    input  wire        normal_valid,
    input  wire        normal_write,
    input  wire [31:0] normal_addr,
    input  wire [31:0] normal_wdata,
    input  wire  [3:0] normal_wstrb,
    output wire [31:0] normal_rdata,
    output wire        normal_ready,

    // Framebuffer scanout master.
    //
    // Scanout is structurally read-only at this arbitration boundary.
    input  wire        scanout_valid,
    input  wire [31:0] scanout_addr,
    output wire [31:0] scanout_rdata,
    output wire        scanout_ready,

    // Shared 32-bit target toward jupiter_sdram_frontend.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    localparam [1:0] GRANT_NONE    = 2'd0;
    localparam [1:0] GRANT_NORMAL  = 2'd1;
    localparam [1:0] GRANT_SCANOUT = 2'd2;

    reg [1:0] grant_state;

    // True when the held transaction began while both requesters
    // were active.
    reg grant_contested;

    // Most recent requester whose completed transaction began contested.
    //
    // Reset to NORMAL so the first post-reset contested free arbitration
    // point selects SCANOUT, matching the selected M11B policy:
    //
    //     SCANOUT -> NORMAL -> SCANOUT -> NORMAL -> ...
    reg [1:0] last_contested_winner;

    wire contested_now =
        normal_valid &&
        scanout_valid;

    // Free-point arbitration.
    reg [1:0] idle_grant;

    always @* begin
        idle_grant = GRANT_NONE;

        if (!reset &&
            (grant_state == GRANT_NONE)) begin

            case ({
                normal_valid,
                scanout_valid
            })
                2'b00:
                    idle_grant = GRANT_NONE;

                2'b10:
                    idle_grant = GRANT_NORMAL;

                2'b01:
                    idle_grant = GRANT_SCANOUT;

                default: begin
                    if (last_contested_winner ==
                        GRANT_NORMAL)
                        idle_grant = GRANT_SCANOUT;
                    else
                        idle_grant = GRANT_NORMAL;
                end
            endcase
        end
    end

    wire idle_normal_selected =
        (idle_grant == GRANT_NORMAL);

    wire idle_scanout_selected =
        (idle_grant == GRANT_SCANOUT);

    wire normal_selected =
        !reset &&
        ((grant_state == GRANT_NORMAL) ||
         idle_normal_selected);

    wire scanout_selected =
        !reset &&
        ((grant_state == GRANT_SCANOUT) ||
         idle_scanout_selected);

    // Selected requester drives the shared target.
    assign sdram_valid =
        normal_selected  ? normal_valid :
        scanout_selected ? scanout_valid :
                           1'b0;

    // Scanout is structurally incapable of writing SDRAM.
    assign sdram_write =
        normal_selected ?
        normal_write :
        1'b0;

    assign sdram_addr =
        normal_selected  ? normal_addr :
        scanout_selected ? scanout_addr :
                           32'h00000000;

    assign sdram_wdata =
        normal_selected ?
        normal_wdata :
        32'h00000000;

    assign sdram_wstrb =
        normal_selected ?
        normal_wstrb :
        4'b0000;

    // Only the selected requester receives completion/data.
    assign normal_ready =
        normal_selected &&
        normal_valid ?
        sdram_ready :
        1'b0;

    assign scanout_ready =
        scanout_selected &&
        scanout_valid ?
        sdram_ready :
        1'b0;

    assign normal_rdata =
        normal_selected &&
        normal_valid ?
        sdram_rdata :
        32'h00000000;

    assign scanout_rdata =
        scanout_selected &&
        scanout_valid ?
        sdram_rdata :
        32'h00000000;

    // Non-preemptive grant state.
    always @(posedge clk) begin
        if (reset) begin
            grant_state           <= GRANT_NONE;
            grant_contested       <= 1'b0;
            last_contested_winner <= GRANT_NORMAL;
        end else begin
            case (grant_state)
                GRANT_NONE: begin
                    if (idle_grant != GRANT_NONE) begin
                        if (sdram_ready) begin
                            // Immediate completion at the free point.
                            grant_state     <= GRANT_NONE;
                            grant_contested <= 1'b0;

                            if (contested_now)
                                last_contested_winner <=
                                    idle_grant;
                        end else begin
                            // Hold the selected requester until completion.
                            grant_state <=
                                idle_grant;

                            grant_contested <=
                                contested_now;
                        end
                    end
                end

                GRANT_NORMAL: begin
                    if (normal_valid &&
                        sdram_ready) begin

                        grant_state <=
                            GRANT_NONE;

                        if (grant_contested)
                            last_contested_winner <=
                                GRANT_NORMAL;

                        grant_contested <=
                            1'b0;
                    end
                end

                GRANT_SCANOUT: begin
                    if (scanout_valid &&
                        sdram_ready) begin

                        grant_state <=
                            GRANT_NONE;

                        if (grant_contested)
                            last_contested_winner <=
                                GRANT_SCANOUT;

                        grant_contested <=
                            1'b0;
                    end
                end

                default: begin
                    grant_state           <= GRANT_NONE;
                    grant_contested       <= 1'b0;
                    last_contested_winner <= GRANT_NORMAL;
                end
            endcase
        end
    end

endmodule
