`timescale 1ns/1ps

module jupiter_sdram_arbiter_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        cpu_valid = 1'b0;
    reg        cpu_write = 1'b0;
    reg [31:0] cpu_addr  = 32'h00000000;
    reg [31:0] cpu_wdata = 32'h00000000;
    reg  [3:0] cpu_wstrb = 4'b0000;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    reg        gpu_valid = 1'b0;
    reg        gpu_write = 1'b0;
    reg [31:0] gpu_addr  = 32'h00000000;
    reg [31:0] gpu_wdata = 32'h00000000;
    reg  [3:0] gpu_wstrb = 4'b0000;
    wire [31:0] gpu_rdata;
    wire        gpu_ready;

    reg        dma_valid = 1'b0;
    reg        dma_write = 1'b0;
    reg [31:0] dma_addr  = 32'h00000000;
    reg [31:0] dma_wdata = 32'h00000000;
    reg  [3:0] dma_wstrb = 4'b0000;
    wire [31:0] dma_rdata;
    wire        dma_ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;
    reg  [31:0] sdram_rdata = 32'h00000000;
    reg         sdram_ready = 1'b0;

    integer checks = 0;
    integer failures = 0;

    always #5 clk = ~clk;

    jupiter_sdram_arbiter dut
    (
        .clk         (clk),
        .reset       (reset),

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

        .sdram_valid (sdram_valid),
        .sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );

    task check;
        input condition;
        input [8*128-1:0] message;
        begin
            checks = checks + 1;

            if (condition)
                $display("PASS: %0s", message);
            else begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1;

        check(
            !sdram_valid,
            "reset suppresses shared SDRAM request"
        );

        check(
            !cpu_ready &&
            !gpu_ready &&
            !dma_ready,
            "reset acknowledges no master"
        );

        check(
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "reset shared request fields are deterministic zero"
        );

        check(
            cpu_rdata == 32'h00000000 &&
            gpu_rdata == 32'h00000000 &&
            dma_rdata == 32'h00000000,
            "reset master read-data outputs are deterministic zero"
        );

        // ----------------------------------------------------
        // Triple contest #1 after reset: CPU wins.
        // ----------------------------------------------------
        @(negedge clk);
        reset = 1'b0;

        cpu_valid = 1'b1;
        cpu_write = 1'b0;
        cpu_addr  = 32'h10000020;
        cpu_wdata = 32'h11112222;
        cpu_wstrb = 4'b0000;

        gpu_valid = 1'b1;
        gpu_write = 1'b1;
        gpu_addr  = 32'h10001000;
        gpu_wdata = 32'hAABBCCDD;
        gpu_wstrb = 4'b1010;

        dma_valid = 1'b1;
        dma_write = 1'b1;
        dma_addr  = 32'h10002000;
        dma_wdata = 32'h1122AABB;
        dma_wstrb = 4'b1100;

        sdram_ready = 1'b0;
        #1;

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10000020,
            "CPU receives first triple-contested grant after reset"
        );

        check(
            !cpu_ready &&
            !gpu_ready &&
            !dma_ready,
            "all three masters remain stalled while target stalls"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd1 &&
            dut.grant_contested,
            "held contested CPU grant preserves M5 CPU encoding"
        );

        // Change both waiting requesters. CPU must remain selected.
        @(negedge clk);
        gpu_addr  = 32'h10001100;
        gpu_wdata = 32'h55667788;
        dma_addr  = 32'h10002100;
        dma_wdata = 32'h99AABBCC;
        #1;

        check(
            sdram_addr == 32'h10000020 &&
            !sdram_write,
            "held CPU grant is not preempted by GPU or DMA changes"
        );

        sdram_rdata = 32'hCAFEBABE;
        sdram_ready = 1'b1;
        #1;

        check(
            cpu_ready &&
            !gpu_ready &&
            !dma_ready,
            "only CPU receives completion for held CPU grant"
        );

        check(
            cpu_rdata == 32'hCAFEBABE &&
            gpu_rdata == 32'h00000000 &&
            dma_rdata == 32'h00000000,
            "CPU read data is isolated from GPU and DMA"
        );

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Triple contest #2: CPU was last contested winner,
        // therefore GPU wins next.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_addr  = 32'h10000040;
        cpu_write = 1'b1;
        cpu_wdata = 32'h12345678;
        cpu_wstrb = 4'b1111;

        gpu_addr  = 32'h10003000;
        gpu_write = 1'b1;
        gpu_wdata = 32'h89ABCDEF;
        gpu_wstrb = 4'b0011;

        dma_addr  = 32'h10004000;
        dma_write = 1'b0;
        dma_wstrb = 4'b0000;

        sdram_ready = 1'b0;
        #1;

        check(
            sdram_valid &&
            sdram_write &&
            sdram_addr == 32'h10003000,
            "GPU wins triple contest after CPU contested win"
        );

        check(
            sdram_wdata == 32'h89ABCDEF &&
            sdram_wstrb == 4'b0011,
            "GPU write data and strobes reach shared target"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd2 &&
            dut.grant_contested,
            "held contested GPU grant preserves M5 GPU encoding"
        );

        @(negedge clk);
        cpu_addr = 32'h10000080;
        dma_addr = 32'h10004100;
        #1;

        check(
            sdram_addr == 32'h10003000 &&
            sdram_wdata == 32'h89ABCDEF,
            "held GPU grant is not preempted by CPU or DMA changes"
        );

        sdram_rdata = 32'h0BADF00D;
        sdram_ready = 1'b1;
        #1;

        check(
            gpu_ready &&
            !cpu_ready &&
            !dma_ready,
            "only GPU receives completion for held GPU grant"
        );

        check(
            gpu_rdata == 32'h0BADF00D &&
            cpu_rdata == 32'h00000000 &&
            dma_rdata == 32'h00000000,
            "GPU read-data path is isolated from CPU and DMA"
        );

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Triple contest #3: GPU was last winner, therefore DMA.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_addr  = 32'h10000100;
        cpu_write = 1'b0;
        cpu_wstrb = 4'b0000;

        gpu_addr  = 32'h10005000;
        gpu_write = 1'b0;
        gpu_wstrb = 4'b0000;

        dma_addr  = 32'h10006000;
        dma_write = 1'b1;
        dma_wdata = 32'hDEADBEEF;
        dma_wstrb = 4'b1111;

        sdram_ready = 1'b0;
        #1;

        check(
            sdram_valid &&
            sdram_write &&
            sdram_addr == 32'h10006000,
            "DMA wins triple contest after GPU contested win"
        );

        check(
            sdram_wdata == 32'hDEADBEEF &&
            sdram_wstrb == 4'b1111,
            "DMA write data and strobes reach shared target"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd3 &&
            dut.grant_contested,
            "DMA held contested grant uses new encoding three"
        );

        @(negedge clk);
        cpu_addr = 32'h10000120;
        gpu_addr = 32'h10005100;
        #1;

        check(
            sdram_addr == 32'h10006000 &&
            sdram_wdata == 32'hDEADBEEF,
            "held DMA grant is not preempted by CPU or GPU changes"
        );

        sdram_rdata = 32'h13579BDF;
        sdram_ready = 1'b1;
        #1;

        check(
            dma_ready &&
            !cpu_ready &&
            !gpu_ready,
            "only DMA receives completion for held DMA grant"
        );

        check(
            dma_rdata == 32'h13579BDF &&
            cpu_rdata == 32'h00000000 &&
            gpu_rdata == 32'h00000000,
            "DMA read-data path is isolated from CPU and GPU"
        );

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // DMA was last contested winner. Triple contest returns
        // cyclic priority to CPU. Complete immediately.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_addr = 32'h10000140;
        gpu_addr = 32'h10005200;
        dma_addr = 32'h10006100;

        sdram_rdata = 32'h55AA55AA;
        sdram_ready = 1'b1;
        #1;

        check(
            sdram_addr == 32'h10000140 &&
            cpu_ready &&
            !gpu_ready &&
            !dma_ready,
            "triple round-robin cycles DMA back to CPU"
        );

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Skip inactive GPU:
        // previous contested winner CPU -> next is GPU, but GPU
        // is absent, so DMA wins CPU/DMA contest.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_valid = 1'b1;
        gpu_valid = 1'b0;
        dma_valid = 1'b1;

        cpu_addr = 32'h10000160;
        dma_addr = 32'h10006200;

        sdram_ready = 1'b0;
        #1;

        check(
            sdram_addr == 32'h10006200,
            "round-robin skips inactive GPU and selects DMA"
        );

        @(posedge clk);
        #1;

        @(negedge clk);
        sdram_ready = 1'b1;
        #1;

        check(
            dma_ready &&
            !cpu_ready,
            "DMA completes CPU/DMA skipped-requester contest"
        );

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Previous winner DMA -> CPU absent -> GPU.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_valid = 1'b0;
        gpu_valid = 1'b1;
        dma_valid = 1'b1;

        gpu_addr = 32'h10005300;
        dma_addr = 32'h10006300;

        sdram_ready = 1'b1;
        #1;

        check(
            gpu_ready &&
            !dma_ready &&
            sdram_addr == 32'h10005300,
            "round-robin skips inactive CPU and selects GPU"
        );

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Previous winner GPU -> DMA absent -> CPU.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_valid = 1'b1;
        gpu_valid = 1'b1;
        dma_valid = 1'b0;

        cpu_addr = 32'h10000180;
        gpu_addr = 32'h10005400;

        sdram_ready = 1'b1;
        #1;

        check(
            cpu_ready &&
            !gpu_ready &&
            sdram_addr == 32'h10000180,
            "round-robin skips inactive DMA and selects CPU"
        );

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Uncontested transactions must not change contested
        // history. CPU won the last contest.
        //
        // Complete an uncontested DMA transaction. The next
        // CPU/DMA contest must still skip inactive GPU and choose
        // DMA, proving the uncontested DMA did not rewrite history.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_valid = 1'b0;
        gpu_valid = 1'b0;
        dma_valid = 1'b1;
        dma_addr  = 32'h10006400;

        sdram_ready = 1'b1;
        #1;

        check(
            dma_ready &&
            sdram_addr == 32'h10006400,
            "uncontested DMA transaction completes immediately"
        );

        @(posedge clk);
        #1;

        @(negedge clk);

        cpu_valid = 1'b1;
        gpu_valid = 1'b0;
        dma_valid = 1'b1;

        cpu_addr = 32'h100001A0;
        dma_addr = 32'h10006500;

        sdram_ready = 1'b0;
        #1;

        check(
            sdram_addr == 32'h10006500,
            "uncontested DMA transaction preserves contested history"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd3 &&
            dut.grant_contested,
            "CPU/DMA contest records held contested DMA grant"
        );

        @(negedge clk);
        sdram_ready = 1'b1;
        #1;

        check(
            dma_ready &&
            !cpu_ready,
            "held DMA contest completes non-preemptively"
        );

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Immediate contested completion also updates history.
        // DMA just won, so CPU wins a CPU/GPU contest.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_valid = 1'b1;
        gpu_valid = 1'b1;
        dma_valid = 1'b0;

        cpu_addr = 32'h100001C0;
        gpu_addr = 32'h10005500;

        sdram_ready = 1'b1;
        #1;

        check(
            cpu_ready &&
            !gpu_ready &&
            sdram_addr == 32'h100001C0,
            "immediate contested completion follows DMA with CPU"
        );

        @(posedge clk);
        #1;

        // CPU now won contested history. With all three active,
        // GPU is next. Hold that grant, then assert reset.
        @(negedge clk);

        cpu_valid = 1'b1;
        gpu_valid = 1'b1;
        dma_valid = 1'b1;

        cpu_addr = 32'h100001E0;
        gpu_addr = 32'h10005600;
        dma_addr = 32'h10006600;

        sdram_ready = 1'b0;
        #1;

        check(
            sdram_addr == 32'h10005600,
            "GPU is selected before reset-cancellation test"
        );

        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd2 &&
            dut.grant_contested,
            "GPU contested grant becomes held before reset"
        );

        @(negedge clk);
        reset = 1'b1;
        #1;

        check(
            !sdram_valid,
            "reset suppresses an in-progress three-master grant"
        );

        check(
            !cpu_ready &&
            !gpu_ready &&
            !dma_ready,
            "reset suppresses all master completion signals"
        );

        check(
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "reset suppresses held shared request fields"
        );

        @(posedge clk);
        #1;

        // Reset restores first-contest CPU preference.
        @(negedge clk);
        reset = 1'b0;
        sdram_ready = 1'b0;
        #1;

        check(
            sdram_addr == 32'h100001E0,
            "reset restores CPU priority for first triple contest"
        );

        // The CPU request is stalled here. Preserve the valid/ready
        // requester contract and let the restored-priority transaction
        // complete before asking the arbiter to return idle.
        @(posedge clk);
        #1;

        check(
            dut.grant_state == 2'd1 &&
            dut.grant_contested,
            "post-reset CPU contested grant becomes held"
        );

        @(negedge clk);
        sdram_ready = 1'b1;
        #1;

        check(
            cpu_ready &&
            !gpu_ready &&
            !dma_ready,
            "post-reset CPU grant completes before idle transition"
        );

        @(posedge clk);
        #1;

        // Return to deterministic idle only after the held logical
        // transaction has completed.
        @(negedge clk);

        cpu_valid = 1'b0;
        gpu_valid = 1'b0;
        dma_valid = 1'b0;
        sdram_ready = 1'b0;
        #1;

        check(
            !sdram_valid &&
            !cpu_ready &&
            !gpu_ready &&
            !dma_ready,
            "three-master arbiter returns to deterministic idle state"
        );

        check(
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "idle shared request fields are deterministic zero"
        );

        check(
            cpu_rdata == 32'h00000000 &&
            gpu_rdata == 32'h00000000 &&
            dma_rdata == 32'h00000000,
            "idle master read-data outputs are deterministic zero"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display(
                "RESULT: PASS  (%0d checks)",
                checks
            );
            $display("==============================");
            $finish;
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
