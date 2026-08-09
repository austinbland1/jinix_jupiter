# Simulator: Icarus Verilog (iverilog + vvp).

CORE_SRCS = ../rtl/jupiter_core.sv \
            jupiter_core_tb.sv

SYSTEM_SRCS = template_compat_stubs.sv \
              ../rtl/mycore.v \
              ../rtl/jupiter_core.sv \
              $(CPU_SUBSYSTEM_RTL) \
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

INTERCONNECT_RTL = ../rtl/memory/jupiter_interconnect.sv
INTERNAL_RAM_RTL = ../rtl/memory/jupiter_internal_ram.sv
MMIO_SCRATCH_RTL = ../rtl/peripherals/jupiter_mmio_scratch.sv
SDRAM_FRONTEND_RTL = ../rtl/memory/jupiter_sdram_frontend.sv
SDRAM_CONTROLLER_RTL = ../rtl/memory/jupiter_sdram_controller.sv
SDRAM_MODEL = jupiter_sdram_model.sv

CPU_SUBSYSTEM_RTL = $(CPU_RTL) \
                    $(INTERCONNECT_RTL) \
                    $(INTERNAL_RAM_RTL) \
                    $(MMIO_SCRATCH_RTL) \
                    $(SDRAM_FRONTEND_RTL) \
                    $(SDRAM_CONTROLLER_RTL) \
                    ../rtl/jupiter_cpu_subsystem.sv

.PHONY: test m1-test cpu-test m3-test m4-test \
	core-test system-test stub-test \
	cpu-state-test cpu-fetch-test cpu-basic-exec-test cpu-alu-test \
	cpu-memory-test cpu-control-test cpu-program-test \
	interconnect-test internal-ram-test mmio-scratch-test \
	cpu-subsystem-test cpu-memory-map-test \
	sdram-frontend-test sdram-controller-test sdram-path-test \
	cpu-sdram-test clean

test: m1-test cpu-test m3-test m4-test

m1-test: core-test system-test stub-test

cpu-test: cpu-state-test cpu-fetch-test cpu-basic-exec-test \
	cpu-alu-test cpu-memory-test cpu-control-test cpu-program-test

m3-test: interconnect-test internal-ram-test mmio-scratch-test \
	cpu-subsystem-test cpu-memory-map-test

m4-test: interconnect-test cpu-subsystem-test system-test \
	sdram-frontend-test sdram-controller-test sdram-path-test \
	cpu-sdram-test

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

interconnect-test:
	iverilog -g2012 -s jupiter_interconnect_tb -o jupiter_interconnect.vvp $(INTERCONNECT_RTL) jupiter_interconnect_tb.sv
	vvp -n jupiter_interconnect.vvp

internal-ram-test:
	iverilog -g2012 -s jupiter_internal_ram_tb -o jupiter_internal_ram.vvp $(INTERNAL_RAM_RTL) jupiter_internal_ram_tb.sv
	vvp -n jupiter_internal_ram.vvp

mmio-scratch-test:
	iverilog -g2012 -s jupiter_mmio_scratch_tb -o jupiter_mmio_scratch.vvp $(MMIO_SCRATCH_RTL) jupiter_mmio_scratch_tb.sv
	vvp -n jupiter_mmio_scratch.vvp

cpu-subsystem-test:
	iverilog -g2012 -s jupiter_cpu_subsystem_tb -o jupiter_cpu_subsystem.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_subsystem_tb.sv
	vvp -n jupiter_cpu_subsystem.vvp

cpu-memory-map-test:
	iverilog -g2012 -s jupiter_cpu_memory_map_tb -o jupiter_cpu_memory_map.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_memory_map_tb.sv
	vvp -n jupiter_cpu_memory_map.vvp

sdram-frontend-test:
	iverilog -g2012 -s jupiter_sdram_frontend_tb -o jupiter_sdram_frontend.vvp $(SDRAM_FRONTEND_RTL) jupiter_sdram_frontend_tb.sv
	vvp -n jupiter_sdram_frontend.vvp

sdram-controller-test:
	iverilog -g2012 -s jupiter_sdram_controller_tb -o jupiter_sdram_controller.vvp $(SDRAM_CONTROLLER_RTL) jupiter_sdram_controller_tb.sv
	vvp -n jupiter_sdram_controller.vvp

sdram-path-test:
	iverilog -g2012 -s jupiter_sdram_path_tb -o jupiter_sdram_path.vvp $(SDRAM_FRONTEND_RTL) $(SDRAM_CONTROLLER_RTL) $(SDRAM_MODEL) jupiter_sdram_path_tb.sv
	vvp -n jupiter_sdram_path.vvp

cpu-sdram-test:
	iverilog -g2012 -s jupiter_cpu_sdram_tb -o jupiter_cpu_sdram.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_cpu_sdram_tb.sv
	vvp -n jupiter_cpu_sdram.vvp

clean:
	rm -f jupiter_core.vvp jupiter_system.vvp jupiter_stubs.vvp \
		jupiter_cpu_state.vvp jupiter_cpu_fetch.vvp \
		jupiter_cpu_basic_exec.vvp jupiter_cpu_alu.vvp \
		jupiter_cpu_memory.vvp jupiter_cpu_control.vvp \
		jupiter_cpu_program.vvp \
		jupiter_interconnect.vvp jupiter_internal_ram.vvp \
		jupiter_mmio_scratch.vvp jupiter_cpu_subsystem.vvp \
		jupiter_cpu_memory_map.vvp \
		jupiter_sdram_frontend.vvp jupiter_sdram_controller.vvp \
		jupiter_sdram_path.vvp jupiter_cpu_sdram.vvp
