`timescale 1ns/1ps

module jupiter_sdram_controller_tb;

    localparam integer POWERUP_CYCLES          = 4;
    localparam integer TRP_CYCLES              = 1;
    localparam integer TRFC_CYCLES             = 2;
    localparam integer TMRD_CYCLES             = 1;
    localparam integer REFRESH_INTERVAL_CYCLES = 6;

    localparam [2:0] CMD_NOP          = 3'b111;
    localparam [2:0] CMD_PRECHARGE    = 3'b010;
    localparam [2:0] CMD_AUTO_REFRESH = 3'b001;
    localparam [2:0] CMD_LOAD_MODE    = 3'b000;

    localparam [12:0] MODE_REGISTER = 13'h233;

    reg clk;
    reg reset;

    wire        initialized;
    wire        SDRAM_CKE;
    wire [12:0] SDRAM_A;
    wire  [1:0] SDRAM_BA;
    wire        SDRAM_DQML;
    wire        SDRAM_DQMH;
    wire        SDRAM_nCS;
    wire        SDRAM_nCAS;
    wire        SDRAM_nRAS;
    wire        SDRAM_nWE;

    wire [2:0] command = {
        SDRAM_nRAS,
        SDRAM_nCAS,
        SDRAM_nWE
    };

    integer checks;
    integer failures;
    integer cycle_count;

    integer c_pre0;
    integer c_ref0a;
    integer c_ref0b;
    integer c_mrs0;
    integer c_pre1;
    integer c_ref1a;
    integer c_ref1b;
    integer c_mrs1;
    integer c_initialized;

    integer c_periodic0a;
    integer c_periodic1a;
    integer c_periodic0b;
    integer c_periodic1b;

    jupiter_sdram_controller #(
        .POWERUP_CYCLES          (POWERUP_CYCLES),
        .TRP_CYCLES              (TRP_CYCLES),
        .TRFC_CYCLES             (TRFC_CYCLES),
        .TMRD_CYCLES             (TMRD_CYCLES),
        .REFRESH_INTERVAL_CYCLES (REFRESH_INTERVAL_CYCLES)
    ) dut (
        .clk         (clk),
        .reset       (reset),

        .initialized (initialized),

        .SDRAM_CKE   (SDRAM_CKE),
        .SDRAM_A     (SDRAM_A),
        .SDRAM_BA    (SDRAM_BA),
        .SDRAM_DQML  (SDRAM_DQML),
        .SDRAM_DQMH  (SDRAM_DQMH),
        .SDRAM_nCS   (SDRAM_nCS),
        .SDRAM_nCAS  (SDRAM_nCAS),
        .SDRAM_nRAS  (SDRAM_nRAS),
        .SDRAM_nWE   (SDRAM_nWE)
    );

    always #5 clk = ~clk;

    always @(posedge clk)
        cycle_count = cycle_count + 1;

    task automatic check;
        input condition;
        input [8*100-1:0] message;
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

    task automatic wait_for_command;
        input  [2:0] expected_command;
        input        expected_cs;
        input integer max_cycles;
        input [8*100-1:0] description;
        output integer seen_cycle;

        integer i;
        reg found;
        begin
            found = 1'b0;
            seen_cycle = -1;

            for (i = 0; (i < max_cycles) && !found; i = i + 1) begin
                @(posedge clk);
                #1;

                if (command != CMD_NOP) begin
                    found = 1'b1;
                    seen_cycle = cycle_count;

                    check(
                        command == expected_command,
                        description
                    );

                    check(
                        SDRAM_nCS == expected_cs,
                        "command uses expected SDRAM chip selection"
                    );
                end
            end

            if (!found) begin
                check(1'b0, description);
                check(
                    1'b0,
                    "expected SDRAM command appeared before timeout"
                );
            end
        end
    endtask

    initial begin
        clk         = 1'b0;
        reset       = 1'b1;
        checks      = 0;
        failures    = 0;
        cycle_count = 0;

        repeat (3) @(posedge clk);

        #1;

        check(
            initialized == 1'b0,
            "controller is not initialized during reset"
        );

        check(
            command == CMD_NOP,
            "controller issues no SDRAM command during reset"
        );

        check(
            SDRAM_CKE == 1'b1,
            "SDRAM clock-enable remains asserted"
        );

        check(
            SDRAM_DQML == 1'b0 && SDRAM_DQMH == 1'b0,
            "maintenance path leaves both data masks unmasked"
        );

        @(negedge clk);
        reset = 1'b0;

        // ----------------------------------------------------
        // POWER-UP WAIT
        // ----------------------------------------------------

        repeat (3) begin
            @(posedge clk);
            #1;

            check(
                initialized == 1'b0,
                "initialized stays low during power-up wait"
            );

            check(
                command == CMD_NOP,
                "power-up wait issues only NOP"
            );
        end

        // ----------------------------------------------------
        // CHIP SELECTION 0 INITIALIZATION
        // ----------------------------------------------------

        wait_for_command(
            CMD_PRECHARGE,
            1'b0,
            4,
            "chip 0 initialization begins with PRECHARGE",
            c_pre0
        );

        check(
            SDRAM_A[10] == 1'b1,
            "chip 0 PRECHARGE sets A10 for all banks"
        );

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b0,
            8,
            "chip 0 first AUTO REFRESH follows PRECHARGE",
            c_ref0a
        );

        check(
            (c_ref0a - c_pre0) >= (TRP_CYCLES + 1),
            "chip 0 PRECHARGE recovery spacing is respected"
        );

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b0,
            8,
            "chip 0 second AUTO REFRESH is issued",
            c_ref0b
        );

        check(
            (c_ref0b - c_ref0a) >= (TRFC_CYCLES + 1),
            "chip 0 refresh recovery spacing is respected"
        );

        wait_for_command(
            CMD_LOAD_MODE,
            1'b0,
            8,
            "chip 0 initialization loads the mode register",
            c_mrs0
        );

        check(
            (c_mrs0 - c_ref0b) >= (TRFC_CYCLES + 1),
            "chip 0 second refresh recovery spacing is respected"
        );

        check(
            SDRAM_A == MODE_REGISTER,
            "chip 0 mode register selects BL8, CAS latency 3, and single-location writes"
        );

        check(
            SDRAM_BA == 2'b00,
            "chip 0 LOAD MODE targets base mode register"
        );

        // ----------------------------------------------------
        // CHIP SELECTION 1 INITIALIZATION
        // ----------------------------------------------------

        wait_for_command(
            CMD_PRECHARGE,
            1'b1,
            8,
            "chip 1 initialization begins with PRECHARGE",
            c_pre1
        );

        check(
            (c_pre1 - c_mrs0) >= (TMRD_CYCLES + 1),
            "chip 0 mode-register delay is respected"
        );

        check(
            SDRAM_A[10] == 1'b1,
            "chip 1 PRECHARGE sets A10 for all banks"
        );

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b1,
            8,
            "chip 1 first AUTO REFRESH follows PRECHARGE",
            c_ref1a
        );

        check(
            (c_ref1a - c_pre1) >= (TRP_CYCLES + 1),
            "chip 1 PRECHARGE recovery spacing is respected"
        );

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b1,
            8,
            "chip 1 second AUTO REFRESH is issued",
            c_ref1b
        );

        check(
            (c_ref1b - c_ref1a) >= (TRFC_CYCLES + 1),
            "chip 1 refresh recovery spacing is respected"
        );

        wait_for_command(
            CMD_LOAD_MODE,
            1'b1,
            8,
            "chip 1 initialization loads the mode register",
            c_mrs1
        );

        check(
            (c_mrs1 - c_ref1b) >= (TRFC_CYCLES + 1),
            "chip 1 second refresh recovery spacing is respected"
        );

        check(
            SDRAM_A == MODE_REGISTER,
            "chip 1 mode register selects BL8, CAS latency 3, and single-location writes"
        );

        check(
            initialized == 1'b0,
            "initialized does not assert on the LOAD MODE command itself"
        );

        // ----------------------------------------------------
        // INITIALIZATION COMPLETION
        // ----------------------------------------------------

        c_initialized = -1;

        while (c_initialized < 0) begin
            @(posedge clk);
            #1;

            if (initialized) begin
                c_initialized = cycle_count;
            end else begin
                check(
                    command == CMD_NOP,
                    "mode-register recovery contains no extra command"
                );
            end
        end

        check(
            (c_initialized - c_mrs1) >= (TMRD_CYCLES + 1),
            "final mode-register delay is respected"
        );

        check(
            initialized == 1'b1,
            "initialized asserts after both selections are configured"
        );

        // ----------------------------------------------------
        // PERIODIC REFRESH PAIR 1
        // ----------------------------------------------------

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b0,
            20,
            "periodic refresh services chip selection 0",
            c_periodic0a
        );

        check(
            initialized == 1'b1,
            "initialized stays asserted during periodic refresh"
        );

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b1,
            10,
            "periodic refresh services chip selection 1",
            c_periodic1a
        );

        check(
            (c_periodic1a - c_periodic0a) >=
                (TRFC_CYCLES + 1),
            "periodic refresh recovery separates chip selections"
        );

        check(
            initialized == 1'b1,
            "initialized remains asserted after refresh pair"
        );

        // ----------------------------------------------------
        // PERIODIC REFRESH PAIR 2
        //
        // This proves refresh is recurring rather than a
        // one-time maintenance event.
        // ----------------------------------------------------

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b0,
            30,
            "second periodic refresh again services chip selection 0",
            c_periodic0b
        );

        check(
            (c_periodic0b - c_periodic1a) >=
                REFRESH_INTERVAL_CYCLES,
            "next refresh pair is not scheduled prematurely"
        );

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b1,
            10,
            "second periodic refresh again services chip selection 1",
            c_periodic1b
        );

        check(
            (c_periodic1b - c_periodic0b) >=
                (TRFC_CYCLES + 1),
            "second refresh pair preserves recovery spacing"
        );

        // ----------------------------------------------------
        // RESET RESTART
        // ----------------------------------------------------

        @(negedge clk);
        reset = 1'b1;

        @(posedge clk);
        #1;

        check(
            initialized == 1'b0,
            "reset clears initialized"
        );

        check(
            command == CMD_NOP,
            "reset returns controller to power-up NOP state"
        );

        @(negedge clk);
        reset = 1'b0;

        repeat (3) begin
            @(posedge clk);
            #1;

            check(
                initialized == 1'b0,
                "reinitialization observes power-up delay"
            );
        end

        wait_for_command(
            CMD_PRECHARGE,
            1'b0,
            4,
            "reset restarts initialization from chip 0 PRECHARGE",
            c_pre0
        );

        // ----------------------------------------------------
        // FINAL RESULT
        // ----------------------------------------------------

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("==============================");
            $finish;
        end else begin
            $display(
                "RESULT: FAIL  (%0d failures / %0d checks)",
                failures,
                checks
            );
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
