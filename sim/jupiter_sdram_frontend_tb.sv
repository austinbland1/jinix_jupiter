`timescale 1ns/1ps

module jupiter_sdram_frontend_tb;

    localparam [31:0] SDRAM_BASE = 32'h10000000;

    reg         clk;
    reg         reset;

    reg         m_valid;
    reg         m_write;
    reg  [31:0] m_addr;
    reg  [31:0] m_wdata;
    reg  [3:0]  m_wstrb;
    wire [31:0] m_rdata;
    wire        m_ready;

    reg  [15:0] sdram_sz;

    wire        half_valid;
    wire        half_write;
    wire [25:0] half_addr;
    wire [15:0] half_wdata;
    wire [1:0]  half_wstrb;
    reg  [15:0] half_rdata;
    reg         half_ready;

    integer checks;
    integer failures;

    jupiter_sdram_frontend dut (
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

    always #5 clk = ~clk;

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

    task automatic unavailable_read;
        input [31:0] addr;
        input [15:0] size;
        input [8*100-1:0] description;
        begin
            @(negedge clk);

            sdram_sz  = size;
            m_valid   = 1'b1;
            m_write   = 1'b0;
            m_addr    = addr;
            m_wdata   = 32'd0;
            m_wstrb   = 4'b0000;
            half_ready = 1'b0;

            #1;

            check(m_ready == 1'b1, description);
            check(m_rdata == 32'h00000000,
                  "unavailable read returns deterministic zero");
            check(half_valid == 1'b0,
                  "unavailable read does not reach controller side");

            @(posedge clk);
            #1;
            m_valid = 1'b0;
        end
    endtask

    task automatic accepted_boundary_read;
        input [31:0] addr;
        input [15:0] size;
        input [25:0] expected_half_addr;
        input [8*100-1:0] description;
        begin
            @(negedge clk);

            sdram_sz   = size;
            m_valid    = 1'b1;
            m_write    = 1'b0;
            m_addr     = addr;
            m_wdata    = 32'd0;
            m_wstrb    = 4'b0000;
            half_rdata = 16'h1111;
            half_ready = 1'b1;

            @(posedge clk);
            #1;

            check(half_valid == 1'b1, description);
            check(half_write == 1'b0,
                  "boundary read low half is a read");
            check(half_addr == expected_half_addr,
                  "boundary read low-half address is correct");

            @(posedge clk);
            #1;

            check(half_valid == 1'b1,
                  "boundary read advances to high half");
            check(half_addr == expected_half_addr + 26'd1,
                  "boundary read high-half address is correct");

            half_rdata = 16'h2222;
            #1;

            check(m_ready == 1'b1,
                  "boundary read completes on high half");
            check(m_rdata == 32'h22221111,
                  "boundary read assembles two 16-bit halves");

            @(posedge clk);
            #1;

            m_valid    = 1'b0;
            half_ready = 1'b0;
        end
    endtask

    initial begin
        clk         = 1'b0;
        reset       = 1'b1;

        m_valid     = 1'b0;
        m_write     = 1'b0;
        m_addr      = 32'd0;
        m_wdata     = 32'd0;
        m_wstrb     = 4'd0;

        sdram_sz    = 16'd0;

        half_rdata  = 16'd0;
        half_ready  = 1'b0;

        checks      = 0;
        failures    = 0;

        repeat (3) @(posedge clk);

        #1;
        check(m_ready == 1'b0,
              "frontend does not acknowledge while reset request path is idle");
        check(half_valid == 1'b0,
              "controller-side request is idle during reset");

        @(negedge clk);
        reset = 1'b0;

        // ----------------------------------------------------
        // Availability / validity behavior.
        // ----------------------------------------------------

        unavailable_read(
            SDRAM_BASE,
            16'h0001,
            "size code without valid flag is unavailable"
        );

        unavailable_read(
            SDRAM_BASE,
            16'h8000,
            "valid flag with no SDRAM size is unavailable"
        );

        unavailable_read(
            32'h0FFFFFFC,
            16'h8003,
            "address below SDRAM aperture is unavailable"
        );

        unavailable_read(
            SDRAM_BASE + 32'd2,
            16'h8003,
            "misaligned 32-bit SDRAM access is unavailable"
        );

        // ----------------------------------------------------
        // 32-bit write -> two 16-bit writes.
        // Exercise stalls on both halves.
        // ----------------------------------------------------

        @(negedge clk);

        sdram_sz   = 16'h8001;
        m_valid    = 1'b1;
        m_write    = 1'b1;
        m_addr     = SDRAM_BASE + 32'h20;
        m_wdata    = 32'hA1B2C3D4;
        m_wstrb    = 4'b1101;
        half_ready = 1'b0;

        @(posedge clk);
        #1;

        check(half_valid == 1'b1,
              "write produces low-half controller request");
        check(half_write == 1'b1,
              "low-half controller request is a write");
        check(half_addr == 26'h000010,
              "write low-half address converts byte address to halfword address");
        check(half_wdata == 16'hC3D4,
              "write low half carries bits 15:0");
        check(half_wstrb == 2'b01,
              "write low half maps wstrb[1:0]");
        check(m_ready == 1'b0,
              "Jupiter write remains stalled while low half is stalled");

        repeat (2) begin
            @(posedge clk);
            #1;

            check(half_valid == 1'b1,
                  "low-half request remains valid during wait state");
            check(half_addr == 26'h000010,
                  "low-half address remains stable during wait state");
            check(half_wdata == 16'hC3D4,
                  "low-half data remains stable during wait state");
            check(half_wstrb == 2'b01,
                  "low-half strobes remain stable during wait state");
        end

        half_ready = 1'b1;

        @(posedge clk);
        #1;

        half_ready = 1'b0;
        #1;

        check(half_valid == 1'b1,
              "write advances to high-half controller request");
        check(half_write == 1'b1,
              "high-half controller request is a write");
        check(half_addr == 26'h000011,
              "write high-half address increments by one halfword");
        check(half_wdata == 16'hA1B2,
              "write high half carries bits 31:16");
        check(half_wstrb == 2'b11,
              "write high half maps wstrb[3:2]");
        check(m_ready == 1'b0,
              "Jupiter write remains stalled while high half is stalled");

        @(posedge clk);
        #1;

        check(half_addr == 26'h000011,
              "high-half address remains stable during wait state");
        check(half_wdata == 16'hA1B2,
              "high-half data remains stable during wait state");
        check(half_wstrb == 2'b11,
              "high-half strobes remain stable during wait state");

        half_ready = 1'b1;
        #1;

        check(m_ready == 1'b1,
              "32-bit write completes when high-half transfer is ready");
        check(m_rdata == 32'h00000000,
              "write completion presents deterministic zero read data");

        @(posedge clk);
        #1;

        m_valid    = 1'b0;
        half_ready = 1'b0;

        // ----------------------------------------------------
        // 32-bit read -> two 16-bit reads.
        // Verify wait-state stability and read assembly.
        // ----------------------------------------------------

        @(negedge clk);

        sdram_sz    = 16'h8001;
        m_valid     = 1'b1;
        m_write     = 1'b0;
        m_addr      = SDRAM_BASE + 32'h24;
        m_wdata     = 32'd0;
        m_wstrb     = 4'b0000;
        half_rdata  = 16'h0000;
        half_ready  = 1'b0;

        @(posedge clk);
        #1;

        check(half_valid == 1'b1,
              "read produces low-half controller request");
        check(half_write == 1'b0,
              "low-half read request has write deasserted");
        check(half_addr == 26'h000012,
              "read low-half address is correct");
        check(half_wstrb == 2'b00,
              "read low-half write strobes are zero");
        check(m_ready == 1'b0,
              "Jupiter read waits for low-half completion");

        repeat (2) begin
            @(posedge clk);
            #1;

            check(half_valid == 1'b1,
                  "read low-half request remains valid while stalled");
            check(half_addr == 26'h000012,
                  "read low-half address remains stable while stalled");
        end

        half_rdata = 16'hBEEF;
        half_ready = 1'b1;

        @(posedge clk);
        #1;

        half_ready = 1'b0;

        check(half_valid == 1'b1,
              "read advances to high-half request");
        check(half_addr == 26'h000013,
              "read high-half address increments by one halfword");
        check(half_write == 1'b0,
              "high-half read request has write deasserted");

        half_rdata = 16'hCAFE;
        half_ready = 1'b1;
        #1;

        check(m_ready == 1'b1,
              "32-bit read completes when high half is ready");
        check(m_rdata == 32'hCAFEBEEF,
              "32-bit read combines high and low 16-bit results");

        @(posedge clk);
        #1;

        m_valid    = 1'b0;
        half_ready = 1'b0;

        // ----------------------------------------------------
        // Installed-capacity boundaries.
        // ----------------------------------------------------

        accepted_boundary_read(
            32'h11FFFFFC,
            16'h8001,
            26'h0FFFFFE,
            "last aligned 32-bit word of 32 MiB SDRAM is available"
        );

        unavailable_read(
            32'h12000000,
            16'h8001,
            "first address beyond 32 MiB SDRAM is unavailable"
        );

        accepted_boundary_read(
            32'h13FFFFFC,
            16'h8002,
            26'h1FFFFFE,
            "last aligned 32-bit word of 64 MiB SDRAM is available"
        );

        unavailable_read(
            32'h14000000,
            16'h8002,
            "first address beyond 64 MiB SDRAM is unavailable"
        );

        accepted_boundary_read(
            32'h17FFFFFC,
            16'h8003,
            26'h3FFFFFE,
            "last aligned 32-bit word of 128 MiB SDRAM is available"
        );

        unavailable_read(
            32'h18000000,
            16'h8003,
            "former M3 reservation above 128 MiB is unavailable"
        );

        // ----------------------------------------------------
        // Final result.
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
