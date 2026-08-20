`timescale 1ns/1ps

module jupiter_interconnect_audio_tb;

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
        .m_valid     (m_valid),
        .m_write     (m_write),
        .m_addr      (m_addr),
        .m_wdata     (m_wdata),
        .m_wstrb     (m_wstrb),

        .m_rdata     (m_rdata),
        .m_ready     (m_ready),

        .ram_valid   (ram_valid),
        .ram_write   (ram_write),
        .ram_addr    (ram_addr),
        .ram_wdata   (ram_wdata),
        .ram_wstrb   (ram_wstrb),
        .ram_rdata   (ram_rdata),
        .ram_ready   (ram_ready),

        .mmio_valid  (mmio_valid),
        .mmio_write  (mmio_write),
        .mmio_addr   (mmio_addr),
        .mmio_wdata  (mmio_wdata),
        .mmio_wstrb  (mmio_wstrb),
        .mmio_rdata  (mmio_rdata),
        .mmio_ready  (mmio_ready),

        .gpu_valid   (gpu_valid),
        .gpu_write   (gpu_write),
        .gpu_addr    (gpu_addr),
        .gpu_wdata   (gpu_wdata),
        .gpu_wstrb   (gpu_wstrb),
        .gpu_rdata   (gpu_rdata),
        .gpu_ready   (gpu_ready),

        .dma_valid   (dma_valid),
        .dma_write   (dma_write),
        .dma_addr    (dma_addr),
        .dma_wdata   (dma_wdata),
        .dma_wstrb   (dma_wstrb),
        .dma_rdata   (dma_rdata),
        .dma_ready   (dma_ready),

        .audio_valid (audio_valid),
        .audio_write (audio_write),
        .audio_addr  (audio_addr),
        .audio_wdata (audio_wdata),
        .audio_wstrb (audio_wstrb),
        .audio_rdata (audio_rdata),
        .audio_ready (audio_ready),

        .sdram_valid (sdram_valid),
        .sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );


    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin

            checks = checks + 1;

            if (condition)
                $display(
                    "PASS: %0s",
                    message
                );
            else begin

                failures = failures + 1;

                $display(
                    "FAIL: %0s",
                    message
                );

            end
        end
    endtask


    initial begin

        checks = 0;
        failures = 0;

        m_valid = 1'b0;
        m_write = 1'b0;
        m_addr = 32'h00000000;
        m_wdata = 32'h00000000;
        m_wstrb = 4'b0000;

        ram_rdata = 32'h00000000;
        ram_ready = 1'b0;

        mmio_rdata = 32'h00000000;
        mmio_ready = 1'b0;

        gpu_rdata = 32'h00000000;
        gpu_ready = 1'b0;

        dma_rdata = 32'h00000000;
        dma_ready = 1'b0;

        audio_rdata = 32'h00000000;
        audio_ready = 1'b0;

        sdram_rdata = 32'h00000000;
        sdram_ready = 1'b0;

        #1;


        check(
            !ram_valid &&
            !mmio_valid &&
            !gpu_valid &&
            !dma_valid &&
            !audio_valid &&
            !sdram_valid,
            "idle master selects no target including audio"
        );


        check(
            !m_ready,
            "idle master receives no completion"
        );


        // Audio base.
        m_valid = 1'b1;
        m_write = 1'b0;
        m_addr = 32'h00001300;
        m_wstrb = 4'b0000;

        audio_rdata = 32'h13572468;
        audio_ready = 1'b0;

        #1;


        check(
            !ram_valid &&
            !mmio_valid &&
            !gpu_valid &&
            !dma_valid &&
            audio_valid &&
            !sdram_valid,
            "audio base selects only audio"
        );


        check(
            !m_ready,
            "audio stall propagates to CPU master"
        );


        check(
            audio_addr == 32'h00001300,
            "audio receives full system address"
        );


        check(
            !audio_write &&
            audio_wstrb == 4'b0000,
            "audio read controls are forwarded"
        );


        audio_ready = 1'b1;

        #1;


        check(
            m_ready,
            "audio completion propagates to CPU master"
        );


        check(
            m_rdata == 32'h13572468,
            "audio read data propagates to CPU master"
        );


        // Upper boundary.
        m_addr = 32'h000013FC;

        #1;


        check(
            audio_valid &&
            !dma_valid &&
            !sdram_valid,
            "audio upper boundary selects audio"
        );


        // Write forwarding.
        m_addr = 32'h00001328;
        m_write = 1'b1;
        m_wdata = 32'h89ABCDEF;
        m_wstrb = 4'b0101;

        #1;


        check(
            audio_valid &&
            audio_write,
            "audio write request is forwarded"
        );


        check(
            audio_wdata == 32'h89ABCDEF &&
            audio_wstrb == 4'b0101,
            "audio write data and strobes are forwarded"
        );


        // Address after audio aperture.
        m_addr = 32'h00001600;
        m_write = 1'b0;
        m_wstrb = 4'b0000;

        audio_ready = 1'b0;

        #1;


        check(
            !ram_valid &&
            !mmio_valid &&
            !gpu_valid &&
            !dma_valid &&
            !audio_valid &&
            !sdram_valid,
            "address after loader aperture selects no target"
        );


        check(
            m_ready &&
            m_rdata == 32'h00000000,
            "address after loader aperture uses unmapped response"
        );


        // DMA boundary unchanged.
        m_addr = 32'h000012FC;

        dma_rdata = 32'h0BADF00D;
        dma_ready = 1'b1;

        #1;


        check(
            dma_valid &&
            !audio_valid,
            "DMA upper boundary remains DMA after audio integration"
        );


        check(
            m_ready &&
            m_rdata == 32'h0BADF00D,
            "DMA completion remains unchanged"
        );


        // SDRAM unchanged.
        m_addr = 32'h10000000;

        dma_ready = 1'b0;

        sdram_rdata = 32'hCAFEBABE;
        sdram_ready = 1'b1;

        #1;


        check(
            sdram_valid &&
            !audio_valid,
            "SDRAM base remains SDRAM after audio integration"
        );


        check(
            m_ready &&
            m_rdata == 32'hCAFEBABE,
            "SDRAM completion remains unchanged"
        );


        // Misaligned audio access.
        m_addr = 32'h00001301;

        sdram_ready = 1'b0;

        #1;


        check(
            !ram_valid &&
            !mmio_valid &&
            !gpu_valid &&
            !dma_valid &&
            !audio_valid &&
            !sdram_valid,
            "misaligned audio access selects no target"
        );


        check(
            m_ready &&
            m_rdata == 32'h00000000,
            "misaligned audio access completes deterministically"
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
