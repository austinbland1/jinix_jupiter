# Simulator: Icarus Verilog (iverilog + vvp).

CORE_SRCS = ../rtl/jupiter_core.sv \
            jupiter_core_tb.sv

SYSTEM_SRCS = template_compat_stubs.sv \
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
GPU_2D3D_ARBITER_RTL = ../rtl/gpu/jupiter_gpu_2d3d_arbiter.sv
GPU_3D_RASTER_RTL = ../rtl/gpu/jupiter_gpu_3d_raster.sv
GPU_3D_RTL = $(GPU_3D_RASTER_RTL) ../rtl/gpu/jupiter_gpu_3d.sv
GPU_2D_RTL = $(GPU_2D3D_ARBITER_RTL) $(GPU_3D_RTL) ../rtl/gpu/jupiter_gpu_2d.sv
DMA_RTL = ../rtl/dma/jupiter_dma.sv
AUDIO_RTL = ../rtl/audio/jupiter_audio.sv
CONTROLLER_RTL = ../rtl/peripherals/jupiter_controllers.sv
SDRAM_ARBITER_RTL = ../rtl/memory/jupiter_sdram_arbiter.sv
SDRAM_SCANOUT_ARBITER_RTL = ../rtl/memory/jupiter_sdram_scanout_arbiter.sv
VIDEO_SCANOUT_RTL = ../rtl/video/jupiter_video_scanout.sv
SDRAM_FRONTEND_RTL = ../rtl/memory/jupiter_sdram_frontend.sv
SDRAM_CONTROLLER_RTL = ../rtl/memory/jupiter_sdram_controller.sv
SDRAM_MODEL = jupiter_sdram_model.sv

CPU_SUBSYSTEM_RTL = $(CPU_RTL) \
                    $(INTERCONNECT_RTL) \
                    $(INTERNAL_RAM_RTL) \
                    $(MMIO_SCRATCH_RTL) \
                    $(GPU_2D_RTL) \
                    $(DMA_RTL) \
                    $(AUDIO_RTL) \
                     $(CONTROLLER_RTL) \
                    $(SDRAM_ARBITER_RTL) \
                    $(SDRAM_SCANOUT_ARBITER_RTL) \
                    $(VIDEO_SCANOUT_RTL) \
                    $(SDRAM_FRONTEND_RTL) \
                    $(SDRAM_CONTROLLER_RTL) \
                    ../rtl/jupiter_cpu_subsystem.sv

.PHONY: test m1-test cpu-test m3-test m4-test m5b-test m5c-test m5d-test m5e-test m6b-test m6c-test m6d-test m6e-test m7b-test m7c-test m8b-test m9b-test m9c-test \
	core-test system-test stub-test \
	cpu-state-test cpu-fetch-test cpu-basic-exec-test cpu-alu-test \
	cpu-memory-test cpu-control-test cpu-program-test \
	interconnect-test internal-ram-test mmio-scratch-test gpu-regs-test dma-regs-test dma-multiword-test dma-copy-test cpu-dma-contention-test gpu-dma-contention-test three-master-contention-test \
	gpu-tilemap-test gpu-tiledata-test gpu-framebuffer-test \
	gpu-full-tile-test gpu-full-map-test \
	cpu-subsystem-test cpu-memory-map-test cpu-gpu-mmio-test cpu-dma-mmio-test \
	audio-regs-test audio-playback-test audio-mixer-test interconnect-audio-test cpu-audio-mmio-test audio-topology-test \
	controller-regs-test interconnect-controller-test cpu-controller-mmio-test controller-topology-test \
	assembler-test image-builder-test boot-image-test \
	sdram-arbiter-test shared-sdram-test dma-sdram-path-test gpu-sdram-render-test \
	gpu-sdram-contention-test \
	sdram-frontend-test sdram-controller-test sdram-path-test \
	cpu-sdram-test clean

test: m1-test cpu-test m3-test m4-test m5b-test m5c-test m5d-test m5e-test m6b-test m6c-test m6d-test m6e-test m7b-test m7c-test m8b-test m9b-test m9c-test m10b1-test m10b2-test m10c-test

m1-test: core-test system-test stub-test

