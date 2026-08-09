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

    // DMA SDRAM master.
    input  wire        dma_valid,
    input  wire        dma_write,
    input  wire [31:0] dma_addr,
    input  wire [31:0] dma_wdata,
    input  wire  [3:0] dma_wstrb,
    output wire [31:0] dma_rdata,
    output wire        dma_ready,

    // Shared 32-bit target toward jupiter_sdram_frontend.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_ready
);

    // Preserve the Milestone 5 CPU/GPU encodings because existing
    // integration regressions inspect grant_state hierarchically.
    localparam [1:0] GRANT_NONE = 2'd0;
    localparam [1:0] GRANT_CPU  = 2'd1;
    localparam [1:0] GRANT_GPU  = 2'd2;
    localparam [1:0] GRANT_DMA  = 2'd3;

    reg [1:0] grant_state;

    // Records whether the currently held grant began with at least
    // two masters requesting simultaneously.
    reg grant_contested;

    // Most recent master whose completed transaction began contested.
    //
    // Reset to DMA so the next cyclic preference is CPU:
    //
    //     CPU -> GPU -> DMA -> CPU
    //
    // Therefore CPU wins the first post-reset contested arbitration
    // whenever CPU participates.
    reg [1:0] last_contested_winner;

    wire contested_now =
        (cpu_valid && gpu_valid) ||
        (cpu_valid && dma_valid) ||
        (gpu_valid && dma_valid);

    // Combinational arbitration is used only while no transaction is held.
    //
    // An uncontested requester is selected immediately.
    //
    // For a contest, search cyclically after the previous contested winner,
    // skipping inactive requesters.
    reg [1:0] idle_grant;

    always @* begin
        idle_grant = GRANT_NONE;

        if (!reset &&
            (grant_state == GRANT_NONE)) begin

            case ({
                cpu_valid,
                gpu_valid,
                dma_valid
            })
                3'b000:
                    idle_grant = GRANT_NONE;

                3'b100:
                    idle_grant = GRANT_CPU;

                3'b010:
                    idle_grant = GRANT_GPU;

                3'b001:
                    idle_grant = GRANT_DMA;

                default: begin
                    case (last_contested_winner)
                        GRANT_CPU: begin
                            if (gpu_valid)
                                idle_grant = GRANT_GPU;
                            else if (dma_valid)
                                idle_grant = GRANT_DMA;
                            else
                                idle_grant = GRANT_CPU;
                        end

                        GRANT_GPU: begin
                            if (dma_valid)
                                idle_grant = GRANT_DMA;
                            else if (cpu_valid)
                                idle_grant = GRANT_CPU;
                            else
                                idle_grant = GRANT_GPU;
                        end

                        default: begin
                            // GRANT_DMA and defensive/default state:
                            // begin cyclic search with CPU.
                            if (cpu_valid)
                                idle_grant = GRANT_CPU;
                            else if (gpu_valid)
                                idle_grant = GRANT_GPU;
                            else
                                idle_grant = GRANT_DMA;
                        end
                    endcase
                end
            endcase
        end
    end

    wire idle_cpu_selected =
        (idle_grant == GRANT_CPU);

    wire idle_gpu_selected =
        (idle_grant == GRANT_GPU);

    wire idle_dma_selected =
        (idle_grant == GRANT_DMA);

    wire cpu_selected =
        !reset &&
        ((grant_state == GRANT_CPU) ||
         idle_cpu_selected);

    wire gpu_selected =
        !reset &&
        ((grant_state == GRANT_GPU) ||
         idle_gpu_selected);

    wire dma_selected =
        !reset &&
        ((grant_state == GRANT_DMA) ||
         idle_dma_selected);

    assign sdram_valid =
        cpu_selected ? cpu_valid :
        gpu_selected ? gpu_valid :
        dma_selected ? dma_valid :
                       1'b0;

    assign sdram_write =
        cpu_selected ? cpu_write :
        gpu_selected ? gpu_write :
        dma_selected ? dma_write :
                       1'b0;

    assign sdram_addr =
        cpu_selected ? cpu_addr :
        gpu_selected ? gpu_addr :
        dma_selected ? dma_addr :
                       32'h00000000;

    assign sdram_wdata =
        cpu_selected ? cpu_wdata :
        gpu_selected ? gpu_wdata :
        dma_selected ? dma_wdata :
                       32'h00000000;

    assign sdram_wstrb =
        cpu_selected ? cpu_wstrb :
        gpu_selected ? gpu_wstrb :
        dma_selected ? dma_wstrb :
                       4'b0000;

    assign cpu_ready =
        cpu_selected && cpu_valid ?
        sdram_ready :
        1'b0;

    assign gpu_ready =
        gpu_selected && gpu_valid ?
        sdram_ready :
        1'b0;

    assign dma_ready =
        dma_selected && dma_valid ?
        sdram_ready :
        1'b0;

    assign cpu_rdata =
        cpu_selected && cpu_valid ?
        sdram_rdata :
        32'h00000000;

    assign gpu_rdata =
        gpu_selected && gpu_valid ?
        sdram_rdata :
        32'h00000000;

    assign dma_rdata =
        dma_selected && dma_valid ?
        sdram_rdata :
        32'h00000000;

    always @(posedge clk) begin
        if (reset) begin
            grant_state           <= GRANT_NONE;
            grant_contested       <= 1'b0;
            last_contested_winner <= GRANT_DMA;
        end else begin
            case (grant_state)
                GRANT_NONE: begin
                    if (idle_grant != GRANT_NONE) begin
                        if (sdram_ready) begin
                            // Immediate completion at the free arbitration
                            // point. Only a contested completion changes
                            // round-robin history.
                            grant_state     <= GRANT_NONE;
                            grant_contested <= 1'b0;

                            if (contested_now)
                                last_contested_winner <=
                                    idle_grant;
                        end else begin
                            // Hold this master until its logical 32-bit
                            // transaction completes.
                            grant_state <= idle_grant;
                            grant_contested <=
                                contested_now;
                        end
                    end
                end

                GRANT_CPU: begin
                    if (cpu_valid &&
                        sdram_ready) begin

                        grant_state <= GRANT_NONE;

                        if (grant_contested)
                            last_contested_winner <=
                                GRANT_CPU;

                        grant_contested <= 1'b0;
                    end
                end

                GRANT_GPU: begin
                    if (gpu_valid &&
                        sdram_ready) begin

                        grant_state <= GRANT_NONE;

                        if (grant_contested)
                            last_contested_winner <=
                                GRANT_GPU;

                        grant_contested <= 1'b0;
                    end
                end

                GRANT_DMA: begin
                    if (dma_valid &&
                        sdram_ready) begin

                        grant_state <= GRANT_NONE;

                        if (grant_contested)
                            last_contested_winner <=
                                GRANT_DMA;

                        grant_contested <= 1'b0;
                    end
                end

                default: begin
                    grant_state           <= GRANT_NONE;
                    grant_contested       <= 1'b0;
                    last_contested_winner <= GRANT_DMA;
                end
            endcase
        end
    end

endmodule
