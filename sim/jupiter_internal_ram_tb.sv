`timescale 1ns/1ps

module jupiter_internal_ram_tb;

    reg         clk;

    reg         valid;
    reg         write;
    reg  [31:0] addr;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;

    wire [31:0] rdata;
    wire        ready;

    integer checks;
    integer failures;

    jupiter_internal_ram dut
    (
        .clk   (clk),

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

    task write_word;
        input [31:0] address;
        input [31:0] data;
        input [3:0]  strobes;
        begin
            @(negedge clk);
            valid = 1'b1;
            write = 1'b1;
            addr  = address;
            wdata = data;
            wstrb = strobes;

            #1;
            check(ready,
                  "valid RAM write is immediately ready");

            @(posedge clk);
            #1;

            @(negedge clk);
            valid = 1'b0;
            write = 1'b0;
            wstrb = 4'b0000;
        end
    endtask

    task read_word;
        input [31:0] address;
        input [31:0] expected;
        begin
            @(negedge clk);
            valid = 1'b1;
            write = 1'b0;
            addr  = address;
            wstrb = 4'b0000;

            #1;
            check(ready,
                  "valid RAM read is immediately ready");
            check(rdata == expected,
                  "RAM read returns expected word");

            @(posedge clk);
            #1;

            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    initial begin
        clk      = 1'b0;
        valid    = 1'b0;
        write    = 1'b0;
        addr     = 32'h00000000;
        wdata    = 32'h00000000;
        wstrb    = 4'b0000;

        checks   = 0;
        failures = 0;

        #1;

        check(!ready,
              "idle RAM does not acknowledge a transaction");
        check(rdata == 32'h00000000,
              "idle RAM read data is deterministic zero");

        // Full-word write/read at the first RAM location.
        write_word(32'h00000000, 32'h11223344, 4'b1111);
        read_word (32'h00000000, 32'h11223344);

        // A separate word must retain independent state.
        write_word(32'h00000004, 32'hA5A55A5A, 4'b1111);
        read_word (32'h00000004, 32'hA5A55A5A);
        read_word (32'h00000000, 32'h11223344);

        // Verify individual byte enables.
        write_word(32'h00000000, 32'hFFEEDDCC, 4'b0001);
        read_word (32'h00000000, 32'h112233CC);

        write_word(32'h00000000, 32'hFFEEDDCC, 4'b0010);
        read_word (32'h00000000, 32'h1122DDCC);

        write_word(32'h00000000, 32'hFFEEDDCC, 4'b0100);
        read_word (32'h00000000, 32'h11EEDDCC);

        write_word(32'h00000000, 32'hFFEEDDCC, 4'b1000);
        read_word (32'h00000000, 32'hFFEEDDCC);

        // Zero strobes must leave the word unchanged.
        write_word(32'h00000000, 32'h00000000, 4'b0000);
        read_word (32'h00000000, 32'hFFEEDDCC);

        // Verify the highest aligned word in the 4 KiB region.
        write_word(32'h00000FFC, 32'hDEADBEEF, 4'b1111);
        read_word (32'h00000FFC, 32'hDEADBEEF);

        // Verify a middle location as another independent RAM word.
        write_word(32'h00000800, 32'hCAFEBABE, 4'b1111);
        read_word (32'h00000800, 32'hCAFEBABE);
        read_word (32'h00000FFC, 32'hDEADBEEF);

        // Return to idle.
        @(negedge clk);
        valid = 1'b0;
        write = 1'b0;
        #1;

        check(!ready,
              "RAM returns to idle after transactions");
        check(rdata == 32'h00000000,
              "idle read data returns to zero after transactions");

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
