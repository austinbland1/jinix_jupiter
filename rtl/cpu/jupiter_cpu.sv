module jupiter_cpu
(
    input  wire        clk,
    input  wire        reset,

    output wire        mem_valid,
    output wire        mem_write,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_wstrb,

    input  wire [31:0] mem_rdata,
    input  wire        mem_ready,

    output wire        halted
);

    // Milestone 2 ISA opcodes.
    localparam [7:0] OP_NOP  = 8'h00;
    localparam [7:0] OP_ADD  = 8'h01;
    localparam [7:0] OP_SUB  = 8'h02;
    localparam [7:0] OP_AND  = 8'h03;
    localparam [7:0] OP_OR   = 8'h04;
    localparam [7:0] OP_XOR  = 8'h05;

    localparam [7:0] OP_ADDI = 8'h10;

    localparam [7:0] OP_LDW  = 8'h20;
    localparam [7:0] OP_STW  = 8'h21;

    localparam [7:0] OP_BEQ  = 8'h30;
    localparam [7:0] OP_BNE  = 8'h31;
    localparam [7:0] OP_J    = 8'h32;

    localparam [7:0] OP_HALT = 8'hFF;

    // M2A-2 establishes only the real CPU-facing module boundary.
    //
    // Fetch, decode, architectural registers, execution, memory sequencing,
    // control flow, and HALT behavior are intentionally implemented in later
    // Milestone 2 checkpoints.
    //
    // Drive the external interface to a deterministic inactive state until
    // that execution machinery exists.

    assign mem_valid = 1'b0;
    assign mem_write = 1'b0;
    assign mem_addr  = 32'h00000000;
    assign mem_wdata = 32'h00000000;
    assign mem_wstrb = 4'b0000;
    assign halted    = 1'b0;

    // Keep currently-unused inputs explicit during this interface-only step.
    wire _unused = &{1'b0, clk, reset, mem_rdata, mem_ready};

endmodule
