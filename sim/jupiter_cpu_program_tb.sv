`timescale 1ns/1ps

module jupiter_cpu_program_tb;

    reg clk   = 1'b0;
    reg reset = 1'b1;

    wire        mem_valid;
    wire        mem_write;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;
    wire        mem_ready;
    wire        halted;

    reg [31:0] memory [0:255];
    reg [1:0] ready_phase = 2'd0;

    integer checks = 0;
    integer failures = 0;
    integer cycles = 0;
    integer store_count = 0;
    integer data_read_count = 0;
    integer i;

    /*
     * Deterministic Milestone 2 program
     *
     * 00: ADDI r1,  r0, 256
     * 04: ADDI r2,  r0, 7
     * 08: ADDI r3,  r0, 5
     * 0C: ADD  r4,  r2, r3       -> 12
     * 10: SUB  r5,  r2, r3       -> 2
     * 14: AND  r6,  r2, r3       -> 5
     * 18: OR   r7,  r2, r3       -> 7
     * 1C: XOR  r8,  r2, r3       -> 2
     * 20: STW  r4,  0(r1)        -> memory[0x100] = 12
     * 24: LDW  r9,  0(r1)        -> r9 = 12
     * 28: BEQ  r9,  r4, +1       -> 30, taken
     * 2C: ADDI r10, r0, 99       -> skipped
     * 30: BNE  r5,  r8, +1       -> not taken
     * 34: ADDI r10, r0, 1
     * 38: ADDI r11, r0, 3
     * 3C: SUB  r11, r11, r10
     * 40: BNE  r11, r0, -2       -> loop to 3C until zero
     * 44: J    +1                -> 4C
     * 48: ADDI r12, r0, 99       -> skipped
     * 4C: ADDI r12, r0, 42
     * 50: NOP
     * 54: HALT
     */

    always #5 clk = ~clk;

    assign mem_ready =
        !reset &&
        mem_valid &&
        (ready_phase == 2'd2);

    assign mem_rdata = memory[mem_addr[9:2]];

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

    /*
     * Deterministic two-cycle memory wait.
     *
     * Because the CPU must hold transaction information stable until
     * valid && ready, this also exercises the unified memory handshake
     * throughout an actual multi-instruction program.
     */
    always @(posedge clk) begin
        if (reset) begin
            ready_phase <= 2'd0;
        end else begin
            ready_phase <= ready_phase + 2'd1;

            if (mem_valid && mem_ready) begin
                if (mem_write) begin
                    memory[mem_addr[9:2]] <= mem_wdata;
                    store_count <= store_count + 1;
                end else if (mem_addr == 32'h00000100) begin
                    data_read_count <= data_read_count + 1;
                end
            end
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'h00000000;

        // ADDI r1, r0, 256
        memory[0] =
            {8'h10, 5'd1, 5'd0, 14'd256};

        // ADDI r2, r0, 7
        memory[1] =
            {8'h10, 5'd2, 5'd0, 14'd7};

        // ADDI r3, r0, 5
        memory[2] =
            {8'h10, 5'd3, 5'd0, 14'd5};

        // ADD r4, r2, r3
        memory[3] =
            {8'h01, 5'd4, 5'd2, 5'd3, 9'd0};

        // SUB r5, r2, r3
        memory[4] =
            {8'h02, 5'd5, 5'd2, 5'd3, 9'd0};

        // AND r6, r2, r3
        memory[5] =
            {8'h03, 5'd6, 5'd2, 5'd3, 9'd0};

        // OR r7, r2, r3
        memory[6] =
            {8'h04, 5'd7, 5'd2, 5'd3, 9'd0};

        // XOR r8, r2, r3
        memory[7] =
            {8'h05, 5'd8, 5'd2, 5'd3, 9'd0};

        // STW r4, 0(r1)
        memory[8] =
            {8'h21, 5'd4, 5'd1, 14'd0};

        // LDW r9, 0(r1)
        memory[9] =
            {8'h20, 5'd9, 5'd1, 14'd0};

        // BEQ r9, r4, +1
        memory[10] =
            {8'h30, 5'd9, 5'd4, 14'd1};

        // Skipped if BEQ works.
        memory[11] =
            {8'h10, 5'd10, 5'd0, 14'd99};

        // BNE r5, r8, +1 -- values equal, so not taken.
        memory[12] =
            {8'h31, 5'd5, 5'd8, 14'd1};

        // ADDI r10, r0, 1
        memory[13] =
            {8'h10, 5'd10, 5'd0, 14'd1};

        // ADDI r11, r0, 3
        memory[14] =
            {8'h10, 5'd11, 5'd0, 14'd3};

        // SUB r11, r11, r10
        memory[15] =
            {8'h02, 5'd11, 5'd11, 5'd10, 9'd0};

        // BNE r11, r0, -2
        memory[16] =
            {8'h31, 5'd11, 5'd0, 14'h3FFE};

        // J +1
        memory[17] =
            {8'h32, 24'd1};

        // Skipped if J works.
        memory[18] =
            {8'h10, 5'd12, 5'd0, 14'd99};

        // ADDI r12, r0, 42
        memory[19] =
            {8'h10, 5'd12, 5'd0, 14'd42};

        // NOP
        memory[20] =
            32'h00000000;

        // HALT
        memory[21] =
            32'hFF000000;

        // Hold synchronous reset.
        repeat (3) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;

        // Run until HALT or timeout.
        while (!halted && cycles < 2000) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(halted === 1'b1,
              "deterministic program reaches HALT before timeout");

        check(dut.pc === 32'h00000054,
              "HALT occurs at expected final PC 0x54");

        check(dut.regs[1] === 32'h00000100,
              "r1 contains data-memory base address");

        check(dut.regs[2] === 32'd7,
              "r2 contains first ALU operand");

        check(dut.regs[3] === 32'd5,
              "r3 contains second ALU operand");

        check(dut.regs[4] === 32'd12,
              "ADD result is correct");

        check(dut.regs[5] === 32'd2,
              "SUB result is correct");

        check(dut.regs[6] === 32'd5,
              "AND result is correct");

        check(dut.regs[7] === 32'd7,
              "OR result is correct");

        check(dut.regs[8] === 32'd2,
              "XOR result is correct");

        check(dut.regs[9] === 32'd12,
              "LDW returns value previously written by STW");

        check(memory[64] === 32'd12,
              "STW writes expected value to address 0x100");

        check(store_count === 1,
              "program performs exactly one data store");

        check(data_read_count === 1,
              "program performs exactly one data load");

        check(dut.regs[10] === 32'd1,
              "taken and not-taken forward branches follow expected paths");

        check(dut.regs[11] === 32'd0,
              "backward BNE loop terminates at zero");

        check(dut.regs[12] === 32'd42,
              "J skips the unwanted instruction");

        check(dut.regs[0] === 32'h00000000,
              "r0 remains hardwired to zero");

        check(mem_valid === 1'b0,
              "halted CPU issues no memory transaction");

        if (failures == 0) begin
            $display("");
            $display("==============================");
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("PROGRAM_CYCLES: %0d", cycles);
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
