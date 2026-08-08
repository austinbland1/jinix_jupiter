# Simulator: Icarus Verilog (iverilog + vvp).

CORE_SRCS = ../rtl/jupiter_core.sv \
            jupiter_core_tb.sv

SYSTEM_SRCS = template_compat_stubs.sv \
              ../rtl/mycore.v \
              ../rtl/jupiter_core.sv \
              ../rtl/jupiter_system.sv \
              jupiter_system_tb.sv

STUB_SRCS = ../rtl/cpu/jupiter_cpu_stub.sv \
            ../rtl/memory/jupiter_memory_stub.sv \
            ../rtl/dma/jupiter_dma_stub.sv \
            ../rtl/gpu/jupiter_gpu_stub.sv \
            ../rtl/audio/jupiter_audio_stub.sv \
            ../rtl/peripherals/jupiter_peripherals_stub.sv \
            jupiter_stubs_tb.sv

.PHONY: test core-test system-test stub-test clean

test: core-test system-test stub-test

core-test:
	iverilog -g2012 -s jupiter_core_tb -o jupiter_core.vvp $(CORE_SRCS)
	vvp -n jupiter_core.vvp

system-test:
	iverilog -g2012 -s jupiter_system_tb -o jupiter_system.vvp $(SYSTEM_SRCS)
	vvp -n jupiter_system.vvp

stub-test:
	iverilog -g2012 -s jupiter_stubs_tb -o jupiter_stubs.vvp $(STUB_SRCS)
	vvp -n jupiter_stubs.vvp

clean:
	rm -f jupiter_core.vvp jupiter_system.vvp jupiter_stubs.vvp
