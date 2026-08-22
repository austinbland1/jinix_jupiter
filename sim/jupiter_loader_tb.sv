`timescale 1ns/1ps

module jupiter_loader_tb;

    reg         clk;
    reg         reset;

    reg         ioctl_download;
    reg  [15:0] ioctl_index;
    reg         ioctl_wr;
    reg  [26:0] ioctl_addr;
    reg   [7:0] ioctl_dout;
    wire        ioctl_wait;

    reg         mmio_valid;
    reg         mmio_write;
    reg  [31:0] mmio_addr;
    reg  [31:0] mmio_wdata;
    reg   [3:0] mmio_wstrb;
    wire [31:0] mmio_rdata;
    wire        mmio_ready;

    reg         sdram_size_valid;
    reg  [31:0] sdram_max_addr;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;
    reg         sdram_ready;

    wire        loader_active;

    integer checks;
    integer failures;
    integer write_count;

    reg [31:0] write_addr_0;
    reg [31:0] write_data_0;
    reg [31:0] write_addr_1;
    reg [31:0] write_data_1;

    jupiter_loader dut
    (
        .clk              (clk),
        .reset            (reset),

        .ioctl_download   (ioctl_download),
        .ioctl_index      (ioctl_index),
        .ioctl_wr         (ioctl_wr),
        .ioctl_addr       (ioctl_addr),
        .ioctl_dout       (ioctl_dout),
        .ioctl_wait       (ioctl_wait),

        .mmio_valid       (mmio_valid),
        .mmio_write       (mmio_write),
        .mmio_addr        (mmio_addr),
        .mmio_wdata       (mmio_wdata),
        .mmio_wstrb       (mmio_wstrb),
        .mmio_rdata       (mmio_rdata),
        .mmio_ready       (mmio_ready),

        .sdram_size_valid (sdram_size_valid),
        .sdram_max_addr   (sdram_max_addr),

        .sdram_valid      (sdram_valid),
        .sdram_write      (sdram_write),
        .sdram_addr       (sdram_addr),
        .sdram_wdata      (sdram_wdata),
        .sdram_wstrb      (sdram_wstrb),
        .sdram_ready      (sdram_ready),

        .loader_active    (loader_active)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset &&
            sdram_valid &&
            sdram_ready) begin

            if (write_count == 0) begin
                write_addr_0 <= sdram_addr;
                write_data_0 <= sdram_wdata;
            end

            if (write_count == 1) begin
                write_addr_1 <= sdram_addr;
                write_data_1 <= sdram_wdata;
            end

            write_count <=
                write_count + 1;
        end
    end

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
            ioctl_download = 1'b0;
            ioctl_index = 16'd0;
            ioctl_wr = 1'b0;
            ioctl_addr = 27'd0;
            ioctl_dout = 8'd0;

            mmio_valid = 1'b0;
            mmio_write = 1'b0;
            mmio_addr = 32'd0;
            mmio_wdata = 32'd0;
            mmio_wstrb = 4'd0;

            sdram_size_valid = 1'b1;
            sdram_max_addr = 32'h11FFFFFF;
            sdram_ready = 1'b1;

            write_count = 0;
            write_addr_0 = 32'd0;
            write_data_0 = 32'd0;
            write_addr_1 = 32'd0;
            write_data_1 = 32'd0;

            step;
            step;

            @(negedge clk);
            reset = 1'b0;
            step;
        end
    endtask

    task start_download;
        input [15:0] index;
        begin
            @(negedge clk);
            ioctl_index = index;
            ioctl_addr = 27'd0;
            ioctl_download = 1'b1;
            step;
        end
    endtask

    task stop_download;
        begin
            @(negedge clk);
            ioctl_download = 1'b0;
            ioctl_wr = 1'b0;
            step;
        end
    endtask

    task send_byte;
        input [7:0] value;
        begin
            while (ioctl_wait)
                step;

            @(negedge clk);
            ioctl_dout = value;
            ioctl_wr = 1'b1;

            step;

            @(negedge clk);
            ioctl_wr = 1'b0;
            ioctl_addr = ioctl_addr + 27'd1;
        end
    endtask

    task read_mmio;
        input [31:0] address;
        output [31:0] value;
        begin
            mmio_addr = address;
            mmio_write = 1'b0;
            mmio_valid = 1'b1;
            #1;
            value = mmio_rdata;
            check(mmio_ready === 1'b1, "MMIO read must complete immediately");
            mmio_valid = 1'b0;
            #1;
        end
    endtask

    reg [31:0] value;

    initial begin
        clk = 1'b0;
        reset = 1'b0;
        ioctl_download = 1'b0;
        ioctl_index = 16'd0;
        ioctl_wr = 1'b0;
        ioctl_addr = 27'd0;
        ioctl_dout = 8'd0;
        mmio_valid = 1'b0;
        mmio_write = 1'b0;
        mmio_addr = 32'd0;
        mmio_wdata = 32'd0;
        mmio_wstrb = 4'd0;
        sdram_size_valid = 1'b1;
        sdram_max_addr = 32'h11FFFFFF;
        sdram_ready = 1'b1;
        checks = 0;
        failures = 0;
        write_count = 0;

        // Reset-state MMIO.
        reset_dut;
        read_mmio(32'h00001500, value);
        check(value == 32'h00000000, "STATUS must reset to zero");
        read_mmio(32'h00001504, value);
        check(value == 32'h00000000, "LOAD_SIZE must reset to zero");
        read_mmio(32'h00001508, value);
        check(value == 32'h10000000, "LOAD_BASE must read 0x10000000");
        read_mmio(32'h0000150C, value);
        check(value == 32'h00000000, "reserved loader MMIO offset must read zero");

        // Non-matching index is completely ignored.
        start_download(16'h0002);
        check(loader_active === 1'b0, "non-matching download must not assert loader_active");
        send_byte(8'h44);
        send_byte(8'h33);
        send_byte(8'h22);
        send_byte(8'h11);
        stop_download;
        step;
        check(write_count == 0, "non-matching download must not write SDRAM");
        read_mmio(32'h00001500, value);
        check(value == 32'h00000000, "non-matching download must not change STATUS");

        // Two complete little-endian words and address auto-increment.
        reset_dut;
        start_download(16'h0001);
        check(loader_active === 1'b1, "matching download must assert loader_active");
        send_byte(8'h44);
        send_byte(8'h33);
        send_byte(8'h22);
        send_byte(8'h11);
        send_byte(8'hDD);
        send_byte(8'hCC);
        send_byte(8'hBB);
        send_byte(8'hAA);
        stop_download;
        step;
        check(write_count == 2, "two complete words must produce two SDRAM writes");
        check(write_addr_0 == 32'h10000000, "first write address must equal LOAD_BASE");
        check(write_data_0 == 32'h11223344, "first word must assemble low byte first");
        check(write_addr_1 == 32'h10000004, "second write address must auto-increment by four");
        check(write_data_1 == 32'hAABBCCDD, "second word must assemble low byte first");
        read_mmio(32'h00001500, value);
        check(value[2] == 1'b0, "LOADING must clear after completion");
        check(value[0] == 1'b1, "DONE must set after matching download completion");
        check(value[1] == 1'b0, "OVERFLOW must remain clear for in-range load");
        read_mmio(32'h00001504, value);
        check(value == 32'd8, "LOAD_SIZE must count bytes actually written");

        // A trailing partial word is discarded.
        reset_dut;
        start_download(16'h0001);
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h03);
        stop_download;
        step;
        check(write_count == 0, "partial trailing word must be discarded");
        read_mmio(32'h00001504, value);
        check(value == 32'd0, "partial trailing word must not increase LOAD_SIZE");
        read_mmio(32'h00001500, value);
        check(value[0] == 1'b1, "DONE must still set after partial-tail completion");

        // Backpressure is exported through ioctl_wait until the shared path
        // returns ready.
        reset_dut;
        sdram_ready = 1'b0;
        start_download(16'h0001);
        send_byte(8'h78);
        send_byte(8'h56);
        send_byte(8'h34);
        send_byte(8'h12);
        #1;
        check(sdram_valid === 1'b1, "complete word must become an SDRAM request");
        check(ioctl_wait === 1'b1, "outstanding unready word must assert ioctl_wait");
        check(loader_active === 1'b1, "outstanding word must keep loader_active asserted");

        @(negedge clk);
        sdram_ready = 1'b1;
        step;
        #1;
        check(ioctl_wait === 1'b0, "ioctl_wait must clear when write completes");
        stop_download;
        step;
        check(write_count == 1, "backpressured word must complete exactly once");

        // Capacity boundary: only one word fits.
        reset_dut;
        sdram_max_addr = 32'h10000003;
        start_download(16'h0001);
        send_byte(8'h04);
        send_byte(8'h03);
        send_byte(8'h02);
        send_byte(8'h01);
        send_byte(8'h08);
        send_byte(8'h07);
        send_byte(8'h06);
        send_byte(8'h05);
        stop_download;
        step;
        check(write_count == 1, "overflow must suppress writes beyond installed capacity");
        read_mmio(32'h00001504, value);
        check(value == 32'd4, "LOAD_SIZE must stop at bytes successfully written");
        read_mmio(32'h00001500, value);
        check(value[1] == 1'b1, "OVERFLOW must become sticky when next word exceeds capacity");

        // No SDRAM configuration accepts bytes but emits no writes.
        reset_dut;
        sdram_size_valid = 1'b0;
        sdram_max_addr = 32'h00000000;
        start_download(16'h0001);
        send_byte(8'hEF);
        send_byte(8'hBE);
        send_byte(8'hAD);
        send_byte(8'hDE);
        stop_download;
        step;
        check(write_count == 0, "no-SDRAM configuration must suppress writes");
        check(ioctl_wait === 1'b0, "overflow discard path must not deadlock HPS transfer");
        read_mmio(32'h00001500, value);
        check(value[1] == 1'b1, "no-SDRAM complete word must set OVERFLOW");

        // Sticky status clears only when the next matching download begins.
        start_download(16'h0002);
        step;
        read_mmio(32'h00001500, value);
        check(value[1] == 1'b1, "non-matching download must not clear OVERFLOW");
        stop_download;

        start_download(16'h0001);
        read_mmio(32'h00001500, value);
        check(value[0] == 1'b0, "new matching download must clear DONE");
        check(value[1] == 1'b0, "new matching download must clear OVERFLOW");
        stop_download;

        // Writes to the read-side loader aperture are ignored.
        mmio_addr = 32'h00001508;
        mmio_wdata = 32'hDEADBEEF;
        mmio_wstrb = 4'hF;
        mmio_write = 1'b1;
        mmio_valid = 1'b1;
        #1;
        check(mmio_ready === 1'b1, "loader MMIO write must complete deterministically");
        mmio_valid = 1'b0;
        mmio_write = 1'b0;
        read_mmio(32'h00001508, value);
        check(value == 32'h10000000, "loader MMIO writes must not alter LOAD_BASE");

        if (failures == 0) begin
            $display("PASS: jupiter_loader (%0d checks)", checks);
            $finish;
        end

        $display("FAIL: jupiter_loader %0d/%0d checks failed", failures, checks);
        $fatal(1);
    end

endmodule
