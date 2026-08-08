`timescale 1ns/1ps

module jupiter_cpu_memory_tb;

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

    // Program:
    //
    // 0x00 ADDI r1, r0, 68
    // 0x04 ADDI r2, r0, 42
    // 0x08 STW  r2, -4(r1)   -> address 64
    // 0x0C LDW  r3, -4(r1)   -> address 64
    // 0x10 LDW  r0, -4(r1)   -> transaction occurs, writeback discarded
    // 0x14 HALT

    localparam [31:0] ADDI_R1_R0_68 =
        {8'h10, 5'd1, 5'd0, 14'd68};

    localparam [31:0] ADDI_R2_R0_42 =
        {8'h10, 5'd2, 5'd0, 14'd42};

    localparam [31:0] STW_R2_R1_M4 =
        {8'h21, 5'd2, 5'd1, 14'h3FFC};

    localparam [31:0] LDW_R3_R1_M4 =
        {8'h20, 5'd3, 5'd1, 14'h3FFC};

    localparam [31:0] LDW_R0_R1_M4 =
        {8'h20, 5'd0, 5'd1, 14'h3FFC};

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

    task fetch_and_decode;
        input [31:0] expected_pc;
        input [31:0] instruction;
        begin
            check(mem_valid === 1'b1,
                  "instruction fetch is active");

            check(mem_write === 1'b0 &&
                  mem_addr === expected_pc &&
                  mem_wstrb === 4'b0000,
                  "instruction fetch has expected read request");

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

        // Establish base address r1 = 68.
        fetch_and_decode(32'h00000000, ADDI_R1_R0_68);

        check(dut.regs[1] === 32'd68,
              "setup ADDI writes base register r1 = 68");

        // Establish store value r2 = 42.
        fetch_and_decode(32'h00000004, ADDI_R2_R0_42);

        check(dut.regs[2] === 32'd42,
              "setup ADDI writes store value r2 = 42");

        // STW r2, -4(r1) -> address 64.
        fetch_and_decode(32'h00000008, STW_R2_R1_M4);

        check(mem_valid === 1'b1,
              "STW begins a data-memory transaction");

        check(mem_write === 1'b1,
              "STW asserts write");

        check(mem_addr === 32'd64,
              "STW sign-extends offset and computes address 64");

        check(mem_wdata === 32'd42,
              "STW presents source register value");

        check(mem_wstrb === 4'b1111,
              "STW enables all four byte lanes");

        // Stall the store. All request information must remain stable.
        repeat (3) begin
            @(posedge clk);
            #1;

            check(mem_valid === 1'b1 &&
                  mem_write === 1'b1 &&
                  mem_addr  === 32'd64 &&
                  mem_wdata === 32'd42 &&
                  mem_wstrb === 4'b1111,
                  "STW request remains stable while mem_ready is low");
        end

        // Complete store.
        @(negedge clk);
        mem_ready = 1'b1;

        @(posedge clk);
        #1;

        check(dut.pc === 32'h0000000C,
              "STW advances PC after transaction completion");

        check(mem_valid === 1'b1 &&
              mem_write === 1'b0 &&
              mem_addr === 32'h0000000C,
              "CPU resumes instruction fetch after STW");

        @(negedge clk);
        mem_ready = 1'b0;

        // LDW r3, -4(r1) -> address 64.
        fetch_and_decode(32'h0000000C, LDW_R3_R1_M4);

        check(mem_valid === 1'b1,
              "LDW begins a data-memory transaction");

        check(mem_write === 1'b0,
              "LDW is a read");

        check(mem_addr === 32'd64,
              "LDW sign-extends offset and computes address 64");

        check(mem_wstrb === 4'b0000,
              "LDW has no write strobes");

        // Stall the load.
        repeat (2) begin
            @(posedge clk);
            #1;

            check(mem_valid === 1'b1 &&
                  mem_write === 1'b0 &&
                  mem_addr === 32'd64 &&
                  mem_wstrb === 4'b0000,
                  "LDW request remains stable while mem_ready is low");
        end

        // Complete load with recognizable data.
        @(negedge clk);
        mem_rdata = 32'hDEADBEEF;
        mem_ready = 1'b1;

        @(posedge clk);
        #1;

        check(dut.regs[3] === 32'hDEADBEEF,
              "LDW writes returned data to destination register");

        check(dut.pc === 32'h00000010,
              "LDW advances PC after transaction completion");

        @(negedge clk);
        mem_ready = 1'b0;
        mem_rdata = 32'h00000000;

        // LDW targeting r0 must still perform the read transaction.
        fetch_and_decode(32'h00000010, LDW_R0_R1_M4);

        check(mem_valid === 1'b1 &&
              mem_write === 1'b0 &&
              mem_addr === 32'd64,
              "LDW targeting r0 still performs memory read");

        @(negedge clk);
        mem_rdata = 32'hCAFEBABE;
        mem_ready = 1'b1;

        @(posedge clk);
        #1;

        check(dut.regs[0] === 32'h00000000,
              "LDW result targeting r0 is discarded");

        check(dut.pc === 32'h00000014,
              "r0-targeting LDW still advances PC");

        @(negedge clk);
        mem_ready = 1'b0;
        mem_rdata = 32'h00000000;

        // HALT.
        fetch_and_decode(32'h00000014, HALT);

        check(halted === 1'b1,
              "HALT terminates memory test program");

        check(mem_valid === 1'b0,
              "halted CPU issues no further memory transaction");

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
