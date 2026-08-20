`timescale 1ns/1ps

module jupiter_loader_boundary_chain_tb;

    reg         clk;
    reg         reset;
    reg         game_reset;

    reg         cpu_valid;
    reg         cpu_write;
    reg  [31:0] cpu_addr;
    reg  [31:0] cpu_wdata;
    reg   [3:0] cpu_wstrb;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    reg         gpu_valid;
    reg         gpu_write;
    reg  [31:0] gpu_addr;
    reg  [31:0] gpu_wdata;
    reg   [3:0] gpu_wstrb;
    wire [31:0] gpu_rdata;
    wire        gpu_ready;

    reg         dma_valid;
    reg         dma_write;
    reg  [31:0] dma_addr;
    reg  [31:0] dma_wdata;
    reg   [3:0] dma_wstrb;
    wire [31:0] dma_rdata;
    wire        dma_ready;

    wire        normal_valid;
    wire        normal_write;
    wire [31:0] normal_addr;
    wire [31:0] normal_wdata;
    wire  [3:0] normal_wstrb;
    wire [31:0] normal_rdata;
    wire        normal_ready;

    reg         scanout_valid;
    reg  [31:0] scanout_addr;
    wire [31:0] scanout_rdata;
    wire        scanout_ready;

    wire        game_valid;
    wire        game_write;
    wire [31:0] game_addr;
    wire [31:0] game_wdata;
    wire  [3:0] game_wstrb;
    wire [31:0] game_rdata;
    wire        game_ready;

    reg         loader_valid;
    reg  [31:0] loader_addr;
    reg  [31:0] loader_wdata;
    reg   [3:0] loader_wstrb;
    wire        loader_ready;

    wire        target_valid;
    wire        target_write;
    wire [31:0] target_addr;
    wire [31:0] target_wdata;
    wire  [3:0] target_wstrb;
    reg  [31:0] target_rdata;
    reg         target_ready;

    integer checks;
    integer failures;

    jupiter_sdram_arbiter first_stage
    (
        .clk         (clk),
        .reset       (game_reset),

        .cpu_valid   (cpu_valid),
        .cpu_write   (cpu_write),
        .cpu_addr    (cpu_addr),
        .cpu_wdata   (cpu_wdata),
        .cpu_wstrb   (cpu_wstrb),
        .cpu_rdata   (cpu_rdata),
        .cpu_ready   (cpu_ready),

        .gpu_valid   (gpu_valid),
        .gpu_write   (gpu_write),
        .gpu_addr    (gpu_addr),
        .gpu_wdata   (gpu_wdata),
        .gpu_wstrb   (gpu_wstrb),
        .gpu_rdata   (gpu_rdata),
        .gpu_ready   (gpu_ready),

        .dma_valid   (dma_valid),
        .dma_write   (dma_write),
        .dma_addr    (dma_addr),
        .dma_wdata   (dma_wdata),
        .dma_wstrb   (dma_wstrb),
        .dma_rdata   (dma_rdata),
        .dma_ready   (dma_ready),

        .sdram_valid (normal_valid),
        .sdram_write (normal_write),
        .sdram_addr  (normal_addr),
        .sdram_wdata (normal_wdata),
        .sdram_wstrb (normal_wstrb),
        .sdram_rdata (normal_rdata),
        .sdram_ready (normal_ready)
    );

    jupiter_sdram_scanout_arbiter second_stage
    (
        .clk           (clk),
        .reset         (game_reset),

        .normal_valid  (normal_valid),
        .normal_write  (normal_write),
        .normal_addr   (normal_addr),
        .normal_wdata  (normal_wdata),
        .normal_wstrb  (normal_wstrb),
        .normal_rdata  (normal_rdata),
        .normal_ready  (normal_ready),

        .scanout_valid (scanout_valid),
        .scanout_addr  (scanout_addr),
        .scanout_rdata (scanout_rdata),
        .scanout_ready (scanout_ready),

        .sdram_valid   (game_valid),
        .sdram_write   (game_write),
        .sdram_addr    (game_addr),
        .sdram_wdata   (game_wdata),
        .sdram_wstrb   (game_wstrb),
        .sdram_rdata   (game_rdata),
        .sdram_ready   (game_ready)
    );

    jupiter_sdram_loader_arbiter third_stage
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

        .sdram_valid  (target_valid),
        .sdram_write  (target_write),
        .sdram_addr   (target_addr),
        .sdram_wdata  (target_wdata),
        .sdram_wstrb  (target_wstrb),
        .sdram_rdata  (target_rdata),
        .sdram_ready  (target_ready)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*112-1:0] message;
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

    task clear_inputs;
        begin
            cpu_valid = 1'b0;
            cpu_write = 1'b0;
            cpu_addr = 32'd0;
            cpu_wdata = 32'd0;
            cpu_wstrb = 4'd0;

            gpu_valid = 1'b0;
            gpu_write = 1'b0;
            gpu_addr = 32'd0;
            gpu_wdata = 32'd0;
            gpu_wstrb = 4'd0;

            dma_valid = 1'b0;
            dma_write = 1'b0;
            dma_addr = 32'd0;
            dma_wdata = 32'd0;
            dma_wstrb = 4'd0;

            scanout_valid = 1'b0;
            scanout_addr = 32'd0;

            loader_valid = 1'b0;
            loader_addr = 32'd0;
            loader_wdata = 32'd0;
            loader_wstrb = 4'd0;

            target_rdata = 32'h12345678;
            target_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        game_reset = 1'b1;
        checks = 0;
        failures = 0;
        clear_inputs;

        step;
        step;

        @(negedge clk);
        reset = 1'b0;
        game_reset = 1'b0;
        step;

        // Build a held GPU transaction through both existing game arbiters and
        // the new downstream loader arbiter.
        @(negedge clk);
        gpu_valid = 1'b1;
        gpu_write = 1'b1;
        gpu_addr = 32'h10008000;
        gpu_wdata = 32'hCAFED00D;
        gpu_wstrb = 4'hF;
        target_ready = 1'b0;
        #1;

        check(target_valid === 1'b1, "GPU request must reach third-stage target before core_reset");
        check(target_addr == 32'h10008000, "GPU address must reach third-stage target before core_reset");

        step; // all three arbitration stages may capture the stalled request
        #1;

        check(first_stage.grant_state != 2'd0, "first-stage arbiter must hold stalled GPU grant");
        check(second_stage.grant_state != 2'd0, "scanout arbiter must hold stalled normal grant");
        check(third_stage.grant_state != 2'd0, "loader arbiter must hold stalled game transaction");

        // Matching download asserts core_reset. Existing game arbiters are
        // reset through their unchanged reset inputs, while the new loader
        // arbiter remains alive and retains the already-presented request.
        @(negedge clk);
        game_reset = 1'b1;
        gpu_valid = 1'b0;
        loader_valid = 1'b1;
        loader_addr = 32'h10000000;
        loader_wdata = 32'hAABBCCDD;
        loader_wstrb = 4'hF;

        step;
        #1;

        check(first_stage.grant_state == 2'd0, "core_reset must clear first-stage stale grant");
        check(second_stage.grant_state == 2'd0, "core_reset must clear scanout-stage stale grant");
        check(third_stage.grant_state != 2'd0, "new loader arbiter must retain the pre-reset game transaction");
        check(target_addr == 32'h10008000, "pre-reset game transaction must drain before loader");
        check(loader_ready === 1'b0, "loader must remain stalled behind pre-reset game transaction");

        // Complete the pre-reset game request. The new loader arbiter owns the
        // completion and then exposes the loader at the next free point.
        @(negedge clk);
        target_ready = 1'b1;
        #1;

        check(target_addr == 32'h10008000, "drain completion must still belong to pre-reset game transaction");
        check(loader_ready === 1'b0, "loader must not steal pre-reset completion");

        step;
        #1;

        check(target_addr == 32'h10000000, "loader must receive path after pre-reset transaction drains");
        check(loader_ready === 1'b1, "loader must complete after drain boundary");

        // End the load, release game reset, and prove a CPU request is not
        // blocked by stale grants in either pre-existing arbiter.
        @(negedge clk);
        loader_valid = 1'b0;
        game_reset = 1'b0;
        target_ready = 1'b1;
        cpu_valid = 1'b1;
        cpu_write = 1'b0;
        cpu_addr = 32'h10000020;
        cpu_wdata = 32'd0;
        cpu_wstrb = 4'd0;
        #1;

        check(target_valid === 1'b1, "post-load CPU request must reach SDRAM immediately");
        check(target_addr == 32'h10000020, "post-load CPU address must not be blocked by stale grant");
        check(cpu_ready === 1'b1, "post-load CPU request must complete");
        check(cpu_rdata == 32'h12345678, "post-load CPU read data must return normally");

        if (failures == 0) begin
            $display("PASS: M12 in-flight reset/arbitration boundary (%0d checks)", checks);
            $finish;
        end

        $display("FAIL: M12 in-flight boundary %0d/%0d checks failed", failures, checks);
        $fatal(1);
    end

endmodule
