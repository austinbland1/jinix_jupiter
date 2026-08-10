`timescale 1ns/1ps

module jupiter_gpu_3d_flat_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;

    localparam [31:0] VERTEX_BASE      = 32'h10000000;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h10010000;

    localparam [1:0] FETCH_WORD = 2'd1;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        valid = 1'b0;
    reg        write = 1'b0;
    reg [31:0] addr  = 32'h00000000;
    reg [31:0] wdata = 32'h00000000;
    reg  [3:0] wstrb = 4'b0000;

    wire [31:0] rdata;
    wire        ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;

    reg [31:0] sdram_rdata = 32'h00000000;
    reg        sdram_ready = 1'b0;

    integer checks = 0;
    integer failures = 0;

    integer read_completions = 0;
    integer write_completions = 0;

    integer i;
    integer watchdog;
    integer wait_cycles;

    reg [31:0] held_addr;
    reg [31:0] held_data;
    reg  [3:0] held_wstrb;

    jupiter_gpu_3d dut
    (
        .clk         (clk),
        .reset       (reset),

        .valid       (valid),
        .write       (write),
        .addr        (addr),
        .wdata       (wdata),
        .wstrb       (wstrb),

        .rdata       (rdata),
        .ready       (ready),

        .sdram_valid (sdram_valid),
        .sdram_write (sdram_write),
        .sdram_addr  (sdram_addr),
        .sdram_wdata (sdram_wdata),
        .sdram_wstrb (sdram_wstrb),
        .sdram_rdata (sdram_rdata),
        .sdram_ready (sdram_ready)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (sdram_valid && sdram_ready) begin
            if (sdram_write)
                write_completions <= write_completions + 1;
            else
                read_completions <= read_completions + 1;
        end
    end

    function automatic [31:0] vertex_word;
        input integer index;

        begin
            case (index)
                0:  vertex_word = 32'h00004000;
                1:  vertex_word = 32'h00004000;
                2:  vertex_word = 32'h00001000;
                3:  vertex_word = 32'h00000000;
                4:  vertex_word = 32'h00000000;
                5:  vertex_word = 32'h00010000;

                6:  vertex_word = 32'h00034000;
                7:  vertex_word = 32'h00004000;
                8:  vertex_word = 32'h00002000;
                9:  vertex_word = 32'h00010000;
                10: vertex_word = 32'h00000000;
                11: vertex_word = 32'h00010000;

                12: vertex_word = 32'h00004000;
                13: vertex_word = 32'h00034000;
                14: vertex_word = 32'h00003000;
                15: vertex_word = 32'h00000000;
                16: vertex_word = 32'h00010000;
                17: vertex_word = 32'h00010000;

                default:
                    vertex_word = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [31:0] expected_write_addr;
        input integer index;

        begin
            case (index)
                0: expected_write_addr = FRAMEBUFFER_BASE + 32'd0;
                1: expected_write_addr = FRAMEBUFFER_BASE + 32'd0;
                2: expected_write_addr = FRAMEBUFFER_BASE + 32'd4;
                3: expected_write_addr = FRAMEBUFFER_BASE + 32'd8;
                4: expected_write_addr = FRAMEBUFFER_BASE + 32'd8;
                5: expected_write_addr = FRAMEBUFFER_BASE + 32'd16;

                default:
                    expected_write_addr = 32'hDEADBEEF;
            endcase
        end
    endfunction

    function automatic [31:0] expected_write_data;
        input integer index;

        begin
            case (index)
                1, 4:
                    expected_write_data = 32'hF8000000;

                default:
                    expected_write_data = 32'h0000F800;
            endcase
        end
    endfunction

    function automatic [3:0] expected_write_wstrb;
        input integer index;

        begin
            case (index)
                1, 4:
                    expected_write_wstrb = 4'b1100;

                default:
                    expected_write_wstrb = 4'b0011;
            endcase
        end
    endfunction

    task check;
        input condition;
        input [1023:0] message;

        begin
            checks = checks + 1;

            if (condition) begin
                $display("PASS: %0s", message);
            end else begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task mmio_write;
        input [31:0] address;
        input [31:0] data;
        input  [3:0] strobes;

        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b1;
            addr  = address;
            wdata = data;
            wstrb = strobes;

            #1;

            check(
                ready === 1'b1,
                "MMIO write completes without wait"
            );

            @(posedge clk);
            #1;

            valid = 1'b0;
            write = 1'b0;
            addr  = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;
        end
    endtask

    task complete_vertex_word;
        input integer index;

        begin
            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        VERTEX_BASE +
                        (index * 4)
                    ) &&
                sdram_wstrb == 4'b0000,
                "expected vertex fetch is presented"
            );

            @(negedge clk);

            sdram_rdata = vertex_word(index);
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr ==
                    (
                        VERTEX_BASE +
                        (index * 4)
                    ),
                "vertex fetch remains stable through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;
        end
    endtask

    task wait_for_framebuffer_write;
        input integer index;

        begin
            wait_cycles = 0;

            while (
                !(sdram_valid && sdram_write) &&
                (wait_cycles < 32768)
            ) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
            end

            check(
                wait_cycles < 32768,
                "covered pixel produces framebuffer write before watchdog"
            );

            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr == expected_write_addr(index) &&
                sdram_wdata == expected_write_data(index) &&
                sdram_wstrb == expected_write_wstrb(index),
                "framebuffer write matches deterministic RGB565 reference"
            );

            check(
                sdram_addr[1:0] == 2'b00,
                "framebuffer transaction address is 32-bit aligned"
            );

            check(
                (sdram_wstrb == 4'b0011) ||
                (sdram_wstrb == 4'b1100),
                "framebuffer write touches exactly one RGB565 halfword"
            );
        end
    endtask

    task complete_framebuffer_write;
        input integer index;

        begin
            @(negedge clk);

            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr == expected_write_addr(index) &&
                sdram_wdata == expected_write_data(index) &&
                sdram_wstrb == expected_write_wstrb(index),
                "framebuffer request remains exact through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;
        end
    endtask

    initial begin

        repeat (2)
            @(posedge clk);

        #1;

        check(
            !dut.busy &&
            !dut.done &&
            !dut.error &&
            !sdram_valid,
            "reset leaves flat renderer idle"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_write(
            REG_VERTEX_BASE,
            VERTEX_BASE,
            4'b1111
        );

        mmio_write(
            REG_FRAMEBUFFER_BASE,
            FRAMEBUFFER_BASE,
            4'b1111
        );

        mmio_write(
            REG_TARGET_SIZE,
            32'h00040004,
            4'b1111
        );

        mmio_write(
            REG_MODE,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000010,
            4'b1111
        );

        mmio_write(
            REG_FLAT_COLOR,
            32'h0000F800,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy &&
            dut.fetch_state == FETCH_WORD,
            "flat command begins with vertex fetch"
        );

        for (i = 0; i < 18; i = i + 1)
            complete_vertex_word(i);

        // ----------------------------------------------------
        // First covered pixel: hold backpressure for several clocks.
        // ----------------------------------------------------

        wait_for_framebuffer_write(0);

        held_addr  = sdram_addr;
        held_data  = sdram_wdata;
        held_wstrb = sdram_wstrb;

        repeat (3) begin
            @(posedge clk);
            #1;

            check(
                sdram_valid &&
                sdram_write &&
                sdram_addr == held_addr &&
                sdram_wdata == held_data &&
                sdram_wstrb == held_wstrb &&
                dut.raster_covered_valid,
                "covered framebuffer request remains stable while stalled"
            );
        end

        check(
            dut.raster_covered_x == 16'd0 &&
            dut.raster_covered_y == 16'd0,
            "stalled first fragment retains pixel coordinates"
        );

        // Live color changes while BUSY must affect only a later command.
        mmio_write(
            REG_FLAT_COLOR,
            32'h000007E0,
            4'b1111
        );

        check(
            dut.flat_color_reg == 32'h000007E0 &&
            dut.active_flat_color == 32'h0000F800,
            "live FLAT_COLOR write does not alter active command color"
        );

        check(
            sdram_valid &&
            sdram_write &&
            sdram_addr == held_addr &&
            sdram_wdata == held_data &&
            sdram_wstrb == held_wstrb,
            "MMIO write does not disturb stalled framebuffer request"
        );

        complete_framebuffer_write(0);

        // ----------------------------------------------------
        // Remaining deterministic covered pixels.
        // ----------------------------------------------------

        for (i = 1; i < 6; i = i + 1) begin
            wait_for_framebuffer_write(i);
            complete_framebuffer_write(i);
        end

        watchdog = 0;

        while (!dut.done && (watchdog < 32768)) begin
            @(posedge clk);
            #1;
            watchdog = watchdog + 1;
        end

        check(
            watchdog < 32768,
            "flat command completes after final framebuffer write"
        );

        check(
            dut.done &&
            !dut.busy &&
            !dut.error,
            "flat RGB565 command completes successfully"
        );

        check(
            dut.raster_coverage_count == 32'd6,
            "flat renderer consumes exactly six covered samples"
        );

        check(
            dut.raster_sample_count == 32'd16,
            "flat renderer scans deterministic sixteen-sample bounding box"
        );

        check(
            read_completions == 18,
            "flat command performs exactly eighteen vertex reads"
        );

        check(
            write_completions == 6,
            "flat command performs exactly six framebuffer writes"
        );

        check(
            dut.flat_color_reg == 32'h000007E0 &&
            dut.active_flat_color == 32'h0000F800,
            "completed command preserves live-versus-active color separation"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "completed flat command returns SDRAM interface idle"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display(
                "FLAT_VERTEX_READS: %0d",
                read_completions
            );
            $display(
                "FLAT_FRAMEBUFFER_WRITES: %0d",
                write_completions
            );
            $display(
                "FLAT_COVERED_PIXELS: %0d",
                dut.raster_coverage_count
            );
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );
        end

        $display("==============================");

        if (failures != 0)
            $fatal(1);

        $finish;
    end

endmodule
