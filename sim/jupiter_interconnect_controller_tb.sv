`timescale 1ns/1ps

module jupiter_interconnect_controller_tb;

    reg         m_valid;
    reg         m_write;
    reg  [31:0] m_addr;
    reg  [31:0] m_wdata;
    reg   [3:0] m_wstrb;

    wire [31:0] m_rdata;
    wire        m_ready;

    wire ram_valid, ram_write;
    wire [31:0] ram_addr, ram_wdata;
    wire [3:0] ram_wstrb;
    reg [31:0] ram_rdata;
    reg ram_ready;

    wire mmio_valid, mmio_write;
    wire [31:0] mmio_addr, mmio_wdata;
    wire [3:0] mmio_wstrb;
    reg [31:0] mmio_rdata;
    reg mmio_ready;

    wire gpu_valid, gpu_write;
    wire [31:0] gpu_addr, gpu_wdata;
    wire [3:0] gpu_wstrb;
    reg [31:0] gpu_rdata;
    reg gpu_ready;

    wire dma_valid, dma_write;
    wire [31:0] dma_addr, dma_wdata;
    wire [3:0] dma_wstrb;
    reg [31:0] dma_rdata;
    reg dma_ready;

    wire audio_valid, audio_write;
    wire [31:0] audio_addr, audio_wdata;
    wire [3:0] audio_wstrb;
    reg [31:0] audio_rdata;
    reg audio_ready;

    wire controller_valid, controller_write;
    wire [31:0] controller_addr, controller_wdata;
    wire [3:0] controller_wstrb;
    reg [31:0] controller_rdata;
    reg controller_ready;

    wire sdram_valid, sdram_write;
    wire [31:0] sdram_addr, sdram_wdata;
    wire [3:0] sdram_wstrb;
    reg [31:0] sdram_rdata;
    reg sdram_ready;

    integer checks;
    integer failures;


    jupiter_interconnect dut
    (
        .m_valid(m_valid),
        .m_write(m_write),
        .m_addr(m_addr),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_rdata(m_rdata),
        .m_ready(m_ready),

        .ram_valid(ram_valid),
        .ram_write(ram_write),
        .ram_addr(ram_addr),
        .ram_wdata(ram_wdata),
        .ram_wstrb(ram_wstrb),
        .ram_rdata(ram_rdata),
        .ram_ready(ram_ready),

        .mmio_valid(mmio_valid),
        .mmio_write(mmio_write),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_wstrb(mmio_wstrb),
        .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready),

        .gpu_valid(gpu_valid),
        .gpu_write(gpu_write),
        .gpu_addr(gpu_addr),
        .gpu_wdata(gpu_wdata),
        .gpu_wstrb(gpu_wstrb),
        .gpu_rdata(gpu_rdata),
        .gpu_ready(gpu_ready),

        .dma_valid(dma_valid),
        .dma_write(dma_write),
        .dma_addr(dma_addr),
        .dma_wdata(dma_wdata),
        .dma_wstrb(dma_wstrb),
        .dma_rdata(dma_rdata),
        .dma_ready(dma_ready),

        .audio_valid(audio_valid),
        .audio_write(audio_write),
        .audio_addr(audio_addr),
        .audio_wdata(audio_wdata),
        .audio_wstrb(audio_wstrb),
        .audio_rdata(audio_rdata),
        .audio_ready(audio_ready),

        .controller_valid(controller_valid),
        .controller_write(controller_write),
        .controller_addr(controller_addr),
        .controller_wdata(controller_wdata),
        .controller_wstrb(controller_wstrb),
        .controller_rdata(controller_rdata),
        .controller_ready(controller_ready),

        .sdram_valid(sdram_valid),
        .sdram_write(sdram_write),
        .sdram_addr(sdram_addr),
        .sdram_wdata(sdram_wdata),
        .sdram_wstrb(sdram_wstrb),
        .sdram_rdata(sdram_rdata),
        .sdram_ready(sdram_ready)
    );


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


    initial begin

        checks = 0;
        failures = 0;

        m_valid = 0;
        m_write = 0;
        m_addr = 0;
        m_wdata = 0;
        m_wstrb = 0;

        ram_rdata = 0;
        ram_ready = 0;
        mmio_rdata = 0;
        mmio_ready = 0;
        gpu_rdata = 0;
        gpu_ready = 0;
        dma_rdata = 0;
        dma_ready = 0;
        audio_rdata = 0;
        audio_ready = 0;
        controller_rdata = 0;
        controller_ready = 0;
        sdram_rdata = 0;
        sdram_ready = 0;

        #1;

        check(
            !ram_valid &&
            !mmio_valid &&
            !gpu_valid &&
            !dma_valid &&
            !audio_valid &&
            !controller_valid &&
            !sdram_valid &&
            !m_ready,
            "idle selects no target"
        );


        m_valid = 1;
        m_addr = 32'h00001400;

        controller_rdata = 32'h13579BDF;
        controller_ready = 0;

        #1;

        check(
            controller_valid &&
            !ram_valid &&
            !mmio_valid &&
            !gpu_valid &&
            !dma_valid &&
            !audio_valid &&
            !sdram_valid,
            "controller base selects only controller"
        );

        check(
            !m_ready,
            "controller stall propagates"
        );

        check(
            controller_addr == 32'h00001400,
            "controller receives full system address"
        );


        controller_ready = 1;

        #1;

        check(
            m_ready &&
            m_rdata == 32'h13579BDF,
            "controller response propagates"
        );


        m_addr = 32'h000014FC;

        #1;

        check(
            controller_valid &&
            !audio_valid &&
            !sdram_valid,
            "controller upper boundary selects controller"
        );


        m_addr = 32'h00001404;
        m_write = 1;
        m_wdata = 32'h89ABCDEF;
        m_wstrb = 4'b0101;

        #1;

        check(
            controller_valid &&
            controller_write &&
            controller_wdata == 32'h89ABCDEF &&
            controller_wstrb == 4'b0101,
            "controller write controls are forwarded"
        );


        m_addr = 32'h000013FC;
        m_write = 0;
        m_wstrb = 0;
        controller_ready = 0;
        audio_rdata = 32'h0BADF00D;
        audio_ready = 1;

        #1;

        check(
            audio_valid &&
            !controller_valid &&
            m_ready &&
            m_rdata == 32'h0BADF00D,
            "audio upper boundary remains unchanged"
        );


        m_addr = 32'h00001600;
        audio_ready = 0;

        #1;

        check(
            !ram_valid &&
            !mmio_valid &&
            !gpu_valid &&
            !dma_valid &&
            !audio_valid &&
            !controller_valid &&
            !sdram_valid &&
            m_ready &&
            m_rdata == 0,
            "address after loader aperture is unmapped"
        );


        m_addr = 32'h00001401;

        #1;

        check(
            !controller_valid &&
            m_ready &&
            m_rdata == 0,
            "misaligned controller access is invalid"
        );


        m_addr = 32'h10000000;
        sdram_rdata = 32'hCAFEBABE;
        sdram_ready = 1;

        #1;

        check(
            sdram_valid &&
            !controller_valid &&
            m_ready &&
            m_rdata == 32'hCAFEBABE,
            "SDRAM base remains unchanged"
        );


        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
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
