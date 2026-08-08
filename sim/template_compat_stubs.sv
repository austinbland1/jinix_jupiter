// Simulation-only compatibility models for MiSTer template helpers.
//
// The original rtl/cos.sv uses an unpacked-array initialization syntax
// unsupported by the current Icarus Verilog installation.
//
// The original rtl/lfsr.v uses the Intel/Altera lcell FPGA primitive.
//
// These models are used ONLY by the Jupiter wrapper integration test.
// They are not synthesizable replacements and must never be added to files.qip.

module lfsr #(
    parameter N = 63
)
(
    output wire [N-1:0] rnd
);

    // Deterministic value is sufficient for wrapper equivalence testing.
    assign rnd = {N{1'b0}};

endmodule


module cos
(
    input  wire [9:0] x,
    output wire [7:0] y
);

    // Deterministic varying value. The integration test compares the
    // wrapper against a direct mycore reference using this same model.
    assign y = x[7:0] ^ {8{x[8]}};

endmodule