cpu-test: cpu-state-test cpu-fetch-test cpu-basic-exec-test \
	cpu-alu-test cpu-memory-test cpu-control-test cpu-program-test

m3-test: interconnect-test internal-ram-test mmio-scratch-test \
	cpu-subsystem-test cpu-memory-map-test

m4-test: interconnect-test cpu-subsystem-test system-test \
	sdram-frontend-test sdram-controller-test sdram-path-test \
	cpu-sdram-test

.PHONY: m10b1-test m10b2-test m10c-test gpu-3d-test gpu-2d3d-arbiter-test gpu-3d-mmio-test gpu-3d-vertex-test gpu-3d-triangle-test gpu-3d-raster-integration-test gpu-3d-flat-test gpu-3d-depth-test gpu-3d-depth-integration-test gpu-3d-depth-overlap-test

m10b1-test: gpu-3d-test gpu-2d3d-arbiter-test gpu-3d-mmio-test

m10b2-test: gpu-3d-vertex-test gpu-3d-triangle-test gpu-3d-raster-integration-test gpu-3d-flat-test

m10c-test: gpu-3d-depth-test gpu-3d-depth-integration-test gpu-3d-depth-overlap-test

m5b-test: gpu-regs-test cpu-gpu-mmio-test

m5c-test: sdram-arbiter-test shared-sdram-test

m5d-test: gpu-tilemap-test gpu-tiledata-test gpu-framebuffer-test gpu-full-tile-test gpu-full-map-test

m5e-test: gpu-sdram-render-test gpu-sdram-contention-test

m6b-test: dma-regs-test cpu-dma-mmio-test

m6c-test: sdram-arbiter-test dma-sdram-path-test

m6d-test: dma-regs-test dma-multiword-test dma-copy-test

m6e-test: cpu-dma-contention-test gpu-dma-contention-test three-master-contention-test

m7b-test: audio-regs-test audio-playback-test audio-mixer-test interconnect-audio-test cpu-audio-mmio-test

m7c-test: system-test audio-topology-test
m8b-test: controller-regs-test interconnect-controller-test cpu-controller-mmio-test interconnect-test interconnect-audio-test system-test controller-topology-test

m9b-test: assembler-test image-builder-test

m9c-test: boot-image-test

audio-topology-test:
	python3 check_m7c_audio_topology.py

controller-topology-test:
	python3 check_m8b2_controller_topology.py

assembler-test:
	python3 -B ../software/devkit/test_jupiter_asm.py

image-builder-test:
	python3 -B ../software/tools/test_build_system_image.py

boot-image-test:
	python3 -B ../software/devkit/jupiter_asm.py ../software/bios/bios.asm -o m9c_bios.hex --origin 0x00000000
	python3 -B ../software/devkit/jupiter_asm.py ../software/bios/test_program.asm -o m9c_program.hex --origin 0x00000400
	python3 -B ../software/tools/build_system_image.py --bios m9c_bios.hex --app m9c_program.hex --output m9c_system.mem
	python3 -B check_m9c_boot_image.py m9c_bios.hex m9c_program.hex m9c_system.mem
	iverilog -g2012 -s jupiter_boot_image_tb -o jupiter_boot_image.vvp $(CPU_SUBSYSTEM_RTL) jupiter_boot_image_tb.sv
	vvp -n jupiter_boot_image.vvp +IMAGE=m9c_system.mem

audio-regs-test:
	iverilog -g2012 -s jupiter_audio_tb -o jupiter_audio.vvp $(AUDIO_RTL) jupiter_audio_tb.sv
	vvp -n jupiter_audio.vvp

audio-playback-test:
	iverilog -g2012 -s jupiter_audio_playback_tb -o jupiter_audio_playback.vvp $(AUDIO_RTL) jupiter_audio_playback_tb.sv
	vvp -n jupiter_audio_playback.vvp

audio-mixer-test:
	iverilog -g2012 -s jupiter_audio_mixer_tb -o jupiter_audio_mixer.vvp $(AUDIO_RTL) jupiter_audio_mixer_tb.sv
	vvp -n jupiter_audio_mixer.vvp

interconnect-audio-test:
	iverilog -g2012 -s jupiter_interconnect_audio_tb -o jupiter_interconnect_audio.vvp $(INTERCONNECT_RTL) jupiter_interconnect_audio_tb.sv
	vvp -n jupiter_interconnect_audio.vvp

