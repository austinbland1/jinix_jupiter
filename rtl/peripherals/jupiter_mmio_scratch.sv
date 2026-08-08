module jupiter_mmio_scratch
(
    input  wire        clk,
    input  wire        reset,

    input  wire        valid,
    input  wire        write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,

    output wire [31:0] rdata,
    output wire        ready
);

    // Milestone 3 scratch register at system address 0x00001000.
    //
    // Address decoding is performed by jupiter_interconnect. The full
    // system address remains present here for observability and future
    // expansion, but a valid request to this target already represents
    // the selected scratch-register transaction.
    reg [31:0] scratch_reg;

    // This Milestone 3 MMIO target does not insert wait states.
    assign ready = valid;

    // Reads return the current register value. Idle and write cycles
    // present deterministic zero read data.
    assign rdata =
        (valid && !write)
        ? scratch_reg
        : 32'h00000000;

    always @(posedge clk) begin
        if (reset) begin
            scratch_reg <= 32'h00000000;
        end else if (valid && write) begin
            if (wstrb[0])
                scratch_reg[7:0] <= wdata[7:0];

            if (wstrb[1])
                scratch_reg[15:8] <= wdata[15:8];

            if (wstrb[2])
                scratch_reg[23:16] <= wdata[23:16];

            if (wstrb[3])
                scratch_reg[31:24] <= wdata[31:24];
        end
    end

endmodule
