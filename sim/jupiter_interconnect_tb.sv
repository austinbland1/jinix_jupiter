`timescale 1ns/1ps

module jupiter_interconnect_tb;

    reg         m_valid;
    reg         m_write;
    reg  [31:0] m_addr;
    reg  [31:0] m_wdata;
    reg  [3:0]  m_wstrb;

    wire [31:0] m_rdata;
    wire        m_ready;

    wire        ram_valid;
    wire        ram_write;
    wire [31:0] ram_addr;
    wire [31:0] ram_wdata;
    wire [3:0]  ram_wstrb;

    reg  [31:0] ram_rdata;
    reg         ram_ready;

    wire        mmio_valid;
    wire        mmio_write;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [3:0]  mmio_wstrb;

    reg  [31:0] mmio_rdata;
    reg         mmio_ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire [3:0]  sdram_wstrb;

    reg  [31:0] sdram_rdata;
    reg         sdram_ready;

    integer checks;
    integer failures;

    jupiter_interconnect dut
    (
        .m_valid    (m_valid),
        .m_write    (m_write),
        .m_addr     (m_addr),
        .m_wdata    (m_wdata),
        .m_wstrb    (m_wstrb),

        .m_rdata    (m_rdata),
        .m_ready    (m_ready),

        .ram_valid  (ram_valid),
        .ram_write  (ram_write),
        .ram_addr   (ram_addr),
        .ram_wdata  (ram_wdata),
        .ram_wstrb  (ram_wstrb),
        .ram_rdata  (ram_rdata),
        .ram_ready  (ram_ready),

        .mmio_valid (mmio_valid),
        .mmio_write (mmio_write),
        .mmio_addr  (mmio_addr),
        .mmio_wdata (mmio_wdata),
        .mmio_wstrb (mmio_wstrb),
        .mmio_rdata (mmio_rdata),
        .mmio_ready (mmio_ready),

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

    initial begin
        checks   = 0;
        failures = 0;

        m_valid = 1'b0;
        m_write = 1'b0;
        m_addr  = 32'h00000000;
        m_wdata = 32'h00000000;
        m_wstrb = 4'b0000;

        ram_rdata = 32'h00000000;
        ram_ready = 1'b0;

        mmio_rdata = 32'h00000000;
        mmio_ready = 1'b0;

        sdram_rdata = 32'h00000000;
        sdram_ready = 1'b0;

        #1;

        check(!ram_valid && !mmio_valid && !sdram_valid,
              "idle master selects no target");
        check(!m_ready,
              "idle master receives no completion");
        check(m_rdata == 32'h00000000,
              "idle read data is deterministic zero");

        // RAM read while the target is stalled.
        m_valid = 1'b1;
        m_write = 1'b0;
        m_addr  = 32'h00000020;
        m_wdata = 32'h11223344;
        m_wstrb = 4'b0000;
        #1;

        check(ram_valid && !mmio_valid && !sdram_valid,
              "RAM address selects only RAM");
        check(!m_ready,
              "RAM stall propagates to master");
        check(ram_addr == 32'h00000020,
              "RAM receives full system address");
        check(!ram_write && ram_wstrb == 4'b0000,
              "RAM read control signals are forwarded");

        ram_rdata = 32'hA5A55A5A;
        ram_ready = 1'b1;
        #1;

        check(m_ready,
              "RAM completion propagates to master");
        check(m_rdata == 32'hA5A55A5A,
              "RAM read data propagates to master");

        // Highest aligned word in RAM.
        m_addr = 32'h00000FFC;
        #1;

        check(ram_valid && !mmio_valid && !sdram_valid,
              "RAM upper boundary selects RAM");

        // RAM write forwarding.
        m_addr  = 32'h00000040;
        m_write = 1'b1;
        m_wdata = 32'hDEADBEEF;
        m_wstrb = 4'b1010;
        #1;

        check(ram_valid && ram_write,
              "RAM write request is forwarded");
        check(ram_wdata == 32'hDEADBEEF &&
              ram_wstrb == 4'b1010,
              "RAM write data and byte strobes are forwarded");

        // MMIO read while target stalls.
        m_write     = 1'b0;
        m_addr      = 32'h00001000;
        m_wstrb     = 4'b0000;
        ram_ready   = 1'b0;
        mmio_ready  = 1'b0;
        mmio_rdata  = 32'hCAFEBABE;
        #1;

        check(!ram_valid && mmio_valid && !sdram_valid,
              "MMIO address selects only MMIO");
        check(!m_ready,
              "MMIO stall propagates to master");
        check(mmio_addr == 32'h00001000,
              "MMIO receives full system address");

        mmio_ready = 1'b1;
        #1;

        check(m_ready,
              "MMIO completion propagates to master");
        check(m_rdata == 32'hCAFEBABE,
              "MMIO read data propagates to master");

        // MMIO write forwarding.
        m_write = 1'b1;
        m_wdata = 32'h12345678;
        m_wstrb = 4'b1111;
        #1;

        check(mmio_valid && mmio_write,
              "MMIO write request is forwarded");
        check(mmio_wdata == 32'h12345678 &&
              mmio_wstrb == 4'b1111,
              "MMIO write data and strobes are forwarded");

        // Misaligned access must not reach either target.
        m_addr       = 32'h00001001;
        m_write      = 1'b0;
        ram_ready    = 1'b0;
        mmio_ready   = 1'b0;
        #1;

        check(!ram_valid && !mmio_valid && !sdram_valid,
              "misaligned access selects no target");
        check(m_ready && m_rdata == 32'h00000000,
              "misaligned access receives deterministic invalid response");

        // Address immediately after the MMIO register.
        m_addr = 32'h00001004;
        #1;

        check(!ram_valid && !mmio_valid && !sdram_valid,
              "unmapped low address selects no target");
        check(m_ready && m_rdata == 32'h00000000,
              "unmapped low read completes with zero");

        // Milestone 4 external SDRAM target.
        m_addr        = 32'h10000000;
        m_write       = 1'b0;
        m_wstrb       = 4'b0000;
        sdram_rdata   = 32'h13579BDF;
        sdram_ready   = 1'b0;
        #1;

        check(!ram_valid && !mmio_valid && sdram_valid,
              "SDRAM base address selects only SDRAM");
        check(!m_ready,
              "SDRAM stall propagates to master");
        check(sdram_addr == 32'h10000000,
              "SDRAM receives full system address");
        check(!sdram_write && sdram_wstrb == 4'b0000,
              "SDRAM read control signals are forwarded");

        sdram_ready = 1'b1;
        #1;

        check(m_ready,
              "SDRAM completion propagates to master");
        check(m_rdata == 32'h13579BDF,
              "SDRAM read data propagates to master");

        // Highest aligned word in the 128 MiB M4 SDRAM aperture.
        m_addr = 32'h17FFFFFC;
        #1;

        check(!ram_valid && !mmio_valid && sdram_valid,
              "SDRAM upper boundary selects SDRAM");

        // The former M3 reservation above the M4 aperture is unmapped.
        m_addr      = 32'h18000000;
        sdram_ready = 1'b0;
        #1;

        check(!ram_valid && !mmio_valid && !sdram_valid,
              "address above M4 SDRAM aperture selects no target");
        check(m_ready && m_rdata == 32'h00000000,
              "address above M4 SDRAM aperture uses unmapped response");

        // Unmapped write must complete without selecting a target.
        m_addr   = 32'h20000000;
        m_write  = 1'b1;
        m_wdata  = 32'hFFFFFFFF;
        m_wstrb  = 4'b1111;
        #1;

        check(!ram_valid && !mmio_valid && !sdram_valid,
              "unmapped write selects no target");
        check(m_ready,
              "unmapped write completes deterministically");

        check(
            !(ram_valid && mmio_valid) &&
            !(ram_valid && sdram_valid) &&
            !(mmio_valid && sdram_valid),
            "implemented targets are never selected simultaneously"
        );

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
