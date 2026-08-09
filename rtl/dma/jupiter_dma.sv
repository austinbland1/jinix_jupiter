module jupiter_dma
(
    input  wire        clk,
    input  wire        reset,

    // CPU-visible MMIO target.
    input  wire        valid,
    input  wire        write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire  [3:0] wstrb,

    output reg  [31:0] rdata,
    output wire        ready,

    // External-SDRAM master.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,

    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    localparam [31:0] REG_CONTROL      = 32'h00001200;
    localparam [31:0] REG_STATUS       = 32'h00001204;
    localparam [31:0] REG_SRC_BASE     = 32'h00001208;
    localparam [31:0] REG_DST_BASE     = 32'h0000120C;
    localparam [31:0] REG_LENGTH_WORDS = 32'h00001210;

    reg [31:0] src_base_reg;
    reg [31:0] dst_base_reg;
    reg [31:0] length_words_reg;

    reg [31:0] active_src_base;
    reg [31:0] active_dst_base;
    reg [31:0] active_length_words;

    reg busy;
    reg done;

    // M6B-1 implements control/state only. The later transfer-engine
    // checkpoint will drive the external-SDRAM master interface.
    assign sdram_valid = 1'b0;
    assign sdram_write = 1'b0;
    assign sdram_addr  = 32'h00000000;
    assign sdram_wdata = 32'h00000000;
    assign sdram_wstrb = 4'b0000;

    // The standalone MMIO block has no wait states. Production address
    // selection will be supplied by the interconnect in M6B-2.
    assign ready = valid;

    always @* begin
        rdata = 32'h00000000;

        if (valid && !write) begin
            case (addr)
                REG_CONTROL:
                    rdata = 32'h00000000;

                REG_STATUS:
                    rdata = {30'd0, done, busy};

                REG_SRC_BASE:
                    rdata = src_base_reg;

                REG_DST_BASE:
                    rdata = dst_base_reg;

                REG_LENGTH_WORDS:
                    rdata = length_words_reg;

                default:
                    rdata = 32'h00000000;
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            src_base_reg       <= 32'h00000000;
            dst_base_reg       <= 32'h00000000;
            length_words_reg   <= 32'h00000000;

            active_src_base     <= 32'h00000000;
            active_dst_base     <= 32'h00000000;
            active_length_words <= 32'h00000000;

            busy <= 1'b0;
            done <= 1'b0;
        end else if (valid && write) begin
            case (addr)
                REG_CONTROL: begin
                    if (wstrb[0] &&
                        wdata[0] &&
                        !busy) begin

                        active_src_base <=
                            src_base_reg;

                        active_dst_base <=
                            dst_base_reg;

                        active_length_words <=
                            length_words_reg;

                        done <= 1'b0;

                        if (length_words_reg ==
                            32'h00000000) begin

                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            busy <= 1'b1;
                        end
                    end
                end

                REG_STATUS: begin
                    // Read-only.
                end

                REG_SRC_BASE: begin
                    if (wstrb[0])
                        src_base_reg[7:0] <=
                            wdata[7:0];

                    if (wstrb[1])
                        src_base_reg[15:8] <=
                            wdata[15:8];

                    if (wstrb[2])
                        src_base_reg[23:16] <=
                            wdata[23:16];

                    if (wstrb[3])
                        src_base_reg[31:24] <=
                            wdata[31:24];
                end

                REG_DST_BASE: begin
                    if (wstrb[0])
                        dst_base_reg[7:0] <=
                            wdata[7:0];

                    if (wstrb[1])
                        dst_base_reg[15:8] <=
                            wdata[15:8];

                    if (wstrb[2])
                        dst_base_reg[23:16] <=
                            wdata[23:16];

                    if (wstrb[3])
                        dst_base_reg[31:24] <=
                            wdata[31:24];
                end

                REG_LENGTH_WORDS: begin
                    if (wstrb[0])
                        length_words_reg[7:0] <=
                            wdata[7:0];

                    if (wstrb[1])
                        length_words_reg[15:8] <=
                            wdata[15:8];

                    if (wstrb[2])
                        length_words_reg[23:16] <=
                            wdata[23:16];

                    if (wstrb[3])
                        length_words_reg[31:24] <=
                            wdata[31:24];
                end

                default: begin
                    // Reserved aligned offsets ignore writes.
                end
            endcase
        end
    end

    // These inputs become functional when the transfer engine is added.
    // Keeping them explicitly referenced avoids implying that B1 performs
    // any memory transaction.
    wire unused_sdram_inputs =
        ^{sdram_rdata, sdram_ready};

endmodule
