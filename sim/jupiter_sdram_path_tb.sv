`timescale 1ns/1ps

module jupiter_sdram_path_tb;

    localparam [31:0] SDRAM_BASE = 32'h10000000;

    localparam integer POWERUP_CYCLES          = 4;
    localparam integer TRP_CYCLES              = 1;
    localparam integer TRFC_CYCLES             = 2;
    localparam integer TMRD_CYCLES             = 1;
    localparam integer TRCD_CYCLES             = 1;
    localparam integer CAS_CYCLES              = 3;
    localparam integer READ_RECOVERY_CYCLES    = 2;
    localparam integer WRITE_RECOVERY_CYCLES   = 3;

    // Long enough that ordinary test traffic will not accidentally
    // trigger refresh. The dedicated refresh-deferral test injects
    // refresh_due explicitly.
    localparam integer REFRESH_INTERVAL_CYCLES = 1000;

    localparam [2:0] CMD_NOP          = 3'b111;
    localparam [2:0] CMD_ACTIVE       = 3'b011;
    localparam [2:0] CMD_READ         = 3'b101;
    localparam [2:0] CMD_WRITE        = 3'b100;
    localparam [2:0] CMD_AUTO_REFRESH = 3'b001;

    reg clk;
    reg reset;

    // ------------------------------------------------------------
    // Jupiter-side 32-bit transaction interface.
    // ------------------------------------------------------------

    reg         m_valid;
    reg         m_write;
    reg  [31:0] m_addr;
    reg  [31:0] m_wdata;
    reg   [3:0] m_wstrb;
    wire [31:0] m_rdata;
    wire        m_ready;

    reg  [15:0] sdram_sz;

    // ------------------------------------------------------------
    // Frontend -> controller halfword interface.
    // ------------------------------------------------------------

    wire        half_valid;
    wire        half_write;
    wire [25:0] half_addr;
    wire [15:0] half_wdata;
    wire  [1:0] half_wstrb;
    wire [15:0] half_rdata;
    wire        half_ready;

    // ------------------------------------------------------------
    // Physical SDRAM interface.
    // ------------------------------------------------------------

    wire        initialized;

    wire        SDRAM_CKE;
    wire [12:0] SDRAM_A;
    wire  [1:0] SDRAM_BA;
    wire [15:0] SDRAM_DQ;
    wire        SDRAM_DQML;
    wire        SDRAM_DQMH;
    wire        SDRAM_nCS;
    wire        SDRAM_nCAS;
    wire        SDRAM_nRAS;
    wire        SDRAM_nWE;

    wire        protocol_error;

    wire [2:0] command = {
        SDRAM_nRAS,
        SDRAM_nCAS,
        SDRAM_nWE
    };

    integer checks;
    integer failures;

    // ------------------------------------------------------------
    // DUT chain.
    // ------------------------------------------------------------

    jupiter_sdram_frontend dut_frontend (
        .clk        (clk),
        .reset      (reset),

        .m_valid    (m_valid),
        .m_write    (m_write),
        .m_addr     (m_addr),
        .m_wdata    (m_wdata),
        .m_wstrb    (m_wstrb),
        .m_rdata    (m_rdata),
        .m_ready    (m_ready),

        .sdram_sz   (sdram_sz),

        .half_valid (half_valid),
        .half_write (half_write),
        .half_addr  (half_addr),
        .half_wdata (half_wdata),
        .half_wstrb (half_wstrb),
        .half_rdata (half_rdata),
        .half_ready (half_ready)
    );

    jupiter_sdram_controller #(
        .POWERUP_CYCLES          (POWERUP_CYCLES),
        .TRP_CYCLES              (TRP_CYCLES),
        .TRFC_CYCLES             (TRFC_CYCLES),
        .TMRD_CYCLES             (TMRD_CYCLES),
        .TRCD_CYCLES             (TRCD_CYCLES),
        .CAS_CYCLES              (CAS_CYCLES),
        .READ_RECOVERY_CYCLES    (READ_RECOVERY_CYCLES),
        .WRITE_RECOVERY_CYCLES   (WRITE_RECOVERY_CYCLES),
        .REFRESH_INTERVAL_CYCLES (REFRESH_INTERVAL_CYCLES)
    ) dut_controller (
        .clk         (clk),
        .reset       (reset),

        .initialized (initialized),

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

    jupiter_sdram_model #(
        .CAS_CYCLES (CAS_CYCLES),
        .SLOTS      (64)
    ) dram (
        .clk            (clk),
        .reset          (reset),

        .SDRAM_CKE      (SDRAM_CKE),
        .SDRAM_A        (SDRAM_A),
        .SDRAM_BA       (SDRAM_BA),
        .SDRAM_DQ       (SDRAM_DQ),
        .SDRAM_DQML     (SDRAM_DQML),
        .SDRAM_DQMH     (SDRAM_DQMH),
        .SDRAM_nCS      (SDRAM_nCS),
        .SDRAM_nCAS     (SDRAM_nCAS),
        .SDRAM_nRAS     (SDRAM_nRAS),
        .SDRAM_nWE      (SDRAM_nWE),

        .protocol_error (protocol_error)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Test helpers.
    // ------------------------------------------------------------

    task automatic check;
        input condition;
        input [8*120-1:0] message;
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

    task automatic jupiter_write;
        input [31:0] addr;
        input [31:0] data;
        input  [3:0] wstrb;

        integer guard;
        begin
            @(negedge clk);

            m_valid = 1'b1;
            m_write = 1'b1;
            m_addr  = addr;
            m_wdata = data;
            m_wstrb = wstrb;

            guard = 0;

            while ((m_ready !== 1'b1) && (guard < 500)) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end

            check(
                m_ready == 1'b1,
                "Jupiter write completes before timeout"
            );

            if (m_ready == 1'b1) begin
                check(
                    m_rdata == 32'h00000000,
                    "Jupiter write completion returns deterministic zero"
                );
            end

            @(negedge clk);

            m_valid = 1'b0;
            m_write = 1'b0;
            m_addr  = 32'd0;
            m_wdata = 32'd0;
            m_wstrb = 4'd0;
        end
    endtask

    task automatic jupiter_read;
        input  [31:0] addr;
        output [31:0] data;

        integer guard;
        begin
            data = 32'hxxxxxxxx;

            @(negedge clk);

            m_valid = 1'b1;
            m_write = 1'b0;
            m_addr  = addr;
            m_wdata = 32'd0;
            m_wstrb = 4'd0;

            guard = 0;

            while ((m_ready !== 1'b1) && (guard < 500)) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end

            check(
                m_ready == 1'b1,
                "Jupiter read completes before timeout"
            );

            if (m_ready == 1'b1)
                data = m_rdata;

            @(negedge clk);

            m_valid = 1'b0;
            m_addr  = 32'd0;
        end
    endtask

    task automatic wait_for_command;
        input [2:0] expected_command;
        input       expected_cs;
        input integer max_cycles;
        input [8*120-1:0] description;

        integer i;
        reg found;
        begin
            found = 1'b0;

            for (i = 0; (i < max_cycles) && !found; i = i + 1) begin
                @(posedge clk);
                #1;

                if (command == expected_command) begin
                    found = 1'b1;

                    check(
                        SDRAM_nCS == expected_cs,
                        description
                    );
                end
            end

            if (!found)
                check(1'b0, description);
        end
    endtask

    task automatic observe_write_half;
        input [25:0] expected_h;
        input [15:0] expected_data;
        input  [1:0] expected_wstrb;

        integer guard;
        reg found;
        begin
            found = 1'b0;
            guard = 0;

            while (!found && guard < 100) begin
                @(posedge clk);
                #1;
                guard = guard + 1;

                if (command == CMD_ACTIVE) begin
                    found = 1'b1;

                    check(
                        SDRAM_nCS == expected_h[25],
                        "ACTIVE selects expected MiSTer SDRAM device"
                    );

                    check(
                        SDRAM_A == expected_h[16:4],
                        "ACTIVE carries expected row address"
                    );

                    check(
                        SDRAM_BA == expected_h[3:2],
                        "ACTIVE carries expected bank address"
                    );
                end
            end

            check(
                found,
                "expected ACTIVE command appears"
            );

            found = 1'b0;
            guard = 0;

            while (!found && guard < 100) begin
                @(posedge clk);
                #1;
                guard = guard + 1;

                if (command == CMD_WRITE) begin
                    found = 1'b1;

                    check(
                        SDRAM_nCS == expected_h[25],
                        "WRITE selects expected MiSTer SDRAM device"
                    );

                    check(
                        SDRAM_BA == expected_h[3:2],
                        "WRITE preserves expected bank address"
                    );

                    check(
                        SDRAM_A[9:0] ==
                            {expected_h[24:17], expected_h[1:0]},
                        "WRITE carries expected column address"
                    );

                    check(
                        SDRAM_A[10] == 1'b1,
                        "WRITE requests auto-precharge"
                    );

                    check(
                        SDRAM_DQ == expected_data,
                        "WRITE drives expected 16-bit data"
                    );

                    check(
                        {SDRAM_DQMH, SDRAM_DQML} ==
                            ~expected_wstrb,
                        "WRITE maps byte strobes to active-high masks"
                    );
                end
            end

            check(
                found,
                "expected WRITE command appears"
            );
        end
    endtask

    // ------------------------------------------------------------
    // Main regression.
    // ------------------------------------------------------------

    reg [31:0] read_value;

    localparam [31:0] MAP_ADDR = 32'h14A12340;

    localparam [25:0] MAP_H0 =
        (MAP_ADDR - SDRAM_BASE) >> 1;

    localparam [25:0] MAP_H1 =
        MAP_H0 + 26'd1;

    integer guard;
    integer refresh_before_second;

    initial begin
        clk      = 1'b0;
        reset    = 1'b1;

        m_valid  = 1'b0;
        m_write  = 1'b0;
        m_addr   = 32'd0;
        m_wdata  = 32'd0;
        m_wstrb  = 4'd0;

        // Valid 128 MiB MiSTer SDRAM report.
        sdram_sz = 16'h8003;

        checks   = 0;
        failures = 0;

        // ----------------------------------------------------
        // RESET / INITIALIZATION
        // ----------------------------------------------------

        repeat (3) @(posedge clk);

        #1;

        check(
            initialized == 1'b0,
            "physical SDRAM controller begins uninitialized"
        );

        @(negedge clk);
        reset = 1'b0;

        guard = 0;

        while ((initialized !== 1'b1) && (guard < 100)) begin
            @(posedge clk);
            #1;
            guard = guard + 1;
        end

        check(
            initialized == 1'b1,
            "physical SDRAM initialization completes"
        );

        check(
            protocol_error == 1'b0,
            "SDRAM model reports no initialization protocol error"
        );

        // ----------------------------------------------------
        // ADDRESS MAPPING + CHIP 1 WRITE
        //
        // MAP_ADDR is above the first 64 MiB of the Jupiter SDRAM
        // aperture, so H[25] must select the second MiSTer device.
        // Observe both physical halfword operations independently
        // of the model's storage lookup.
        // ----------------------------------------------------

        fork
            begin
                jupiter_write(
                    MAP_ADDR,
                    32'h89ABCDEF,
                    4'b1111
                );
            end

            begin
                observe_write_half(
                    MAP_H0,
                    16'hCDEF,
                    2'b11
                );

                observe_write_half(
                    MAP_H1,
                    16'h89AB,
                    2'b11
                );
            end
        join

        check(
            MAP_H0[25] == 1'b1,
            "mapping test genuinely exercises chip selection 1"
        );

        check(
            protocol_error == 1'b0,
            "chip 1 mapped write causes no SDRAM protocol error"
        );

        jupiter_read(
            MAP_ADDR,
            read_value
        );

        check(
            read_value == 32'h89ABCDEF,
            "chip 1 32-bit write/read round trip preserves data"
        );

        // ----------------------------------------------------
        // CHIP 0 FULL-WIDTH ROUND TRIP
        // ----------------------------------------------------

        jupiter_write(
            32'h10000100,
            32'hDEADBEEF,
            4'b1111
        );

        jupiter_read(
            32'h10000100,
            read_value
        );

        check(
            read_value == 32'hDEADBEEF,
            "chip 0 32-bit write/read round trip preserves data"
        );

        check(
            protocol_error == 1'b0,
            "chip 0 round trip causes no SDRAM protocol error"
        );

        // ----------------------------------------------------
        // BYTE MASK / WRITE STROBE TEST
        //
        // Initial bytes:
        //   11 22 33 44
        //
        // Partial data:
        //   AA BB CC DD
        //
        // wstrb 0101 replaces byte lanes 2 and 0 only:
        //   11 BB 33 DD
        // ----------------------------------------------------

        jupiter_write(
            32'h10000200,
            32'h11223344,
            4'b1111
        );

        jupiter_write(
            32'h10000200,
            32'hAABBCCDD,
            4'b0101
        );

        jupiter_read(
            32'h10000200,
            read_value
        );

        check(
            read_value == 32'h11BB33DD,
            "DQML/DQMH preserve masked byte lanes"
        );

        check(
            protocol_error == 1'b0,
            "partial write causes no SDRAM protocol error"
        );

        // ----------------------------------------------------
        // REFRESH DEFERRAL BETWEEN THE TWO HALFWORDS
        //
        // Inject refresh_due while the controller is acknowledging
        // the LOW halfword. The HIGH halfword must complete before
        // any AUTO REFRESH command is issued.
        // ----------------------------------------------------

        refresh_before_second = 0;

        fork
            begin
                jupiter_write(
                    32'h10000300,
                    32'hCAFEBABE,
                    4'b1111
                );
            end

            begin
                // First controller acknowledgment is the low half.
                wait (
                    (half_ready === 1'b1) &&
                    (m_ready === 1'b0)
                );

                #1;

                // Simulation-only injection of a pending refresh.
                dut_controller.refresh_due = 1'b1;

                // Consume the low-half acknowledgment.
                @(posedge clk);
                #1;

                guard = 0;

                while ((m_ready !== 1'b1) && (guard < 100)) begin
                    if (command == CMD_AUTO_REFRESH)
                        refresh_before_second =
                            refresh_before_second + 1;

                    @(posedge clk);
                    #1;

                    guard = guard + 1;
                end

                check(
                    m_ready == 1'b1,
                    "second halfword completes after refresh becomes due"
                );

                check(
                    refresh_before_second == 0,
                    "pending refresh does not split a 32-bit Jupiter transaction"
                );
            end
        join

        // The pending refresh must now run before subsequent traffic.
        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b0,
            20,
            "deferred refresh services chip selection 0 after transaction"
        );

        wait_for_command(
            CMD_AUTO_REFRESH,
            1'b1,
            20,
            "deferred refresh services chip selection 1 after transaction"
        );

        jupiter_read(
            32'h10000300,
            read_value
        );

        check(
            read_value == 32'hCAFEBABE,
            "transaction spanning refresh-due event retains correct data"
        );

        check(
            protocol_error == 1'b0,
            "complete integrated path reports no SDRAM protocol error"
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
