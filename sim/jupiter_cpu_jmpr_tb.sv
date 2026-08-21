`timescale 1ns/1ps

module jupiter_cpu_jmpr_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;

    wire        mem_valid;
    wire        mem_write;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;
    wire        mem_ready;
    wire        halted;

    reg [31:0] memory [0:63];

    integer failures = 0;
    integer cycles = 0;
    integer i;

    localparam [31:0] NOP  = 32'h00000000;
    localparam [31:0] HALT = 32'hFF000000;

    function [31:0] encode_i;
        input [7:0] opcode;
        input [4:0] rd;
        input [4:0] rs1;
        input integer imm14;
        begin
            encode_i = {opcode, rd, rs1, imm14[13:0]};
        end
    endfunction

    assign mem_ready = mem_valid;

    always @* begin
        if (mem_addr[31:8] == 24'h000000)
            mem_rdata = memory[mem_addr[7:2]];
        else
            mem_rdata = NOP;
    end

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

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (condition)
                $display("PASS: %0s", message);
            else begin
                $display("FAIL: %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task clear_memory;
        begin
            for (i = 0; i < 64; i = i + 1)
                memory[i] = NOP;
        end
    endtask

    task pulse_reset;
        begin
            reset = 1'b1;
            repeat (3) @(posedge clk);
            reset = 1'b0;
        end
    endtask

    task run_until_halt;
        input integer max_cycles;
        begin
            cycles = 0;
            while (!halted && (cycles < max_cycles)) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (mem_valid)
                    check(mem_addr[1:0] == 2'b00,
                          "all instruction fetches remain word aligned");
            end
            check(halted, "program reaches HALT before timeout");
        end
    endtask

    initial begin
        clear_memory();

        memory[0] = encode_i(8'h10, 5'd5,  5'd0,  32);
        memory[1] = encode_i(8'h10, 5'd31, 5'd0,  85);
        memory[2] = encode_i(8'h33, 5'd31, 5'd5,   0);
        memory[3] = HALT;
        memory[8] = encode_i(8'h10, 5'd6,  5'd0, 291);
        memory[9] = HALT;

        pulse_reset();
        run_until_halt(80);

        check(dut.regs[5] == 32'h00000020,
              "JMPR preserves its base register");
        check(dut.regs[31] == 32'h00000055,
              "JMPR does not write nonzero bits in reserved rd field");
        check(dut.regs[6] == 32'h00000123,
              "JMPR reaches rs1 plus positive imm14 target");
        check(dut.pc == 32'h00000024,
              "positive JMPR program halts at expected target sequence");

        clear_memory();
        memory[0] = encode_i(8'h10, 5'd5, 5'd0,  32);
        memory[1] = encode_i(8'h33, 5'd0, 5'd5, -16);
        memory[2] = HALT;
        memory[4] = encode_i(8'h10, 5'd7, 5'd0, 801);
        memory[5] = HALT;

        pulse_reset();
        run_until_halt(80);

        check(dut.regs[7] == 32'h00000321,
              "JMPR sign-extends negative imm14 in target calculation");
        check(dut.pc == 32'h00000014,
              "negative JMPR program halts at expected target sequence");

        if (failures != 0) begin
            $display("");
            $display("==============================");
            $display("RESULT: FAIL  (%0d failures)", failures);
            $display("==============================");
            $fatal(1);
        end

        $display("");
        $display("==============================");
        $display("RESULT: PASS  (JMPR CPU semantics)");
        $display("==============================");
        $finish;
    end

endmodule
