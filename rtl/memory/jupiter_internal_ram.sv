module jupiter_internal_ram
(
    input  wire        clk,

    input  wire        valid,
    input  wire        write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,

    output wire [31:0] rdata,
    output wire        ready
);

    // Milestone 3 internal/test RAM:
    // 4096 bytes = 1024 x 32-bit words.
    //
    // Address decoding is performed by jupiter_interconnect. This target
    // therefore receives only aligned addresses in 0x00000000-0x00000FFF
    // during normal system operation.
    reg [31:0] memory [0:1023];

    wire [9:0] word_index = addr[11:2];

    // The M3 internal RAM does not insert wait states.
    //
    // With valid asserted, the transaction completes on the next active
    // clock edge because ready is already asserted before that edge.
    assign ready = valid;

    // Read data is combinational. It is meaningful for an active read
    // transaction; idle and write cycles return deterministic zero here.
    assign rdata =
        (valid && !write)
        ? memory[word_index]
        : 32'h00000000;

    always @(posedge clk) begin
        if (valid && write) begin
            if (wstrb[0])
                memory[word_index][7:0] <= wdata[7:0];

            if (wstrb[1])
                memory[word_index][15:8] <= wdata[15:8];

            if (wstrb[2])
                memory[word_index][23:16] <= wdata[23:16];

            if (wstrb[3])
                memory[word_index][31:24] <= wdata[31:24];
        end
    end

endmodule
