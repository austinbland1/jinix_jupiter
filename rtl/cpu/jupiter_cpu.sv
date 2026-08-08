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

    // Architectural state established by Milestone 2.
    //
    // Instruction execution is not implemented yet. The state defined here
    // establishes the reset behavior required by docs/ISA_SPEC.md.

    reg [31:0] pc;
    reg [31:0] regs [0:31];
    reg        halted_reg;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            pc         <= 32'h00000000;
            halted_reg <= 1'b0;

            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'h00000000;
        end else begin
            // r0 is architecturally hardwired to zero.
            regs[0] <= 32'h00000000;
        end
    end

    // Fetch and execution are intentionally absent at this checkpoint.
    // Until the execution state machine exists, the memory port remains idle.
    assign mem_valid = 1'b0;
    assign mem_write = 1'b0;
    assign mem_addr  = 32'h00000000;
    assign mem_wdata = 32'h00000000;
    assign mem_wstrb = 4'b0000;

    assign halted = halted_reg;

    // Memory-response inputs are unused until fetch/load sequencing exists.
    wire _unused = &{1'b0, mem_rdata, mem_ready};

endmodule
