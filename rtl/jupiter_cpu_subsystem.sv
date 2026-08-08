module jupiter_cpu_subsystem
(
    input  wire clk,
    input  wire reset,

    output wire halted
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
        .mmio_ready (mmio_ready)
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

endmodule
