`timescale 1ns/1ps

module jupiter_cpu_control_tb;

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

    // Static control-flow test program:
    //
    // 00: ADDI r1, r0, 5
    // 04: ADDI r2, r0, 5
    // 08: ADDI r3, r0, 7
    // 0C: BEQ  r1, r2, +2   -> 18   taken forward
    // 10: BNE  r1, r2, +5   -> 14   not taken
    // 14: BNE  r1, r3, +2   -> 20   taken forward
    // 18: BEQ  r1, r2, -3   -> 10   taken backward
    // 20: BEQ  r1, r3, +3   -> 24   not taken
    // 24: J    +2           -> 30   forward jump
    // 2C: HALT
    // 30: J    -2           -> 2C   backward jump

    localparam [31:0] ADDI_R1_R0_5 =
        {8'h10, 5'd1, 5'd0, 14'd5};

    localparam [31:0] ADDI_R2_R0_5 =
        {8'h10, 5'd2, 5'd0, 14'd5};

    localparam [31:0] ADDI_R3_R0_7 =
        {8'h10, 5'd3, 5'd0, 14'd7};

    localparam [31:0] BEQ_R1_R2_P2 =
        {8'h30, 5'd1, 5'd2, 14'd2};

    localparam [31:0] BNE_R1_R2_P5 =
        {8'h31, 5'd1, 5'd2, 14'd5};

    localparam [31:0] BNE_R1_R3_P2 =
        {8'h31, 5'd1, 5'd3, 14'd2};

    // -3 in signed 14-bit two's complement.
    localparam [31:0] BEQ_R1_R2_M3 =
        {8'h30, 5'd1, 5'd2, 14'h3FFD};

    localparam [31:0] BEQ_R1_R3_P3 =
        {8'h30, 5'd1, 5'd3, 14'd3};

    localparam [31:0] J_P2 =
        {8'h32, 24'd2};

    // -2 in signed 24-bit two's complement.
    localparam [31:0] J_M2 =
        {8'h32, 24'hFFFFFE};

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

    task fetch_and_execute;
        input [31:0] expected_pc;
        input [31:0] instruction;
        begin
            check(mem_valid === 1'b1,
                  "instruction fetch is active");

            check(mem_write === 1'b0 &&
                  mem_addr === expected_pc &&
                  mem_wstrb === 4'b0000,
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

        fetch_and_execute(32'h00000000, ADDI_R1_R0_5);
        check(dut.regs[1] === 32'd5,
              "setup writes r1 = 5");

        fetch_and_execute(32'h00000004, ADDI_R2_R0_5);
        check(dut.regs[2] === 32'd5,
              "setup writes r2 = 5");

        fetch_and_execute(32'h00000008, ADDI_R3_R0_7);
        check(dut.regs[3] === 32'd7,
              "setup writes r3 = 7");

        // Taken forward BEQ: 0C + 4 + (2 * 4) = 18.
        fetch_and_execute(32'h0000000C, BEQ_R1_R2_P2);

        check(dut.pc === 32'h00000018,
              "taken BEQ computes forward PC-relative target");

        // Taken backward BEQ: 18 + 4 + (-3 * 4) = 10.
        fetch_and_execute(32'h00000018, BEQ_R1_R2_M3);

        check(dut.pc === 32'h00000010,
              "taken BEQ sign-extends backward word offset");

        // Not-taken BNE ignores its encoded branch target.
        fetch_and_execute(32'h00000010, BNE_R1_R2_P5);

        check(dut.pc === 32'h00000014,
              "not-taken BNE advances to PC plus four");

        // Taken BNE: 14 + 4 + (2 * 4) = 20.
        fetch_and_execute(32'h00000014, BNE_R1_R3_P2);

        check(dut.pc === 32'h00000020,
              "taken BNE computes forward PC-relative target");

        // Not-taken BEQ.
        fetch_and_execute(32'h00000020, BEQ_R1_R3_P3);

        check(dut.pc === 32'h00000024,
              "not-taken BEQ advances to PC plus four");

        // Forward J: 24 + 4 + (2 * 4) = 30.
        fetch_and_execute(32'h00000024, J_P2);

        check(dut.pc === 32'h00000030,
              "J computes forward PC-relative target");

        // Backward J: 30 + 4 + (-2 * 4) = 2C.
        fetch_and_execute(32'h00000030, J_M2);

        check(dut.pc === 32'h0000002C,
              "J sign-extends backward word offset");

        check(dut.regs[1] === 32'd5 &&
              dut.regs[2] === 32'd5 &&
              dut.regs[3] === 32'd7,
              "control-flow instructions preserve source registers");

        fetch_and_execute(32'h0000002C, HALT);

        check(halted === 1'b1,
              "HALT terminates control-flow test program");

        check(dut.pc === 32'h0000002C,
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
