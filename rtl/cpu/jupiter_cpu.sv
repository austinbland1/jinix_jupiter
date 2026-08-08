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

    wire [7:0]  opcode      = instruction_reg[31:24];
    wire [4:0]  rd_index    = instruction_reg[23:19];
    wire [4:0]  rs1_index   = instruction_reg[18:14];
    wire [4:0]  rs2_index   = instruction_reg[13:9];
    wire [31:0] imm14_sext  =
        {{18{instruction_reg[13]}}, instruction_reg[13:0]};

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

            if (!halted_reg) begin
                case (state)
                    STATE_FETCH: begin
                        // Capture an instruction only when the documented
                        // valid/ready transaction completes.
                        if (mem_ready) begin
                            instruction_reg <= mem_rdata;
                            state           <= STATE_DECODE;
                        end
                    end

                    STATE_DECODE: begin
                        case (opcode)
                            OP_NOP: begin
                                pc    <= pc + 32'd4;
                                state <= STATE_FETCH;
                            end

                            OP_ADD: begin
                            if (rd_index != 5'd0)
                                regs[rd_index] <=
                                    regs[rs1_index] + regs[rs2_index];

                            pc    <= pc + 32'd4;
                            state <= STATE_FETCH;
                        end

                        OP_SUB: begin
                            if (rd_index != 5'd0)
                                regs[rd_index] <=
                                    regs[rs1_index] - regs[rs2_index];

                            pc    <= pc + 32'd4;
                            state <= STATE_FETCH;
                        end

                        OP_AND: begin
                            if (rd_index != 5'd0)
                                regs[rd_index] <=
                                    regs[rs1_index] & regs[rs2_index];

                            pc    <= pc + 32'd4;
                            state <= STATE_FETCH;
                        end

                        OP_OR: begin
                            if (rd_index != 5'd0)
                                regs[rd_index] <=
                                    regs[rs1_index] | regs[rs2_index];

                            pc    <= pc + 32'd4;
                            state <= STATE_FETCH;
                        end

                        OP_XOR: begin
                            if (rd_index != 5'd0)
                                regs[rd_index] <=
                                    regs[rs1_index] ^ regs[rs2_index];

                            pc    <= pc + 32'd4;
                            state <= STATE_FETCH;
                        end

                        OP_ADDI: begin
                                if (rd_index != 5'd0)
                                    regs[rd_index] <=
                                        regs[rs1_index] + imm14_sext;

                                pc    <= pc + 32'd4;
                                state <= STATE_FETCH;
                            end

                            OP_HALT: begin
                                halted_reg <= 1'b1;
                                state      <= STATE_DECODE;
                            end

                            default: begin
                                // Reserved-opcode behavior is architecturally
                                // undefined in Milestone 2. Hold here rather
                                // than silently treating it as another opcode.
                                state <= STATE_DECODE;
                            end
                        endcase
                    end

                    default: begin
                        state <= STATE_FETCH;
                    end
                endcase
            end
        end
    end

    // Unified CPU memory transaction port.
    //
    // At this checkpoint only instruction fetch uses the memory interface.
    assign mem_valid = !reset &&
                       !halted_reg &&
                       (state == STATE_FETCH);

    assign mem_write = 1'b0;
    assign mem_addr  = pc;
    assign mem_wdata = 32'h00000000;
    assign mem_wstrb = 4'b0000;

    assign halted = halted_reg;

endmodule
