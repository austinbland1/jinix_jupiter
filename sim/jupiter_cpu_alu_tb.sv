`timescale 1ns/1ps

module jupiter_cpu_alu_tb;

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

    localparam [31:0] ADDI_R1_R0_7 =
        {8'h10, 5'd1, 5'd0, 14'd7};

    localparam [31:0] ADDI_R2_R0_3 =
        {8'h10, 5'd2, 5'd0, 14'd3};

    localparam [31:0] ADD_R3_R1_R2 =
        {8'h01, 5'd3, 5'd1, 5'd2, 9'd0};

    localparam [31:0] SUB_R4_R1_R2 =
        {8'h02, 5'd4, 5'd1, 5'd2, 9'd0};

    localparam [31:0] AND_R5_R1_R2 =
        {8'h03, 5'd5, 5'd1, 5'd2, 9'd0};

    localparam [31:0] OR_R6_R1_R2 =
        {8'h04, 5'd6, 5'd1, 5'd2, 9'd0};

    localparam [31:0] XOR_R7_R1_R2 =
        {8'h05, 5'd7, 5'd1, 5'd2, 9'd0};

    localparam [31:0] SUB_R8_R0_R1 =
        {8'h02, 5'd8, 5'd0, 5'd1, 9'd0};

    localparam [31:0] ADD_R0_R1_R2 =
        {8'h01, 5'd0, 5'd1, 5'd2, 9'd0};

    localparam [31:0] HALT =
        32'hFF000000;

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

    task execute_instruction;
        input [31:0] expected_addr;
        input [31:0] instruction;
        begin
            check(mem_valid === 1'b1,
                  "instruction fetch is active");

            check(mem_addr === expected_addr,
                  "instruction fetch uses expected PC");

            @(negedge clk);
            mem_rdata = instruction;
            mem_ready = 1'b1;

            @(posedge clk);
            #1;

            check(mem_valid === 1'b0,
                  "fetch deasserts during decode");

            @(negedge clk);
            mem_ready = 1'b0;
            mem_rdata = 32'h00000000;

            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;
        #1;

        execute_instruction(32'h00, ADDI_R1_R0_7);
        check(dut.regs[1] === 32'd7,
              "setup ADDI writes r1 = 7");

        execute_instruction(32'h04, ADDI_R2_R0_3);
        check(dut.regs[2] === 32'd3,
              "setup ADDI writes r2 = 3");

        execute_instruction(32'h08, ADD_R3_R1_R2);
        check(dut.regs[3] === 32'd10,
              "ADD computes 7 + 3 = 10");

        execute_instruction(32'h0C, SUB_R4_R1_R2);
        check(dut.regs[4] === 32'd4,
              "SUB computes 7 - 3 = 4");

        execute_instruction(32'h10, AND_R5_R1_R2);
        check(dut.regs[5] === 32'd3,
              "AND computes 7 AND 3 = 3");

        execute_instruction(32'h14, OR_R6_R1_R2);
        check(dut.regs[6] === 32'd7,
              "OR computes 7 OR 3 = 7");

        execute_instruction(32'h18, XOR_R7_R1_R2);
        check(dut.regs[7] === 32'd4,
              "XOR computes 7 XOR 3 = 4");

        execute_instruction(32'h1C, SUB_R8_R0_R1);
        check(dut.regs[8] === 32'hFFFFFFF9,
              "SUB wraps modulo 2^32");

        execute_instruction(32'h20, ADD_R0_R1_R2);
        check(dut.regs[0] === 32'h00000000,
              "register-register write to r0 is discarded");

        execute_instruction(32'h24, HALT);

        check(halted === 1'b1,
              "HALT terminates ALU test program");

        check(dut.pc === 32'h00000024,
              "HALT leaves PC at halt instruction");

        check(mem_valid === 1'b0,
              "halted CPU issues no further fetch");

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
