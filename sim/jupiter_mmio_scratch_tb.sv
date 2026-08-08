`timescale 1ns/1ps

module jupiter_mmio_scratch_tb;

    reg         clk;
    reg         reset;

    reg         valid;
    reg         write;
    reg  [31:0] addr;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;

    wire [31:0] rdata;
    wire        ready;

    integer checks;
    integer failures;

    jupiter_mmio_scratch dut
    (
        .clk   (clk),
        .reset (reset),

        .valid (valid),
        .write (write),
        .addr  (addr),
        .wdata (wdata),
        .wstrb (wstrb),

        .rdata (rdata),
        .ready (ready)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*100-1:0] message;
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

    task write_scratch;
        input [31:0] data;
        input [3:0]  strobes;
        begin
            @(negedge clk);
            valid = 1'b1;
            write = 1'b1;
            addr  = 32'h00001000;
            wdata = data;
            wstrb = strobes;

            #1;
            check(ready,
                  "valid MMIO write is immediately ready");
            check(rdata == 32'h00000000,
                  "MMIO write presents deterministic zero read data");

            @(posedge clk);
            #1;

            @(negedge clk);
            valid = 1'b0;
            write = 1'b0;
            wstrb = 4'b0000;
        end
    endtask

    task read_scratch;
        input [31:0] expected;
        begin
            @(negedge clk);
            valid = 1'b1;
            write = 1'b0;
            addr  = 32'h00001000;
            wstrb = 4'b0000;

            #1;
            check(ready,
                  "valid MMIO read is immediately ready");
            check(rdata == expected,
                  "MMIO read returns expected scratch value");

            @(posedge clk);
            #1;

            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    initial begin
        clk      = 1'b0;
        reset    = 1'b1;

        valid    = 1'b0;
        write    = 1'b0;
        addr     = 32'h00001000;
        wdata    = 32'h00000000;
        wstrb    = 4'b0000;

        checks   = 0;
        failures = 0;

        // Establish the documented synchronous reset state.
        repeat (2) @(posedge clk);
        #1;

        check(dut.scratch_reg == 32'h00000000,
              "reset clears scratch register");

        @(negedge clk);
        reset = 1'b0;
        #1;

        check(!ready,
              "idle MMIO target does not acknowledge");
        check(rdata == 32'h00000000,
              "idle MMIO read data is deterministic zero");

        // Full-word write and readback.
        write_scratch(32'h11223344, 4'b1111);
        read_scratch (32'h11223344);

        // Verify byte-write enables individually.
        write_scratch(32'hFFEEDDCC, 4'b0001);
        read_scratch (32'h112233CC);

        write_scratch(32'hFFEEDDCC, 4'b0010);
        read_scratch (32'h1122DDCC);

        write_scratch(32'hFFEEDDCC, 4'b0100);
        read_scratch (32'h11EEDDCC);

        write_scratch(32'hFFEEDDCC, 4'b1000);
        read_scratch (32'hFFEEDDCC);

        // Zero strobes leave the register unchanged.
        write_scratch(32'h00000000, 4'b0000);
        read_scratch (32'hFFEEDDCC);

        // Reset must clear previously written state.
        @(negedge clk);
        reset = 1'b1;

        @(posedge clk);
        #1;

        check(dut.scratch_reg == 32'h00000000,
              "reset clears previously written scratch state");

        @(negedge clk);
        reset = 1'b0;

        read_scratch(32'h00000000);

        // Return to idle.
        @(negedge clk);
        valid = 1'b0;
        write = 1'b0;
        #1;

        check(!ready,
              "MMIO target returns to idle");
        check(rdata == 32'h00000000,
              "idle read data remains deterministic zero");

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
