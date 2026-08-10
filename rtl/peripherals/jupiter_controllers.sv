module jupiter_controllers
(
    // CPU-visible controller MMIO target.
    input  wire        valid,
    input  wire        write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire  [3:0] wstrb,

    // Raw bit-preserving controller state selected by M8A.
    input  wire [31:0] controller_0_state,
    input  wire [31:0] controller_1_state,
    input  wire [31:0] controller_2_state,
    input  wire [31:0] controller_3_state,
    input  wire [31:0] controller_4_state,
    input  wire [31:0] controller_5_state,

    output reg  [31:0] rdata,
    output wire        ready
);

    localparam [31:0] REG_CONTROLLER_0 = 32'h00001400;
    localparam [31:0] REG_CONTROLLER_1 = 32'h00001404;
    localparam [31:0] REG_CONTROLLER_2 = 32'h00001408;
    localparam [31:0] REG_CONTROLLER_3 = 32'h0000140C;
    localparam [31:0] REG_CONTROLLER_4 = 32'h00001410;
    localparam [31:0] REG_CONTROLLER_5 = 32'h00001414;

    // This read-only target inserts no wait states.
    assign ready = valid;

    always @* begin

        rdata = 32'h00000000;

        if (valid && !write) begin

            case (addr)

                REG_CONTROLLER_0:
                    rdata = controller_0_state;

                REG_CONTROLLER_1:
                    rdata = controller_1_state;

                REG_CONTROLLER_2:
                    rdata = controller_2_state;

                REG_CONTROLLER_3:
                    rdata = controller_3_state;

                REG_CONTROLLER_4:
                    rdata = controller_4_state;

                REG_CONTROLLER_5:
                    rdata = controller_5_state;

                default:
                    rdata = 32'h00000000;

            endcase
        end
    end

    // wdata and wstrb are intentionally ignored.
    // Writes complete but cannot modify external controller state.

endmodule
