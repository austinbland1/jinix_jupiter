`timescale 1ns/1ps

module jupiter_dma_tb;

    localparam [31:0] REG_CONTROL      = 32'h00001200;
    localparam [31:0] REG_STATUS       = 32'h00001204;
    localparam [31:0] REG_SRC_BASE     = 32'h00001208;
    localparam [31:0] REG_DST_BASE     = 32'h0000120C;
    localparam [31:0] REG_LENGTH_WORDS = 32'h00001210;
    localparam [31:0] REG_RESERVED     = 32'h00001214;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        valid = 1'b0;
    reg        write = 1'b0;
    reg [31:0] addr = 32'h00000000;
    reg [31:0] wdata = 32'h00000000;
    reg  [3:0] wstrb = 4'b0000;

    wire [31:0] rdata;
    wire        ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;

    reg [31:0] sdram_rdata = 32'h00000000;
    reg        sdram_ready = 1'b0;

    integer checks = 0;
    integer failures = 0;

    jupiter_dma dut (
        .clk         (clk),
        .reset       (reset),

        .valid       (valid),
        .write       (write),
        .addr        (addr),
        .wdata       (wdata),
        .wstrb       (wstrb),
        .rdata       (rdata),
        .ready       (ready),

        .sdram_valid (sdram_valid),
        .sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );

    always #5 clk = ~clk;

    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin
            checks = checks + 1;

            if (condition) begin
                $display("PASS: %0s", message);
            end else begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task automatic mmio_write;
        input [31:0] wr_addr;
        input [31:0] wr_data;
        input  [3:0] wr_strb;
        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b1;
            addr = wr_addr;
            wdata = wr_data;
            wstrb = wr_strb;

            @(posedge clk);
            #1;

            check(
                ready,
                "DMA MMIO write completes without wait state"
            );

            @(negedge clk);

            valid = 1'b0;
            write = 1'b0;
            addr = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;
        end
    endtask

    task automatic mmio_read;
        input [31:0] rd_addr;
        input [31:0] expected;
        input [8*128-1:0] message;
        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b0;
            addr = rd_addr;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;

            check(
                ready,
                "DMA MMIO read completes without wait state"
            );

            check(
                rdata == expected,
                message
            );

            @(negedge clk);

            valid = 1'b0;
            addr = 32'h00000000;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1;

        check(
            dut.src_base_reg == 32'h00000000,
            "SRC_BASE resets to zero"
        );

        check(
            dut.dst_base_reg == 32'h00000000,
            "DST_BASE resets to zero"
        );

        check(
            dut.length_words_reg == 32'h00000000,
            "LENGTH_WORDS resets to zero"
        );

        check(
            !dut.busy && !dut.done,
            "STATUS resets with BUSY and DONE clear"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "M6B-1 SDRAM master resets deterministically idle"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_read(
            REG_CONTROL,
            32'h00000000,
            "write-only CONTROL reads as zero"
        );

        mmio_read(
            REG_STATUS,
            32'h00000000,
            "STATUS begins idle and not done"
        );

        mmio_read(
            REG_SRC_BASE,
            32'h00000000,
            "SRC_BASE initial read is zero"
        );

        mmio_read(
            REG_DST_BASE,
            32'h00000000,
            "DST_BASE initial read is zero"
        );

        mmio_read(
            REG_LENGTH_WORDS,
            32'h00000000,
            "LENGTH_WORDS initial read is zero"
        );

        mmio_read(
            REG_RESERVED,
            32'h00000000,
            "reserved DMA register reads as zero"
        );

        // Full-width configuration writes.
        mmio_write(
            REG_SRC_BASE,
            32'h10001000,
            4'b1111
        );

        mmio_write(
            REG_DST_BASE,
            32'h10002000,
            4'b1111
        );

        mmio_write(
            REG_LENGTH_WORDS,
            32'h00000003,
            4'b1111
        );

        mmio_read(
            REG_SRC_BASE,
            32'h10001000,
            "SRC_BASE stores full-width write"
        );

        mmio_read(
            REG_DST_BASE,
            32'h10002000,
            "DST_BASE stores full-width write"
        );

        mmio_read(
            REG_LENGTH_WORDS,
            32'h00000003,
            "LENGTH_WORDS stores full-width write"
        );

        // Byte-lane behavior.
        mmio_write(
            REG_SRC_BASE,
            32'hAABBCCDD,
            4'b0101
        );

        mmio_read(
            REG_SRC_BASE,
            32'h10BB10DD,
            "SRC_BASE honors byte write strobes"
        );

        mmio_write(
            REG_DST_BASE,
            32'hAABBCCDD,
            4'b1010
        );

        mmio_read(
            REG_DST_BASE,
            32'hAA00CC00,
            "DST_BASE honors byte write strobes"
        );

        mmio_write(
            REG_LENGTH_WORDS,
            32'h11223344,
            4'b0011
        );

        mmio_read(
            REG_LENGTH_WORDS,
            32'h00003344,
            "LENGTH_WORDS honors byte write strobes"
        );

        // STATUS is read-only.
        mmio_write(
            REG_STATUS,
            32'hFFFFFFFF,
            4'b1111
        );

        mmio_read(
            REG_STATUS,
            32'h00000000,
            "writes to STATUS are ignored"
        );

        // Reserved writes have no effect.
        mmio_write(
            REG_RESERVED,
            32'hDEADBEEF,
            4'b1111
        );

        mmio_read(
            REG_RESERVED,
            32'h00000000,
            "reserved DMA write remains deterministic zero"
        );

        mmio_read(
            REG_SRC_BASE,
            32'h10BB10DD,
            "reserved write does not corrupt SRC_BASE"
        );

        // START requires the low-byte strobe.
        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0010
        );

        check(
            !dut.busy && !dut.done,
            "CONTROL.START requires low-byte write strobe"
        );

        // Zero-length transfer completes immediately.
        mmio_write(
            REG_SRC_BASE,
            32'h10010000,
            4'b1111
        );

        mmio_write(
            REG_DST_BASE,
            32'h10020000,
            4'b1111
        );

        mmio_write(
            REG_LENGTH_WORDS,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            !dut.busy && dut.done,
            "zero-length START completes immediately"
        );

        check(
            dut.active_src_base == 32'h10010000,
            "zero-length START snapshots SRC_BASE"
        );

        check(
            dut.active_dst_base == 32'h10020000,
            "zero-length START snapshots DST_BASE"
        );

        check(
            dut.active_length_words == 32'h00000000,
            "zero-length START snapshots LENGTH_WORDS"
        );

        mmio_read(
            REG_STATUS,
            32'h00000002,
            "STATUS reports DONE after zero-length transfer"
        );

        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.busy && dut.done,
            "DONE remains sticky while idle"
        );

        check(
            !sdram_valid,
            "zero-length transfer issues no SDRAM request"
        );

        // Nonzero START enters bounded B1 busy state.
        mmio_write(
            REG_SRC_BASE,
            32'h10030000,
            4'b1111
        );

        mmio_write(
            REG_DST_BASE,
            32'h10040000,
            4'b1111
        );

        mmio_write(
            REG_LENGTH_WORDS,
            32'h00000003,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy && !dut.done,
            "nonzero START asserts BUSY and clears DONE"
        );

        check(
            dut.active_src_base == 32'h10030000,
            "nonzero START snapshots SRC_BASE"
        );

        check(
            dut.active_dst_base == 32'h10040000,
            "nonzero START snapshots DST_BASE"
        );

        check(
            dut.active_length_words == 32'h00000003,
            "nonzero START snapshots LENGTH_WORDS"
        );

        mmio_read(
            REG_STATUS,
            32'h00000001,
            "STATUS reports BUSY for bounded B1 transfer state"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "M6B-1 does not fake DMA memory traffic"
        );

        // Live configuration stays writable while BUSY.
        mmio_write(
            REG_SRC_BASE,
            32'h10050000,
            4'b1111
        );

        mmio_write(
            REG_DST_BASE,
            32'h10060000,
            4'b1111
        );

        mmio_write(
            REG_LENGTH_WORDS,
            32'h00000008,
            4'b1111
        );

        mmio_read(
            REG_SRC_BASE,
            32'h10050000,
            "live SRC_BASE remains writable while BUSY"
        );

        mmio_read(
            REG_DST_BASE,
            32'h10060000,
            "live DST_BASE remains writable while BUSY"
        );

        mmio_read(
            REG_LENGTH_WORDS,
            32'h00000008,
            "live LENGTH_WORDS remains writable while BUSY"
        );

        check(
            dut.active_src_base == 32'h10030000 &&
            dut.active_dst_base == 32'h10040000 &&
            dut.active_length_words == 32'h00000003,
            "live writes do not alter active DMA snapshot"
        );

        // BUSY START is ignored.
        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.active_src_base == 32'h10030000 &&
            dut.active_dst_base == 32'h10040000 &&
            dut.active_length_words == 32'h00000003,
            "START while BUSY does not replace active snapshot"
        );

        check(
            dut.busy && !dut.done,
            "START while BUSY leaves status unchanged"
        );

        // Controller-side inputs cannot create fake B1 progress.
        sdram_rdata = 32'hCAFEBABE;
        sdram_ready = 1'b1;

        repeat (4) @(posedge clk);
        #1;

        check(
            dut.busy && !dut.done,
            "M6B-1 does not fake nonzero transfer completion"
        );

        check(
            !sdram_valid &&
            sdram_addr == 32'h00000000,
            "SDRAM inputs cannot create a B1 memory request"
        );

        // Reset clears all control and active state.
        @(negedge clk);
        reset = 1'b1;

        @(posedge clk);
        #1;

        check(
            !dut.busy && !dut.done,
            "reset clears BUSY and DONE"
        );

        check(
            dut.src_base_reg == 32'h00000000 &&
            dut.dst_base_reg == 32'h00000000 &&
            dut.length_words_reg == 32'h00000000,
            "reset clears live DMA configuration"
        );

        check(
            dut.active_src_base == 32'h00000000 &&
            dut.active_dst_base == 32'h00000000 &&
            dut.active_length_words == 32'h00000000,
            "reset clears active DMA snapshots"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "reset leaves DMA memory master deterministically idle"
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
