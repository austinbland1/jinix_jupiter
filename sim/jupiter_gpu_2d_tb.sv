`timescale 1ns/1ps

module jupiter_gpu_2d_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001100;
    localparam [31:0] REG_STATUS           = 32'h00001104;
    localparam [31:0] REG_TILEMAP_BASE     = 32'h00001108;
    localparam [31:0] REG_TILEDATA_BASE    = 32'h0000110C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001110;
    localparam [31:0] REG_MAP_SIZE         = 32'h00001114;
    localparam [31:0] REG_RESERVED         = 32'h00001120;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        valid = 1'b0;
    reg        write = 1'b0;
    reg [31:0] addr  = 32'h00000000;
    reg [31:0] wdata = 32'h00000000;
    reg  [3:0] wstrb = 4'b0000;

    wire [31:0] rdata;
    wire        ready;

    integer checks = 0;
    reg [31:0] read_value;

    always #5 clk = ~clk;

    jupiter_gpu_2d dut
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

    task check;
        input condition;
        input [8*128-1:0] message;
        begin
            checks = checks + 1;

            if (!condition)
                $fatal(1, "FAIL: %0s", message);
            else
                $display("PASS: %0s", message);
        end
    endtask

    task mmio_write;
        input [31:0] write_addr;
        input [31:0] write_data;
        input  [3:0] write_strobes;
        begin
            @(negedge clk);
            valid = 1'b1;
            write = 1'b1;
            addr  = write_addr;
            wdata = write_data;
            wstrb = write_strobes;

            #1;
            check(ready == 1'b1,
                  "GPU MMIO write completes without wait state");

            @(posedge clk);
            #1;

            @(negedge clk);
            valid = 1'b0;
            write = 1'b0;
            addr  = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;
        end
    endtask

    task mmio_read;
        input  [31:0] read_addr;
        output [31:0] read_data;
        begin
            @(negedge clk);
            valid = 1'b1;
            write = 1'b0;
            addr  = read_addr;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;
            check(ready == 1'b1,
                  "GPU MMIO read completes without wait state");

            read_data = rdata;

            @(negedge clk);
            valid = 1'b0;
            addr  = 32'h00000000;
        end
    endtask

    initial begin
        check(ready == 1'b0,
              "idle GPU MMIO target does not assert ready");

        repeat (3) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;

        mmio_read(REG_CONTROL, read_value);
        check(read_value == 32'h00000000,
              "write-only CONTROL reads as zero");

        mmio_read(REG_STATUS, read_value);
        check(read_value == 32'h00000000,
              "STATUS resets with busy and done clear");

        mmio_read(REG_TILEMAP_BASE, read_value);
        check(read_value == 32'h00000000,
              "TILEMAP_BASE resets to zero");

        mmio_read(REG_TILEDATA_BASE, read_value);
        check(read_value == 32'h00000000,
              "TILEDATA_BASE resets to zero");

        mmio_read(REG_FRAMEBUFFER_BASE, read_value);
        check(read_value == 32'h00000000,
              "FRAMEBUFFER_BASE resets to zero");

        mmio_read(REG_MAP_SIZE, read_value);
        check(read_value == 32'h00000000,
              "MAP_SIZE resets to zero");

        mmio_read(REG_RESERVED, read_value);
        check(read_value == 32'h00000000,
              "reserved GPU MMIO offset reads as zero");

        // Full-word write followed by one-byte replacement.
        mmio_write(REG_TILEMAP_BASE, 32'h11223344, 4'b1111);
        mmio_write(REG_TILEMAP_BASE, 32'hAABBCCDD, 4'b0010);
        mmio_read(REG_TILEMAP_BASE, read_value);
        check(read_value == 32'h1122CC44,
              "TILEMAP_BASE honors byte write strobes");

        mmio_write(REG_TILEDATA_BASE, 32'h10002000, 4'b1111);
        mmio_write(REG_FRAMEBUFFER_BASE, 32'h10004000, 4'b1111);

        // MAP_SIZE implements only the low sixteen bits.
        mmio_write(REG_MAP_SIZE, 32'hA5A50102, 4'b1111);
        mmio_read(REG_MAP_SIZE, read_value);
        check(read_value == 32'h00000102,
              "MAP_SIZE stores width and height bytes only");

        // STATUS is read-only.
        mmio_write(REG_STATUS, 32'hFFFFFFFF, 4'b1111);
        mmio_read(REG_STATUS, read_value);
        check(read_value == 32'h00000000,
              "writes to STATUS are ignored");

        // Reserved writes must not alter implemented registers.
        mmio_write(REG_RESERVED, 32'hDEADBEEF, 4'b1111);
        mmio_read(REG_TILEMAP_BASE, read_value);
        check(read_value == 32'h1122CC44,
              "reserved write does not corrupt TILEMAP_BASE");

        // A CONTROL write without the low-byte strobe cannot start.
        mmio_write(REG_CONTROL, 32'h00000001, 4'b0010);
        mmio_read(REG_STATUS, read_value);
        check(read_value == 32'h00000000,
              "CONTROL.START requires low-byte write strobe");

        // Width zero is a real architecture-defined no-memory completion.
        mmio_write(REG_MAP_SIZE, 32'h00000100, 4'b0011);
        mmio_write(REG_CONTROL, 32'h00000001, 4'b0001);

        mmio_read(REG_STATUS, read_value);
        check(read_value == 32'h00000002,
              "zero-width operation completes immediately with done set");

        check(dut.active_tilemap_base == 32'h1122CC44,
              "start snapshots TILEMAP_BASE");
        check(dut.active_tiledata_base == 32'h10002000,
              "start snapshots TILEDATA_BASE");
        check(dut.active_framebuffer_base == 32'h10004000,
              "start snapshots FRAMEBUFFER_BASE");
        check(dut.active_map_size == 16'h0100,
              "start snapshots MAP_SIZE");

        // Configure a real nonzero image and start it.
        mmio_write(REG_TILEMAP_BASE, 32'h10008000, 4'b1111);
        mmio_write(REG_TILEDATA_BASE, 32'h1000A000, 4'b1111);
        mmio_write(REG_FRAMEBUFFER_BASE, 32'h1000C000, 4'b1111);
        mmio_write(REG_MAP_SIZE, 32'h00000202, 4'b0011);
        mmio_write(REG_CONTROL, 32'h00000001, 4'b0001);

        mmio_read(REG_STATUS, read_value);
        check(read_value == 32'h00000001,
              "nonzero operation asserts busy and clears done");

        check(dut.active_tilemap_base == 32'h10008000,
              "nonzero start snapshots TILEMAP_BASE");
        check(dut.active_tiledata_base == 32'h1000A000,
              "nonzero start snapshots TILEDATA_BASE");
        check(dut.active_framebuffer_base == 32'h1000C000,
              "nonzero start snapshots FRAMEBUFFER_BASE");
        check(dut.active_map_size == 16'h0202,
              "nonzero start snapshots MAP_SIZE");

        // Live configuration may change while busy, but the active
        // operation snapshot must not.
        mmio_write(REG_TILEMAP_BASE, 32'h1000E000, 4'b1111);
        mmio_write(REG_CONTROL, 32'h00000001, 4'b0001);

        check(dut.active_tilemap_base == 32'h10008000,
              "start request while busy does not replace active snapshot");
        check(dut.active_map_size == 16'h0202,
              "busy start request leaves active size unchanged");

        mmio_read(REG_TILEMAP_BASE, read_value);
        check(read_value == 32'h1000E000,
              "live configuration remains writable while busy");

        mmio_read(REG_STATUS, read_value);
        check(read_value == 32'h00000001,
              "M5B-1 does not fake completion of nonzero rendering");

        // Reset remains the only way M5B-1 clears a nonzero busy state.
        @(negedge clk);
        reset = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        mmio_read(REG_STATUS, read_value);
        check(read_value == 32'h00000000,
              "reset clears busy and done");

        mmio_read(REG_TILEMAP_BASE, read_value);
        check(read_value == 32'h00000000,
              "reset clears GPU configuration registers");

        $display("");
        $display("==============================");
        $display("RESULT: PASS  (%0d checks)", checks);
        $display("==============================");

        $finish(0);
    end

endmodule