cpu-audio-mmio-test:
	iverilog -g2012 -s jupiter_cpu_audio_mmio_tb -o jupiter_cpu_audio_mmio.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_audio_mmio_tb.sv
	vvp -n jupiter_cpu_audio_mmio.vvp

controller-regs-test:
	iverilog -g2012 -s jupiter_controllers_tb -o jupiter_controllers.vvp $(CONTROLLER_RTL) jupiter_controllers_tb.sv
	vvp -n jupiter_controllers.vvp

interconnect-controller-test:
	iverilog -g2012 -s jupiter_interconnect_controller_tb -o jupiter_interconnect_controller.vvp $(INTERCONNECT_RTL) jupiter_interconnect_controller_tb.sv
	vvp -n jupiter_interconnect_controller.vvp

cpu-controller-mmio-test:
	iverilog -g2012 -s jupiter_cpu_controller_mmio_tb -o jupiter_cpu_controller_mmio.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_controller_mmio_tb.sv
	vvp -n jupiter_cpu_controller_mmio.vvp

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

gpu-regs-test:
	iverilog -g2012 -s jupiter_gpu_2d_tb -o jupiter_gpu_2d.vvp $(GPU_2D_RTL) jupiter_gpu_2d_tb.sv
	vvp -n jupiter_gpu_2d.vvp

gpu-tilemap-test:
	iverilog -g2012 -s jupiter_gpu_tilemap_tb -o jupiter_gpu_tilemap.vvp $(GPU_2D_RTL) jupiter_gpu_tilemap_tb.sv
	vvp -n jupiter_gpu_tilemap.vvp

gpu-tiledata-test:
	iverilog -g2012 -s jupiter_gpu_tiledata_tb -o jupiter_gpu_tiledata.vvp $(GPU_2D_RTL) jupiter_gpu_tiledata_tb.sv
	vvp -n jupiter_gpu_tiledata.vvp

gpu-framebuffer-test:
	iverilog -g2012 -s jupiter_gpu_framebuffer_tb -o jupiter_gpu_framebuffer.vvp $(GPU_2D_RTL) jupiter_gpu_framebuffer_tb.sv
	vvp -n jupiter_gpu_framebuffer.vvp

gpu-full-tile-test:
	iverilog -g2012 -s jupiter_gpu_full_tile_tb -o jupiter_gpu_full_tile.vvp $(GPU_2D_RTL) jupiter_gpu_full_tile_tb.sv
	vvp -n jupiter_gpu_full_tile.vvp

gpu-full-map-test:
	iverilog -g2012 -s jupiter_gpu_full_map_tb -o jupiter_gpu_full_map.vvp $(GPU_2D_RTL) jupiter_gpu_full_map_tb.sv
	vvp -n jupiter_gpu_full_map.vvp

cpu-subsystem-test:
	iverilog -g2012 -s jupiter_cpu_subsystem_tb -o jupiter_cpu_subsystem.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_subsystem_tb.sv
	vvp -n jupiter_cpu_subsystem.vvp

cpu-memory-map-test:
	iverilog -g2012 -s jupiter_cpu_memory_map_tb -o jupiter_cpu_memory_map.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_memory_map_tb.sv
	vvp -n jupiter_cpu_memory_map.vvp

cpu-gpu-mmio-test:
	iverilog -g2012 -s jupiter_cpu_gpu_mmio_tb -o jupiter_cpu_gpu_mmio.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_gpu_mmio_tb.sv
	vvp -n jupiter_cpu_gpu_mmio.vvp

cpu-dma-mmio-test:
	iverilog -g2012 -s jupiter_cpu_dma_mmio_tb -o jupiter_cpu_dma_mmio.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_dma_mmio_tb.sv
	vvp -n jupiter_cpu_dma_mmio.vvp

sdram-arbiter-test:
	iverilog -g2012 -s jupiter_sdram_arbiter_tb -o jupiter_sdram_arbiter.vvp $(SDRAM_ARBITER_RTL) jupiter_sdram_arbiter_tb.sv
	vvp -n jupiter_sdram_arbiter.vvp

