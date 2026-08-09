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
            "DMA SDRAM master resets deterministically idle"
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

        // ----------------------------------------------------
        // M6D-1: deterministic one-word transfer.
        // ----------------------------------------------------
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
            32'h00000001,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy && !dut.done,
            "single-word START asserts BUSY and clears DONE"
        );

        check(
            dut.active_src_base == 32'h10030000,
            "single-word START snapshots SRC_BASE"
        );

        check(
            dut.active_dst_base == 32'h10040000,
            "single-word START snapshots DST_BASE"
        );

        check(
            dut.active_length_words == 32'h00000001,
            "single-word START snapshots LENGTH_WORDS"
        );

        check(
            dut.current_src_addr == 32'h10030000 &&
            dut.current_dst_addr == 32'h10040000 &&
            dut.remaining_words == 32'h00000001,
            "single-word START initializes active progress"
        );

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10030000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "DMA begins with aligned 32-bit source read"
        );

        mmio_read(
            REG_STATUS,
            32'h00000001,
            "STATUS reports BUSY during stalled source read"
        );

        // Live configuration stays writable while the active read stalls.
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
            dut.active_length_words == 32'h00000001,
            "live writes do not alter active DMA snapshot"
        );

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10030000,
            "live MMIO writes do not alter stalled source request"
        );

        // BUSY START must not replace the active transfer.
        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.active_src_base == 32'h10030000 &&
            dut.active_dst_base == 32'h10040000 &&
            dut.active_length_words == 32'h00000001,
            "START while BUSY does not replace active snapshot"
        );

        check(
            dut.busy && !dut.done,
            "START while BUSY leaves transfer status unchanged"
        );

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10030000,
            "BUSY START does not disturb stalled source read"
        );

        // The source request must remain stable for arbitrary stalls.
        sdram_rdata = 32'hDEADBEEF;

        repeat (3) begin
            @(posedge clk);
            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == 32'h10030000 &&
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000,
                "source read request remains stable while stalled"
            );
        end

        check(
            dut.read_data_reg == 32'h00000000,
            "stalled source data is not captured before ready"
        );

        // Complete exactly one source read.
        @(negedge clk);
        sdram_rdata = 32'hCAFEBABE;
        sdram_ready = 1'b1;
        #1;

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10030000,
            "source read presents stable request on completion"
        );

        @(posedge clk);
        #1;

        check(
            dut.busy && !dut.done,
            "source completion keeps DMA BUSY for destination write"
        );

        check(
            dut.read_data_reg == 32'hCAFEBABE,
            "completed source read captures exact 32-bit data"
        );

        check(
            sdram_valid &&
            sdram_write &&
            sdram_addr == 32'h10040000 &&
            sdram_wdata == 32'hCAFEBABE &&
            sdram_wstrb == 4'b1111,
            "captured source word becomes destination write"
        );

        // Stall the destination write and change read-side input data.
        // The captured write payload must remain unchanged.
        @(negedge clk);
        sdram_ready = 1'b0;
        sdram_rdata = 32'h01234567;
        #1;

        repeat (3) begin
            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr == 32'h10040000 &&
                sdram_wdata == 32'hCAFEBABE &&
                sdram_wstrb == 4'b1111,
                "destination write request remains stable while stalled"
            );

            @(posedge clk);
            #1;
        end

        check(
            dut.read_data_reg == 32'hCAFEBABE,
            "captured source word remains stable through write stall"
        );

        check(
            dut.current_src_addr == 32'h10030000 &&
            dut.current_dst_addr == 32'h10040000 &&
            dut.remaining_words == 32'h00000001,
            "addresses and remaining count do not advance before write ready"
        );

        // Complete the destination write.
        @(negedge clk);
        sdram_ready = 1'b1;
        #1;

        check(
            sdram_valid &&
            sdram_write &&
            sdram_addr == 32'h10040000 &&
            sdram_wdata == 32'hCAFEBABE &&
            sdram_wstrb == 4'b1111,
            "destination write fields remain stable on completion"
        );

        @(posedge clk);
        #1;

        check(
            !dut.busy && dut.done,
            "final destination write clears BUSY and asserts DONE"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "completed DMA returns memory master to deterministic idle"
        );

        check(
            dut.current_src_addr == 32'h10030004 &&
            dut.current_dst_addr == 32'h10040004,
            "completed word increments source and destination by four"
        );

        check(
            dut.remaining_words == 32'h00000000,
            "completed word decrements remaining count to zero"
        );

        check(
            dut.active_src_base == 32'h10030000 &&
            dut.active_dst_base == 32'h10040000 &&
            dut.active_length_words == 32'h00000001,
            "completion preserves original START snapshot"
        );

        @(negedge clk);
        sdram_ready = 1'b0;

        mmio_read(
            REG_STATUS,
            32'h00000002,
            "STATUS reports sticky DONE after single-word transfer"
        );

        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.busy && dut.done,
            "DONE remains sticky after functional transfer"
        );

        // Reset clears control, progress, and captured-data state.
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
            dut.current_src_addr == 32'h00000000 &&
            dut.current_dst_addr == 32'h00000000 &&
            dut.remaining_words == 32'h00000000 &&
            dut.read_data_reg == 32'h00000000,
            "reset clears DMA transfer progress"
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
