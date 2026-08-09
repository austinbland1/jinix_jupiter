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
        input [8*120-1:0] message;
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

        check(!sdram_valid,
              "reset suppresses shared SDRAM request");
        check(!cpu_ready && !gpu_ready,
              "reset acknowledges neither master");

        // ----------------------------------------------------
        // First contested request after reset: CPU wins.
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

        sdram_ready = 1'b0;
        #1;

        check(sdram_valid && !sdram_write &&
              sdram_addr == 32'h10000020,
              "CPU receives first contested grant after reset");
        check(!cpu_ready && !gpu_ready,
              "both masters remain stalled while shared target stalls");

        // Let the grant latch, then alter only the waiting GPU request.
        @(posedge clk);
        #1;

        @(negedge clk);
        gpu_addr  = 32'h10002000;
        gpu_wdata = 32'h55667788;
        gpu_wstrb = 4'b0101;
        #1;

        check(sdram_valid &&
              sdram_addr == 32'h10000020 &&
              !sdram_write,
              "stalled CPU grant is not preempted by GPU changes");

        sdram_rdata = 32'hCAFEBABE;
        sdram_ready = 1'b1;
        #1;

        check(cpu_ready && !gpu_ready,
              "CPU alone receives completion for CPU grant");
        check(cpu_rdata == 32'hCAFEBABE &&
              gpu_rdata == 32'h00000000,
              "CPU read data is routed only to CPU");

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Previous contested winner was CPU, so GPU wins next.
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

        sdram_ready = 1'b0;
        #1;

        check(sdram_valid && sdram_write &&
              sdram_addr == 32'h10003000,
              "GPU wins contested grant after CPU contested win");
        check(sdram_wdata == 32'h89ABCDEF &&
              sdram_wstrb == 4'b0011,
              "GPU write data and strobes reach shared target");

        @(posedge clk);
        #1;

        // Alter only the waiting CPU request while GPU remains granted.
        @(negedge clk);
        cpu_addr  = 32'h10000080;
        cpu_wdata = 32'hDEADBEEF;
        #1;

        check(sdram_addr == 32'h10003000 &&
              sdram_wdata == 32'h89ABCDEF,
              "stalled GPU grant is not preempted by CPU changes");

        sdram_rdata = 32'h0BADF00D;
        sdram_ready = 1'b1;
        #1;

        check(gpu_ready && !cpu_ready,
              "GPU alone receives completion for GPU grant");
        check(gpu_rdata == 32'h0BADF00D &&
              cpu_rdata == 32'h00000000,
              "GPU read-data path is isolated from CPU");

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // Uncontested CPU request must not change contested
        // round-robin history. GPU won the last contested grant,
        // so CPU must still win the next tie.
        // ----------------------------------------------------
        @(negedge clk);

        gpu_valid = 1'b0;

        cpu_valid = 1'b1;
        cpu_write = 1'b0;
        cpu_addr  = 32'h10000100;
        cpu_wstrb = 4'b0000;

        sdram_rdata = 32'h11223344;
        sdram_ready = 1'b1;
        #1;

        check(sdram_valid &&
              sdram_addr == 32'h10000100 &&
              cpu_ready,
              "uncontested CPU request completes immediately");

        @(posedge clk);
        #1;

        @(negedge clk);

        cpu_valid = 1'b1;
        cpu_addr  = 32'h10000120;

        gpu_valid = 1'b1;
        gpu_write = 1'b0;
        gpu_addr  = 32'h10004000;
        gpu_wstrb = 4'b0000;

        sdram_ready = 1'b0;
        #1;

        check(sdram_addr == 32'h10000120,
              "uncontested transaction does not disturb contested history");

        @(posedge clk);
        #1;

        @(negedge clk);
        sdram_ready = 1'b1;
        #1;

        check(cpu_ready && !gpu_ready,
              "CPU contested grant completes non-preemptively");

        @(posedge clk);
        #1;

        // ----------------------------------------------------
        // CPU just won a contested transaction, so an immediate
        // contested transaction must select GPU.
        // ----------------------------------------------------
        @(negedge clk);

        cpu_addr  = 32'h10000140;
        gpu_addr  = 32'h10005000;
        sdram_rdata = 32'h55AA55AA;
        sdram_ready = 1'b1;
        #1;

        check(sdram_addr == 32'h10005000 &&
              gpu_ready && !cpu_ready,
              "immediate contested completion selects GPU after CPU win");

        @(posedge clk);
        #1;

        // GPU just won, therefore CPU must win the next tie.
        @(negedge clk);

        cpu_addr = 32'h10000160;
        gpu_addr = 32'h10006000;
        sdram_ready = 1'b0;
        #1;

        check(sdram_addr == 32'h10000160,
              "round-robin returns contested priority to CPU");

        // The CPU grant becomes held at the next edge.
        @(posedge clk);
        #1;

        // Reset must cancel a held grant and suppress the target.
        @(negedge clk);
        reset = 1'b1;
        #1;

        check(!sdram_valid,
              "reset suppresses an in-progress granted request");
        check(!cpu_ready && !gpu_ready,
              "reset suppresses master completion signals");

        @(posedge clk);
        #1;

        @(negedge clk);
        cpu_valid   = 1'b0;
        gpu_valid   = 1'b0;
        sdram_ready = 1'b0;
        reset       = 1'b0;
        #1;

        check(!sdram_valid &&
              !cpu_ready &&
              !gpu_ready,
              "arbiter returns to deterministic idle state");

        check(sdram_addr == 32'h00000000 &&
              sdram_wdata == 32'h00000000 &&
              sdram_wstrb == 4'b0000,
              "idle shared request fields are deterministic zero");

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("==============================");
            $finish;
        end else begin
            $display("RESULT: FAIL  (%0d failures / %0d checks)",
                     failures, checks);
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
