`timescale 1ns/1ps

module jupiter_controllers_tb;

    reg         valid;
    reg         write;
    reg  [31:0] addr;
    reg  [31:0] wdata;
    reg   [3:0] wstrb;

    reg  [31:0] controller_0_state;
    reg  [31:0] controller_1_state;
    reg  [31:0] controller_2_state;
    reg  [31:0] controller_3_state;
    reg  [31:0] controller_4_state;
    reg  [31:0] controller_5_state;

    wire [31:0] rdata;
    wire        ready;

    integer checks;
    integer failures;
    integer bit_index;


    jupiter_controllers dut
    (
        .valid (valid),
        .write (write),
        .addr  (addr),
        .wdata (wdata),
        .wstrb (wstrb),

        .controller_0_state (controller_0_state),
        .controller_1_state (controller_1_state),
        .controller_2_state (controller_2_state),
        .controller_3_state (controller_3_state),
        .controller_4_state (controller_4_state),
        .controller_5_state (controller_5_state),

        .rdata (rdata),
        .ready (ready)
    );


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


    task automatic read_check;
        input [31:0] test_addr;
        input [31:0] expected;
        input [8*128-1:0] message;
        begin

            valid = 1'b1;
            write = 1'b0;
            addr  = test_addr;
            wdata = 32'h00000000;
            wstrb = 4'b0000;

            #1;

            check(
                ready &&
                rdata == expected,
                message
            );
        end
    endtask


    initial begin

        checks = 0;
        failures = 0;

        valid = 1'b0;
        write = 1'b0;
        addr  = 32'h00000000;
        wdata = 32'h00000000;
        wstrb = 4'b0000;

        controller_0_state = 32'h00000001;
        controller_1_state = 32'h80000000;
        controller_2_state = 32'hA5A55A5A;
        controller_3_state = 32'hFFFFFFFF;
        controller_4_state = 32'h01234567;
        controller_5_state = 32'h89ABCDEF;

        #1;

        check(
            !ready &&
            rdata == 32'h00000000,
            "idle target is not ready and presents deterministic zero"
        );


        read_check(32'h00001400, controller_0_state,
                   "controller zero returns exact state");

        read_check(32'h00001404, controller_1_state,
                   "controller one returns exact state");

        read_check(32'h00001408, controller_2_state,
                   "controller two returns exact state");

        read_check(32'h0000140C, controller_3_state,
                   "controller three returns exact state");

        read_check(32'h00001410, controller_4_state,
                   "controller four returns exact state");

        read_check(32'h00001414, controller_5_state,
                   "controller five returns exact state");


        for (
            bit_index = 0;
            bit_index < 32;
            bit_index = bit_index + 1
        ) begin

            controller_0_state =
                32'h00000001 << bit_index;

            read_check(
                32'h00001400,
                controller_0_state,
                "controller raw bit position is preserved"
            );
        end


        controller_0_state = 32'h13579BDF;
        controller_3_state = 32'h2468ACE0;

        read_check(
            32'h00001400,
            32'h13579BDF,
            "controller zero remains independent"
        );

        read_check(
            32'h0000140C,
            32'h2468ACE0,
            "changed controller state is immediately visible"
        );


        read_check(
            32'h00001418,
            32'h00000000,
            "first reserved offset returns zero"
        );

        read_check(
            32'h000014FC,
            32'h00000000,
            "last reserved aligned offset returns zero"
        );


        valid = 1'b1;
        write = 1'b1;
        addr  = 32'h00001400;
        wdata = 32'hDEADBEEF;
        wstrb = 4'b1111;

        #1;

        check(
            ready &&
            rdata == 32'h00000000,
            "implemented-register write completes as no-op"
        );


        write = 1'b0;

        #1;

        check(
            rdata == controller_0_state,
            "implemented-register write has no state effect"
        );


        write = 1'b1;
        addr  = 32'h00001420;
        wdata = 32'hFFFFFFFF;
        wstrb = 4'b0101;

        #1;

        check(
            ready &&
            rdata == 32'h00000000,
            "reserved write completes as no-op"
        );


        valid = 1'b0;
        write = 1'b0;

        #1;

        check(
            !ready &&
            rdata == 32'h00000000,
            "idle behavior remains deterministic"
        );


        $display("");
        $display("==============================");

        if (failures == 0) begin
            $display("RESULT: PASS  (%0d checks)", checks);
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
