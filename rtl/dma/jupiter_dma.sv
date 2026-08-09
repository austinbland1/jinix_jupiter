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

    localparam [1:0] STATE_IDLE  = 2'd0;
    localparam [1:0] STATE_READ  = 2'd1;
    localparam [1:0] STATE_WRITE = 2'd2;

    // Live CPU-visible configuration.
    reg [31:0] src_base_reg;
    reg [31:0] dst_base_reg;
    reg [31:0] length_words_reg;

    // START snapshots. These remain unchanged for the whole transfer.
    reg [31:0] active_src_base;
    reg [31:0] active_dst_base;
    reg [31:0] active_length_words;

    reg busy;
    reg done;

    // Active transfer progress.
    reg  [1:0] transfer_state;
    reg [31:0] current_src_addr;
    reg [31:0] current_dst_addr;
    reg [31:0] remaining_words;
    reg [31:0] read_data_reg;

    // One logical 32-bit transaction is presented at a time.
    //
    // READ holds its source address stable until ready.
    // WRITE holds destination address, captured data, and all four
    // byte strobes stable until ready.
    assign sdram_valid =
        busy &&
        ((transfer_state == STATE_READ) ||
         (transfer_state == STATE_WRITE));

    assign sdram_write =
        busy &&
        (transfer_state == STATE_WRITE);

    assign sdram_addr =
        (busy && (transfer_state == STATE_READ))
            ? current_src_addr :
        (busy && (transfer_state == STATE_WRITE))
            ? current_dst_addr :
              32'h00000000;

    assign sdram_wdata =
        (busy && (transfer_state == STATE_WRITE))
            ? read_data_reg :
              32'h00000000;

    assign sdram_wstrb =
        (busy && (transfer_state == STATE_WRITE))
            ? 4'b1111 :
              4'b0000;

    // DMA MMIO itself has no wait states.
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
            src_base_reg        <= 32'h00000000;
            dst_base_reg        <= 32'h00000000;
            length_words_reg    <= 32'h00000000;

            active_src_base     <= 32'h00000000;
            active_dst_base     <= 32'h00000000;
            active_length_words <= 32'h00000000;

            busy <= 1'b0;
            done <= 1'b0;

            transfer_state   <= STATE_IDLE;
            current_src_addr <= 32'h00000000;
            current_dst_addr <= 32'h00000000;
            remaining_words  <= 32'h00000000;
            read_data_reg    <= 32'h00000000;
        end else begin
            // ------------------------------------------------
            // DMA memory-transfer state machine.
            // ------------------------------------------------
            if (busy) begin
                case (transfer_state)
                    STATE_READ: begin
                        if (sdram_ready) begin
                            read_data_reg <= sdram_rdata;
                            transfer_state <= STATE_WRITE;
                        end
                    end

                    STATE_WRITE: begin
                        if (sdram_ready) begin
                            current_src_addr <=
                                current_src_addr + 32'd4;

                            current_dst_addr <=
                                current_dst_addr + 32'd4;

                            remaining_words <=
                                remaining_words - 32'd1;

                            if (remaining_words ==
                                32'd1) begin

                                busy <= 1'b0;
                                done <= 1'b1;
                                transfer_state <=
                                    STATE_IDLE;
                            end else begin
                                transfer_state <=
                                    STATE_READ;
                            end
                        end
                    end

                    default: begin
                        // Defensive recovery from an impossible active
                        // state. Normal operation never reaches this path.
                        busy <= 1'b0;
                        done <= 1'b0;
                        transfer_state <= STATE_IDLE;
                    end
                endcase
            end

            // ------------------------------------------------
            // CPU-visible writes.
            //
            // Live configuration remains writable during BUSY.
            // START is accepted only when BUSY was already clear.
            // ------------------------------------------------
            if (valid && write) begin
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

                            current_src_addr <=
                                src_base_reg;

                            current_dst_addr <=
                                dst_base_reg;

                            remaining_words <=
                                length_words_reg;

                            read_data_reg <=
                                32'h00000000;

                            done <= 1'b0;

                            if (length_words_reg ==
                                32'h00000000) begin

                                busy <= 1'b0;
                                done <= 1'b1;
                                transfer_state <=
                                    STATE_IDLE;
                            end else begin
                                busy <= 1'b1;
                                transfer_state <=
                                    STATE_READ;
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
    end

endmodule
