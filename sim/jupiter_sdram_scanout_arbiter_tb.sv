`timescale 1ns/1ps

module jupiter_sdram_scanout_arbiter_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        normal_valid = 1'b0;
    reg        normal_write = 1'b0;
    reg [31:0] normal_addr  = 32'h00000000;
    reg [31:0] normal_wdata = 32'h00000000;
    reg  [3:0] normal_wstrb = 4'b0000;

    wire [31:0] normal_rdata;
    wire        normal_ready;

    reg        scanout_valid = 1'b0;
    reg [31:0] scanout_addr  = 32'h00000000;

    wire [31:0] scanout_rdata;
    wire        scanout_ready;

    wire        sdram_valid;
    wire        sdram_write;
    wire [31:0] sdram_addr;
    wire [31:0] sdram_wdata;
    wire  [3:0] sdram_wstrb;

    reg [31:0] sdram_rdata = 32'h00000000;
    reg        sdram_ready = 1'b0;

    integer pass_count = 0;
    integer fail_count = 0;

    localparam [1:0] GRANT_NONE    = 2'd0;
    localparam [1:0] GRANT_NORMAL  = 2'd1;
    localparam [1:0] GRANT_SCANOUT = 2'd2;

    always #5 clk = ~clk;

    jupiter_sdram_scanout_arbiter dut
    (
        .clk            (clk),
        .reset          (reset),

        .normal_valid   (normal_valid),
        .normal_write   (normal_write),
        .normal_addr    (normal_addr),
        .normal_wdata   (normal_wdata),
        .normal_wstrb   (normal_wstrb),
        .normal_rdata   (normal_rdata),
        .normal_ready   (normal_ready),

        .scanout_valid  (scanout_valid),
        .scanout_addr   (scanout_addr),
        .scanout_rdata  (scanout_rdata),
        .scanout_ready  (scanout_ready),

        .sdram_valid    (sdram_valid),
        .sdram_write    (sdram_write),
        .sdram_addr     (sdram_addr),
        .sdram_wdata    (sdram_wdata),
        .sdram_wstrb    (sdram_wstrb),
        .sdram_rdata    (sdram_rdata),
        .sdram_ready    (sdram_ready)
    );

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display(
                    "PASS: %0s",
                    message
                );
            end else begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL: %0s",
                    message
                );
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task clear_requesters;
        begin
            normal_valid  = 1'b0;
            normal_write  = 1'b0;
            normal_addr   = 32'h00000000;
            normal_wdata  = 32'h00000000;
            normal_wstrb  = 4'b0000;

            scanout_valid = 1'b0;
            scanout_addr  = 32'h00000000;

            sdram_ready   = 1'b0;
            sdram_rdata   = 32'h00000000;

            #1;
        end
    endtask

    initial begin
        // ====================================================
        // Reset
        // ====================================================

        clear_requesters();

        tick();
        tick();

        check(
            dut.grant_state == GRANT_NONE,
            "reset leaves no held grant"
        );

        check(
            dut.last_contested_winner == GRANT_NORMAL,
            "reset preference makes scanout next contested winner"
        );

        check(
            sdram_valid == 1'b0 &&
            normal_ready == 1'b0 &&
            scanout_ready == 1'b0,
            "reset suppresses all target/requester handshakes"
        );

        reset = 1'b0;
        #1;

        check(
            sdram_valid == 1'b0,
            "idle arbiter emits no SDRAM request"
        );

        // ====================================================
        // Uncontested normal write, stalled then completed
        // ====================================================

        normal_valid = 1'b1;
        normal_write = 1'b1;
        normal_addr  = 32'h10001000;
        normal_wdata = 32'h11223344;
        normal_wstrb = 4'b1010;
        sdram_ready  = 1'b0;

        #1;

        check(
            sdram_valid &&
            sdram_write &&
            sdram_addr == 32'h10001000 &&
            sdram_wdata == 32'h11223344 &&
            sdram_wstrb == 4'b1010,
            "uncontested normal write passes through exactly"
        );

        check(
            !normal_ready &&
            !scanout_ready,
            "stalled normal request reports no completion"
        );

        tick();

        check(
            dut.grant_state == GRANT_NORMAL,
            "stalled normal transaction captures held normal grant"
        );

        // A newly arriving scanout request cannot replace the held normal
        // transaction.
        scanout_valid = 1'b1;
        scanout_addr  = 32'h10008000;

        #1;

        check(
            sdram_addr == 32'h10001000 &&
            sdram_write &&
            sdram_wdata == 32'h11223344 &&
            sdram_wstrb == 4'b1010,
            "new scanout requester cannot replace held normal transaction"
        );

        sdram_rdata = 32'hA5A55A5A;
        sdram_ready = 1'b1;

        #1;

        check(
            normal_ready &&
            !scanout_ready,
            "only held normal requester sees completion"
        );

        check(
            normal_rdata == 32'hA5A55A5A &&
            scanout_rdata == 32'h00000000,
            "completion data routes only to held normal requester"
        );

        tick();

        clear_requesters();

        check(
            dut.grant_state == GRANT_NONE,
            "completed normal transaction releases grant"
        );

        check(
            dut.last_contested_winner == GRANT_NORMAL,
            "uncontested completion does not change contested history"
        );

        // ====================================================
        // First post-reset contest: scanout must win
        // ====================================================

        normal_valid  = 1'b1;
        normal_write  = 1'b1;
        normal_addr   = 32'h10002000;
        normal_wdata  = 32'hCAFEBABE;
        normal_wstrb  = 4'b1111;

        scanout_valid = 1'b1;
        scanout_addr  = 32'h10010000;

        sdram_ready   = 1'b0;

        #1;

        check(
            sdram_valid &&
            sdram_addr == 32'h10010000,
            "scanout wins first contested arbitration after reset"
        );

        check(
            !sdram_write &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "scanout selection is structurally read-only"
        );

        tick();

        check(
            dut.grant_state == GRANT_SCANOUT,
            "stalled first contest holds scanout grant"
        );

        check(
            dut.grant_contested == 1'b1,
            "held first contest records contested origin"
        );

        // Alter the losing normal requester. The held scanout transaction
        // remains selected.
        normal_addr  = 32'h10003000;
        normal_wdata = 32'hDEADC0DE;
        normal_wstrb = 4'b0011;

        #1;

        check(
            sdram_addr == 32'h10010000 &&
            !sdram_write &&
            sdram_wstrb == 4'b0000,
            "held scanout request ignores changes from losing requester"
        );

        sdram_rdata = 32'h56781234;
        sdram_ready = 1'b1;

        #1;

        check(
            scanout_ready &&
            !normal_ready,
            "held scanout requester alone sees completion"
        );

        check(
            scanout_rdata == 32'h56781234 &&
            normal_rdata == 32'h00000000,
            "scanout receives exact target read data"
        );

        tick();

        clear_requesters();

        check(
            dut.last_contested_winner == GRANT_SCANOUT,
            "completed contested scanout becomes round-robin history"
        );

        // ====================================================
        // Next contest: normal must win and remain held
        // ====================================================

        normal_valid  = 1'b1;
        normal_write  = 1'b0;
        normal_addr   = 32'h10004000;
        normal_wdata  = 32'h00000000;
        normal_wstrb  = 4'b0000;

        scanout_valid = 1'b1;
        scanout_addr  = 32'h10011000;

        sdram_ready   = 1'b0;

        #1;

        check(
            sdram_addr == 32'h10004000,
            "normal wins contested arbitration after scanout win"
        );

        check(
            !sdram_write,
            "selected normal read remains a read"
        );

        tick();

        check(
            dut.grant_state == GRANT_NORMAL &&
            dut.grant_contested,
            "stalled second contest holds contested normal grant"
        );

        // Mutating only the losing scanout address cannot replace normal.
        scanout_addr = 32'h10012000;
        #1;

        check(
            sdram_addr == 32'h10004000,
            "held normal contest ignores losing scanout changes"
        );

        sdram_rdata = 32'h89ABCDEF;
        sdram_ready = 1'b1;

        #1;

        check(
            normal_ready &&
            !scanout_ready &&
            normal_rdata == 32'h89ABCDEF,
            "contested normal completion routes exact read result"
        );

        tick();

        clear_requesters();

        check(
            dut.last_contested_winner == GRANT_NORMAL,
            "completed contested normal becomes round-robin history"
        );

        // ====================================================
        // Third contest: scanout alternates back
        // ====================================================

        normal_valid  = 1'b1;
        normal_write  = 1'b1;
        normal_addr   = 32'h10005000;
        normal_wdata  = 32'h01020304;
        normal_wstrb  = 4'b1111;

        scanout_valid = 1'b1;
        scanout_addr  = 32'h10013000;

        sdram_rdata   = 32'h13572468;
        sdram_ready   = 1'b1;

        #1;

        check(
            sdram_addr == 32'h10013000 &&
            scanout_ready &&
            !normal_ready,
            "third contested free point alternates back to scanout"
        );

        check(
            !sdram_write &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "immediate contested scanout completion remains read-only"
        );

        check(
            scanout_rdata == 32'h13572468,
            "immediate scanout completion receives exact read data"
        );

        tick();

        clear_requesters();

        check(
            dut.last_contested_winner == GRANT_SCANOUT,
            "immediate contested scanout completion updates history"
        );

        // ====================================================
        // Normal-only immediate pass-through
        // ====================================================

        normal_valid = 1'b1;
        normal_write = 1'b1;
        normal_addr  = 32'h10006000;
        normal_wdata = 32'h55AA33CC;
        normal_wstrb = 4'b1100;
        sdram_ready  = 1'b1;

        #1;

        check(
            sdram_valid &&
            sdram_write &&
            sdram_addr == 32'h10006000 &&
            sdram_wdata == 32'h55AA33CC &&
            sdram_wstrb == 4'b1100 &&
            normal_ready,
            "scanout-idle normal traffic passes through immediately"
        );

        tick();

        clear_requesters();

        check(
            dut.last_contested_winner == GRANT_SCANOUT,
            "uncontested normal pass-through preserves contested history"
        );

        // ====================================================
        // Scanout-only immediate read
        // ====================================================

        scanout_valid = 1'b1;
        scanout_addr  = 32'h10014000;
        sdram_rdata   = 32'hF81F07E0;
        sdram_ready   = 1'b1;

        #1;

        check(
            sdram_valid &&
            !sdram_write &&
            sdram_addr == 32'h10014000 &&
            sdram_wdata == 32'h00000000 &&
            sdram_wstrb == 4'b0000,
            "normal-idle scanout read passes through immediately"
        );

        check(
            scanout_ready &&
            scanout_rdata == 32'hF81F07E0 &&
            !normal_ready,
            "scanout-only completion routes exact result"
        );

        tick();

        clear_requesters();

        // ====================================================
        // Reset cancels held arbitration state
        // ====================================================

        normal_valid  = 1'b1;
        normal_write  = 1'b0;
        normal_addr   = 32'h10007000;

        scanout_valid = 1'b1;
        scanout_addr  = 32'h10015000;

        sdram_ready   = 1'b0;

        #1;

        // Previous contested history is SCANOUT, so NORMAL is selected.
        check(
            sdram_addr == 32'h10007000,
            "pre-reset contest selects expected alternating normal requester"
        );

        tick();

        check(
            dut.grant_state == GRANT_NORMAL,
            "pre-reset stalled transaction is held"
        );

        reset = 1'b1;
        tick();

        check(
            dut.grant_state == GRANT_NONE &&
            !dut.grant_contested,
            "reset cancels held transaction and contested state"
        );

        check(
            dut.last_contested_winner == GRANT_NORMAL,
            "reset restores first-contest scanout preference"
        );

        check(
            !sdram_valid &&
            !normal_ready &&
            !scanout_ready,
            "reset suppresses requesters even while inputs remain asserted"
        );

        clear_requesters();
        reset = 1'b0;
        #1;

        // ====================================================
        // Final result
        // ====================================================

        $display("");
        $display("==============================");

        if (fail_count == 0) begin
            $display(
                "RESULT: PASS  (%0d checks)",
                pass_count
            );
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                fail_count,
                pass_count + fail_count
            );
        end

        $display("==============================");

        if (fail_count != 0)
            $fatal(
                1,
                "M11B-2a scanout arbiter regression failed"
            );

        $finish;
    end

endmodule
