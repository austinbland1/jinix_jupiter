# Simulator: Icarus Verilog (iverilog + vvp).

CORE_SRCS = ../rtl/jupiter_core.sv \
            jupiter_core_tb.sv

SYSTEM_SRCS = template_compat_stubs.sv \
              ../rtl/mycore.v \
              ../rtl/jupiter_core.sv \
              ../rtl/jupiter_system.sv \
              jupiter_system_tb.sv

.PHONY: test core-test system-test clean

test: core-test system-test

core-test:
	iverilog -g2012 -s jupiter_core_tb -o jupiter_core.vvp $(CORE_SRCS)
	vvp -n jupiter_core.vvp

system-test:
	iverilog -g2012 -s jupiter_system_tb -o jupiter_system.vvp $(SYSTEM_SRCS)
	vvp -n jupiter_system.vvp

clean:
	rm -f jupiter_core.vvp jupiter_system.vvp
