`timescale 1ns/1ps

module jupiter_cpu_controller_mmio_tb;

    reg clk;
    reg reset;

    reg [31:0] controller_0_state;
    reg [31:0] controller_1_state;
    reg [31:0] controller_2_state;
    reg [31:0] controller_3_state;
    reg [31:0] controller_4_state;
    reg [31:0] controller_5_state;

    wire halted;

    integer checks;
    integer failures;
    integer cycles;

    integer controller_store_count;
    integer controller_load_count;

    reg bad_controller_selection;


    jupiter_cpu_subsystem dut
    (
        .clk      (clk),
        .reset    (reset),

        .sdram_sz (16'h0000),

        .controller_0_state(controller_0_state),
        .controller_1_state(controller_1_state),
        .controller_2_state(controller_2_state),
        .controller_3_state(controller_3_state),
        .controller_4_state(controller_4_state),
        .controller_5_state(controller_5_state),

        .halted   (halted)
    );


    always #5 clk = ~clk;


    function [31:0] enc_i;
        input [7:0] opcode;
        input [4:0] rd;
        input [4:0] rs1;
        input [13:0] imm14;
        begin
            enc_i = {opcode, rd, rs1, imm14};
        end
    endfunction


    function [31:0] enc_s;
        input [7:0] opcode;
        input [4:0] rs2;
        input [4:0] rs1;
        input [13:0] imm14;
        begin
            enc_s = {opcode, rs2, rs1, imm14};
        end
    endfunction


    function [31:0] enc_n;
        input [7:0] opcode;
        begin
            enc_n = {opcode, 24'h000000};
        end
    endfunction


    task automatic check;
        input condition;
        input [8*128-1:0] message;
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

        if (
            !reset &&
            dut.cpu_mem_valid &&
            dut.cpu_mem_ready &&
            dut.cpu_mem_addr >= 32'h00001400 &&
            dut.cpu_mem_addr <= 32'h000014FF
        ) begin

            if (!(
                dut.controller_valid &&
                !dut.ram_valid &&
                !dut.mmio_valid &&
                !dut.gpu_valid &&
                !dut.dma_valid &&
                !dut.audio_valid &&
                !dut.sdram_valid
            ))
                bad_controller_selection <= 1'b1;


            if (dut.cpu_mem_write)
                controller_store_count <=
                    controller_store_count + 1;
            else
                controller_load_count <=
                    controller_load_count + 1;
        end
    end


    initial begin

        clk = 0;
        reset = 1;

        checks = 0;
        failures = 0;
        cycles = 0;

        controller_store_count = 0;
        controller_load_count = 0;
        bad_controller_selection = 0;

        controller_0_state = 32'h80000001;
        controller_1_state = 32'h00010002;
        controller_2_state = 32'hA5A55A5A;
        controller_3_state = 32'hFFFFFFFF;
        controller_4_state = 32'h01234567;
        controller_5_state = 32'h89ABCDEF;


        /*
         * 00 ADDI r1,r0,5120    r1 = 0x1400
         * 04 LDW  r2,0(r1)
         * 08 LDW  r3,4(r1)
         * 0C LDW  r4,8(r1)
         * 10 LDW  r5,12(r1)
         * 14 LDW  r6,16(r1)
         * 18 LDW  r7,20(r1)
         * 1C LDW  r8,24(r1)     reserved = 0
         * 20 ADDI r9,r0,123
         * 24 STW  r9,0(r1)      ignored
         * 28 LDW  r10,0(r1)
         * 2C HALT
         */

        dut.ram.memory[0] =
            enc_i(8'h10, 5'd1, 5'd0, 14'd5120);

        dut.ram.memory[1] =
            enc_i(8'h20, 5'd2, 5'd1, 14'd0);

        dut.ram.memory[2] =
            enc_i(8'h20, 5'd3, 5'd1, 14'd4);

        dut.ram.memory[3] =
            enc_i(8'h20, 5'd4, 5'd1, 14'd8);

        dut.ram.memory[4] =
            enc_i(8'h20, 5'd5, 5'd1, 14'd12);

        dut.ram.memory[5] =
            enc_i(8'h20, 5'd6, 5'd1, 14'd16);

        dut.ram.memory[6] =
            enc_i(8'h20, 5'd7, 5'd1, 14'd20);

        dut.ram.memory[7] =
            enc_i(8'h20, 5'd8, 5'd1, 14'd24);

        dut.ram.memory[8] =
            enc_i(8'h10, 5'd9, 5'd0, 14'd123);

        dut.ram.memory[9] =
            enc_s(8'h21, 5'd9, 5'd1, 14'd0);

        dut.ram.memory[10] =
            enc_i(8'h20, 5'd10, 5'd1, 14'd0);

        dut.ram.memory[11] =
            enc_n(8'hFF);


        repeat (3)
            @(posedge clk);

        #1;


        check(
            !halted,
            "CPU begins controller integration program"
        );

        check(
            dut.scratch.scratch_reg == 0 &&
            dut.gpu.tilemap_base_reg == 0 &&
            dut.dma.src_base_reg == 0 &&
            dut.audio.sample_addr_reg == 0,
            "unrelated MMIO begins unchanged"
        );


        @(negedge clk);
        reset = 0;


        while (
            !halted &&
            cycles < 500
        ) begin

            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end


        check(
            halted,
            "CPU reaches HALT before timeout"
        );

        check(
            dut.cpu.pc == 32'h0000002C,
            "HALT occurs at expected PC"
        );

        check(
            dut.cpu.regs[1] == 32'h00001400,
            "CPU constructs controller MMIO base"
        );

        check(
            dut.cpu.regs[2] == controller_0_state,
            "CPU reads controller zero"
        );

        check(
            dut.cpu.regs[3] == controller_1_state,
            "CPU reads controller one"
        );

        check(
            dut.cpu.regs[4] == controller_2_state,
            "CPU reads controller two"
        );

        check(
            dut.cpu.regs[5] == controller_3_state,
            "CPU reads controller three"
        );

        check(
            dut.cpu.regs[6] == controller_4_state,
            "CPU reads controller four"
        );

        check(
            dut.cpu.regs[7] == controller_5_state,
            "CPU reads controller five"
        );

        check(
            dut.cpu.regs[8] == 32'h00000000,
            "reserved controller offset returns zero"
        );

        check(
            dut.cpu.regs[10] == controller_0_state,
            "controller write does not change later read"
        );

        check(
            controller_store_count == 1,
            "exactly one controller store completes"
        );

        check(
            controller_load_count == 8,
            "exactly eight controller loads complete"
        );

        check(
            !bad_controller_selection,
            "controller MMIO selects only controller target"
        );

        check(
            dut.scratch.scratch_reg == 0 &&
            dut.gpu.tilemap_base_reg == 0 &&
            dut.dma.src_base_reg == 0 &&
            dut.audio.sample_addr_reg == 0,
            "controller accesses preserve unrelated MMIO state"
        );

        check(
            !dut.cpu_mem_valid,
            "halted CPU issues no transaction"
        );

        check(
            dut.cpu.regs[0] == 0,
            "r0 remains hardwired zero"
        );


        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("PROGRAM_CYCLES: %0d", cycles);
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
