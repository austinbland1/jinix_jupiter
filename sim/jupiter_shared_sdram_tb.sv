`timescale 1ns/1ps

module jupiter_shared_sdram_tb;

    localparam [31:0] CPU_ADDR = 32'h10000000;
    localparam [31:0] GPU_ADDR = 32'h10000004;
    localparam [31:0] GPU_DATA = 32'hA1B2C3D4;

    localparam [2:0] CMD_ACTIVE = 3'b011;
    localparam [2:0] CMD_READ   = 3'b101;
    localparam [2:0] CMD_WRITE  = 3'b100;

    reg clk;
    reg reset;

    wire halted;

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

    wire protocol_error;

    wire [2:0] sdram_command = {
        SDRAM_nRAS,
        SDRAM_nCAS,
        SDRAM_nWE
    };

    integer checks;
    integer failures;
    integer cycles;
    integer wait_cycles;

    integer physical_active_count;
    integer physical_write_count;
    integer physical_read_count;

    reg [31:0] gpu_readback;

    jupiter_cpu_subsystem dut
    (
        .clk        (clk),
        .reset      (reset),

        // Valid MiSTer report: 128 MiB SDRAM installed.
        .sdram_sz   (16'h8003),

        .SDRAM_CKE  (SDRAM_CKE),
        .SDRAM_A    (SDRAM_A),
        .SDRAM_BA   (SDRAM_BA),
        .SDRAM_DQ   (SDRAM_DQ),
        .SDRAM_DQML (SDRAM_DQML),
        .SDRAM_DQMH (SDRAM_DQMH),
        .SDRAM_nCS  (SDRAM_nCS),
        .SDRAM_nCAS (SDRAM_nCAS),
        .SDRAM_nRAS (SDRAM_nRAS),
        .SDRAM_nWE  (SDRAM_nWE),

        .halted     (halted)
    );

    jupiter_sdram_model #(
        .CAS_CYCLES (3),
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

    function [31:0] enc_r;
        input [7:0] opcode;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            enc_r = {
                opcode,
                rd,
                rs1,
                rs2,
                9'd0
            };
        end
    endfunction

    function [31:0] enc_i;
        input [7:0]  opcode;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [13:0] imm14;
        begin
            enc_i = {
                opcode,
                rd,
                rs1,
                imm14
            };
        end
    endfunction

    function [31:0] enc_s;
        input [7:0]  opcode;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [13:0] imm14;
        begin
            enc_s = {
                opcode,
                rs2,
                rs1,
                imm14
            };
        end
    endfunction

    function [31:0] enc_n;
        input [7:0] opcode;
        begin
            enc_n = {
                opcode,
                24'd0
            };
        end
    endfunction

    task automatic check;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;

            if (condition)
                $display("PASS: %0s", message);
            else begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    always @(posedge clk) begin
        if (!reset) begin
            case (sdram_command)
                CMD_ACTIVE:
                    physical_active_count <=
                        physical_active_count + 1;

                CMD_WRITE:
                    physical_write_count <=
                        physical_write_count + 1;

                CMD_READ:
                    physical_read_count <=
                        physical_read_count + 1;

                default: begin
                end
            endcase
        end
    end

    integer i;

    initial begin
        clk   = 1'b0;
        reset = 1'b1;

        checks   = 0;
        failures = 0;
        cycles   = 0;
        wait_cycles = 0;

        physical_active_count = 0;
        physical_write_count  = 0;
        physical_read_count   = 0;

        gpu_readback = 32'h00000000;

        /*
         * Real CPU program:
         *
         * 00: ADDI r1, r0, 4096
         *     Double r1 sixteen times to form 0x10000000.
         * 44: ADDI r2, r0, 42
         * 48: STW  r2, 0(r1)
         * 4C: LDW  r3, 0(r1)
         * 50: HALT
         *
         * When the CPU store reaches the SDRAM arbiter, the testbench
         * asserts the otherwise-idle GPU SDRAM-master interface. This is
         * simulation-only path injection; no renderer traffic is invented
         * in the synthesizable GPU.
         */

        dut.ram.memory_b0[0] = (enc_i(8'h10, 5'd1, 5'd0, 14'd4096));
        dut.ram.memory_b1[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4096)) >> 8);
        dut.ram.memory_b2[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4096)) >> 16);
        dut.ram.memory_b3[0] = ((enc_i(8'h10, 5'd1, 5'd0, 14'd4096)) >> 24);

        for (i = 1; i <= 16; i = i + 1) begin
            dut.ram.memory_b0[i] = (enc_r(
                    8'h01,
                    5'd1,
                    5'd1,
                    5'd1
                ));
            dut.ram.memory_b1[i] = ((enc_r(
                    8'h01,
                    5'd1,
                    5'd1,
                    5'd1
                )) >> 8);
            dut.ram.memory_b2[i] = ((enc_r(
                    8'h01,
                    5'd1,
                    5'd1,
                    5'd1
                )) >> 16);
            dut.ram.memory_b3[i] = ((enc_r(
                    8'h01,
                    5'd1,
                    5'd1,
                    5'd1
                )) >> 24);
        end

        dut.ram.memory_b0[17] = (enc_i(8'h10, 5'd2, 5'd0, 14'd42));
        dut.ram.memory_b1[17] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 8);
        dut.ram.memory_b2[17] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 16);
        dut.ram.memory_b3[17] = ((enc_i(8'h10, 5'd2, 5'd0, 14'd42)) >> 24);

        dut.ram.memory_b0[18] = (enc_s(8'h21, 5'd2, 5'd1, 14'd0));
        dut.ram.memory_b1[18] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd0)) >> 8);
        dut.ram.memory_b2[18] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd0)) >> 16);
        dut.ram.memory_b3[18] = ((enc_s(8'h21, 5'd2, 5'd1, 14'd0)) >> 24);

        dut.ram.memory_b0[19] = (enc_i(8'h20, 5'd3, 5'd1, 14'd0));
        dut.ram.memory_b1[19] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd0)) >> 8);
        dut.ram.memory_b2[19] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd0)) >> 16);
        dut.ram.memory_b3[19] = ((enc_i(8'h20, 5'd3, 5'd1, 14'd0)) >> 24);

        dut.ram.memory_b0[20] = (enc_n(8'hFF));
        dut.ram.memory_b1[20] = ((enc_n(8'hFF)) >> 8);
        dut.ram.memory_b2[20] = ((enc_n(8'hFF)) >> 16);
        dut.ram.memory_b3[20] = ((enc_n(8'hFF)) >> 24);

        repeat (3) @(posedge clk);
        #1;

        check(
            !dut.gpu_sdram_valid &&
            !dut.gpu_sdram_write &&
            dut.gpu_sdram_addr == 32'h00000000 &&
            dut.gpu_sdram_wdata == 32'h00000000 &&
            dut.gpu_sdram_wstrb == 4'b0000,
            "functional GPU SDRAM master is deterministically idle before M5D"
        );

        check(
            !dut.shared_sdram_valid,
            "shared post-arbiter SDRAM interface is idle during reset"
        );

        @(negedge clk);
        reset = 1'b0;

        // Wait for the real CPU store request at the interconnect side of
        // the arbiter. This occurs before the frontend completes it.
        while (!(dut.sdram_valid &&
                 dut.sdram_write &&
                 dut.sdram_addr == CPU_ADDR) &&
               cycles < 1000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end

        check(
            dut.sdram_valid &&
            dut.sdram_write &&
            dut.sdram_addr == CPU_ADDR,
            "real CPU store reaches CPU side of integrated SDRAM arbiter"
        );

        // Simulation-only injection onto the real but currently idle GPU
        // master interface. Hold the valid request through ready exactly as
        // a future renderer must.
        force dut.gpu_sdram_valid = 1'b1;
        force dut.gpu_sdram_write = 1'b1;
        force dut.gpu_sdram_addr  = GPU_ADDR;
        force dut.gpu_sdram_wdata = GPU_DATA;
        force dut.gpu_sdram_wstrb = 4'b1111;
        #1;

        check(
            dut.shared_sdram_valid &&
            dut.shared_sdram_write &&
            dut.shared_sdram_addr == CPU_ADDR,
            "first integrated CPU/GPU contention selects CPU after reset"
        );

        check(
            !dut.gpu_sdram_ready,
            "waiting GPU requester receives no CPU transaction completion"
        );

        // Let the contested CPU grant become held.
        @(posedge clk);
        #1;

        check(
            dut.sdram_arbiter.grant_state == 2'd1 &&
            dut.sdram_arbiter.grant_contested,
            "integrated arbiter records held contested CPU grant"
        );

        // The CPU transaction traverses frontend/controller first. Once it
        // completes, the waiting GPU request must become the shared request.
        wait_cycles = 0;

        while (!(dut.shared_sdram_valid &&
                 dut.shared_sdram_write &&
                 dut.shared_sdram_addr == GPU_ADDR) &&
               wait_cycles < 12000) begin
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end

        check(
            dut.shared_sdram_valid &&
            dut.shared_sdram_write &&
            dut.shared_sdram_addr == GPU_ADDR,
            "waiting GPU write reaches shared frontend after CPU transaction"
        );

        check(
            dut.shared_sdram_wdata == GPU_DATA &&
            dut.shared_sdram_wstrb == 4'b1111,
            "GPU write data and strobes survive integrated arbitration"
        );

        // Wait for GPU write completion while keeping the request stable.
        wait_cycles = 0;

        while (!dut.gpu_sdram_ready &&
               wait_cycles < 1000) begin
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end

        check(
            dut.gpu_sdram_ready,
            "GPU write completes through shared frontend/controller path"
        );

        @(posedge clk);
        #1;

        @(negedge clk);
        release dut.gpu_sdram_valid;
        release dut.gpu_sdram_write;
        release dut.gpu_sdram_addr;
        release dut.gpu_sdram_wdata;
        release dut.gpu_sdram_wstrb;
        #1;

        check(
            !dut.gpu_sdram_valid,
            "GPU master returns to synthesizable idle behavior after injection"
        );

        // The real CPU must still complete its following load correctly,
        // proving that the GPU write to the adjacent word did not corrupt it.
        while (!halted && cycles < 20000) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(
            halted,
            "CPU reaches HALT after contended shared-SDRAM traffic"
        );

        check(
            dut.cpu.regs[3] == 32'd42,
            "CPU reads its original SDRAM word correctly after GPU write"
        );

        // Read the GPU-written word back through the same integrated path.
        @(negedge clk);

        force dut.gpu_sdram_valid = 1'b1;
        force dut.gpu_sdram_write = 1'b0;
        force dut.gpu_sdram_addr  = GPU_ADDR;
        force dut.gpu_sdram_wdata = 32'h00000000;
        force dut.gpu_sdram_wstrb = 4'b0000;
        #1;

        check(
            dut.shared_sdram_valid &&
            !dut.shared_sdram_write &&
            dut.shared_sdram_addr == GPU_ADDR,
            "GPU read reaches shared frontend through integrated arbiter"
        );

        wait_cycles = 0;

        while (!dut.gpu_sdram_ready &&
               wait_cycles < 1000) begin
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end

        gpu_readback = dut.gpu_sdram_rdata;

        check(
            dut.gpu_sdram_ready,
            "GPU read completes through shared frontend/controller path"
        );

        check(
            gpu_readback == GPU_DATA,
            "GPU SDRAM write/read round trip preserves 32-bit data"
        );

        @(posedge clk);
        #1;

        @(negedge clk);
        release dut.gpu_sdram_valid;
        release dut.gpu_sdram_write;
        release dut.gpu_sdram_addr;
        release dut.gpu_sdram_wdata;
        release dut.gpu_sdram_wstrb;
        #1;

        check(
            !dut.gpu_sdram_valid &&
            !dut.shared_sdram_valid,
            "shared path returns to idle after CPU and GPU traffic"
        );

        $display(
            "BL8_ASSERT jupiter_shared_sdram_tb physical_write_count=%0d EXPECTED=4",
            physical_write_count
        );

        check(
            physical_write_count == 4,
            "BL8 physical physical_write_count matches calibrated expectation"
        );

        $display(
            "BL8_ASSERT jupiter_shared_sdram_tb physical_read_count=%0d EXPECTED=1",
            physical_read_count
        );

        check(
            physical_read_count == 1,
            "BL8 physical physical_read_count matches calibrated expectation"
        );

        $display(
            "BL8_ASSERT jupiter_shared_sdram_tb physical_active_count=%0d EXPECTED=5",
            physical_active_count
        );

        check(
            physical_active_count == 5,
            "BL8 physical physical_active_count matches calibrated expectation"
        );

        check(
            protocol_error == 1'b0,
            "behavioral SDRAM reports no protocol error during shared traffic"
        );

        check(
            dut.cpu.regs[0] == 32'h00000000,
            "r0 remains hardwired to zero"
        );

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display(
                "RESULT: PASS  (%0d checks)",
                checks
            );
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
