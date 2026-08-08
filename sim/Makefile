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

CPU_RTL = ../rtl/cpu/jupiter_cpu.sv

.PHONY: test m1-test cpu-test core-test system-test stub-test \
	cpu-state-test cpu-fetch-test cpu-basic-exec-test cpu-alu-test \
	cpu-memory-test cpu-control-test cpu-program-test clean

test: m1-test cpu-test

m1-test: core-test system-test stub-test

cpu-test: cpu-state-test cpu-fetch-test cpu-basic-exec-test \
	cpu-alu-test cpu-memory-test cpu-control-test cpu-program-test

core-test:
	iverilog -g2012 -s jupiter_core_tb -o jupiter_core.vvp $(CORE_SRCS)
	vvp -n jupiter_core.vvp

system-test:
	iverilog -g2012 -s jupiter_system_tb -o jupiter_system.vvp $(SYSTEM_SRCS)
	vvp -n jupiter_system.vvp

stub-test:
	iverilog -g2012 -s jupiter_stubs_tb -o jupiter_stubs.vvp $(STUB_SRCS)
	vvp -n jupiter_stubs.vvp


cpu-state-test:
	iverilog -g2012 -s jupiter_cpu_state_tb -o jupiter_cpu_state.vvp $(CPU_RTL) jupiter_cpu_state_tb.sv
	vvp -n jupiter_cpu_state.vvp

cpu-fetch-test:
	iverilog -g2012 -s jupiter_cpu_fetch_tb -o jupiter_cpu_fetch.vvp $(CPU_RTL) jupiter_cpu_fetch_tb.sv
	vvp -n jupiter_cpu_fetch.vvp

cpu-basic-exec-test:
	iverilog -g2012 -s jupiter_cpu_basic_exec_tb -o jupiter_cpu_basic_exec.vvp $(CPU_RTL) jupiter_cpu_basic_exec_tb.sv
	vvp -n jupiter_cpu_basic_exec.vvp

cpu-alu-test:
	iverilog -g2012 -s jupiter_cpu_alu_tb -o jupiter_cpu_alu.vvp $(CPU_RTL) jupiter_cpu_alu_tb.sv
	vvp -n jupiter_cpu_alu.vvp

cpu-memory-test:
	iverilog -g2012 -s jupiter_cpu_memory_tb -o jupiter_cpu_memory.vvp $(CPU_RTL) jupiter_cpu_memory_tb.sv
	vvp -n jupiter_cpu_memory.vvp

cpu-control-test:
	iverilog -g2012 -s jupiter_cpu_control_tb -o jupiter_cpu_control.vvp $(CPU_RTL) jupiter_cpu_control_tb.sv
	vvp -n jupiter_cpu_control.vvp

cpu-program-test:
	iverilog -g2012 -s jupiter_cpu_program_tb -o jupiter_cpu_program.vvp $(CPU_RTL) jupiter_cpu_program_tb.sv
	vvp -n jupiter_cpu_program.vvp

clean:
	rm -f jupiter_core.vvp jupiter_system.vvp jupiter_stubs.vvp \
		jupiter_cpu_state.vvp jupiter_cpu_fetch.vvp \
		jupiter_cpu_basic_exec.vvp jupiter_cpu_alu.vvp \
		jupiter_cpu_memory.vvp jupiter_cpu_control.vvp \
		jupiter_cpu_program.vvp
