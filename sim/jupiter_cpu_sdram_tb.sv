`timescale 1ns/1ps

module jupiter_cpu_sdram_tb;

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

    localparam [2:0] CMD_ACTIVE = 3'b011;
    localparam [2:0] CMD_READ   = 3'b101;
    localparam [2:0] CMD_WRITE  = 3'b100;

    integer checks;
    integer failures;
    integer cycles;

    integer cpu_sdram_store_count;
    integer cpu_sdram_load_count;

    integer physical_active_count;
    integer physical_write_count;
    integer physical_read_count;

    reg bad_sdram_selection;

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

            if (condition) begin
                $display("PASS: %0s", message);
            end else begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Observe CPU-visible completed SDRAM transactions.
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (!reset &&
            dut.cpu_mem_valid &&
            dut.cpu_mem_ready &&
            dut.cpu_mem_addr == 32'h10000000) begin

            if (!dut.sdram_valid ||
                dut.ram_valid ||
                dut.mmio_valid)
                bad_sdram_selection <= 1'b1;

            if (dut.cpu_mem_write)
                cpu_sdram_store_count <=
                    cpu_sdram_store_count + 1;
            else
                cpu_sdram_load_count <=
                    cpu_sdram_load_count + 1;
        end
    end

    // ------------------------------------------------------------
    // Observe actual physical SDRAM data commands.
    //
    // One logical 32-bit Jupiter access becomes two 16-bit SDRAM
    // accesses, so the CPU store should produce two physical WRITE
    // commands and the CPU load should produce two physical READ
    // commands.
    // ------------------------------------------------------------

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

        cpu_sdram_store_count = 0;
        cpu_sdram_load_count  = 0;

        physical_active_count = 0;
        physical_write_count  = 0;
        physical_read_count   = 0;

        bad_sdram_selection = 1'b0;

        /*
         * Deterministic Milestone 4 CPU -> SDRAM program:
         *
         * 00: ADDI r1, r0, 4096
         *
         *     Double r1 sixteen times:
         *     0x00001000 << 16 = 0x10000000
         *
         * 44: ADDI r2, r0, 42
         * 48: STW  r2, 0(r1)       SDRAM[0x10000000] = 42
         * 4C: LDW  r3, 0(r1)       r3 = 42
         * 50: HALT
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
            !halted,
            "CPU begins external-SDRAM program from reset state"
        );

        check(
            !dut.sdram_initialized,
            "SDRAM controller begins uninitialized"
        );

        @(negedge clk);
        reset = 1'b0;

        while (!halted && cycles < 10000) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(
            halted,
            "CPU reaches HALT before timeout"
        );

        check(
            dut.cpu.pc == 32'h00000050,
            "HALT occurs at expected final PC 0x50"
        );

        check(
            dut.sdram_initialized,
            "SDRAM initialization completes before program finishes"
        );

        check(
            dut.cpu.regs[1] == 32'h10000000,
            "CPU constructs external SDRAM base address"
        );

        check(
            dut.cpu.regs[2] == 32'd42,
            "CPU store source register contains expected value"
        );

        check(
            dut.cpu.regs[3] == 32'd42,
            "CPU loads external SDRAM value back into r3"
        );

        check(
            cpu_sdram_store_count == 1,
            "exactly one CPU store completes in external SDRAM"
        );

        check(
            cpu_sdram_load_count == 1,
            "exactly one CPU load completes in external SDRAM"
        );

        check(
            !bad_sdram_selection,
            "CPU external-memory accesses select only SDRAM target"
        );

        check(
            physical_write_count == 2,
            "32-bit CPU store produces two physical 16-bit WRITEs"
        );

        check(
            physical_read_count == 2,
            "32-bit CPU load produces two physical 16-bit READs"
        );

        check(
            physical_active_count == 4,
            "store and load together produce four ACTIVE commands"
        );

        check(
            protocol_error == 1'b0,
            "behavioral SDRAM reports no protocol error"
        );

        check(
            !dut.cpu_mem_valid,
            "halted CPU issues no further memory transaction"
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
            $display(
                "PROGRAM_CYCLES: %0d",
                cycles
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
