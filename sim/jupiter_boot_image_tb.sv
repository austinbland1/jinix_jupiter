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

    
    // M12E boot-image cartridge loader fixture (simulation only).
    reg ioctl_download;
    reg [15:0] ioctl_index;
    reg ioctl_wr;
    reg [26:0] ioctl_addr;
    reg [7:0] ioctl_dout;
    wire ioctl_wait;
    reg [7:0] m12e_fixture_cartridge [0:47];
    integer m12e_fixture_i;

    // M12E cartridge SDRAM physical simulation backing.
    wire m12e_sdram_cke;
    wire [12:0] m12e_sdram_a;
    wire [1:0] m12e_sdram_ba;
    wire [15:0] m12e_sdram_dq;
    wire m12e_sdram_dqml;
    wire m12e_sdram_dqmh;
    wire m12e_sdram_ncs;
    wire m12e_sdram_ncas;
    wire m12e_sdram_nras;
    wire m12e_sdram_nwe;
    wire m12e_sdram_model_protocol_error;  // jupiter_sdram_model.protocol_error observability

jupiter_cpu_subsystem dut
    (
        .clk      (clk),
        .reset    (reset),
        .sdram_sz (16'h8003),
        .SDRAM_CKE(m12e_sdram_cke),
        .SDRAM_A(m12e_sdram_a),
        .SDRAM_BA(m12e_sdram_ba),
        .SDRAM_DQ(m12e_sdram_dq),
        .SDRAM_DQML(m12e_sdram_dqml),
        .SDRAM_DQMH(m12e_sdram_dqmh),
        .SDRAM_nCS(m12e_sdram_ncs),
        .SDRAM_nCAS(m12e_sdram_ncas),
        .SDRAM_nRAS(m12e_sdram_nras),
        .SDRAM_nWE(m12e_sdram_nwe),
        .halted   (halted),
    
        .ioctl_download(ioctl_download),
        .ioctl_index(ioctl_index),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_wait(ioctl_wait)
);
    // Canonical physical SDRAM model for the M12E cartridge path.
    jupiter_sdram_model #(
        .CAS_CYCLES(3),
        .SLOTS(64)
    ) m12e_dram (
        .clk(clk),
        .reset(reset),
        .SDRAM_CKE(m12e_sdram_cke),
        .SDRAM_A(m12e_sdram_a),
        .SDRAM_BA(m12e_sdram_ba),
        .SDRAM_DQ(m12e_sdram_dq),
        .SDRAM_DQML(m12e_sdram_dqml),
        .SDRAM_DQMH(m12e_sdram_dqmh),
        .SDRAM_nCS(m12e_sdram_ncs),
        .SDRAM_nCAS(m12e_sdram_ncas),
        .SDRAM_nRAS(m12e_sdram_nras),
        .SDRAM_nWE(m12e_sdram_nwe),
        .protocol_error(m12e_sdram_model_protocol_error)
    );


    task automatic m12e_fixture_send_byte;
        input integer byte_addr;
        input [7:0] byte_data;
        begin
            while (ioctl_wait !== 1'b0)
                @(posedge clk);
            @(negedge clk);
            ioctl_addr = byte_addr;
            ioctl_dout = byte_data;
            ioctl_wr = 1'b1;
            @(negedge clk);
            ioctl_wr = 1'b0;
        end
    endtask

    initial begin
        ioctl_download = 1'b0;
        ioctl_index = 1;
        ioctl_wr = 1'b0;
        ioctl_addr = 0;
        ioctl_dout = 0;
        m12e_fixture_cartridge[0] = 8'h4A;
        m12e_fixture_cartridge[1] = 8'h55;
        m12e_fixture_cartridge[2] = 8'h50;
        m12e_fixture_cartridge[3] = 8'h31;
        m12e_fixture_cartridge[4] = 8'h01;
        m12e_fixture_cartridge[5] = 8'h00;
        m12e_fixture_cartridge[6] = 8'h00;
        m12e_fixture_cartridge[7] = 8'h00;
        m12e_fixture_cartridge[8] = 8'h30;
        m12e_fixture_cartridge[9] = 8'h00;
        m12e_fixture_cartridge[10] = 8'h00;
        m12e_fixture_cartridge[11] = 8'h00;
        m12e_fixture_cartridge[12] = 8'h20;
        m12e_fixture_cartridge[13] = 8'h00;
        m12e_fixture_cartridge[14] = 8'h00;
        m12e_fixture_cartridge[15] = 8'h00;
        m12e_fixture_cartridge[16] = 8'h2A;
        m12e_fixture_cartridge[17] = 8'h50;
        m12e_fixture_cartridge[18] = 8'h28;
        m12e_fixture_cartridge[19] = 8'h40;
        m12e_fixture_cartridge[20] = 8'h00;
        m12e_fixture_cartridge[21] = 8'h00;
        m12e_fixture_cartridge[22] = 8'h00;
        m12e_fixture_cartridge[23] = 8'h00;
        m12e_fixture_cartridge[24] = 8'h00;
        m12e_fixture_cartridge[25] = 8'h00;
        m12e_fixture_cartridge[26] = 8'h00;
        m12e_fixture_cartridge[27] = 8'h00;
        m12e_fixture_cartridge[28] = 8'h00;
        m12e_fixture_cartridge[29] = 8'h00;
        m12e_fixture_cartridge[30] = 8'h00;
        m12e_fixture_cartridge[31] = 8'h00;
        m12e_fixture_cartridge[32] = 8'h00;
        m12e_fixture_cartridge[33] = 8'h10;
        m12e_fixture_cartridge[34] = 8'h08;
        m12e_fixture_cartridge[35] = 8'h10;
        m12e_fixture_cartridge[36] = 8'h2A;
        m12e_fixture_cartridge[37] = 8'h00;
        m12e_fixture_cartridge[38] = 8'h10;
        m12e_fixture_cartridge[39] = 8'h10;
        m12e_fixture_cartridge[40] = 8'h00;
        m12e_fixture_cartridge[41] = 8'h40;
        m12e_fixture_cartridge[42] = 8'h10;
        m12e_fixture_cartridge[43] = 8'h21;
        m12e_fixture_cartridge[44] = 8'h00;
        m12e_fixture_cartridge[45] = 8'h00;
        m12e_fixture_cartridge[46] = 8'h00;
        m12e_fixture_cartridge[47] = 8'hFF;

        wait (reset === 1'b0);
        repeat (2) @(posedge clk);

        @(negedge clk);

        repeat (4) @(posedge clk);
    end


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
                dut.cpu_mem_addr == 32'h10000020)
                saw_app_entry_fetch <= 1'b1;

            if (dut.cpu_mem_write &&
                dut.cpu_mem_addr == 32'h00001000 &&
                dut.cpu_mem_wdata == 32'd42)
                saw_scratch_store <= 1'b1;
        end
    end

    // Compatibility storage for split-byte implementation RAM.
    reg [31:0] boot_image_words [0:1023];
    integer boot_image_index;

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
        $readmemh(
            image_path,
            boot_image_words
        );

        for (
            boot_image_index = 0;
            boot_image_index < 1024;
            boot_image_index = boot_image_index + 1
        ) begin
            dut.ram.memory_b0[boot_image_index] =
                boot_image_words[boot_image_index][7:0];

            dut.ram.memory_b1[boot_image_index] =
                boot_image_words[boot_image_index][15:8];

            dut.ram.memory_b2[boot_image_index] =
                boot_image_words[boot_image_index][23:16];

            dut.ram.memory_b3[boot_image_index] =
                boot_image_words[boot_image_index][31:24];
        end
        #1;
        check(({dut.ram.memory_b3[255], dut.ram.memory_b2[255], dut.ram.memory_b1[255], dut.ram.memory_b0[255]}) == 32'h00000000,
              "last BIOS-region padding word is zero");
        check(({dut.ram.memory_b3[256], dut.ram.memory_b2[256], dut.ram.memory_b1[256], dut.ram.memory_b0[256]}) == 32'h10081000,
              "application begins at 0x10000020");
        check(({dut.ram.memory_b3[257], dut.ram.memory_b2[257], dut.ram.memory_b1[257], dut.ram.memory_b0[257]}) == 32'h1010002A,
              "application immediate instruction matches assembler output");
        check(({dut.ram.memory_b3[258], dut.ram.memory_b2[258], dut.ram.memory_b1[258], dut.ram.memory_b0[258]}) == 32'h21104000,
              "application store instruction matches assembler output");
        check(({dut.ram.memory_b3[259], dut.ram.memory_b2[259], dut.ram.memory_b1[259], dut.ram.memory_b0[259]}) == 32'hFF000000,
              "application HALT is loaded at 0x1000002C");
        check(({dut.ram.memory_b3[1023], dut.ram.memory_b2[1023], dut.ram.memory_b1[1023], dut.ram.memory_b0[1023]}) == 32'h00000000,
              "final system-image word is zero-filled");

        repeat (3) @(posedge clk);
        #1;

        check(!halted,
              "CPU remains unhalted while reset is asserted");
        check(dut.cpu.pc == 32'h00000000,
              "reset establishes BIOS entry PC 0x00000000");

        @(negedge clk);
        ioctl_index = 1;
        ioctl_download = 1'b1;
        reset = 1'b0;

        for (m12e_fixture_i = 0; m12e_fixture_i < 48; m12e_fixture_i = m12e_fixture_i + 1)
            m12e_fixture_send_byte(m12e_fixture_i, m12e_fixture_cartridge[m12e_fixture_i]);

        while (ioctl_wait !== 1'b0)
            @(posedge clk);
        @(negedge clk);
        ioctl_wr = 1'b0;
        ioctl_download = 1'b0;

        while (!halted && cycles < 512) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check(halted,
              "BIOS/application program reaches HALT before timeout");
        check(saw_bios_fetch,
              "CPU fetches BIOS through normal internal-RAM path");
        check(saw_app_entry_fetch,
              "BIOS transfers execution to application entry 0x10000020");
        check(saw_scratch_store,
              "host-built application performs expected MMIO store");
        check(dut.scratch.scratch_reg == 32'd42,
              "application writes 42 to MMIO scratch register");
        check(dut.cpu.regs[1] == 32'h00001000,
              "application constructs MMIO scratch address");
        check(dut.cpu.regs[2] == 32'd42,
              "application executes host-assembled immediate instruction");
        check(dut.cpu.pc == 32'h1000002C,
              "HALT occurs at expected application PC 0x1000002C");
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
