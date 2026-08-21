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
    localparam [7:0] OP_JMPR = 8'h33;

    localparam [7:0] OP_HALT = 8'hFF;

    // Architectural state established by Milestone 2.

    localparam [1:0] STATE_FETCH  = 2'd0;
    localparam [1:0] STATE_DECODE = 2'd1;
    localparam [1:0] STATE_LOAD   = 2'd2;
    localparam [1:0] STATE_STORE  = 2'd3;

    reg [31:0] pc;
    reg [31:0] regs [0:31];
    reg [31:0] instruction_reg;
    reg [1:0]  state;
    reg        halted_reg;

    reg [31:0] data_addr_reg;
    reg [31:0] store_data_reg;
    reg [4:0]  load_rd_reg;

    wire [7:0]  opcode      = instruction_reg[31:24];
    wire [4:0]  rd_index    = instruction_reg[23:19];
    wire [4:0]  rs1_index   = instruction_reg[18:14];
    wire [4:0]  rs2_index   = instruction_reg[13:9];
    wire [4:0]  branch_rs1_index = instruction_reg[23:19];
    wire [4:0]  branch_rs2_index = instruction_reg[18:14];

    // B/J displacements are signed word offsets relative to PC + 4.
    wire [31:0] branch_offset =
        {{16{instruction_reg[13]}}, instruction_reg[13:0], 2'b00};

    wire [31:0] jump_offset =
        {{6{instruction_reg[23]}}, instruction_reg[23:0], 2'b00};
    wire [31:0] imm14_sext  =
        {{18{instruction_reg[13]}}, instruction_reg[13:0]};

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            pc              <= 32'h00000000;
            instruction_reg <= 32'h00000000;
            state           <= STATE_FETCH;
            halted_reg      <= 1'b0;
            data_addr_reg   <= 32'h00000000;
            store_data_reg  <= 32'h00000000;
            load_rd_reg     <= 5'd0;

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

                            OP_BEQ: begin
                            if (regs[branch_rs1_index] ==
                                regs[branch_rs2_index])
                                pc <= pc + 32'd4 + branch_offset;
                            else
                                pc <= pc + 32'd4;

                            state <= STATE_FETCH;
                        end

                        OP_BNE: begin
                            if (regs[branch_rs1_index] !=
                                regs[branch_rs2_index])
                                pc <= pc + 32'd4 + branch_offset;
                            else
                                pc <= pc + 32'd4;

                            state <= STATE_FETCH;
                        end

                        OP_J: begin
                            pc    <= pc + 32'd4 + jump_offset;
                            state <= STATE_FETCH;
                        end

                        OP_JMPR: begin
                            pc    <= regs[rs1_index] + imm14_sext;
                            state <= STATE_FETCH;
                        end

                        OP_LDW: begin
                            data_addr_reg <=
                                regs[rs1_index] + imm14_sext;
                            load_rd_reg <= rd_index;
                            state       <= STATE_LOAD;
                        end

                        OP_STW: begin
                            data_addr_reg <=
                                regs[rs1_index] + imm14_sext;
                            store_data_reg <= regs[rd_index];
                            state          <= STATE_STORE;
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

                    STATE_LOAD: begin
                        if (mem_ready) begin
                            if (load_rd_reg != 5'd0)
                                regs[load_rd_reg] <= mem_rdata;

                            pc    <= pc + 32'd4;
                            state <= STATE_FETCH;
                        end
                    end

                    STATE_STORE: begin
                        if (mem_ready) begin
                            pc    <= pc + 32'd4;
                            state <= STATE_FETCH;
                        end
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
    // FETCH and LOAD are reads. STORE is a full 32-bit write. Transaction
    // address/data information is held in registers so it remains stable
    // for any number of cycles while mem_ready is low.
    assign mem_valid = !reset &&
                       !halted_reg &&
                       ((state == STATE_FETCH) ||
                        (state == STATE_LOAD) ||
                        (state == STATE_STORE));

    assign mem_write = !reset &&
                       !halted_reg &&
                       (state == STATE_STORE);

    assign mem_addr = reset
        ? 32'h00000000
        : ((state == STATE_FETCH) ? pc : data_addr_reg);

    assign mem_wdata = (!reset && (state == STATE_STORE))
        ? store_data_reg
        : 32'h00000000;

    assign mem_wstrb = (!reset && (state == STATE_STORE))
        ? 4'b1111
        : 4'b0000;

    assign halted = halted_reg;

endmodule
