module jupiter_interconnect
(
    // CPU master transaction interface.
    input  wire        m_valid,
    input  wire        m_write,
    input  wire [31:0] m_addr,
    input  wire [31:0] m_wdata,
    input  wire [3:0]  m_wstrb,

    output wire [31:0] m_rdata,
    output wire        m_ready,

    // Internal/test RAM target.
    output wire        ram_valid,
    output wire        ram_write,
    output wire [31:0] ram_addr,
    output wire [31:0] ram_wdata,
    output wire [3:0]  ram_wstrb,

    input  wire [31:0] ram_rdata,
    input  wire        ram_ready,

    // Milestone 3 MMIO target.
    output wire        mmio_valid,
    output wire        mmio_write,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    output wire [3:0]  mmio_wstrb,

    input  wire [31:0] mmio_rdata,
    input  wire        mmio_ready,

    // Milestone 5 GPU control-MMIO target.
    output wire        gpu_valid,
    output wire        gpu_write,
    output wire [31:0] gpu_addr,
    output wire [31:0] gpu_wdata,
    output wire [3:0]  gpu_wstrb,

    input  wire [31:0] gpu_rdata,
    input  wire        gpu_ready,

    // Milestone 4 external SDRAM target.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire [3:0]  sdram_wstrb,

    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    localparam [31:0] RAM_START  = 32'h00000000;
    localparam [31:0] RAM_END    = 32'h00000FFF;

    localparam [31:0] MMIO_START = 32'h00001000;
    localparam [31:0] MMIO_END   = 32'h00001003;

    localparam [31:0] GPU_START  = 32'h00001100;
    localparam [31:0] GPU_END    = 32'h000011FF;

    localparam [31:0] SDRAM_START = 32'h10000000;
    localparam [31:0] SDRAM_END   = 32'h17FFFFFF;

    wire aligned = (m_addr[1:0] == 2'b00);

    wire ram_selected =
        m_valid &&
        aligned &&
        (m_addr >= RAM_START) &&
        (m_addr <= RAM_END);

    wire mmio_selected =
        m_valid &&
        aligned &&
        (m_addr >= MMIO_START) &&
        (m_addr <= MMIO_END);

    wire gpu_selected =
        m_valid &&
        aligned &&
        (m_addr >= GPU_START) &&
        (m_addr <= GPU_END);

    wire sdram_selected =
        m_valid &&
        aligned &&
        (m_addr >= SDRAM_START) &&
        (m_addr <= SDRAM_END);

    // Requests retain their full system address at each target boundary.
    assign ram_valid = ram_selected;
    assign ram_write = m_write;
    assign ram_addr  = m_addr;
    assign ram_wdata = m_wdata;
    assign ram_wstrb = m_wstrb;

    assign mmio_valid = mmio_selected;
    assign mmio_write = m_write;
    assign mmio_addr  = m_addr;
    assign mmio_wdata = m_wdata;
    assign mmio_wstrb = m_wstrb;

    assign gpu_valid = gpu_selected;
    assign gpu_write = m_write;
    assign gpu_addr  = m_addr;
    assign gpu_wdata = m_wdata;
    assign gpu_wstrb = m_wstrb;

    assign sdram_valid = sdram_selected;
    assign sdram_write = m_write;
    assign sdram_addr  = m_addr;
    assign sdram_wdata = m_wdata;
    assign sdram_wstrb = m_wstrb;

    // A selected target controls completion and read data.
    //
    // Any valid request that selects no implemented aligned target receives
    // the documented deterministic unmapped response immediately:
    // ready = 1, read data = 0, and no target request is asserted.
    assign m_ready =
        !m_valid       ? 1'b0 :
        ram_selected   ? ram_ready :
        mmio_selected  ? mmio_ready :
        gpu_selected   ? gpu_ready :
        sdram_selected ? sdram_ready :
                         1'b1;

    assign m_rdata =
        !m_valid       ? 32'h00000000 :
        ram_selected   ? ram_rdata :
        mmio_selected  ? mmio_rdata :
        gpu_selected   ? gpu_rdata :
        sdram_selected ? sdram_rdata :
                         32'h00000000;

endmodule