shared-sdram-test:
	iverilog -g2012 -s jupiter_shared_sdram_tb -o jupiter_shared_sdram.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_shared_sdram_tb.sv
	vvp -n jupiter_shared_sdram.vvp

dma-sdram-path-test:
	iverilog -g2012 -s jupiter_dma_sdram_path_tb -o jupiter_dma_sdram_path.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_dma_sdram_path_tb.sv
	vvp -n jupiter_dma_sdram_path.vvp

gpu-sdram-render-test:
	iverilog -g2012 -s jupiter_gpu_sdram_render_tb -o jupiter_gpu_sdram_render.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_gpu_sdram_render_tb.sv
	vvp -n jupiter_gpu_sdram_render.vvp

gpu-sdram-contention-test:
	iverilog -g2012 -s jupiter_gpu_sdram_contention_tb -o jupiter_gpu_sdram_contention.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_gpu_sdram_contention_tb.sv
	vvp -n jupiter_gpu_sdram_contention.vvp

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

dma-regs-test:
	iverilog -g2012 -s jupiter_dma_tb -o jupiter_dma.vvp $(DMA_RTL) jupiter_dma_tb.sv
	vvp -n jupiter_dma.vvp

dma-multiword-test:
	iverilog -g2012 -s jupiter_dma_multiword_tb -o jupiter_dma_multiword.vvp $(DMA_RTL) jupiter_dma_multiword_tb.sv
	vvp -n jupiter_dma_multiword.vvp

dma-copy-test:
	iverilog -g2012 -s jupiter_dma_copy_tb -o jupiter_dma_copy.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_dma_copy_tb.sv
	vvp -n jupiter_dma_copy.vvp

cpu-dma-contention-test:
	iverilog -g2012 -s jupiter_cpu_dma_contention_tb -o jupiter_cpu_dma_contention.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_cpu_dma_contention_tb.sv
	vvp -n jupiter_cpu_dma_contention.vvp

gpu-dma-contention-test:
	iverilog -g2012 -s jupiter_gpu_dma_contention_tb -o jupiter_gpu_dma_contention.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_gpu_dma_contention_tb.sv
	vvp -n jupiter_gpu_dma_contention.vvp

three-master-contention-test:
	iverilog -g2012 -s jupiter_three_master_contention_tb -o jupiter_three_master_contention.vvp $(CPU_SUBSYSTEM_RTL) $(SDRAM_MODEL) jupiter_three_master_contention_tb.sv
	vvp -n jupiter_three_master_contention.vvp

gpu-3d-test:
	iverilog -g2012 -s jupiter_gpu_3d_tb -o jupiter_gpu_3d.vvp $(GPU_3D_RTL) jupiter_gpu_3d_tb.sv
	vvp -n jupiter_gpu_3d.vvp

gpu-2d3d-arbiter-test:
	iverilog -g2012 -s jupiter_gpu_2d3d_arbiter_tb -o jupiter_gpu_2d3d_arbiter.vvp $(GPU_2D3D_ARBITER_RTL) jupiter_gpu_2d3d_arbiter_tb.sv
	vvp -n jupiter_gpu_2d3d_arbiter.vvp

gpu-3d-mmio-test:
	iverilog -g2012 -s jupiter_gpu_3d_mmio_tb -o jupiter_gpu_3d_mmio.vvp $(GPU_2D_RTL) jupiter_gpu_3d_mmio_tb.sv
	vvp -n jupiter_gpu_3d_mmio.vvp

gpu-3d-vertex-test:
	iverilog -g2012 -s jupiter_gpu_3d_vertex_tb -o jupiter_gpu_3d_vertex.vvp $(GPU_3D_RTL) jupiter_gpu_3d_vertex_tb.sv
	vvp -n jupiter_gpu_3d_vertex.vvp

gpu-3d-triangle-test:
	iverilog -g2012 -s jupiter_gpu_3d_triangle_tb -o jupiter_gpu_3d_triangle.vvp $(GPU_3D_RASTER_RTL) jupiter_gpu_3d_triangle_tb.sv
	vvp -n jupiter_gpu_3d_triangle.vvp

