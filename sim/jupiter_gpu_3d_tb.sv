`timescale 1ns/1ps

module jupiter_gpu_3d_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_STATUS           = 32'h00001144;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_TEXTURE_BASE     = 32'h0000114C;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_DEPTH_BASE       = 32'h00001154;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_TEXTURE_SIZE     = 32'h0000115C;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;
    localparam [31:0] REG_RESERVED         = 32'h0000116C;

    localparam [1:0] FETCH_IDLE     = 2'd0;
    localparam [1:0] FETCH_WORD     = 2'd1;
    localparam [1:0] FETCH_VALIDATE = 2'd2;

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
    integer sdram_request_count = 0;
    integer completion_watchdog = 0;

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
        if (sdram_valid && sdram_ready)
            sdram_request_count <= sdram_request_count + 1;
    end

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
                "MMIO write completes without wait state"
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

    task mmio_read;
        input [31:0] address;
        input [31:0] expected;
        input [1023:0] message;
        begin
            @(negedge clk);

            valid = 1'b1;
            write = 1'b0;
            addr  = address;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;

            check(
                ready === 1'b1,
                "MMIO read completes without wait state"
            );

            check(
                rdata === expected,
                message
            );

            valid = 1'b0;
            addr  = 32'h00000000;

            #1;
        end
    endtask

    function automatic [31:0] vertex_word;
        input integer index;
        begin
            case (index)
                0:  vertex_word = 32'h00010000;
                1:  vertex_word = 32'h00010000;
                2:  vertex_word = 32'h00001000;
                3:  vertex_word = 32'h00000000;
                4:  vertex_word = 32'h00000000;
                5:  vertex_word = 32'h00010000;

                6:  vertex_word = 32'h00020000;
                7:  vertex_word = 32'h00020000;
                8:  vertex_word = 32'h00002000;
                9:  vertex_word = 32'h00010000;
                10: vertex_word = 32'h00000000;
                11: vertex_word = 32'h00010000;

                12: vertex_word = 32'h00030000;
                13: vertex_word = 32'h00030000;
                14: vertex_word = 32'h00003000;
                15: vertex_word = 32'h00000000;
                16: vertex_word = 32'h00010000;
                17: vertex_word = 32'h00010000;

                default:
                    vertex_word = 32'hDEADBEEF;
            endcase
        end
    endfunction

    task complete_vertex_record;
        integer fetch_index;
        begin
            for (
                fetch_index = 0;
                fetch_index < 18;
                fetch_index = fetch_index + 1
            ) begin

                check(
                    sdram_valid &&
                    !sdram_write &&
                    sdram_addr ==
                        (
                            dut.active_vertex_base +
                            (fetch_index * 4)
                        ) &&
                    sdram_wdata == 32'h00000000 &&
                    sdram_wstrb == 4'b0000,
                    "expected vertex word read is presented"
                );

                @(negedge clk);

                sdram_rdata = vertex_word(fetch_index);
                sdram_ready = 1'b1;

                #1;

                check(
                    sdram_valid &&
                    !sdram_write &&
                    sdram_addr ==
                        (
                            dut.active_vertex_base +
                            (fetch_index * 4)
                        ),
                    "vertex word remains presented through completion"
                );

                @(posedge clk);
                #1;

                sdram_ready = 1'b0;
                sdram_rdata = 32'h00000000;
            end

            check(
                dut.fetch_state == FETCH_VALIDATE &&
                dut.busy &&
                !dut.done &&
                !sdram_valid,
                "vertex record enters transaction-free validation"
            );

            completion_watchdog = 0;

            while (
                !dut.done &&
                (completion_watchdog < 16)
            ) begin
                @(posedge clk);
                #1;

                completion_watchdog =
                    completion_watchdog + 1;
            end

            check(
                completion_watchdog < 16,
                "degenerate raster completion stays bounded"
            );

            check(
                !dut.busy &&
                dut.done &&
                !dut.error &&
                dut.fetch_state == FETCH_IDLE,
                "valid fetched degenerate triangle completes normally"
            );

            check(
                !sdram_valid &&
                !sdram_write,
                "degenerate standalone command emits no framebuffer traffic"
            );
        end
    endtask

    initial begin

        // ----------------------------------------------------
        // Reset behavior
        // ----------------------------------------------------

        repeat (2)
            @(posedge clk);

        #1;

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b0 &&
            dut.error === 1'b0 &&
            dut.fetch_state == FETCH_IDLE &&
            dut.vertex_word_index == 5'd0,
            "reset clears 3D status and vertex-fetch state"
        );

        check(
            sdram_valid === 1'b0 &&
            sdram_write === 1'b0 &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "reset shell presents no SDRAM transaction"
        );

        @(negedge clk);
        reset = 1'b0;

        mmio_read(
            REG_CONTROL,
            32'h00000000,
            "CONTROL reads deterministic zero"
        );

        mmio_read(
            REG_STATUS,
            32'h00000000,
            "STATUS begins clear"
        );

        mmio_read(
            REG_RESERVED,
            32'h00000000,
            "reserved 3D offset reads zero"
        );

        // ----------------------------------------------------
        // Byte-strobe behavior
        // ----------------------------------------------------

        mmio_write(
            REG_VERTEX_BASE,
            32'h11223344,
            4'b0001
        );

        mmio_read(
            REG_VERTEX_BASE,
            32'h00000044,
            "low-byte strobe updates only selected byte"
        );

        mmio_write(
            REG_VERTEX_BASE,
            32'hAABBCCDD,
            4'b1010
        );

        mmio_read(
            REG_VERTEX_BASE,
            32'hAA00CC44,
            "sparse byte strobes preserve unselected bytes"
        );

        mmio_write(
            REG_RESERVED,
            32'hDEADBEEF,
            4'b1111
        );

        mmio_read(
            REG_RESERVED,
            32'h00000000,
            "reserved 3D write has no effect"
        );

        mmio_read(
            REG_VERTEX_BASE,
            32'hAA00CC44,
            "reserved write does not corrupt live register"
        );

        // ----------------------------------------------------
        // Deterministic invalid-command failure
        // ----------------------------------------------------

        mmio_write(
            REG_VERTEX_BASE,
            32'h10000000,
            4'b1111
        );

        mmio_write(
            REG_FRAMEBUFFER_BASE,
            32'h10001000,
            4'b1111
        );

        // height = 1, width = 0 -> invalid target.
        mmio_write(
            REG_TARGET_SIZE,
            32'h00010000,
            4'b1111
        );

        mmio_write(
            REG_MODE,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.error === 1'b1 &&
            dut.fetch_state == FETCH_IDLE,
            "invalid target completes immediately with ERROR"
        );

        mmio_read(
            REG_STATUS,
            32'h00000006,
            "invalid command reports DONE and ERROR"
        );

        check(
            sdram_request_count == 0,
            "invalid command issues zero SDRAM requests"
        );

        // ----------------------------------------------------
        // Valid vertex-fetch command
        // ----------------------------------------------------

        mmio_write(
            REG_TARGET_SIZE,
            32'h00020002,
            4'b1111
        );

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000010,
            4'b1111
        );

        mmio_write(
            REG_FLAT_COLOR,
            32'h0000F81F,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b1 &&
            dut.done === 1'b0 &&
            dut.error === 1'b0 &&
            dut.fetch_state == FETCH_WORD &&
            dut.vertex_word_index == 5'd0,
            "valid START enters vertex-fetch state"
        );

        check(
            dut.active_vertex_base == 32'h10000000 &&
            dut.active_framebuffer_base == 32'h10001000 &&
            dut.active_target_size == 32'h00020002 &&
            dut.active_mode == 32'h00000000 &&
            dut.active_blend_alpha == 32'h00000010 &&
            dut.active_flat_color == 32'h0000F81F,
            "accepted START snapshots live configuration"
        );

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10000000,
            "accepted command begins vertex word zero read"
        );

        // Live configuration remains writable while the active snapshot is
        // immutable.
        mmio_write(
            REG_FLAT_COLOR,
            32'h00001234,
            4'b1111
        );

        check(
            dut.flat_color_reg == 32'h00001234 &&
            dut.active_flat_color == 32'h0000F81F,
            "live write during fetch does not mutate active snapshot"
        );

        // START while BUSY is ignored.
        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy &&
            dut.fetch_state == FETCH_WORD &&
            dut.vertex_word_index == 5'd0 &&
            dut.active_flat_color == 32'h0000F81F,
            "START while vertex fetch is busy is ignored"
        );

        complete_vertex_record();

        mmio_read(
            REG_STATUS,
            32'h00000002,
            "successful vertex fetch reports sticky DONE"
        );

        mmio_read(
            REG_FLAT_COLOR,
            32'h00001234,
            "live write during fetch is retained for next command"
        );

        // ----------------------------------------------------
        // Next command consumes updated live configuration
        // ----------------------------------------------------

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy &&
            dut.fetch_state == FETCH_WORD &&
            dut.active_flat_color == 32'h00001234,
            "next START consumes updated live configuration"
        );

        mmio_write(
            REG_FLAT_COLOR,
            32'h00005678,
            4'b1111
        );

        check(
            dut.active_flat_color == 32'h00001234 &&
            dut.flat_color_reg == 32'h00005678,
            "second live write also preserves active snapshot"
        );

        complete_vertex_record();

        mmio_read(
            REG_FLAT_COLOR,
            32'h00005678,
            "second live write remains available for later commands"
        );

        // ----------------------------------------------------
        // Alpha validation
        // ----------------------------------------------------

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000011,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.error === 1'b1,
            "alpha greater than 16 deterministically fails"
        );

        // ----------------------------------------------------
        // Texture validation only when texture mode is enabled
        // ----------------------------------------------------

        mmio_write(
            REG_BLEND_ALPHA,
            32'h00000010,
            4'b1111
        );

        mmio_write(
            REG_TEXTURE_BASE,
            32'h10002000,
            4'b1111
        );

        mmio_write(
            REG_TEXTURE_SIZE,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_MODE,
            32'h00000001,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b0 &&
            dut.done === 1'b1 &&
            dut.error === 1'b1,
            "enabled texture with zero dimensions fails"
        );

        // Disable texture again. Zero texture size is then legal.
        mmio_write(
            REG_MODE,
            32'h00000000,
            4'b1111
        );

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy === 1'b1 &&
            dut.fetch_state == FETCH_WORD &&
            dut.error === 1'b0,
            "disabled texture does not require texture dimensions"
        );

        complete_vertex_record();

        check(
            dut.done === 1'b1 &&
            dut.busy === 1'b0 &&
            dut.error === 1'b0,
            "texture-disabled command completes successfully"
        );

        // ----------------------------------------------------
        // Global M10B-1 memory-boundary proof
        // ----------------------------------------------------

        check(
            sdram_request_count == 54,
            "three successful commands complete exactly fifty-four vertex reads"
        );

        check(
            sdram_valid === 1'b0 &&
            sdram_write === 1'b0 &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "vertex-fetch engine returns deterministic idle SDRAM values"
        );

        check(
            ready === 1'b0,
            "MMIO ready deasserts when no request is present"
        );

        // ----------------------------------------------------
        // Result
        // ----------------------------------------------------

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
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
