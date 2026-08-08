module jupiter_interconnect
(
    // Single Milestone 3 master transaction interface.
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
    input  wire        mmio_ready
);

    localparam [31:0] RAM_START  = 32'h00000000;
    localparam [31:0] RAM_END    = 32'h00000FFF;

    localparam [31:0] MMIO_START = 32'h00001000;
    localparam [31:0] MMIO_END   = 32'h00001003;

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

    // A selected target controls completion and read data.
    //
    // Any valid request that selects no implemented aligned target receives
    // the documented deterministic unmapped response immediately:
    // ready = 1, read data = 0, and no target request is asserted.
    assign m_ready =
        !m_valid       ? 1'b0 :
        ram_selected   ? ram_ready :
        mmio_selected  ? mmio_ready :
                         1'b1;

    assign m_rdata =
        !m_valid       ? 32'h00000000 :
        ram_selected   ? ram_rdata :
        mmio_selected  ? mmio_rdata :
                         32'h00000000;

endmodule