gpu-3d-raster-integration-test:
	iverilog -g2012 -s jupiter_gpu_3d_raster_integration_tb -o jupiter_gpu_3d_raster_integration.vvp $(GPU_3D_RTL) jupiter_gpu_3d_raster_integration_tb.sv
	vvp -n jupiter_gpu_3d_raster_integration.vvp

gpu-3d-flat-test:
	iverilog -g2012 -s jupiter_gpu_3d_flat_tb -o jupiter_gpu_3d_flat.vvp $(GPU_3D_RTL) jupiter_gpu_3d_flat_tb.sv
	vvp -n jupiter_gpu_3d_flat.vvp

gpu-3d-depth-test:
	iverilog -g2012 -s jupiter_gpu_3d_depth_tb -o jupiter_gpu_3d_depth.vvp $(GPU_3D_RASTER_RTL) jupiter_gpu_3d_depth_tb.sv
	vvp -n jupiter_gpu_3d_depth.vvp

gpu-3d-depth-integration-test:
	iverilog -g2012 -s jupiter_gpu_3d_depth_integration_tb -o jupiter_gpu_3d_depth_integration.vvp $(GPU_3D_RTL) jupiter_gpu_3d_depth_integration_tb.sv
	vvp -n jupiter_gpu_3d_depth_integration.vvp

gpu-3d-depth-overlap-test:
	iverilog -g2012 -s jupiter_gpu_3d_depth_overlap_tb -o jupiter_gpu_3d_depth_overlap.vvp $(GPU_3D_RTL) jupiter_gpu_3d_depth_overlap_tb.sv
	vvp -n jupiter_gpu_3d_depth_overlap.vvp

clean:
	rm -f jupiter_gpu_3d_depth.vvp jupiter_gpu_3d_depth_integration.vvp jupiter_gpu_3d_depth_overlap.vvp
	rm -f jupiter_gpu_3d_vertex.vvp jupiter_gpu_3d_triangle.vvp jupiter_gpu_3d_raster_integration.vvp jupiter_gpu_3d_flat.vvp
	rm -f jupiter_gpu_3d.vvp jupiter_gpu_2d3d_arbiter.vvp jupiter_gpu_3d_mmio.vvp
	rm -f m9c_bios.hex m9c_program.hex m9c_system.mem jupiter_boot_image.vvp
	rm -f jupiter_controllers.vvp jupiter_interconnect_controller.vvp jupiter_cpu_controller_mmio.vvp
	rm -f jupiter_core.vvp jupiter_system.vvp jupiter_stubs.vvp \
		jupiter_cpu_state.vvp jupiter_cpu_fetch.vvp \
		jupiter_cpu_basic_exec.vvp jupiter_cpu_alu.vvp \
		jupiter_cpu_memory.vvp jupiter_cpu_control.vvp \
		jupiter_cpu_program.vvp \
		jupiter_interconnect.vvp jupiter_internal_ram.vvp \
		jupiter_mmio_scratch.vvp jupiter_gpu_2d.vvp \
		jupiter_gpu_tilemap.vvp jupiter_gpu_tiledata.vvp \
		jupiter_gpu_framebuffer.vvp jupiter_gpu_full_tile.vvp \
		jupiter_gpu_full_map.vvp jupiter_cpu_subsystem.vvp \
		jupiter_cpu_memory_map.vvp jupiter_cpu_gpu_mmio.vvp \
		jupiter_sdram_arbiter.vvp jupiter_shared_sdram.vvp \
		jupiter_gpu_sdram_render.vvp jupiter_gpu_sdram_contention.vvp \
		jupiter_sdram_frontend.vvp jupiter_sdram_controller.vvp \
		jupiter_sdram_path.vvp jupiter_cpu_sdram.vvp \
		jupiter_dma.vvp jupiter_cpu_dma_mmio.vvp jupiter_dma_sdram_path.vvp \
		jupiter_dma_multiword.vvp jupiter_dma_copy.vvp \
		jupiter_cpu_dma_contention.vvp jupiter_gpu_dma_contention.vvp \
		jupiter_three_master_contention.vvp
	rm -f jupiter_audio.vvp jupiter_audio_playback.vvp jupiter_audio_mixer.vvp jupiter_interconnect_audio.vvp jupiter_cpu_audio_mmio.vvp

# ============================================================
# Milestone 10D - perspective texture mapping and blending
# ============================================================

