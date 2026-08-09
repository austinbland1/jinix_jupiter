`timescale 1ns/1ps

module jupiter_dma_multiword_tb;

    localparam [31:0] REG_CONTROL      = 32'h00001200;
    localparam [31:0] REG_STATUS       = 32'h00001204;
    localparam [31:0] REG_SRC_BASE     = 32'h00001208;
    localparam [31:0] REG_DST_BASE     = 32'h0000120C;
    localparam [31:0] REG_LENGTH_WORDS = 32'h00001210;

    localparam [31:0] SRC_BASE = 32'h10010000;
    localparam [31:0] DST_BASE = 32'h10020000;
    localparam integer WORD_COUNT = 4;

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

    integer logical_read_count = 0;
    integer logical_write_count = 0;

    reg [31:0] source_words [0:WORD_COUNT-1];
    reg [31:0] observed_writes [0:WORD_COUNT-1];

    integer i;

    jupiter_dma dut
    (
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

            if (condition)
                $display("PASS: %0s", message);
            else begin
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
            addr  = wr_addr;
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
            addr  = 32'h00000000;
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
            addr  = rd_addr;
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
            addr  = 32'h00000000;
        end
    endtask

    task automatic complete_read;
        input integer index;
        reg [31:0] expected_addr;
        integer stall;
        begin
            expected_addr =
                SRC_BASE + (index * 4);

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == expected_addr &&
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000,
                "next multiword transaction is exact source read"
            );

            // Deliberately stall every read.
            for (stall = 0;
                 stall < (index + 1);
                 stall = stall + 1) begin

                @(posedge clk);
                #1;

                check(
                    sdram_valid &&
                    !sdram_write &&
                    sdram_addr == expected_addr &&
                    sdram_wdata == 32'h00000000 &&
                    sdram_wstrb == 4'b0000,
                    "multiword source request remains stable while stalled"
                );
            end

            @(negedge clk);

            sdram_rdata =
                source_words[index];

            sdram_ready = 1'b1;
            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == expected_addr,
                "multiword source address remains exact on completion"
            );

            @(posedge clk);
            #1;

            check(
                dut.read_data_reg ==
                source_words[index],
                "multiword source data is captured exactly"
            );

            check(
                dut.transfer_state == 2'd2,
                "completed source read transitions to destination write"
            );

            @(negedge clk);
            sdram_ready = 1'b0;
            #1;
        end
    endtask

    task automatic complete_write;
        input integer index;
        input integer final_word;
        reg [31:0] expected_addr;
        integer stall;
        begin
            expected_addr =
                DST_BASE + (index * 4);

            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr == expected_addr &&
                sdram_wdata == source_words[index] &&
                sdram_wstrb == 4'b1111,
                "next multiword transaction is exact destination write"
            );

            // Use a different deterministic stall length from reads.
            for (stall = 0;
                 stall < (WORD_COUNT - index);
                 stall = stall + 1) begin

                @(posedge clk);
                #1;

                check(
                    sdram_valid &&
                    sdram_write &&
                    sdram_addr == expected_addr &&
                    sdram_wdata == source_words[index] &&
                    sdram_wstrb == 4'b1111,
                    "multiword destination request remains stable while stalled"
                );
            end

            @(negedge clk);
            sdram_ready = 1'b1;
            #1;

            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr == expected_addr &&
                sdram_wdata == source_words[index] &&
                sdram_wstrb == 4'b1111,
                "multiword destination fields remain exact on completion"
            );

            @(posedge clk);
            #1;

            if (final_word) begin
                check(
                    !dut.busy &&
                    dut.done &&
                    dut.transfer_state == 2'd0,
                    "final multiword write completes DMA exactly once"
                );
            end else begin
                check(
                    dut.busy &&
                    !dut.done &&
                    dut.transfer_state == 2'd1,
                    "non-final write returns DMA to source-read state"
                );

                check(
                    dut.current_src_addr ==
                        SRC_BASE + ((index + 1) * 4) &&
                    dut.current_dst_addr ==
                        DST_BASE + ((index + 1) * 4),
                    "non-final write advances both addresses by exactly four"
                );

                check(
                    dut.remaining_words ==
                        WORD_COUNT - index - 1,
                    "non-final write decrements remaining count exactly once"
                );
            end

            @(negedge clk);
            sdram_ready = 1'b0;
            #1;
        end
    endtask

    always @(posedge clk) begin
        if (!reset &&
            sdram_valid &&
            sdram_ready) begin

            if (sdram_write) begin
                logical_write_count <=
                    logical_write_count + 1;

                case (sdram_addr)
                    DST_BASE:
                        observed_writes[0] <=
                            sdram_wdata;

                    DST_BASE + 32'd4:
                        observed_writes[1] <=
                            sdram_wdata;

                    DST_BASE + 32'd8:
                        observed_writes[2] <=
                            sdram_wdata;

                    DST_BASE + 32'd12:
                        observed_writes[3] <=
                            sdram_wdata;

                    default: begin
                    end
                endcase
            end else begin
                logical_read_count <=
                    logical_read_count + 1;
            end
        end
    end

    initial begin
        source_words[0] = 32'h11223344;
        source_words[1] = 32'h89ABCDEF;
        source_words[2] = 32'hCAFEBABE;
        source_words[3] = 32'h0BADF00D;

        for (i = 0;
             i < WORD_COUNT;
             i = i + 1) begin

            observed_writes[i] =
                32'h00000000;
        end

        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.busy &&
            !dut.done &&
            !sdram_valid,
            "multiword test begins from deterministic reset state"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_write(
            REG_SRC_BASE,
            SRC_BASE,
            4'b1111
        );

        mmio_write(
            REG_DST_BASE,
            DST_BASE,
            4'b1111
        );

        mmio_write(
            REG_LENGTH_WORDS,
            WORD_COUNT,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy &&
            !dut.done,
            "four-word START enters BUSY state"
        );

        check(
            dut.active_src_base == SRC_BASE &&
            dut.active_dst_base == DST_BASE &&
            dut.active_length_words == WORD_COUNT,
            "four-word START snapshots complete configuration"
        );

        check(
            dut.current_src_addr == SRC_BASE &&
            dut.current_dst_addr == DST_BASE &&
            dut.remaining_words == WORD_COUNT,
            "four-word START initializes exact progress state"
        );

        for (i = 0;
             i < WORD_COUNT;
             i = i + 1) begin

            complete_read(i);

            check(
                dut.busy &&
                !dut.done,
                "DMA remains BUSY between source read and destination write"
            );

            complete_write(
                i,
                i == (WORD_COUNT - 1)
            );
        end

        check(
            logical_read_count == WORD_COUNT,
            "four-word transfer completes exactly four source reads"
        );

        check(
            logical_write_count == WORD_COUNT,
            "four-word transfer completes exactly four destination writes"
        );

        for (i = 0;
             i < WORD_COUNT;
             i = i + 1) begin

            check(
                observed_writes[i] ==
                source_words[i],
                "destination write sequence preserves exact source word"
            );
        end

        check(
            dut.current_src_addr ==
                SRC_BASE + (WORD_COUNT * 4) &&
            dut.current_dst_addr ==
                DST_BASE + (WORD_COUNT * 4),
            "completed multiword transfer advances both addresses exactly"
        );

        check(
            dut.remaining_words == 32'h00000000,
            "completed multiword transfer leaves zero words remaining"
        );

        check(
            dut.active_src_base == SRC_BASE &&
            dut.active_dst_base == DST_BASE &&
            dut.active_length_words == WORD_COUNT,
            "multiword completion preserves START snapshot"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "multiword completion returns DMA master to idle"
        );

        mmio_read(
            REG_STATUS,
            32'h00000002,
            "STATUS reports DONE after exact four-word transfer"
        );

        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.busy &&
            dut.done &&
            logical_read_count == WORD_COUNT &&
            logical_write_count == WORD_COUNT,
            "idle cycles after completion create no extra DMA transactions"
        );

        check(
            source_words[0] == 32'h11223344 &&
            source_words[1] == 32'h89ABCDEF &&
            source_words[2] == 32'hCAFEBABE &&
            source_words[3] == 32'h0BADF00D,
            "standalone source pattern remains unchanged"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display(
                "RESULT: PASS  (%0d checks)",
                checks
            );

            $display(
                "LOGICAL_READS: %0d",
                logical_read_count
            );

            $display(
                "LOGICAL_WRITES: %0d",
                logical_write_count
            );

            $display(
                "LOGICAL_TOTAL: %0d",
                logical_read_count +
                logical_write_count
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
