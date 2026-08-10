`timescale 1ns/1ps

module jupiter_boot_image_tb;

    reg  clk;
    reg  reset;
    wire halted;

    integer checks;
    integer failures;
    integer cycles;

    reg saw_bios_fetch;
    reg saw_app_entry_fetch;
    reg saw_scratch_store;

    reg [8*512-1:0] image_path;

    jupiter_cpu_subsystem dut
    (
        .clk      (clk),
        .reset    (reset),
        .sdram_sz (16'h0000),
        .halted   (halted)
    );

    always #5 clk = ~clk;

    task check;
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
        if (!reset && dut.cpu_mem_valid && dut.cpu_mem_ready) begin
            if (!dut.cpu_mem_write &&
                dut.cpu_mem_addr == 32'h00000000)
                saw_bios_fetch <= 1'b1;

            if (!dut.cpu_mem_write &&
                dut.cpu_mem_addr == 32'h00000400)
                saw_app_entry_fetch <= 1'b1;

            if (dut.cpu_mem_write &&
                dut.cpu_mem_addr == 32'h00001000 &&
                dut.cpu_mem_wdata == 32'd42)
                saw_scratch_store <= 1'b1;
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;

        checks = 0;
        failures = 0;
        cycles = 0;

        saw_bios_fetch = 1'b0;
        saw_app_entry_fetch = 1'b0;
        saw_scratch_store = 1'b0;

        if (!$value$plusargs("IMAGE=%s", image_path))
            $fatal(1, "IMAGE plusarg is required");

        // Selected M9 simulation-loading mechanism:
        // load the host-generated image into the existing internal RAM
        // before releasing CPU reset. Synthesizable RAM RTL is unchanged.
        $readmemh(image_path, dut.ram.memory);
        #1;

        check(dut.ram.memory[0] == 32'h320000FF,
              "generated BIOS J instruction is loaded at reset vector");
        check(dut.ram.memory[1] == 32'h00000000,
              "unused BIOS word is zero-filled");
        check(dut.ram.memory[255] == 32'h00000000,
              "last BIOS-region padding word is zero");
        check(dut.ram.memory[256] == 32'h10081000,
              "application begins at 0x00000400");
        check(dut.ram.memory[257] == 32'h1010002A,
              "application immediate instruction matches assembler output");
        check(dut.ram.memory[258] == 32'h21104000,
              "application store instruction matches assembler output");
        check(dut.ram.memory[259] == 32'hFF000000,
              "application HALT is loaded at 0x0000040C");
        check(dut.ram.memory[1023] == 32'h00000000,
              "final system-image word is zero-filled");

        repeat (3) @(posedge clk);
        #1;

        check(!halted,
              "CPU remains unhalted while reset is asserted");
        check(dut.cpu.pc == 32'h00000000,
              "reset establishes BIOS entry PC 0x00000000");

        @(negedge clk);
        reset = 1'b0;

        while (!halted && cycles < 100) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(halted,
              "BIOS/application program reaches HALT before timeout");
        check(saw_bios_fetch,
              "CPU fetches BIOS through normal internal-RAM path");
        check(saw_app_entry_fetch,
              "BIOS transfers execution to application entry 0x00000400");
        check(saw_scratch_store,
              "host-built application performs expected MMIO store");
        check(dut.scratch.scratch_reg == 32'd42,
              "application writes 42 to MMIO scratch register");
        check(dut.cpu.regs[1] == 32'h00001000,
              "application constructs MMIO scratch address");
        check(dut.cpu.regs[2] == 32'd42,
              "application executes host-assembled immediate instruction");
        check(dut.cpu.pc == 32'h0000040C,
              "HALT occurs at expected application PC 0x0000040C");
        check(!dut.cpu_mem_valid,
              "halted CPU issues no further memory transaction");
        check(dut.cpu.regs[0] == 32'h00000000,
              "r0 remains hardwired to zero");

        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
            $display("PROGRAM_CYCLES: %0d", cycles);
            $display("==============================");
            $finish;
        end else begin
            $display("RESULT: FAIL  (%0d failures / %0d checks)",
                     failures, checks);
            $display("==============================");
            $fatal(1);
        end
    end

endmodule
