`timescale 1ns/1ps

module jupiter_gpu_3d_vertex_tb;

    localparam [31:0] REG_CONTROL          = 32'h00001140;
    localparam [31:0] REG_STATUS           = 32'h00001144;
    localparam [31:0] REG_VERTEX_BASE      = 32'h00001148;
    localparam [31:0] REG_FRAMEBUFFER_BASE = 32'h00001150;
    localparam [31:0] REG_TARGET_SIZE      = 32'h00001158;
    localparam [31:0] REG_MODE             = 32'h00001160;
    localparam [31:0] REG_BLEND_ALPHA      = 32'h00001164;
    localparam [31:0] REG_FLAT_COLOR       = 32'h00001168;

    localparam [31:0] VERTEX_BASE_A = 32'h10000000;
    localparam [31:0] VERTEX_BASE_B = 32'h10008000;
    localparam [31:0] FRAMEBUFFER_BASE = 32'h10010000;

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
    integer read_completions = 0;
    integer write_completions = 0;
    integer i;
    integer completion_watchdog = 0;

    reg [31:0] held_addr;

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

    task complete_vertex_word;
        input [31:0] base;
        input integer index;
        input [31:0] data;
        begin
            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == (base + (index * 4)) &&
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000,
                "expected aligned vertex read is presented"
            );

            @(negedge clk);

            sdram_rdata = data;
            sdram_ready = 1'b1;

            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == (base + (index * 4)),
                "vertex read remains presented through completion"
            );

            @(posedge clk);
            #1;

            sdram_ready = 1'b0;
            sdram_rdata = 32'h00000000;
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
            dut.fetch_state == FETCH_IDLE &&
            dut.vertex_word_index == 5'd0,
            "reset clears vertex-fetch state"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "reset leaves 3D SDRAM master idle"
        );

        @(negedge clk);
        reset = 1'b0;

        // ----------------------------------------------------
        // Configure one valid flat-render command.
        // Rasterization is not implemented in M10B-2a.
        // ----------------------------------------------------

        mmio_write(
            REG_VERTEX_BASE,
            VERTEX_BASE_A,
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
            !dut.done &&
            !dut.error &&
            dut.fetch_state == FETCH_WORD &&
            dut.vertex_word_index == 5'd0,
            "valid START enters first vertex-fetch word"
        );

        check(
            dut.active_vertex_base == VERTEX_BASE_A,
            "START snapshots VERTEX_BASE"
        );

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == VERTEX_BASE_A,
            "first fetch begins at exact snapshotted VERTEX_BASE"
        );

        // ----------------------------------------------------
        // Explicitly stall first read and prove stability.
        // ----------------------------------------------------

        held_addr = sdram_addr;

        repeat (3) begin
            @(posedge clk);
            #1;

            check(
                sdram_valid &&
                !sdram_write &&
                sdram_addr == held_addr &&
                sdram_wdata == 32'h00000000 &&
                sdram_wstrb == 4'b0000 &&
                dut.vertex_word_index == 5'd0,
                "vertex request remains stable while SDRAM stalls"
            );
        end

        complete_vertex_word(
            VERTEX_BASE_A,
            0,
            vertex_word(0)
        );

        check(
            dut.vertex_word_index == 5'd1 &&
            dut.vertex_words[0] == vertex_word(0),
            "first fetched word is captured and index advances"
        );

        complete_vertex_word(
            VERTEX_BASE_A,
            1,
            vertex_word(1)
        );

        // ----------------------------------------------------
        // Live config may change while busy; active snapshot cannot.
        // ----------------------------------------------------

        mmio_write(
            REG_VERTEX_BASE,
            VERTEX_BASE_B,
            4'b1111
        );

        check(
            dut.vertex_base_reg == VERTEX_BASE_B &&
            dut.active_vertex_base == VERTEX_BASE_A,
            "live VERTEX_BASE write does not alter active snapshot"
        );

        check(
            sdram_addr == (VERTEX_BASE_A + 32'd8),
            "subsequent fetch still uses original active base"
        );

        // START while busy must be ignored.
        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy &&
            dut.active_vertex_base == VERTEX_BASE_A &&
            dut.vertex_word_index == 5'd2,
            "START while vertex fetch is busy is ignored"
        );

        for (i = 2; i < 18; i = i + 1) begin
            complete_vertex_word(
                VERTEX_BASE_A,
                i,
                vertex_word(i)
            );
        end

        check(
            dut.fetch_state == FETCH_VALIDATE &&
            dut.busy &&
            !dut.done &&
            !sdram_valid,
            "eighteenth read advances to transaction-free validation"
        );

        for (i = 0; i < 18; i = i + 1) begin
            check(
                dut.vertex_words[i] == vertex_word(i),
                "fetched vertex word matches deterministic reference"
            );
        end

        check(
            dut.vertex_words[5]  == 32'h00010000 &&
            dut.vertex_words[11] == 32'h00010000 &&
            dut.vertex_words[17] == 32'h00010000,
            "all three fetched 1/W values are nonzero"
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
            "valid fetched degenerate triangle completes before watchdog"
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
            "degenerate vertex-test command emits no framebuffer traffic"
        );

        mmio_read(
            REG_STATUS,
            32'h00000002,
            "successful vertex fetch reports sticky DONE"
        );

        check(
            read_completions == 18 &&
            write_completions == 0,
            "valid command performs exactly eighteen reads and zero writes"
        );

        // ----------------------------------------------------
        // Second command uses updated live VERTEX_BASE and injects
        // a zero 1/W in vertex one.
        // ----------------------------------------------------

        mmio_write(
            REG_CONTROL,
            32'h00000001,
            4'b0001
        );

        check(
            dut.busy &&
            !dut.done &&
            !dut.error &&
            dut.active_vertex_base == VERTEX_BASE_B &&
            sdram_addr == VERTEX_BASE_B,
            "second START snapshots updated VERTEX_BASE"
        );

        for (i = 0; i < 18; i = i + 1) begin
            if (i == 11) begin
                complete_vertex_word(
                    VERTEX_BASE_B,
                    i,
                    32'h00000000
                );
            end else begin
                complete_vertex_word(
                    VERTEX_BASE_B,
                    i,
                    vertex_word(i)
                );
            end
        end

        check(
            dut.fetch_state == FETCH_VALIDATE &&
            !sdram_valid,
            "invalid fetched 1/W still validates only after all reads"
        );

        @(posedge clk);
        #1;

        check(
            !dut.busy &&
            dut.done &&
            dut.error &&
            dut.fetch_state == FETCH_IDLE,
            "zero fetched 1/W completes command with ERROR"
        );

        mmio_read(
            REG_STATUS,
            32'h00000006,
            "zero 1/W reports sticky DONE and ERROR"
        );

        check(
            read_completions == 36 &&
            write_completions == 0,
            "two commands perform exactly thirty-six reads and zero writes"
        );

        check(
            !sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h00000000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "vertex-fetch engine returns SDRAM interface to idle"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display(
                "VERTEX_READ_COMPLETIONS: %0d",
                read_completions
            );
            $display(
                "VERTEX_WRITE_COMPLETIONS: %0d",
                write_completions
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
