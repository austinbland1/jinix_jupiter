`timescale 1ns/1ps

module jupiter_stubs_tb;

    reg clk   = 1'b0;
    reg reset = 1'b1;

    always #5 clk = ~clk;

    jupiter_cpu_stub cpu_stub
    (
        .clk   (clk),
        .reset (reset)
    );

    jupiter_memory_stub memory_stub
    (
        .clk   (clk),
        .reset (reset)
    );

    jupiter_dma_stub dma_stub
    (
        .clk   (clk),
        .reset (reset)
    );

    jupiter_gpu_stub gpu_stub
    (
        .clk   (clk),
        .reset (reset)
    );

    jupiter_audio_stub audio_stub
    (
        .clk   (clk),
        .reset (reset)
    );

    jupiter_peripherals_stub peripherals_stub
    (
        .clk   (clk),
        .reset (reset)
    );

    initial begin
        // Hold reset across several clock edges, then release it.
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Allow the complete placeholder hierarchy to run briefly.
        repeat (5) @(posedge clk);
        #1;

        if (reset !== 1'b0) begin
            $display("FAIL: reset did not deassert");
            $fatal(1);
        end

        $display("");
        $display("==============================");
        $display("RESULT: PASS  (stub hierarchy)");
        $display("==============================");

        $finish(0);
    end

endmodule
