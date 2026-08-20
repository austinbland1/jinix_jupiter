module jupiter_sdram_loader_arbiter
(
    input  wire        clk,
    input  wire        reset,

    // Aggregate game stream from jupiter_sdram_scanout_arbiter.
    input  wire        game_valid,
    input  wire        game_write,
    input  wire [31:0] game_addr,
    input  wire [31:0] game_wdata,
    input  wire  [3:0] game_wstrb,
    output wire [31:0] game_rdata,
    output wire        game_ready,

    // jupiter_loader is structurally write-only at this boundary.
    input  wire        loader_valid,
    input  wire [31:0] loader_addr,
    input  wire [31:0] loader_wdata,
    input  wire  [3:0] loader_wstrb,
    output wire        loader_ready,

    // Shared 32-bit target toward jupiter_sdram_frontend.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    localparam [1:0] GRANT_NONE   = 2'd0;
    localparam [1:0] GRANT_GAME   = 2'd1;
    localparam [1:0] GRANT_LOADER = 2'd2;

    reg [1:0] grant_state;

    // A held transaction is latched so that asserting core_reset cannot
    // truncate a game request already accepted by this third arbitration
    // stage. The old request drains before the loader receives the path.
    reg        held_write;
    reg [31:0] held_addr;
    reg [31:0] held_wdata;
    reg  [3:0] held_wstrb;

    wire idle_loader_selected =
        !reset &&
        (grant_state == GRANT_NONE) &&
        loader_valid;

    wire idle_game_selected =
        !reset &&
        (grant_state == GRANT_NONE) &&
        !loader_valid &&
        game_valid;

    wire held_loader_selected =
        !reset &&
        (grant_state == GRANT_LOADER);

    wire held_game_selected =
        !reset &&
        (grant_state == GRANT_GAME);

    wire loader_selected =
        idle_loader_selected ||
        held_loader_selected;

    wire game_selected =
        idle_game_selected ||
        held_game_selected;

    assign sdram_valid =
        held_loader_selected ||
        held_game_selected ||
        idle_loader_selected ||
        idle_game_selected;

    assign sdram_write =
        held_loader_selected ||
        held_game_selected ?
            held_write :
        idle_loader_selected ?
            1'b1 :
        idle_game_selected ?
            game_write :
            1'b0;

    assign sdram_addr =
        held_loader_selected ||
        held_game_selected ?
            held_addr :
        idle_loader_selected ?
            loader_addr :
        idle_game_selected ?
            game_addr :
            32'h00000000;

    assign sdram_wdata =
        held_loader_selected ||
        held_game_selected ?
            held_wdata :
        idle_loader_selected ?
            loader_wdata :
        idle_game_selected ?
            game_wdata :
            32'h00000000;

    assign sdram_wstrb =
        held_loader_selected ||
        held_game_selected ?
            held_wstrb :
        idle_loader_selected ?
            loader_wstrb :
        idle_game_selected ?
            game_wstrb :
            4'b0000;

    // The selected requester receives completion. A game requester that has
    // already disappeared because core_reset asserted is intentionally not
    // shown a spurious ready, even though its latched transaction is allowed
    // to drain at the downstream target.
    assign game_ready =
        game_selected &&
        game_valid &&
        sdram_ready;

    assign game_rdata =
        game_selected &&
        game_valid ?
            sdram_rdata :
            32'h00000000;

    assign loader_ready =
        loader_selected &&
        loader_valid &&
        sdram_ready;

    always @(posedge clk) begin
        if (reset) begin
            grant_state <=
                GRANT_NONE;

            held_write <=
                1'b0;

            held_addr <=
                32'd0;

            held_wdata <=
                32'd0;

            held_wstrb <=
                4'd0;
        end else begin
            case (grant_state)
                GRANT_NONE: begin
                    if (idle_loader_selected &&
                        !sdram_ready) begin

                        grant_state <=
                            GRANT_LOADER;

                        held_write <=
                            1'b1;

                        held_addr <=
                            loader_addr;

                        held_wdata <=
                            loader_wdata;

                        held_wstrb <=
                            loader_wstrb;
                    end else if (idle_game_selected &&
                                 !sdram_ready) begin

                        grant_state <=
                            GRANT_GAME;

                        held_write <=
                            game_write;

                        held_addr <=
                            game_addr;

                        held_wdata <=
                            game_wdata;

                        held_wstrb <=
                            game_wstrb;
                    end
                end

                GRANT_GAME: begin
                    if (sdram_ready)
                        grant_state <=
                            GRANT_NONE;
                end

                GRANT_LOADER: begin
                    if (sdram_ready)
                        grant_state <=
                            GRANT_NONE;
                end

                default:
                    grant_state <=
                        GRANT_NONE;
            endcase
        end
    end

endmodule