.PHONY: m10d-test \
	gpu-3d-perspective-test \
	gpu-3d-texture-test \
	gpu-3d-blend-test \
	gpu-3d-texture-blend-test \
	m10d-clean

test: m10d-test

m10d-test: \
	gpu-3d-perspective-test \
	gpu-3d-texture-test \
	gpu-3d-blend-test \
	gpu-3d-texture-blend-test

gpu-3d-perspective-test:
	iverilog -g2012 -s jupiter_gpu_3d_perspective_tb -o jupiter_gpu_3d_perspective.vvp ../rtl/gpu/jupiter_gpu_3d_raster.sv jupiter_gpu_3d_perspective_tb.sv
	vvp -n jupiter_gpu_3d_perspective.vvp

gpu-3d-texture-test:
	iverilog -g2012 -s jupiter_gpu_3d_texture_tb -o jupiter_gpu_3d_texture.vvp ../rtl/gpu/jupiter_gpu_3d_raster.sv ../rtl/gpu/jupiter_gpu_3d.sv jupiter_gpu_3d_texture_tb.sv
	vvp -n jupiter_gpu_3d_texture.vvp

gpu-3d-blend-test:
	iverilog -g2012 -s jupiter_gpu_3d_blend_tb -o jupiter_gpu_3d_blend.vvp ../rtl/gpu/jupiter_gpu_3d_raster.sv ../rtl/gpu/jupiter_gpu_3d.sv jupiter_gpu_3d_blend_tb.sv
	vvp -n jupiter_gpu_3d_blend.vvp

gpu-3d-texture-blend-test:
	iverilog -g2012 -s jupiter_gpu_3d_texture_blend_tb -o jupiter_gpu_3d_texture_blend.vvp ../rtl/gpu/jupiter_gpu_3d_raster.sv ../rtl/gpu/jupiter_gpu_3d.sv jupiter_gpu_3d_texture_blend_tb.sv
	vvp -n jupiter_gpu_3d_texture_blend.vvp

clean: m10d-clean

m10d-clean:
	rm -f \
		jupiter_gpu_3d_perspective.vvp \
		jupiter_gpu_3d_texture.vvp \
		jupiter_gpu_3d_blend.vvp \
		jupiter_gpu_3d_texture_blend.vvp

# ============================================================
# Milestone 10E - integrated acceptance and contention
# ============================================================

.PHONY: m10e-test \
	gpu-2d3d-contention-test \
	m10e-clean

test: m10e-test

m10e-test: \
	m10d-test \
	gpu-2d3d-contention-test \
	gpu-dma-contention-test \
	three-master-contention-test

gpu-2d3d-contention-test:
	iverilog -g2012 -s jupiter_gpu_2d3d_contention_tb -o jupiter_gpu_2d3d_contention.vvp ../rtl/gpu/jupiter_gpu_2d3d_arbiter.sv ../rtl/gpu/jupiter_gpu_3d_raster.sv ../rtl/gpu/jupiter_gpu_3d.sv ../rtl/gpu/jupiter_gpu_2d.sv jupiter_gpu_2d3d_contention_tb.sv
	vvp -n jupiter_gpu_2d3d_contention.vvp

clean: m10e-clean

m10e-clean:
	rm -f jupiter_gpu_2d3d_contention.vvp

# ============================================================
# Milestone 11A - release/integration baseline
# ============================================================

.PHONY: m11a-test m11a-integration-static-test

test: m11a-test

m11a-test: m10e-test m11a-integration-static-test

m11a-integration-static-test:
	python3 -B check_m11a_integration_release.py

# ============================================================
# Milestone 11B-2a - second-stage normal/scanout SDRAM arbiter
# ============================================================

.PHONY: m11b2a-test \
	sdram-scanout-arbiter-test \
	m11b2a-clean

test: m11b2a-test

m11b2a-test: m11a-test sdram-scanout-arbiter-test

sdram-scanout-arbiter-test:
	iverilog -g2012 -s jupiter_sdram_scanout_arbiter_tb -o jupiter_sdram_scanout_arbiter.vvp ../rtl/memory/jupiter_sdram_scanout_arbiter.sv jupiter_sdram_scanout_arbiter_tb.sv
	vvp -n jupiter_sdram_scanout_arbiter.vvp

