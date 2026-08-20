`timescale 1ns/1ps

module jupiter_interconnect_loader_tb;

    reg         m_valid;
    reg         m_write;
    reg  [31:0] m_addr;
    reg  [31:0] m_wdata;
    reg   [3:0] m_wstrb;
    wire [31:0] m_rdata;
    wire        m_ready;

    wire        ram_valid;
    wire        ram_write;
    wire [31:0] ram_addr;
    wire [31:0] ram_wdata;
    wire  [3:0] ram_wstrb;
    reg  [31:0] ram_rdata;
    reg         ram_ready;

    wire        mmio_valid;
    wire        mmio_write;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire  [3:0] mmio_wstrb;
    reg  [31:0] mmio_rdata;
    reg         mmio_ready;

    wire        gpu_valid;
    wire        gpu_write;
    wire [31:0] gpu_addr;
    wire [31:0] gpu_wdata;
    wire  [3:0] gpu_wstrb;
    reg  [31:0] gpu_rdata;
    reg         gpu_ready;

    wire        dma_valid;
    wire        dma_write;
    wire [31:0] dma_addr;
    wire [31:0] dma_wdata;
    wire  [3:0] dma_wstrb;
    reg  [31:0] dma_rdata;
    reg         dma_ready;

    wire        audio_valid;
    wire        audio_write;
    wire [31:0] audio_addr;
    wire [31:0] audio_wdata;
    wire  [3:0] audio_wstrb;
    reg  [31:0] audio_rdata;
    reg         audio_ready;

    wire        controller_valid;
    wire        controller_write;
    wire [31:0] controller_addr;
    wire [31:0] controller_wdata;
    wire  [3:0] controller_wstrb;
    reg  [31:0] controller_rdata;
    reg         controller_ready;

    wire        loader_valid;
    wire        loader_write;
    wire [31:0] loader_addr;
    wire [31:0] loader_wdata;
    wire  [3:0] loader_wstrb;
    reg  [31:0] loader_rdata;
    reg         loader_ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;
    reg  [31:0] sdram_rdata;
    reg         sdram_ready;

    integer checks;
    integer failures;

    jupiter_interconnect dut
    (
        .m_valid          (m_valid),
        .m_write          (m_write),
        .m_addr           (m_addr),
        .m_wdata          (m_wdata),
        .m_wstrb          (m_wstrb),
        .m_rdata          (m_rdata),
        .m_ready          (m_ready),

        .ram_valid        (ram_valid),
        .ram_write        (ram_write),
        .ram_addr         (ram_addr),
        .ram_wdata        (ram_wdata),
        .ram_wstrb        (ram_wstrb),
        .ram_rdata        (ram_rdata),
        .ram_ready        (ram_ready),

        .mmio_valid       (mmio_valid),
        .mmio_write       (mmio_write),
        .mmio_addr        (mmio_addr),
        .mmio_wdata       (mmio_wdata),
        .mmio_wstrb       (mmio_wstrb),
        .mmio_rdata       (mmio_rdata),
        .mmio_ready       (mmio_ready),

        .gpu_valid        (gpu_valid),
        .gpu_write        (gpu_write),
        .gpu_addr         (gpu_addr),
        .gpu_wdata        (gpu_wdata),
        .gpu_wstrb        (gpu_wstrb),
        .gpu_rdata        (gpu_rdata),
        .gpu_ready        (gpu_ready),

        .dma_valid        (dma_valid),
        .dma_write        (dma_write),
        .dma_addr         (dma_addr),
        .dma_wdata        (dma_wdata),
        .dma_wstrb        (dma_wstrb),
        .dma_rdata        (dma_rdata),
        .dma_ready        (dma_ready),

        .audio_valid      (audio_valid),
        .audio_write      (audio_write),
        .audio_addr       (audio_addr),
        .audio_wdata      (audio_wdata),
        .audio_wstrb      (audio_wstrb),
        .audio_rdata      (audio_rdata),
        .audio_ready      (audio_ready),

        .controller_valid (controller_valid),
        .controller_write (controller_write),
        .controller_addr  (controller_addr),
        .controller_wdata (controller_wdata),
        .controller_wstrb (controller_wstrb),
        .controller_rdata (controller_rdata),
        .controller_ready (controller_ready),

        .loader_valid     (loader_valid),
        .loader_write     (loader_write),
        .loader_addr      (loader_addr),
        .loader_wdata     (loader_wdata),
        .loader_wstrb     (loader_wstrb),
        .loader_rdata     (loader_rdata),
        .loader_ready     (loader_ready),

        .sdram_valid      (sdram_valid),
        .sdram_write      (sdram_write),
        .sdram_addr       (sdram_addr),
        .sdram_wdata      (sdram_wdata),
        .sdram_wstrb      (sdram_wstrb),
        .sdram_rdata      (sdram_rdata),
        .sdram_ready      (sdram_ready)
    );

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

    task request;
        input [31:0] address;
        input        write;
        begin
            m_addr = address;
            m_write = write;
            m_wdata = 32'hDEADBEEF;
            m_wstrb = 4'hF;
            m_valid = 1'b1;
            #1;
        end
    endtask

    task idle;
        begin
            m_valid = 1'b0;
            #1;
        end
    endtask

    initial begin
        m_valid = 1'b0;
        m_write = 1'b0;
        m_addr = 32'd0;
        m_wdata = 32'd0;
        m_wstrb = 4'd0;

        ram_rdata = 32'h11111111;
        ram_ready = 1'b1;
        mmio_rdata = 32'h22222222;
        mmio_ready = 1'b1;
        gpu_rdata = 32'h33333333;
        gpu_ready = 1'b1;
        dma_rdata = 32'h44444444;
        dma_ready = 1'b1;
        audio_rdata = 32'h55555555;
        audio_ready = 1'b1;
        controller_rdata = 32'h66666666;
        controller_ready = 1'b1;
        loader_rdata = 32'h77777777;
        loader_ready = 1'b1;
        sdram_rdata = 32'h88888888;
        sdram_ready = 1'b1;

        checks = 0;
        failures = 0;

        request(32'h00001500, 1'b0);
        check(loader_valid === 1'b1, "0x1500 must select loader target");
        check(loader_write === 1'b0, "loader read must preserve write control");
        check(loader_addr == 32'h00001500, "loader must receive full system address");
        check(m_ready === 1'b1, "loader ready must control master completion");
        check(m_rdata == 32'h77777777, "loader read data must return to CPU");
        check(controller_valid === 1'b0, "loader aperture must not select controller");
        check(sdram_valid === 1'b0, "loader aperture must not select SDRAM");

        request(32'h000015FC, 1'b1);
        check(loader_valid === 1'b1, "end of loader aperture must decode");
        check(loader_write === 1'b1, "loader write control must propagate");
        check(loader_wdata == 32'hDEADBEEF, "loader write data must propagate");
        check(loader_wstrb == 4'hF, "loader write strobes must propagate");

        request(32'h000014FC, 1'b0);
        check(controller_valid === 1'b1, "controller aperture must remain intact");
        check(loader_valid === 1'b0, "controller aperture must not select loader");
        check(m_rdata == 32'h66666666, "controller read path must remain intact");

        request(32'h00001600, 1'b0);
        check(loader_valid === 1'b0, "0x1600 must remain unmapped");
        check(m_ready === 1'b1, "unmapped aligned request must complete deterministically");
        check(m_rdata == 32'h00000000, "unmapped aligned read must return zero");

        request(32'h00001501, 1'b0);
        check(loader_valid === 1'b0, "unaligned loader-aperture request must not select target");
        check(m_ready === 1'b1, "unaligned unmapped request must complete deterministically");
        check(m_rdata == 32'h00000000, "unaligned loader-aperture read must return zero");

        request(32'h10000000, 1'b0);
        check(sdram_valid === 1'b1, "existing SDRAM aperture must remain intact");
        check(loader_valid === 1'b0, "SDRAM aperture must not select loader");
        check(m_rdata == 32'h88888888, "SDRAM read path must remain intact");

        idle;

        if (failures == 0) begin
            $display("PASS: jupiter_interconnect loader aperture (%0d checks)", checks);
            $finish;
        end

        $display("FAIL: interconnect loader aperture %0d/%0d checks failed", failures, checks);
        $fatal(1);
    end

endmodule
