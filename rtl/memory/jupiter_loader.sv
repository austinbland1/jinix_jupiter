module jupiter_loader
#(
    parameter [31:0] LOAD_BASE = 32'h10000000
)
(
    input  wire        clk,
    input  wire        reset,

    // MiSTer file-transfer stream. WIDE=0 supplies one byte per ioctl_wr.
    input  wire        ioctl_download,
    input  wire [15:0] ioctl_index,
    input  wire        ioctl_wr,
    input  wire [26:0] ioctl_addr,
    input  wire  [7:0] ioctl_dout,
    output wire        ioctl_wait,

    // CPU-visible read-mostly MMIO target.
    input  wire        mmio_valid,
    input  wire        mmio_write,
    input  wire [31:0] mmio_addr,
    input  wire [31:0] mmio_wdata,
    input  wire  [3:0] mmio_wstrb,
    output reg  [31:0] mmio_rdata,
    output wire        mmio_ready,

    // Installed SDRAM capacity boundary supplied by the subsystem.
    input  wire        sdram_size_valid,
    input  wire [31:0] sdram_max_addr,

    // Write-only SDRAM master toward jupiter_sdram_loader_arbiter.
    output wire        sdram_valid,
    output wire        sdram_write,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire  [3:0] sdram_wstrb,
    input  wire        sdram_ready,

    output wire        loader_active
);

    // hps_io exposes a 16-bit index in this framework revision. M12 reserves
    // index 1 for top-level F1,JUP cartridge downloads.
    wire matching_download =
        (ioctl_download === 1'b1) &&
        (ioctl_index == 16'h0001);

    reg matching_download_d;

    reg        done;
    reg        overflow;
    reg [31:0] load_size;

    reg  [1:0] byte_count;
    reg [23:0] byte_buffer;

    reg        pending_valid;
    reg [31:0] pending_addr;
    reg [31:0] pending_wdata;

    reg finish_pending;

    // The core stays quiesced through the final outstanding SDRAM write even
    // if the HPS side drops ioctl_download immediately after the last byte.
    assign loader_active =
        matching_download ||
        pending_valid;

    assign sdram_valid = pending_valid;
    assign sdram_write = 1'b1;
    assign sdram_addr  = pending_addr;
    assign sdram_wdata = pending_wdata;
    assign sdram_wstrb = 4'b1111;

    // Backpressure is visible only while a complete word is outstanding and
    // the downstream shared SDRAM path has not completed it.
    assign ioctl_wait =
        pending_valid &&
        !sdram_ready;

    wire [31:0] next_write_addr =
        LOAD_BASE +
        load_size;

    wire next_write_fits =
        sdram_size_valid &&
        (sdram_max_addr >= LOAD_BASE) &&
        (next_write_addr <= (sdram_max_addr - 32'd3));

    // The HPS byte address is intentionally not used for Jupiter SDRAM
    // addressing. M12 defines write_addr from the count of completed Jupiter
    // words; ioctl_addr remains present at this boundary for exact MiSTer
    // interface traceability.
    wire _unused_ioctl_addr =
        ^ioctl_addr;

    wire _unused_mmio_write_data =
        ^{mmio_wdata, mmio_wstrb};

    assign mmio_ready =
        mmio_valid;

    always @* begin
        mmio_rdata = 32'h00000000;

        if (mmio_valid &&
            !mmio_write) begin
            case (mmio_addr[7:0])
                8'h00:
                    mmio_rdata = {
                        29'd0,
                        overflow,
                        done,
                        loader_active
                    };

                8'h04:
                    mmio_rdata =
                        load_size;

                8'h08:
                    mmio_rdata =
                        LOAD_BASE;

                default:
                    mmio_rdata =
                        32'h00000000;
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            matching_download_d <= 1'b0;

            done           <= 1'b0;
            overflow       <= 1'b0;
            load_size      <= 32'd0;

            byte_count     <= 2'd0;
            byte_buffer    <= 24'd0;

            pending_valid  <= 1'b0;
            pending_addr   <= LOAD_BASE;
            pending_wdata  <= 32'd0;

            finish_pending <= 1'b0;
        end else begin
            matching_download_d <=
                matching_download;

            // A new matching download starts a new loader result record.
            if (matching_download &&
                !matching_download_d) begin

                done           <= 1'b0;
                overflow       <= 1'b0;
                load_size      <= 32'd0;

                byte_count     <= 2'd0;
                byte_buffer    <= 24'd0;

                pending_valid  <= 1'b0;
                pending_addr   <= LOAD_BASE;
                pending_wdata  <= 32'd0;

                finish_pending <= 1'b0;
            end else begin
                // Complete an already-issued 32-bit SDRAM write.
                if (pending_valid &&
                    sdram_ready) begin

                    pending_valid <=
                        1'b0;

                    load_size <=
                        load_size +
                        32'd4;

                    if (finish_pending) begin
                        finish_pending <=
                            1'b0;

                        done <=
                            1'b1;
                    end
                end

                // Accept the next byte only when the current outstanding word
                // is absent or completes in this same cycle.
                if (matching_download) begin
                    if (ioctl_wr &&
                        (!pending_valid ||
                         sdram_ready)) begin

                        case (byte_count)
                            2'd0: begin
                                byte_buffer[7:0] <=
                                    ioctl_dout;

                                byte_count <=
                                    2'd1;
                            end

                            2'd1: begin
                                byte_buffer[15:8] <=
                                    ioctl_dout;

                                byte_count <=
                                    2'd2;
                            end

                            2'd2: begin
                                byte_buffer[23:16] <=
                                    ioctl_dout;

                                byte_count <=
                                    2'd3;
                            end

                            default: begin
                                byte_count <=
                                    2'd0;

                                if (next_write_fits) begin
                                    pending_valid <=
                                        1'b1;

                                    pending_addr <=
                                        next_write_addr;

                                    pending_wdata <= {
                                        ioctl_dout,
                                        byte_buffer
                                    };
                                end else begin
                                    overflow <=
                                        1'b1;
                                end
                            end
                        endcase
                    end
                end else if (matching_download_d) begin
                    // A 1-3 byte tail is deliberately discarded.
                    byte_count  <= 2'd0;
                    byte_buffer <= 24'd0;

                    if (pending_valid &&
                        !sdram_ready) begin

                        finish_pending <=
                            1'b1;
                    end else begin
                        finish_pending <=
                            1'b0;

                        done <=
                            1'b1;
                    end
                end
            end
        end
    end

endmodule