clean: m11b2a-clean

m11b2a-clean:
	rm -f jupiter_sdram_scanout_arbiter.vvp

# ============================================================
# Milestone 11B-2b - scanout MMIO / timing shell
# ============================================================

.PHONY: m11b2b-test \
	video-scanout-test \
	m11b2b-clean

test: m11b2b-test

m11b2b-test: m11b2a-test video-scanout-test

video-scanout-test:
	iverilog -g2012 -s jupiter_video_scanout_tb -o jupiter_video_scanout.vvp ../rtl/video/jupiter_video_scanout.sv jupiter_video_scanout_tb.sv
	vvp -n jupiter_video_scanout.vvp

clean: m11b2b-clean

m11b2b-clean:
	rm -f jupiter_video_scanout.vvp

# ============================================================
# Milestone 11B-2c - functional framebuffer line-buffer scanout
# ============================================================

.PHONY: m11b2c-test \
	video-scanout-fetch-test \
	m11b2c-clean

test: m11b2c-test

m11b2c-test: m11b2b-test video-scanout-fetch-test

video-scanout-fetch-test:
	iverilog -g2012 -s jupiter_video_scanout_fetch_tb -o jupiter_video_scanout_fetch.vvp ../rtl/video/jupiter_video_scanout.sv jupiter_video_scanout_fetch_tb.sv
	vvp -n jupiter_video_scanout_fetch.vvp

clean: m11b2c-clean

m11b2c-clean:
	rm -f jupiter_video_scanout_fetch.vvp


# ============================================================
# Milestone 11B-3a - production subsystem scanout integration
# ============================================================

.PHONY: m11b3a-test \
	cpu-display-mmio-test \
	m11b3a-clean

test: m11b3a-test

m11b3a-test: m11b2c-test cpu-display-mmio-test cpu-gpu-mmio-test system-test

cpu-display-mmio-test:
	iverilog -g2012 -s jupiter_cpu_display_mmio_tb -o jupiter_cpu_display_mmio.vvp $(CPU_SUBSYSTEM_RTL) jupiter_cpu_display_mmio_tb.sv
	vvp -n jupiter_cpu_display_mmio.vvp

clean: m11b3a-clean

m11b3a-clean:
	rm -f jupiter_cpu_display_mmio.vvp


# ============================================================
# Milestone 11B-3b - live framebuffer video cutover
# ============================================================

.PHONY: m11b3b-test \
	system-video-test \
	template-video-cutover-test \
	m11b3b-clean

test: m11b3b-test

m11b3b-test: m11b3a-test system-video-test template-video-cutover-test

system-video-test:
	iverilog -g2012 -s jupiter_system_video_tb -o jupiter_system_video.vvp $(SYSTEM_SRCS) jupiter_system_video_tb.sv
	vvp -n jupiter_system_video.vvp

template-video-cutover-test:
	@grep -Fq 'wire [7:0] video_r;' ../Template.sv
	@grep -Fq 'wire [7:0] video_g;' ../Template.sv
	@grep -Fq 'wire [7:0] video_b;' ../Template.sv
	@grep -Fq '.video_r(video_r),' ../Template.sv
	@grep -Fq '.video_g(video_g),' ../Template.sv
	@grep -Fq '.video_b(video_b),' ../Template.sv
	@grep -Fq 'assign VGA_R = video_r;' ../Template.sv
	@grep -Fq 'assign VGA_G = video_g;' ../Template.sv
	@grep -Fq 'assign VGA_B = video_b;' ../Template.sv
	@grep -Fq 'assign CE_PIXEL = ce_pix;' ../Template.sv
	@grep -Fq 'assign VGA_DE = ~(HBlank | VBlank);' ../Template.sv
	@! grep -Fq '.video(video),' ../Template.sv
	@! grep -Fq '? video :' ../Template.sv
	@! grep -Eq '^[[:space:]]*mycore[[:space:]]+video_demo\b' ../rtl/jupiter_system.sv
	@echo 'PASS: Template maps Jupiter RGB888 scanout directly to MiSTer video'

clean: m11b3b-clean

m11b3b-clean:
	rm -f jupiter_system_video.vvp
