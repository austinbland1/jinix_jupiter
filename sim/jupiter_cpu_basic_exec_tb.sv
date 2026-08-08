`timescale 1ns/1ps

module jupiter_cpu_basic_exec_tb;

    reg clk   = 1'b0;
    reg reset = 1'b1;

    wire        mem_valid;
    wire        mem_write;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        halted;

    reg [31:0] mem_rdata = 32'h00000000;
    reg        mem_ready = 1'b0;

    integer checks = 0;
    integer failures = 0;

    // Program used by this focused execution test:
    //
    // 0x00: NOP
    // 0x04: ADDI r1, r0, 5
    // 0x08: ADDI r2, r1, -2
    // 0x0C: ADDI r0, r1, 7   (write must be discarded)
    // 0x10: HALT
    localparam [31:0] INSN_NOP            = 32'h00000000;
    localparam [31:0] INSN_ADDI_R1_R0_5   = 32'h10080005;
    localparam [31:0] INSN_ADDI_R2_R1_M2  = 32'h10107FFE;
    localparam [31:0] INSN_ADDI_R0_R1_7   = 32'h10004007;
    localparam [31:0] INSN_HALT           = 32'hFF000000;

    always #5 clk = ~clk;

    jupiter_cpu dut
    (
        .clk       (clk),
        .reset     (reset),

        .mem_valid (mem_valid),
        .mem_write (mem_write),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),

        .mem_rdata (mem_rdata),
        .mem_ready (mem_ready),

        .halted    (halted)
    );

    task check;
        input condition;
        input [8*96-1:0] message;
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

    task deliver_instruction;
        input [31:0] expected_addr;
        input [31:0] instruction;
        begin
            check(mem_valid === 1'b1,
                  "instruction fetch is active");

            check(mem_addr === expected_addr,
                  "instruction fetch address matches expected PC");

            // Complete the current fetch.
            @(negedge clk);
            mem_rdata = instruction;
            mem_ready = 1'b1;

            @(posedge clk);
            #1;

            check(mem_valid === 1'b0,
                  "fetch deasserts while captured instruction is decoded");

            // Remove the memory response and allow decode/execute.
            @(negedge clk);
            mem_ready = 1'b0;
            mem_rdata = 32'h00000000;

            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        // Synchronous active-high reset.
        repeat (3) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;
        #1;

        // NOP
        deliver_instruction(32'h00000000, INSN_NOP);

        check(dut.pc === 32'h00000004,
              "NOP advances PC by four");

        // ADDI r1, r0, 5
        deliver_instruction(32'h00000004, INSN_ADDI_R1_R0_5);

        check(dut.regs[1] === 32'h00000005,
              "ADDI writes positive immediate result to r1");

        check(dut.pc === 32'h00000008,
              "ADDI advances PC by four");

        // ADDI r2, r1, -2
        deliver_instruction(32'h00000008, INSN_ADDI_R2_R1_M2);

        check(dut.regs[2] === 32'h00000003,
              "ADDI sign-extends negative imm14 correctly");

        check(dut.pc === 32'h0000000C,
              "second ADDI advances PC by four");

        // Attempt to write r0. Architecturally this must be discarded.
        deliver_instruction(32'h0000000C, INSN_ADDI_R0_R1_7);

        check(dut.regs[0] === 32'h00000000,
              "ADDI write targeting r0 is discarded");

        check(dut.pc === 32'h00000010,
              "r0-targeting ADDI still advances PC");

        // HALT
        deliver_instruction(32'h00000010, INSN_HALT);

        check(halted === 1'b1,
              "HALT places CPU into halted state");

        check(mem_valid === 1'b0,
              "HALT prevents further instruction fetches");

        // Prove that halt persists.
        repeat (3) @(posedge clk);
        #1;

        check(halted === 1'b1 && mem_valid === 1'b0,
              "CPU remains halted without new memory transactions");

        if (failures == 0) begin
            $display("");
            $display("==============================");
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("==============================");
            $finish(0);
        end else begin
            $display("");
            $display("==============================");
            $display("RESULT: FAIL  (%0d failures)", failures);
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
