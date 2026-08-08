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

    localparam [1:0] STATE_FETCH  = 2'd0;
    localparam [1:0] STATE_DECODE = 2'd1;

    reg [31:0] pc;
    reg [31:0] regs [0:31];
    reg [31:0] instruction_reg;
    reg [1:0]  state;
    reg        halted_reg;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            pc              <= 32'h00000000;
            instruction_reg <= 32'h00000000;
            state           <= STATE_FETCH;
            halted_reg      <= 1'b0;

            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'h00000000;
        end else begin
            // r0 is architecturally hardwired to zero.
            regs[0] <= 32'h00000000;

            case (state)
                STATE_FETCH: begin
                    // STATE_FETCH implies mem_valid is asserted.
                    // Capture the instruction only when the documented
                    // valid/ready transaction completes.
                    if (mem_ready) begin
                        instruction_reg <= mem_rdata;
                        state           <= STATE_DECODE;
                    end
                end

                STATE_DECODE: begin
                    // Decode and execution are intentionally deferred to a
                    // later Milestone 2 checkpoint.
                    state <= STATE_DECODE;
                end

                default: begin
                    state <= STATE_FETCH;
                end
            endcase
        end
    end

    // Unified CPU memory transaction port.
    //
    // M2A-4 implements instruction fetch only. PC remains the address of the
    // captured instruction until execution behavior is added later.
    assign mem_valid = !reset && (state == STATE_FETCH);
    assign mem_write = 1'b0;
    assign mem_addr  = pc;
    assign mem_wdata = 32'h00000000;
    assign mem_wstrb = 4'b0000;

    assign halted = halted_reg;

endmodule
