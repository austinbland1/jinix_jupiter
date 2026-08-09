module jupiter_sdram_arbiter
(
    input  wire        clk,
    input  wire        reset,

    // CPU SDRAM master.
    input  wire        cpu_valid,
    input  wire        cpu_write,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire  [3:0] cpu_wstrb,
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,

    // GPU SDRAM master.
    input  wire        gpu_valid,
    input  wire        gpu_write,
    input  wire [31:0] gpu_addr,
    input  wire [31:0] gpu_wdata,
    input  wire  [3:0] gpu_wstrb,
    output wire [31:0] gpu_rdata,
    output wire        gpu_ready,

    // Shared 32-bit target toward jupiter_sdram_frontend.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    localparam [1:0] GRANT_NONE = 2'd0;
    localparam [1:0] GRANT_CPU  = 2'd1;
    localparam [1:0] GRANT_GPU  = 2'd2;

    reg [1:0] grant_state;

    // Records whether the currently held grant began with both masters
    // requesting simultaneously.
    reg grant_contested;

    // One means the GPU won the previous completed contested transaction.
    // Reset to one so the CPU receives the first contested grant.
    reg last_contested_gpu;

    wire idle_cpu_selected =
        !reset &&
        (grant_state == GRANT_NONE) &&
        cpu_valid &&
        (!gpu_valid || last_contested_gpu);

    wire idle_gpu_selected =
        !reset &&
        (grant_state == GRANT_NONE) &&
        gpu_valid &&
        (!cpu_valid || !last_contested_gpu);

    wire cpu_selected =
        !reset &&
        ((grant_state == GRANT_CPU) || idle_cpu_selected);

    wire gpu_selected =
        !reset &&
        ((grant_state == GRANT_GPU) || idle_gpu_selected);

    assign sdram_valid =
        cpu_selected ? cpu_valid :
        gpu_selected ? gpu_valid :
                       1'b0;

    assign sdram_write =
        cpu_selected ? cpu_write :
        gpu_selected ? gpu_write :
                       1'b0;

    assign sdram_addr =
        cpu_selected ? cpu_addr :
        gpu_selected ? gpu_addr :
                       32'h00000000;

    assign sdram_wdata =
        cpu_selected ? cpu_wdata :
        gpu_selected ? gpu_wdata :
                       32'h00000000;

    assign sdram_wstrb =
        cpu_selected ? cpu_wstrb :
        gpu_selected ? gpu_wstrb :
                       4'b0000;

    assign cpu_ready =
        cpu_selected && cpu_valid ? sdram_ready : 1'b0;

    assign gpu_ready =
        gpu_selected && gpu_valid ? sdram_ready : 1'b0;

    assign cpu_rdata =
        cpu_selected && cpu_valid ? sdram_rdata : 32'h00000000;

    assign gpu_rdata =
        gpu_selected && gpu_valid ? sdram_rdata : 32'h00000000;

    always @(posedge clk) begin
        if (reset) begin
            grant_state        <= GRANT_NONE;
            grant_contested    <= 1'b0;
            last_contested_gpu <= 1'b1;
        end else begin
            case (grant_state)
                GRANT_NONE: begin
                    if (idle_cpu_selected) begin
                        if (sdram_ready) begin
                            grant_state     <= GRANT_NONE;
                            grant_contested <= 1'b0;

                            if (gpu_valid)
                                last_contested_gpu <= 1'b0;
                        end else begin
                            grant_state     <= GRANT_CPU;
                            grant_contested <= gpu_valid;
                        end
                    end else if (idle_gpu_selected) begin
                        if (sdram_ready) begin
                            grant_state     <= GRANT_NONE;
                            grant_contested <= 1'b0;

                            if (cpu_valid)
                                last_contested_gpu <= 1'b1;
                        end else begin
                            grant_state     <= GRANT_GPU;
                            grant_contested <= cpu_valid;
                        end
                    end
                end

                GRANT_CPU: begin
                    if (cpu_valid && sdram_ready) begin
                        grant_state <= GRANT_NONE;

                        if (grant_contested)
                            last_contested_gpu <= 1'b0;

                        grant_contested <= 1'b0;
                    end
                end

                GRANT_GPU: begin
                    if (gpu_valid && sdram_ready) begin
                        grant_state <= GRANT_NONE;

                        if (grant_contested)
                            last_contested_gpu <= 1'b1;

                        grant_contested <= 1'b0;
                    end
                end

                default: begin
                    grant_state        <= GRANT_NONE;
                    grant_contested    <= 1'b0;
                    last_contested_gpu <= 1'b1;
                end
            endcase
        end
    end

endmodule
