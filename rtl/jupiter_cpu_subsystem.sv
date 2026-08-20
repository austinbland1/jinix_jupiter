module jupiter_cpu_subsystem
#(
    parameter RAM_INIT_B0 = "",
    parameter RAM_INIT_B1 = "",
    parameter RAM_INIT_B2 = "",
    parameter RAM_INIT_B3 = ""
)
(
    input  wire clk,
    input  wire reset,


    // M11B production framebuffer scanout timing mode.
    input  wire pal,
    input  wire scandouble,

    // MiSTer-reported installed external SDRAM size.
    input  wire [15:0] sdram_sz,

    // M12 MiSTer cartridge download stream.
    input  wire        ioctl_download,
    input  wire [15:0] ioctl_index,
    input  wire        ioctl_wr,
    input  wire [26:0] ioctl_addr,
    input  wire  [7:0] ioctl_dout,
    output wire        ioctl_wait,

    // M8B-1 controller-state boundary.
    //
    // Production hps_io wiring is deferred to M8B-2.
    input  wire [31:0] controller_0_state,
    input  wire [31:0] controller_1_state,
    input  wire [31:0] controller_2_state,
    input  wire [31:0] controller_3_state,
    input  wire [31:0] controller_4_state,
    input  wire [31:0] controller_5_state,

    // Physical external SDR SDRAM interface.
    //
    // SDRAM_CLK remains a later top-level integration concern.
    output wire        SDRAM_CKE,
    output wire [12:0] SDRAM_A,
    output wire  [1:0] SDRAM_BA,
    inout  wire [15:0] SDRAM_DQ,
    output wire        SDRAM_DQML,
    output wire        SDRAM_DQMH,
    output wire        SDRAM_nCS,
    output wire        SDRAM_nCAS,
    output wire        SDRAM_nRAS,
    output wire        SDRAM_nWE,

    // Stable Jupiter mixed PCM samples.
    output wire signed [15:0] audio_l,
    output wire signed [15:0] audio_r,


    // M11B production framebuffer scanout boundary.
    output wire        video_ce_pix,
    output wire        video_hblank,
    output wire        video_hsync,
    output wire        video_vblank,
    output wire        video_vsync,
    output wire  [7:0] video_r,
    output wire  [7:0] video_g,
    output wire  [7:0] video_b,

    output wire        halted
);

    // CPU master transaction interface.
    wire        cpu_mem_valid;
    wire        cpu_mem_write;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [3:0]  cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;
    wire        cpu_mem_ready;

    // Internal RAM target interface.
    wire        ram_valid;
    wire        ram_write;
    wire [31:0] ram_addr;
    wire [31:0] ram_wdata;
    wire [3:0]  ram_wstrb;
    wire [31:0] ram_rdata;
    wire        ram_ready;

    // MMIO target interface.
    wire        mmio_valid;
    wire        mmio_write;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [3:0]  mmio_wstrb;
    wire [31:0] mmio_rdata;
    wire        mmio_ready;

    // GPU control-MMIO target interface.
    wire        gpu_valid;
    wire        gpu_write;
    wire [31:0] gpu_addr;
    wire [31:0] gpu_wdata;
    wire  [3:0] gpu_wstrb;
    wire [31:0] gpu_rdata;
    wire        gpu_ready;

    // M11B display-MMIO subdecode inside the existing GPU aperture.
    wire scanout_mmio_selected =
        gpu_valid &&
        (gpu_addr >= 32'h00001180) &&
        (gpu_addr <= 32'h000011BF);

    wire gpu_render_valid =
        gpu_valid &&
        !scanout_mmio_selected;

    wire [31:0] gpu_render_rdata;
    wire        gpu_render_ready;

    wire [31:0] scanout_mmio_rdata;
    wire        scanout_mmio_ready;

    assign gpu_rdata =
        scanout_mmio_selected ?
            scanout_mmio_rdata :
            gpu_render_rdata;

    assign gpu_ready =
        scanout_mmio_selected ?
            scanout_mmio_ready :
            gpu_render_ready;
    // DMA control-MMIO target interface.
    wire        dma_valid;
    wire        dma_write;
    wire [31:0] dma_addr;
    wire [31:0] dma_wdata;
    wire  [3:0] dma_wstrb;
    wire [31:0] dma_rdata;
    wire        dma_ready;

    // Audio control-MMIO target interface.
    wire        audio_valid;
    wire        audio_write;
    wire [31:0] audio_addr;
    wire [31:0] audio_wdata;
    wire  [3:0] audio_wstrb;
    wire [31:0] audio_rdata;
    wire        audio_ready;

    // Controller input-MMIO target interface.
    wire        controller_valid;
    wire        controller_write;
    wire [31:0] controller_addr;
    wire [31:0] controller_wdata;
    wire  [3:0] controller_wstrb;
    wire [31:0] controller_rdata;
    wire        controller_ready;

    // M12 cartridge-loader MMIO target interface.
    wire        loader_mmio_valid;
    wire        loader_mmio_write;
    wire [31:0] loader_mmio_addr;
    wire [31:0] loader_mmio_wdata;
    wire  [3:0] loader_mmio_wstrb;
    wire [31:0] loader_mmio_rdata;
    wire        loader_mmio_ready;

    // CPU external-SDRAM target interface from the interconnect.
wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;
    wire [31:0] sdram_rdata;
    wire        sdram_ready;

    // GPU external-SDRAM master interface.
    wire        gpu_sdram_valid;
    wire        gpu_sdram_write;
    wire [31:0] gpu_sdram_addr;
    wire [31:0] gpu_sdram_wdata;
    wire  [3:0] gpu_sdram_wstrb;
    wire [31:0] gpu_sdram_rdata;
    wire        gpu_sdram_ready;

    // DMA external-SDRAM master interface.
    //
    // M6C-2 connects this production interface to the shared
    // CPU/GPU/DMA SDRAM arbiter.
    wire        dma_sdram_valid;
    wire        dma_sdram_write;
    wire [31:0] dma_sdram_addr;
    wire [31:0] dma_sdram_wdata;
    wire  [3:0] dma_sdram_wstrb;
    wire [31:0] dma_sdram_rdata;
    wire        dma_sdram_ready;

    // Shared post-arbitration 32-bit interface toward the M4 frontend.
    wire        shared_sdram_valid;
    wire        shared_sdram_write;
    wire [31:0] shared_sdram_addr;
    wire [31:0] shared_sdram_wdata;
    wire  [3:0] shared_sdram_wstrb;
    wire [31:0] shared_sdram_rdata;
    wire        shared_sdram_ready;

    // M11B read-only framebuffer scanout master.
    wire        scanout_sdram_valid;
    wire [31:0] scanout_sdram_addr;
    wire [31:0] scanout_sdram_rdata;
    wire        scanout_sdram_ready;

    // Output of the second-stage normal/scanout arbiter. M12 calls this
    // the aggregate game stream feeding the new third arbitration stage.
    wire        game_sdram_valid;
    wire        game_sdram_write;
    wire [31:0] game_sdram_addr;
    wire [31:0] game_sdram_wdata;
    wire  [3:0] game_sdram_wstrb;
    wire [31:0] game_sdram_rdata;
    wire        game_sdram_ready;

    // M12 cartridge loader write-only SDRAM master.
    wire        loader_sdram_valid;
    wire [31:0] loader_sdram_addr;
    wire [31:0] loader_sdram_wdata;
    wire  [3:0] loader_sdram_wstrb;
    wire        loader_sdram_ready;

    // Output of the third-stage game/loader arbiter toward the unchanged
    // jupiter_sdram_frontend.
    wire        frontend_sdram_valid;
    wire        frontend_sdram_write;
    wire [31:0] frontend_sdram_addr;
    wire [31:0] frontend_sdram_wdata;
    wire  [3:0] frontend_sdram_wstrb;
    wire [31:0] frontend_sdram_rdata;
    wire        frontend_sdram_ready;


    // SDRAM frontend/controller halfword interface.
    wire        half_valid;
    wire        half_write;
    wire [25:0] half_addr;
    wire [15:0] half_wdata;
    wire  [1:0] half_wstrb;
    wire [15:0] half_rdata;
    wire        half_ready;

    wire        sdram_initialized;


    reg [31:0] sdram_capacity_bytes;

    always @* begin
        case (sdram_sz[1:0])
            2'd1:
                sdram_capacity_bytes =
                    32'h02000000;

            2'd2:
                sdram_capacity_bytes =
                    32'h04000000;

            2'd3:
                sdram_capacity_bytes =
                    32'h08000000;

            default:
                sdram_capacity_bytes =
                    32'h00000000;
        endcase
    end

    wire sdram_size_valid =
        sdram_sz[15] &&
        (sdram_capacity_bytes != 32'd0);

    // Both video scanout and the M12 loader consume the inclusive final
    // installed SDRAM byte address.
    wire [31:0] sdram_max_addr =
        sdram_size_valid ?
            (32'h10000000 +
             sdram_capacity_bytes -
             32'd1) :
            32'h00000000;

    wire loader_active;
    wire core_reset =
        reset ||
        loader_active;

    jupiter_cpu cpu
    (
        .clk       (clk),
        .reset     (core_reset),

        .mem_valid (cpu_mem_valid),
        .mem_write (cpu_mem_write),
        .mem_addr  (cpu_mem_addr),
        .mem_wdata (cpu_mem_wdata),
        .mem_wstrb (cpu_mem_wstrb),

        .mem_rdata (cpu_mem_rdata),
        .mem_ready (cpu_mem_ready),

        .halted    (halted)
    );

    jupiter_interconnect bus_fabric
    (
        .m_valid    (cpu_mem_valid),
        .m_write    (cpu_mem_write),
        .m_addr     (cpu_mem_addr),
        .m_wdata    (cpu_mem_wdata),
        .m_wstrb    (cpu_mem_wstrb),

        .m_rdata    (cpu_mem_rdata),
        .m_ready    (cpu_mem_ready),

        .ram_valid  (ram_valid),
        .ram_write  (ram_write),
        .ram_addr   (ram_addr),
        .ram_wdata  (ram_wdata),
        .ram_wstrb  (ram_wstrb),
        .ram_rdata  (ram_rdata),
        .ram_ready  (ram_ready),

        .mmio_valid (mmio_valid),
        .mmio_write (mmio_write),
        .mmio_addr  (mmio_addr),
        .mmio_wdata (mmio_wdata),
        .mmio_wstrb (mmio_wstrb),
        .mmio_rdata (mmio_rdata),
        .mmio_ready (mmio_ready),

        .gpu_valid  (gpu_valid),
        .gpu_write  (gpu_write),
        .gpu_addr   (gpu_addr),
        .gpu_wdata  (gpu_wdata),
        .gpu_wstrb  (gpu_wstrb),
        .gpu_rdata  (gpu_rdata),
        .gpu_ready  (gpu_ready),

        .dma_valid  (dma_valid),
        .dma_write  (dma_write),
        .dma_addr   (dma_addr),
        .dma_wdata  (dma_wdata),
        .dma_wstrb  (dma_wstrb),        .dma_rdata  (dma_rdata),
        .dma_ready  (dma_ready),

        .audio_valid (audio_valid),
        .audio_write (audio_write),
        .audio_addr  (audio_addr),
        .audio_wdata (audio_wdata),
        .audio_wstrb (audio_wstrb),
        .audio_rdata (audio_rdata),
        .audio_ready (audio_ready),

        .controller_valid (controller_valid),
        .controller_write (controller_write),
        .controller_addr  (controller_addr),
        .controller_wdata (controller_wdata),
        .controller_wstrb (controller_wstrb),
        .controller_rdata (controller_rdata),
        .controller_ready (controller_ready),

        .loader_valid (loader_mmio_valid),
        .loader_write (loader_mmio_write),
        .loader_addr  (loader_mmio_addr),
        .loader_wdata (loader_mmio_wdata),
        .loader_wstrb (loader_mmio_wstrb),
        .loader_rdata (loader_mmio_rdata),
        .loader_ready (loader_mmio_ready),

        .sdram_valid (sdram_valid),
.sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );

    jupiter_sdram_arbiter sdram_arbiter
    (
        .clk         (clk),
        .reset       (core_reset),

        .cpu_valid   (sdram_valid),
        .cpu_write   (sdram_write),
        .cpu_addr    (sdram_addr),
        .cpu_wdata   (sdram_wdata),
        .cpu_wstrb   (sdram_wstrb),
        .cpu_rdata   (sdram_rdata),
        .cpu_ready   (sdram_ready),

        .gpu_valid   (gpu_sdram_valid),
        .gpu_write   (gpu_sdram_write),
        .gpu_addr    (gpu_sdram_addr),
        .gpu_wdata   (gpu_sdram_wdata),
        .gpu_wstrb   (gpu_sdram_wstrb),
        .gpu_rdata   (gpu_sdram_rdata),
        .gpu_ready   (gpu_sdram_ready),

        .dma_valid   (dma_sdram_valid),
        .dma_write   (dma_sdram_write),
        .dma_addr    (dma_sdram_addr),
        .dma_wdata   (dma_sdram_wdata),
        .dma_wstrb   (dma_sdram_wstrb),
        .dma_rdata   (dma_sdram_rdata),
        .dma_ready   (dma_sdram_ready),

        .sdram_valid (shared_sdram_valid),
        .sdram_write (shared_sdram_write),
        .sdram_addr  (shared_sdram_addr),
        .sdram_wdata (shared_sdram_wdata),
        .sdram_wstrb (shared_sdram_wstrb),
        .sdram_rdata (shared_sdram_rdata),
        .sdram_ready (shared_sdram_ready)
    );
    jupiter_sdram_scanout_arbiter scanout_sdram_arbiter
    (
        .clk            (clk),
        .reset          (core_reset),

        .normal_valid   (shared_sdram_valid),
        .normal_write   (shared_sdram_write),
        .normal_addr    (shared_sdram_addr),
        .normal_wdata   (shared_sdram_wdata),
        .normal_wstrb   (shared_sdram_wstrb),
        .normal_rdata   (shared_sdram_rdata),
        .normal_ready   (shared_sdram_ready),

        .scanout_valid  (scanout_sdram_valid),
        .scanout_addr   (scanout_sdram_addr),
        .scanout_rdata  (scanout_sdram_rdata),
        .scanout_ready  (scanout_sdram_ready),

        .sdram_valid    (game_sdram_valid),
        .sdram_write    (game_sdram_write),
        .sdram_addr     (game_sdram_addr),
        .sdram_wdata    (game_sdram_wdata),
        .sdram_wstrb    (game_sdram_wstrb),
        .sdram_rdata    (game_sdram_rdata),
        .sdram_ready    (game_sdram_ready)
    );



    jupiter_loader loader
    (
        .clk              (clk),
        .reset            (reset),

        .ioctl_download   (ioctl_download),
        .ioctl_index      (ioctl_index),
        .ioctl_wr         (ioctl_wr),
        .ioctl_addr       (ioctl_addr),
        .ioctl_dout       (ioctl_dout),
        .ioctl_wait       (ioctl_wait),

        .mmio_valid       (loader_mmio_valid),
        .mmio_write       (loader_mmio_write),
        .mmio_addr        (loader_mmio_addr),
        .mmio_wdata       (loader_mmio_wdata),
        .mmio_wstrb       (loader_mmio_wstrb),
        .mmio_rdata       (loader_mmio_rdata),
        .mmio_ready       (loader_mmio_ready),

        .sdram_size_valid (sdram_size_valid),
        .sdram_max_addr   (sdram_max_addr),

        .sdram_valid      (loader_sdram_valid),
        .sdram_write      (),
        .sdram_addr       (loader_sdram_addr),
        .sdram_wdata      (loader_sdram_wdata),
        .sdram_wstrb      (loader_sdram_wstrb),
        .sdram_ready      (loader_sdram_ready),

        .loader_active    (loader_active)
    );

    jupiter_sdram_loader_arbiter loader_sdram_arbiter
    (
        .clk          (clk),
        .reset        (reset),

        .game_valid   (game_sdram_valid),
        .game_write   (game_sdram_write),
        .game_addr    (game_sdram_addr),
        .game_wdata   (game_sdram_wdata),
        .game_wstrb   (game_sdram_wstrb),
        .game_rdata   (game_sdram_rdata),
        .game_ready   (game_sdram_ready),

        .loader_valid (loader_sdram_valid),
        .loader_addr  (loader_sdram_addr),
        .loader_wdata (loader_sdram_wdata),
        .loader_wstrb (loader_sdram_wstrb),
        .loader_ready (loader_sdram_ready),

        .sdram_valid  (frontend_sdram_valid),
        .sdram_write  (frontend_sdram_write),
        .sdram_addr   (frontend_sdram_addr),
        .sdram_wdata  (frontend_sdram_wdata),
        .sdram_wstrb  (frontend_sdram_wstrb),
        .sdram_rdata  (frontend_sdram_rdata),
        .sdram_ready  (frontend_sdram_ready)
    );

    jupiter_sdram_frontend sdram_frontend
    (
        .clk        (clk),
        .reset      (reset),

        .m_valid    (frontend_sdram_valid),
        .m_write    (frontend_sdram_write),
        .m_addr     (frontend_sdram_addr),
        .m_wdata    (frontend_sdram_wdata),
        .m_wstrb    (frontend_sdram_wstrb),
        .m_rdata    (frontend_sdram_rdata),
        .m_ready    (frontend_sdram_ready),

        .sdram_sz   (sdram_sz),

        .half_valid (half_valid),
        .half_write (half_write),
        .half_addr  (half_addr),
        .half_wdata (half_wdata),
        .half_wstrb (half_wstrb),
        .half_rdata (half_rdata),
        .half_ready (half_ready)
    );

    jupiter_sdram_controller sdram_controller
    (
        .clk         (clk),
        .reset       (reset),

        .initialized (sdram_initialized),

        .half_valid  (half_valid),
        .half_write  (half_write),
        .half_addr   (half_addr),
        .half_wdata  (half_wdata),
        .half_wstrb  (half_wstrb),
        .half_rdata  (half_rdata),
        .half_ready  (half_ready),

        .SDRAM_CKE   (SDRAM_CKE),
        .SDRAM_A     (SDRAM_A),
        .SDRAM_BA    (SDRAM_BA),
        .SDRAM_DQ    (SDRAM_DQ),
        .SDRAM_DQML  (SDRAM_DQML),
        .SDRAM_DQMH  (SDRAM_DQMH),
        .SDRAM_nCS   (SDRAM_nCS),
        .SDRAM_nCAS  (SDRAM_nCAS),
        .SDRAM_nRAS  (SDRAM_nRAS),
        .SDRAM_nWE   (SDRAM_nWE)
    );

    jupiter_internal_ram ram
    (
        .clk   (clk),

        .valid (ram_valid),
        .write (ram_write),
        .addr  (ram_addr),
        .wdata (ram_wdata),
        .wstrb (ram_wstrb),

        .rdata (ram_rdata),
        .ready (ram_ready)
    );

    defparam ram.INIT_B0 = RAM_INIT_B0;
    defparam ram.INIT_B1 = RAM_INIT_B1;
    defparam ram.INIT_B2 = RAM_INIT_B2;
    defparam ram.INIT_B3 = RAM_INIT_B3;

    jupiter_mmio_scratch scratch
    (
        .clk   (clk),
        .reset (reset),

        .valid (mmio_valid),
        .write (mmio_write),
        .addr  (mmio_addr),
        .wdata (mmio_wdata),
        .wstrb (mmio_wstrb),

        .rdata (mmio_rdata),
        .ready (mmio_ready)
    );
    jupiter_video_scanout video_scanout
    (
        .clk            (clk),
        .reset          (core_reset),

        .pal            (pal),
        .scandouble     (scandouble),

        .valid          (scanout_mmio_selected),
        .write          (gpu_write),
        .addr           (gpu_addr),
        .wdata          (gpu_wdata),
        .wstrb          (gpu_wstrb),

        .rdata          (scanout_mmio_rdata),
        .ready          (scanout_mmio_ready),

        .sdram_max_addr (sdram_max_addr),

        .sdram_valid    (scanout_sdram_valid),
        .sdram_addr     (scanout_sdram_addr),
        .sdram_rdata    (scanout_sdram_rdata),
        .sdram_ready    (scanout_sdram_ready),

        .ce_pix         (video_ce_pix),

        .HBlank         (video_hblank),
        .HSync          (video_hsync),
        .VBlank         (video_vblank),
        .VSync          (video_vsync),

        .video_r        (video_r),
        .video_g        (video_g),
        .video_b        (video_b)
    );



    jupiter_gpu_2d gpu
    (
        .clk   (clk),
        .reset (core_reset),

        .valid (gpu_render_valid),
        .write (gpu_write),
        .addr  (gpu_addr),
        .wdata (gpu_wdata),
        .wstrb (gpu_wstrb),

        .rdata (gpu_render_rdata),
        .ready (gpu_render_ready),

        .sdram_valid (gpu_sdram_valid),
        .sdram_write (gpu_sdram_write),
        .sdram_addr  (gpu_sdram_addr),
        .sdram_wdata (gpu_sdram_wdata),
        .sdram_wstrb (gpu_sdram_wstrb),
        .sdram_rdata (gpu_sdram_rdata),
        .sdram_ready (gpu_sdram_ready)
    );


    jupiter_dma dma
    (
        .clk   (clk),
        .reset (core_reset),

        .valid (dma_valid),
        .write (dma_write),
        .addr  (dma_addr),
        .wdata (dma_wdata),
        .wstrb (dma_wstrb),

        .rdata (dma_rdata),
        .ready (dma_ready),

        .sdram_valid (dma_sdram_valid),
        .sdram_write (dma_sdram_write),
        .sdram_addr  (dma_sdram_addr),
        .sdram_wdata (dma_sdram_wdata),
        .sdram_wstrb (dma_sdram_wstrb),        .sdram_rdata (dma_sdram_rdata),
        .sdram_ready (dma_sdram_ready)
    );

    jupiter_audio audio
    (
        .clk   (clk),
        .reset (core_reset),

        .valid (audio_valid),
        .write (audio_write),
        .addr  (audio_addr),
        .wdata (audio_wdata),
        .wstrb (audio_wstrb),

        .rdata (audio_rdata),
        .ready (audio_ready),

        .audio_l (audio_l),
        .audio_r (audio_r)
    );

    jupiter_controllers controllers
    (
        .valid (controller_valid),
        .write (controller_write),
        .addr  (controller_addr),
        .wdata (controller_wdata),
        .wstrb (controller_wstrb),

        .controller_0_state (controller_0_state),
        .controller_1_state (controller_1_state),
        .controller_2_state (controller_2_state),
        .controller_3_state (controller_3_state),
        .controller_4_state (controller_4_state),
        .controller_5_state (controller_5_state),

        .rdata (controller_rdata),
        .ready (controller_ready)
    );

endmodule
