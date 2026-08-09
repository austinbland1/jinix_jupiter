module jupiter_cpu_subsystem
(
    input  wire clk,
    input  wire reset,

    // MiSTer-reported installed external SDRAM size.
    input  wire [15:0] sdram_sz,

    // Physical external SDR SDRAM interface.
    //
    // SDRAM_CLK remains a later top-level integration concern.
    output wire        SDRAM_CKE,
    output wire [12:0] SDRAM_A,
    output wire  [1:0] SDRAM_BA,
    inout  wire [15:0] SDRAM_DQ,
    output wire        SDRAM_DQML,
    output wire        SDRAM_DQMH,
    output wire        SDRAM_nCS,
    output wire        SDRAM_nCAS,
    output wire        SDRAM_nRAS,
    output wire        SDRAM_nWE,

    output wire        halted
);

    // CPU master transaction interface.
    wire        cpu_mem_valid;
    wire        cpu_mem_write;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [3:0]  cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;
    wire        cpu_mem_ready;

    // Internal RAM target interface.
    wire        ram_valid;
    wire        ram_write;
    wire [31:0] ram_addr;
    wire [31:0] ram_wdata;
    wire [3:0]  ram_wstrb;
    wire [31:0] ram_rdata;
    wire        ram_ready;

    // MMIO target interface.
    wire        mmio_valid;
    wire        mmio_write;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [3:0]  mmio_wstrb;
    wire [31:0] mmio_rdata;
    wire        mmio_ready;

    // GPU control-MMIO target interface.
    wire        gpu_valid;
    wire        gpu_write;
    wire [31:0] gpu_addr;
    wire [31:0] gpu_wdata;
    wire  [3:0] gpu_wstrb;
    wire [31:0] gpu_rdata;
    wire        gpu_ready;

    // CPU external-SDRAM target interface from the interconnect.
    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;
    wire [31:0] sdram_rdata;
    wire        sdram_ready;

    // GPU external-SDRAM master interface.
    wire        gpu_sdram_valid;
    wire        gpu_sdram_write;
    wire [31:0] gpu_sdram_addr;
    wire [31:0] gpu_sdram_wdata;
    wire  [3:0] gpu_sdram_wstrb;
    wire [31:0] gpu_sdram_rdata;
    wire        gpu_sdram_ready;

    // Shared post-arbitration 32-bit interface toward the M4 frontend.
    wire        shared_sdram_valid;
    wire        shared_sdram_write;
    wire [31:0] shared_sdram_addr;
    wire [31:0] shared_sdram_wdata;
    wire  [3:0] shared_sdram_wstrb;
    wire [31:0] shared_sdram_rdata;
    wire        shared_sdram_ready;

    // SDRAM frontend/controller halfword interface.
    wire        half_valid;
    wire        half_write;
    wire [25:0] half_addr;
    wire [15:0] half_wdata;
    wire  [1:0] half_wstrb;
    wire [15:0] half_rdata;
    wire        half_ready;

    wire        sdram_initialized;

    jupiter_cpu cpu
    (
        .clk       (clk),
        .reset     (reset),

        .mem_valid (cpu_mem_valid),
        .mem_write (cpu_mem_write),
        .mem_addr  (cpu_mem_addr),
        .mem_wdata (cpu_mem_wdata),
        .mem_wstrb (cpu_mem_wstrb),

        .mem_rdata (cpu_mem_rdata),
        .mem_ready (cpu_mem_ready),

        .halted    (halted)
    );

    jupiter_interconnect bus_fabric
    (
        .m_valid    (cpu_mem_valid),
        .m_write    (cpu_mem_write),
        .m_addr     (cpu_mem_addr),
        .m_wdata    (cpu_mem_wdata),
        .m_wstrb    (cpu_mem_wstrb),

        .m_rdata    (cpu_mem_rdata),
        .m_ready    (cpu_mem_ready),

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

        .gpu_valid  (gpu_valid),
        .gpu_write  (gpu_write),
        .gpu_addr   (gpu_addr),
        .gpu_wdata  (gpu_wdata),
        .gpu_wstrb  (gpu_wstrb),
        .gpu_rdata  (gpu_rdata),
        .gpu_ready  (gpu_ready),

        .sdram_valid (sdram_valid),
        .sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );

    jupiter_sdram_arbiter sdram_arbiter
    (
        .clk         (clk),
        .reset       (reset),

        .cpu_valid   (sdram_valid),
        .cpu_write   (sdram_write),
        .cpu_addr    (sdram_addr),
        .cpu_wdata   (sdram_wdata),
        .cpu_wstrb   (sdram_wstrb),
        .cpu_rdata   (sdram_rdata),
        .cpu_ready   (sdram_ready),

        .gpu_valid   (gpu_sdram_valid),
        .gpu_write   (gpu_sdram_write),
        .gpu_addr    (gpu_sdram_addr),
        .gpu_wdata   (gpu_sdram_wdata),
        .gpu_wstrb   (gpu_sdram_wstrb),
        .gpu_rdata   (gpu_sdram_rdata),
        .gpu_ready   (gpu_sdram_ready),

        .sdram_valid (shared_sdram_valid),
        .sdram_write (shared_sdram_write),
        .sdram_addr  (shared_sdram_addr),
        .sdram_wdata (shared_sdram_wdata),
        .sdram_wstrb (shared_sdram_wstrb),
        .sdram_rdata (shared_sdram_rdata),
        .sdram_ready (shared_sdram_ready)
    );

    jupiter_sdram_frontend sdram_frontend
    (
        .clk        (clk),
        .reset      (reset),

        .m_valid    (shared_sdram_valid),
        .m_write    (shared_sdram_write),
        .m_addr     (shared_sdram_addr),
        .m_wdata    (shared_sdram_wdata),
        .m_wstrb    (shared_sdram_wstrb),
        .m_rdata    (shared_sdram_rdata),
        .m_ready    (shared_sdram_ready),

        .sdram_sz   (sdram_sz),

        .half_valid (half_valid),
        .half_write (half_write),
        .half_addr  (half_addr),
        .half_wdata (half_wdata),
        .half_wstrb (half_wstrb),
        .half_rdata (half_rdata),
        .half_ready (half_ready)
    );

    jupiter_sdram_controller sdram_controller
    (
        .clk         (clk),
        .reset       (reset),

        .initialized (sdram_initialized),

        .half_valid  (half_valid),
        .half_write  (half_write),
        .half_addr   (half_addr),
        .half_wdata  (half_wdata),
        .half_wstrb  (half_wstrb),
        .half_rdata  (half_rdata),
        .half_ready  (half_ready),

        .SDRAM_CKE   (SDRAM_CKE),
        .SDRAM_A     (SDRAM_A),
        .SDRAM_BA    (SDRAM_BA),
        .SDRAM_DQ    (SDRAM_DQ),
        .SDRAM_DQML  (SDRAM_DQML),
        .SDRAM_DQMH  (SDRAM_DQMH),
        .SDRAM_nCS   (SDRAM_nCS),
        .SDRAM_nCAS  (SDRAM_nCAS),
        .SDRAM_nRAS  (SDRAM_nRAS),
        .SDRAM_nWE   (SDRAM_nWE)
    );

    jupiter_internal_ram ram
    (
        .clk   (clk),

        .valid (ram_valid),
        .write (ram_write),
        .addr  (ram_addr),
        .wdata (ram_wdata),
        .wstrb (ram_wstrb),

        .rdata (ram_rdata),
        .ready (ram_ready)
    );

    jupiter_mmio_scratch scratch
    (
        .clk   (clk),
        .reset (reset),

        .valid (mmio_valid),
        .write (mmio_write),
        .addr  (mmio_addr),
        .wdata (mmio_wdata),
        .wstrb (mmio_wstrb),

        .rdata (mmio_rdata),
        .ready (mmio_ready)
    );

    jupiter_gpu_2d gpu
    (
        .clk   (clk),
        .reset (reset),

        .valid (gpu_valid),
        .write (gpu_write),
        .addr  (gpu_addr),
        .wdata (gpu_wdata),
        .wstrb (gpu_wstrb),

        .rdata (gpu_rdata),
        .ready (gpu_ready),

        .sdram_valid (gpu_sdram_valid),
        .sdram_write (gpu_sdram_write),
        .sdram_addr  (gpu_sdram_addr),
        .sdram_wdata (gpu_sdram_wdata),
        .sdram_wstrb (gpu_sdram_wstrb),
        .sdram_rdata (gpu_sdram_rdata),
        .sdram_ready (gpu_sdram_ready)
    );

endmodule
