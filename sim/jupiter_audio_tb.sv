`timescale 1ns/1ps

module jupiter_audio_tb;

    localparam [31:0] REG_SAMPLE_ADDR  = 32'h00001300;
    localparam [31:0] REG_SAMPLE_DATA  = 32'h00001304;
    localparam [31:0] REG_OUTPUT_L     = 32'h00001308;
    localparam [31:0] REG_OUTPUT_R     = 32'h0000130C;
    localparam [31:0] REG_SAMPLE_COUNT = 32'h00001310;
    localparam [31:0] REG_RESERVED     = 32'h00001314;

    localparam [31:0] V0_CONTROL  = 32'h00001320;
    localparam [31:0] V0_STATUS   = 32'h00001324;
    localparam [31:0] V0_BASE     = 32'h00001328;
    localparam [31:0] V0_LENGTH   = 32'h0000132C;
    localparam [31:0] V0_VOLUME_L = 32'h00001330;
    localparam [31:0] V0_VOLUME_R = 32'h00001334;
    localparam [31:0] V0_POSITION = 32'h00001338;
    localparam [31:0] V0_RESERVED = 32'h0000133C;

    localparam [31:0] V1_BASE = 32'h00001348;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg        valid = 1'b0;
    reg        write = 1'b0;
    reg [31:0] addr  = 32'h00000000;
    reg [31:0] wdata = 32'h00000000;
    reg  [3:0] wstrb = 4'b0000;

    wire [31:0] rdata;
    wire        ready;

    integer checks = 0;
    integer failures = 0;

    reg [31:0] read_value;


    jupiter_audio dut
    (
        .clk   (clk),
        .reset (reset),

        .valid (valid),
        .write (write),
        .addr  (addr),
        .wdata (wdata),
        .wstrb (wstrb),

        .rdata (rdata),
        .ready (ready)
    );


    always #5 clk = ~clk;


    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin

            checks = checks + 1;

            if (condition)
                $display(
                    "PASS: %0s",
                    message
                );
            else begin

                failures = failures + 1;

                $display(
                    "FAIL: %0s",
                    message
                );

            end
        end
    endtask


    task automatic mmio_write;
        input [31:0] write_addr;
        input [31:0] write_data;
        input  [3:0] write_strobes;
        begin

            @(negedge clk);

            valid = 1'b1;
            write = 1'b1;
            addr = write_addr;
            wdata = write_data;
            wstrb = write_strobes;

            #1;

            check(
                ready == 1'b1,
                "audio MMIO write completes without wait state"
            );

            @(posedge clk);
            #1;

            @(negedge clk);

            valid = 1'b0;
            write = 1'b0;
            addr = 32'h00000000;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

        end
    endtask


    task automatic mmio_read;
        input  [31:0] read_addr;
        output [31:0] read_data;
        begin

            @(negedge clk);

            valid = 1'b1;
            write = 1'b0;
            addr = read_addr;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;

            check(
                ready == 1'b1,
                "audio MMIO read completes without wait state"
            );

            read_data = rdata;

            @(negedge clk);

            valid = 1'b0;
            addr = 32'h00000000;

        end
    endtask


    initial begin

        check(
            ready == 1'b0,
            "idle audio MMIO target does not assert ready"
        );


        repeat (3)
            @(posedge clk);

        #1;


        check(
            dut.sample_addr_reg == 12'h000,
            "SAMPLE_ADDR resets to zero"
        );


        check(
            dut.output_l_reg == 16'sh0000 &&
            dut.output_r_reg == 16'sh0000,
            "audio outputs reset to zero"
        );


        check(
            dut.sample_count_reg == 32'h00000000,
            "SAMPLE_COUNT resets to zero"
        );


        check(
            !dut.voice_active[0] &&
            !dut.voice_done[0],
            "voice zero status resets inactive and not done"
        );


        check(
            dut.voice_base_reg[0] == 12'h000 &&
            dut.voice_length_reg[0] == 13'h0000,
            "voice zero base and length reset to zero"
        );


        check(
            dut.voice_volume_l_reg[0] == 8'h00 &&
            dut.voice_volume_r_reg[0] == 8'h00,
            "voice zero volumes reset to zero"
        );


        check(
            dut.voice_position[0] == 13'h0000,
            "voice zero position resets to zero"
        );


        @(negedge clk);

        reset = 1'b0;


        mmio_read(
            REG_OUTPUT_L,
            read_value
        );

        check(
            read_value == 32'h00000000,
            "M7B-1 OUTPUT_L remains zero without mixer"
        );


        mmio_read(
            REG_OUTPUT_R,
            read_value
        );

        check(
            read_value == 32'h00000000,
            "M7B-1 OUTPUT_R remains zero without mixer"
        );


        mmio_read(
            REG_SAMPLE_COUNT,
            read_value
        );

        check(
            read_value == 32'h00000000,
            "M7B-1 SAMPLE_COUNT remains zero without sample ticks"
        );


        mmio_read(
            REG_RESERVED,
            read_value
        );

        check(
            read_value == 32'h00000000,
            "reserved global audio register reads zero"
        );


        // SAMPLE_ADDR byte-lane behavior.
        mmio_write(
            REG_SAMPLE_ADDR,
            32'h00000123,
            4'b1111
        );


        mmio_write(
            REG_SAMPLE_ADDR,
            32'h00000A55,
            4'b0010
        );


        mmio_read(
            REG_SAMPLE_ADDR,
            read_value
        );


        check(
            read_value == 32'h00000A23,
            "SAMPLE_ADDR implements twelve bits and byte strobes"
        );


        // PCM sample RAM.
        mmio_write(
            REG_SAMPLE_DATA,
            32'h00001234,
            4'b0011
        );


        mmio_write(
            REG_SAMPLE_DATA,
            32'h0000ABCD,
            4'b0010
        );


        mmio_read(
            REG_SAMPLE_DATA,
            read_value
        );


        check(
            read_value == 32'h0000AB34,
            "SAMPLE_DATA preserves unwritten byte lanes"
        );


        check(
            ({dut.sample_ram_hi[12'hA23], dut.sample_ram_lo[12'hA23]}) == 16'hAB34,
            "PCM sample RAM stores selected sample"
        );


        mmio_write(
            REG_SAMPLE_DATA,
            32'h000000CD,
            4'b0001
        );


        mmio_read(
            REG_SAMPLE_DATA,
            read_value
        );


        check(
            read_value == 32'h0000ABCD,
            "SAMPLE_DATA low-byte write strobe is honored"
        );


        // Reserved global register.
        mmio_write(
            REG_RESERVED,
            32'hDEADBEEF,
            4'b1111
        );


        mmio_read(
            REG_RESERVED,
            read_value
        );


        check(
            read_value == 32'h00000000,
            "reserved global audio write is ignored"
        );


        // Voice zero configuration.
        mmio_write(
            V0_BASE,
            32'h00000FFE,
            4'b1111
        );


        mmio_write(
            V0_LENGTH,
            32'h00000010,
            4'b1111
        );


        mmio_write(
            V0_VOLUME_L,
            32'h0000005A,
            4'b0001
        );


        mmio_write(
            V0_VOLUME_R,
            32'h000000C3,
            4'b0001
        );


        mmio_read(
            V0_BASE,
            read_value
        );


        check(
            read_value == 32'h00000FFE,
            "voice BASE stores low twelve bits"
        );


        mmio_read(
            V0_LENGTH,
            read_value
        );


        check(
            read_value == 32'h00000010,
            "voice LENGTH stores low thirteen bits"
        );


        mmio_read(
            V0_VOLUME_L,
            read_value
        );


        check(
            read_value == 32'h0000005A,
            "voice left volume stores low byte"
        );


        mmio_read(
            V0_VOLUME_R,
            read_value
        );


        check(
            read_value == 32'h000000C3,
            "voice right volume stores low byte"
        );


        mmio_write(
            V0_RESERVED,
            32'hFFFFFFFF,
            4'b1111
        );


        mmio_read(
            V0_RESERVED,
            read_value
        );


        check(
            read_value == 32'h00000000,
            "reserved voice register reads zero and ignores writes"
        );


        // Nonzero START.
        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0001
        );


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000001,
            "nonzero START sets ACTIVE and clears DONE"
        );


        check(
            dut.active_base[0] == 12'hFFE,
            "START snapshots configured BASE"
        );


        check(
            dut.active_length[0] == 13'd2,
            "effective length truncates at end of sample RAM"
        );


        check(
            dut.voice_position[0] == 13'd0,
            "START resets POSITION to zero"
        );


        repeat (3)
            @(posedge clk);

        #1;


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000001,
            "M7B-1 does not fake playback completion"
        );


        // Restart while active.
        mmio_write(
            V0_BASE,
            32'h00000064,
            4'b1111
        );


        mmio_write(
            V0_LENGTH,
            32'h00000003,
            4'b1111
        );


        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0001
        );


        check(
            dut.active_base[0] == 12'd100 &&
            dut.active_length[0] == 13'd3,
            "START while active refreshes playback snapshot"
        );


        check(
            dut.voice_position[0] == 13'd0,
            "restart resets POSITION"
        );


        // STOP takes priority over START.
        mmio_write(
            V0_CONTROL,
            32'h00000003,
            4'b0001
        );


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000000,
            "STOP has priority over START and does not set DONE"
        );


        // CONTROL requires byte strobe zero.
        mmio_write(
            V0_LENGTH,
            32'h00000000,
            4'b1111
        );


        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0010
        );


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000000,
            "CONTROL commands require low-byte write strobe"
        );


        // Zero-length START.
        mmio_write(
            V0_CONTROL,
            32'h00000001,
            4'b0001
        );


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000002,
            "zero-length START completes immediately with DONE"
        );


        mmio_read(
            V0_POSITION,
            read_value
        );


        check(
            read_value == 32'h00000000,
            "zero-length START consumes no sample"
        );


        repeat (3)
            @(posedge clk);

        #1;


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000002,
            "DONE remains sticky while idle"
        );


        // CLEAR_DONE requires byte strobe zero.
        mmio_write(
            V0_CONTROL,
            32'h00000004,
            4'b0010
        );


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000002,
            "CLEAR_DONE requires low-byte write strobe"
        );


        mmio_write(
            V0_CONTROL,
            32'h00000004,
            4'b0001
        );


        mmio_read(
            V0_STATUS,
            read_value
        );


        check(
            read_value == 32'h00000000,
            "CLEAR_DONE clears sticky DONE"
        );


        // Voice independence.
        mmio_write(
            V1_BASE,
            32'h00000321,
            4'b1111
        );


        mmio_read(
            V1_BASE,
            read_value
        );


        check(
            read_value == 32'h00000321,
            "voice one BASE is independently writable"
        );


        mmio_read(
            V0_BASE,
            read_value
        );


        check(
            read_value == 32'h00000064,
            "voice one write does not corrupt voice zero"
        );


        $display("");
        $display("==============================");


        if (failures == 0) begin

            $display(
                "RESULT: PASS  (%0d checks)",
                checks
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
