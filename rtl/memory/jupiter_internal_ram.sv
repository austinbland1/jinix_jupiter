module jupiter_internal_ram
#(
    parameter INIT_B0 = "",
    parameter INIT_B1 = "",
    parameter INIT_B2 = "",
    parameter INIT_B3 = ""
)
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
    // Hardware bring-up candidate:
    // split byte lanes allow Cyclone V MLAB inference while preserving
    // the existing asynchronous read and byte-strobe semantics.
    (* ramstyle = "MLAB, no_rw_check" *)
    reg [7:0] memory_b0 [0:1023];

    (* ramstyle = "MLAB, no_rw_check" *)
    reg [7:0] memory_b1 [0:1023];

    (* ramstyle = "MLAB, no_rw_check" *)
    reg [7:0] memory_b2 [0:1023];

    (* ramstyle = "MLAB, no_rw_check" *)
    reg [7:0] memory_b3 [0:1023];

    // Optional deterministic boot image.
    //
    // Empty defaults preserve the original simulation behavior.
    // The production Template path supplies four byte-lane images.
    initial begin
        if (INIT_B0 != "")
            $readmemh(INIT_B0, memory_b0);

        if (INIT_B1 != "")
            $readmemh(INIT_B1, memory_b1);

        if (INIT_B2 != "")
            $readmemh(INIT_B2, memory_b2);

        if (INIT_B3 != "")
            $readmemh(INIT_B3, memory_b3);
    end

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
        ? {
            memory_b3[word_index],
            memory_b2[word_index],
            memory_b1[word_index],
            memory_b0[word_index]
        }
        : 32'h00000000;

    always @(posedge clk) begin
        if (valid && write) begin
            if (wstrb[0])
                memory_b0[word_index] <= wdata[7:0];

            if (wstrb[1])
                memory_b1[word_index] <= wdata[15:8];

            if (wstrb[2])
                memory_b2[word_index] <= wdata[23:16];

            if (wstrb[3])
                memory_b3[word_index] <= wdata[31:24];
        end
    end

endmodule
