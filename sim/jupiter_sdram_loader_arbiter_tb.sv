`timescale 1ns/1ps

module jupiter_sdram_loader_arbiter_tb;

    reg         clk;
    reg         reset;

    reg         game_valid;
    reg         game_write;
    reg  [31:0] game_addr;
    reg  [31:0] game_wdata;
    reg   [3:0] game_wstrb;
    wire [31:0] game_rdata;
    wire        game_ready;

    reg         loader_valid;
    reg  [31:0] loader_addr;
    reg  [31:0] loader_wdata;
    reg   [3:0] loader_wstrb;
    wire        loader_ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;
    reg  [31:0] sdram_rdata;
    reg         sdram_ready;

    integer checks;
    integer failures;

    jupiter_sdram_loader_arbiter dut
    (
        .clk          (clk),
        .reset        (reset),

        .game_valid   (game_valid),
        .game_write   (game_write),
        .game_addr    (game_addr),
        .game_wdata   (game_wdata),
        .game_wstrb   (game_wstrb),
        .game_rdata   (game_rdata),
        .game_ready   (game_ready),

        .loader_valid (loader_valid),
        .loader_addr  (loader_addr),
        .loader_wdata (loader_wdata),
        .loader_wstrb (loader_wstrb),
        .loader_ready (loader_ready),

        .sdram_valid  (sdram_valid),
        .sdram_write  (sdram_write),
        .sdram_addr   (sdram_addr),
        .sdram_wdata  (sdram_wdata),
        .sdram_wstrb  (sdram_wstrb),
        .sdram_rdata  (sdram_rdata),
        .sdram_ready  (sdram_ready)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk);
            reset = 1'b1;
            game_valid = 1'b0;
            game_write = 1'b0;
            game_addr = 32'd0;
            game_wdata = 32'd0;
            game_wstrb = 4'd0;
            loader_valid = 1'b0;
            loader_addr = 32'd0;
            loader_wdata = 32'd0;
            loader_wstrb = 4'd0;
            sdram_rdata = 32'h89ABCDEF;
            sdram_ready = 1'b0;
            step;
            step;
            @(negedge clk);
            reset = 1'b0;
            step;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b0;
        game_valid = 1'b0;
        game_write = 1'b0;
        game_addr = 32'd0;
        game_wdata = 32'd0;
        game_wstrb = 4'd0;
        loader_valid = 1'b0;
        loader_addr = 32'd0;
        loader_wdata = 32'd0;
        loader_wstrb = 4'd0;
        sdram_rdata = 32'h89ABCDEF;
        sdram_ready = 1'b0;
        checks = 0;
        failures = 0;

        // Game-only free-point transaction.
        reset_dut;
        game_valid = 1'b1;
        game_write = 1'b0;
        game_addr = 32'h10001000;
        game_wdata = 32'h11112222;
        game_wstrb = 4'h0;
        sdram_ready = 1'b1;
        #1;
        check(sdram_valid === 1'b1, "game-only request must reach SDRAM");
        check(sdram_write === 1'b0, "game read must remain a read");
        check(sdram_addr == 32'h10001000, "game address must pass through");
        check(game_ready === 1'b1, "game requester must receive ready");
        check(game_rdata == 32'h89ABCDEF, "game requester must receive read data");
        check(loader_ready === 1'b0, "inactive loader must not receive ready");

        // Loader-only free-point transaction.
        reset_dut;
        loader_valid = 1'b1;
        loader_addr = 32'h10000000;
        loader_wdata = 32'hAABBCCDD;
        loader_wstrb = 4'hF;
        sdram_ready = 1'b1;
        #1;
        check(sdram_valid === 1'b1, "loader-only request must reach SDRAM");
        check(sdram_write === 1'b1, "loader path must be structurally write-only");
        check(sdram_addr == 32'h10000000, "loader address must pass through");
        check(sdram_wdata == 32'hAABBCCDD, "loader data must pass through");
        check(sdram_wstrb == 4'hF, "loader strobes must pass through");
        check(loader_ready === 1'b1, "loader requester must receive ready");
        check(game_ready === 1'b0, "inactive game path must not receive ready");

        // Contested free point: loader has selected priority.
        reset_dut;
        game_valid = 1'b1;
        game_write = 1'b1;
        game_addr = 32'h10002000;
        game_wdata = 32'h01020304;
        game_wstrb = 4'hF;
        loader_valid = 1'b1;
        loader_addr = 32'h10000040;
        loader_wdata = 32'h55667788;
        loader_wstrb = 4'hF;
        sdram_ready = 1'b1;
        #1;
        check(sdram_addr == 32'h10000040, "loader must win contested free point");
        check(loader_ready === 1'b1, "loader must receive contested completion");
        check(game_ready === 1'b0, "game must not receive completion when loader wins");

        // Non-preemptive boundary: a game request accepted while downstream
        // is stalled is latched. Even if core_reset makes game_valid vanish
        // and the loader appears, the old game request drains first.
        reset_dut;
        game_valid = 1'b1;
        game_write = 1'b1;
        game_addr = 32'h10003000;
        game_wdata = 32'hCAFEBABE;
        game_wstrb = 4'hF;
        sdram_ready = 1'b0;
        #1;
        check(sdram_addr == 32'h10003000, "stalled game request must initially drive SDRAM");
        step; // capture GRANT_GAME

        @(negedge clk);
        game_valid = 1'b0; // model core_reset quiescence
        loader_valid = 1'b1;
        loader_addr = 32'h10000080;
        loader_wdata = 32'hDEADBEEF;
        loader_wstrb = 4'hF;
        #1;
        check(sdram_valid === 1'b1, "held game request must remain valid after game source quiesces");
        check(sdram_addr == 32'h10003000, "loader must not preempt held game request");
        check(loader_ready === 1'b0, "loader cannot complete before held game drains");

        @(negedge clk);
        sdram_ready = 1'b1;
        #1;
        check(sdram_addr == 32'h10003000, "completion cycle must still belong to held game request");
        check(loader_ready === 1'b0, "loader must not steal held game completion");
        step; // held game completes and grant returns to NONE

        #1;
        check(sdram_addr == 32'h10000080, "loader must receive next free arbitration point");
        check(loader_ready === 1'b1, "loader must complete after held game drains");

        // Loader request is itself non-preemptive while stalled.
        reset_dut;
        loader_valid = 1'b1;
        loader_addr = 32'h100000C0;
        loader_wdata = 32'h0BADF00D;
        loader_wstrb = 4'hF;
        sdram_ready = 1'b0;
        step; // capture GRANT_LOADER

        @(negedge clk);
        game_valid = 1'b1;
        game_write = 1'b0;
        game_addr = 32'h10004000;
        #1;
        check(sdram_addr == 32'h100000C0, "game path must not preempt held loader request");
        check(game_ready === 1'b0, "game must wait behind held loader request");

        @(negedge clk);
        sdram_ready = 1'b1;
        #1;
        check(loader_ready === 1'b1, "held loader must receive completion");
        step;

        @(negedge clk);
        loader_valid = 1'b0;
        #1;
        check(sdram_addr == 32'h10004000, "game path must resume after loader completion");

        if (failures == 0) begin
            $display("PASS: jupiter_sdram_loader_arbiter (%0d checks)", checks);
            $finish;
        end

        $display("FAIL: jupiter_sdram_loader_arbiter %0d/%0d checks failed", failures, checks);
        $fatal(1);
    end

endmodule
