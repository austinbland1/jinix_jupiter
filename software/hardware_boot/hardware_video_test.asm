# ============================================================
# Jinix Jupiter HV6-3C physical three-master contention test.
#
# Assemble at 0x00000400.
#
# Result display:
#   GREEN = all phases passed
#   RED   = failure
#
# Failure encoding:
#   RED base plus N * 8 white scanlines at the top,
#   where N is the failure phase (1..8).
#
# Production display framebuffer:
#   0x10000000
#
# Isolated contention test base:
#   0x10040000
#
# Workload:
#   GPU 2D 2x2 render
#   DMA 64-word copy
#   CPU 64 SDRAM store/load pairs
#
# The GPU and DMA are configured first, GPU starts first,
# DMA starts second, then CPU SDRAM traffic begins while both
# engines report BUSY.
# ============================================================


# ============================================================
# Build r1 = 0x10000000 SDRAM / display framebuffer base.
# ============================================================

ADDI r1, r0, 4096

ADD r1, r1, r1
ADD r1, r1, r1
ADD r1, r1, r1
ADD r1, r1, r1

ADD r1, r1, r1
ADD r1, r1, r1
ADD r1, r1, r1
ADD r1, r1, r1

ADD r1, r1, r1
ADD r1, r1, r1
ADD r1, r1, r1
ADD r1, r1, r1

ADD r1, r1, r1
ADD r1, r1, r1
ADD r1, r1, r1
ADD r1, r1, r1

ADD r2, r1, r0


# ============================================================
# Build r9 = 0x10040000 isolated HV6 test base.
#
# 0x00040000 = 4096 << 6.
# ============================================================

ADDI r9, r0, 4096

ADD r9, r9, r9
ADD r9, r9, r9
ADD r9, r9, r9
ADD r9, r9, r9
ADD r9, r9, r9
ADD r9, r9, r9

ADD r9, r1, r9


# ============================================================
# MMIO bases.
#
# r10 = GPU   0x1100
# r11 = DMA   0x1200
# r12 = VIDEO 0x1180
# ============================================================

ADDI r10, r0, 4352
ADDI r11, r0, 4608
ADDI r12, r0, 4480


# ============================================================
# Test-region addresses relative to 0x10040000.
#
# r13 = GPU TILEMAP      +0x0100
# r14 = GPU TILEDATA     +0x0400
# r15 = GPU FRAMEBUFFER  +0x0800
# r16 = DMA SRC          +0x1000
# r17 = DMA DST          +0x1200
# r18 = CPU CONTENTION   +0x1400
# r19 = GUARD HIGH       +0x1500
#
# GUARD LOW is r9 itself.
# ============================================================

ADDI r13, r9, 256
ADDI r14, r9, 1024
ADDI r15, r9, 2048

ADDI r16, r9, 4096
ADDI r17, r16, 512
ADDI r18, r17, 512
ADDI r19, r18, 256


# ============================================================
# Prepare the physical result framebuffer BLACK.
#
# 320 * 240 / 2 = 38400 packed 32-bit stores.
# 75 << 9 = 38400.
#
# Scanout remains disabled during the contention test so it
# does not become an uncontrolled fourth SDRAM master.
# ============================================================

ADD r3, r2, r0

ADDI r29, r0, 75
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29

hv6_initial_black_fill:
STW  r0, r3, 0
ADDI r3, r3, 4
ADDI r29, r29, -1
BNE  r29, r0, hv6_initial_black_fill


# ============================================================
# Program scanout base and geometry, but leave CONTROL = 0.
#
# SIZE = {height=240, width=320} = 0x00F00140.
# ============================================================

STW r2, r12, 8

ADDI r30, r0, 240

ADD r30, r30, r30
ADD r30, r30, r30
ADD r30, r30, r30
ADD r30, r30, r30

ADD r30, r30, r30
ADD r30, r30, r30
ADD r30, r30, r30
ADD r30, r30, r30

ADD r30, r30, r30
ADD r30, r30, r30
ADD r30, r30, r30
ADD r30, r30, r30

ADD r30, r30, r30
ADD r30, r30, r30
ADD r30, r30, r30
ADD r30, r30, r30

ADDI r30, r30, 320
STW  r30, r12, 12
STW  r0, r12, 0


# ============================================================
# PHASE 1 — CPU SDRAM baseline.
# ============================================================

ADDI r25, r0, 1445
STW  r25, r18, 0
LDW  r26, r18, 0

BNE r26, r25, hv6_fail_cpu_baseline


# ============================================================
# Install unrelated-memory guards.
# ============================================================

ADDI r25, r0, 291
STW  r25, r9, 0

ADDI r25, r0, 1110
STW  r25, r19, 0


# ============================================================
# Initialize GPU 2x2 workload.
#
# Four tilemap entries all select tile index 1.
# Tile 1 contains 32 packed words of 0xFFFFFFFF.
# GPU framebuffer begins at zero.
# ============================================================

ADD  r3, r13, r0
ADDI r24, r0, 4
ADDI r25, r0, 1

hv6_gpu_tilemap_init:
STW  r25, r3, 0
ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_gpu_tilemap_init


ADDI r3, r14, 128
ADDI r24, r0, 32
ADDI r25, r0, -1

hv6_gpu_tiledata_init:
STW  r25, r3, 0
ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_gpu_tiledata_init


ADD  r3, r15, r0
ADDI r24, r0, 128

hv6_gpu_framebuffer_zero:
STW  r0, r3, 0
ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_gpu_framebuffer_zero


# ============================================================
# Initialize DMA source 1..64 and destination zero.
# ============================================================

ADD  r3, r16, r0
ADD  r4, r17, r0
ADDI r24, r0, 64
ADDI r25, r0, 1

hv6_dma_memory_init:
STW  r25, r3, 0
STW  r0, r4, 0

ADDI r3, r3, 4
ADDI r4, r4, 4
ADDI r25, r25, 1

ADDI r24, r24, -1
BNE  r24, r0, hv6_dma_memory_init


# ============================================================
# PHASE 2/3 — DMA baseline.
#
# Copy the first four words.
# ============================================================

STW r16, r11, 8
STW r17, r11, 12

ADDI r25, r0, 4
STW  r25, r11, 16

ADDI r21, r0, 1
STW  r21, r11, 0

ADDI r24, r0, 4096
ADD  r24, r24, r24

ADDI r21, r0, 2

hv6_dma_baseline_poll:
LDW r22, r11, 4
BEQ r22, r21, hv6_dma_baseline_done

ADDI r24, r24, -1
BNE  r24, r0, hv6_dma_baseline_poll

J hv6_fail_dma_baseline_timeout

hv6_dma_baseline_done:

ADD  r3, r17, r0
ADDI r24, r0, 4
ADDI r25, r0, 1

hv6_dma_baseline_verify:
LDW r26, r3, 0
BNE r26, r25, hv6_fail_dma_baseline_data

ADDI r3, r3, 4
ADDI r25, r25, 1
ADDI r24, r24, -1
BNE  r24, r0, hv6_dma_baseline_verify


# ============================================================
# PHASE 4/5 — GPU 2D baseline.
#
# Exact proven register layout:
#   +08 TILEMAP
#   +0C TILEDATA
#   +10 FRAMEBUFFER
#   +14 MAP_SIZE
#   +00 CONTROL.START
# ============================================================

STW r13, r10, 8
STW r14, r10, 12
STW r15, r10, 16

ADDI r25, r0, 514
STW  r25, r10, 20

ADDI r21, r0, 1
STW  r21, r10, 0

ADDI r24, r0, 4096
ADD  r24, r24, r24

ADDI r21, r0, 2

hv6_gpu_baseline_poll:
LDW r22, r10, 4
BEQ r22, r21, hv6_gpu_baseline_done

ADDI r24, r24, -1
BNE  r24, r0, hv6_gpu_baseline_poll

J hv6_fail_gpu_baseline_timeout

hv6_gpu_baseline_done:

ADD  r3, r15, r0
ADDI r24, r0, 128
ADDI r25, r0, -1

hv6_gpu_baseline_verify:
LDW r26, r3, 0
BNE r26, r25, hv6_fail_gpu_baseline_data

ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_gpu_baseline_verify


# ============================================================
# Re-arm output regions for the three-master run.
# ============================================================

ADD  r3, r17, r0
ADDI r24, r0, 64

hv6_dma_destination_rezero:
STW  r0, r3, 0
ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_dma_destination_rezero


ADD  r3, r15, r0
ADDI r24, r0, 128

hv6_gpu_framebuffer_rezero:
STW  r0, r3, 0
ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_gpu_framebuffer_rezero


STW r0, r18, 0


# ============================================================
# Configure GPU again.
# ============================================================

STW r13, r10, 8
STW r14, r10, 12
STW r15, r10, 16

ADDI r25, r0, 514
STW  r25, r10, 20


# ============================================================
# Configure full 64-word DMA.
# ============================================================

STW r16, r11, 8
STW r17, r11, 12

ADDI r25, r0, 64
STW  r25, r11, 16


# ============================================================
# PHASE 6 — Start GPU, then DMA.
# Both must report BUSY before CPU contention begins.
# ============================================================

ADDI r21, r0, 1

STW r21, r10, 0
STW r21, r11, 0

LDW r22, r10, 4
LDW r23, r11, 4

BNE r22, r21, hv6_fail_gpu_busy
BNE r23, r21, hv6_fail_dma_busy


# ============================================================
# 64 real CPU SDRAM store/load pairs while both engines run.
# ============================================================

ADDI r24, r0, 64
ADDI r25, r0, 1

hv6_cpu_contention_loop:
STW r25, r18, 0
LDW r26, r18, 0

BNE r26, r25, hv6_fail_cpu_contention

ADDI r25, r25, 1
ADDI r24, r24, -1
BNE  r24, r0, hv6_cpu_contention_loop


# ============================================================
# Bounded GPU completion poll.
# ============================================================

ADDI r24, r0, 4096
ADD  r24, r24, r24
ADDI r21, r0, 2

hv6_gpu_contention_poll:
LDW r22, r10, 4
BEQ r22, r21, hv6_gpu_contention_done

ADDI r24, r24, -1
BNE  r24, r0, hv6_gpu_contention_poll

J hv6_fail_gpu_contention_timeout

hv6_gpu_contention_done:


# ============================================================
# Bounded DMA completion poll.
# ============================================================

ADDI r24, r0, 4096
ADD  r24, r24, r24
ADDI r21, r0, 2

hv6_dma_contention_poll:
LDW r23, r11, 4
BEQ r23, r21, hv6_dma_contention_done

ADDI r24, r24, -1
BNE  r24, r0, hv6_dma_contention_poll

J hv6_fail_dma_contention_timeout

hv6_dma_contention_done:


# ============================================================
# PHASE 7 — Full post-contention integrity.
#
# GPU framebuffer: all 128 words must be 0xFFFFFFFF.
# ============================================================

ADD  r3, r15, r0
ADDI r24, r0, 128
ADDI r25, r0, -1

hv6_gpu_contention_verify:
LDW r26, r3, 0
BNE r26, r25, hv6_fail_gpu_framebuffer_integrity

ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_gpu_contention_verify


# ============================================================
# DMA source and destination must both equal 1..64.
# ============================================================

ADD  r3, r16, r0
ADD  r4, r17, r0
ADDI r24, r0, 64
ADDI r25, r0, 1

hv6_dma_contention_verify:
LDW r26, r3, 0
BNE r26, r25, hv6_fail_dma_source_integrity

LDW r28, r4, 0
BNE r28, r25, hv6_fail_dma_destination_integrity

ADDI r3, r3, 4
ADDI r4, r4, 4
ADDI r25, r25, 1
ADDI r24, r24, -1
BNE  r24, r0, hv6_dma_contention_verify


# ============================================================
# GPU source data must remain intact.
# ============================================================

ADD  r3, r13, r0
ADDI r24, r0, 4
ADDI r25, r0, 1

hv6_tilemap_source_verify:
LDW r26, r3, 0
BNE r26, r25, hv6_fail_tilemap_integrity

ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_tilemap_source_verify


ADDI r3, r14, 128
ADDI r24, r0, 32
ADDI r25, r0, -1

hv6_tiledata_source_verify:
LDW r26, r3, 0
BNE r26, r25, hv6_fail_tiledata_integrity

ADDI r3, r3, 4
ADDI r24, r24, -1
BNE  r24, r0, hv6_tiledata_source_verify


# ============================================================
# Guards and final CPU contention word.
# ============================================================

ADDI r25, r0, 291
LDW  r26, r9, 0
BNE r26, r25, hv6_fail_low_guard_integrity

ADDI r25, r0, 1110
LDW  r26, r19, 0
BNE r26, r25, hv6_fail_high_guard_integrity

ADDI r25, r0, 64
LDW  r26, r18, 0
BNE r26, r25, hv6_fail_final_contention_word


# ============================================================
# PHASE 8 — final independent SDRAM sanity transaction.
# ============================================================

ADDI r25, r0, 777
STW  r25, r18, 0
LDW  r26, r18, 0

BNE r26, r25, hv6_fail_final_cpu_sanity

J hv6_pass


# ============================================================
# Failure phase entry points.
# ============================================================

hv6_fail_cpu_baseline:
ADDI r31, r0, 1
J hv6_fail

hv6_fail_dma_baseline_timeout:
ADDI r31, r0, 2
J hv6_fail

hv6_fail_dma_baseline_data:
ADDI r31, r0, 3
J hv6_fail

hv6_fail_gpu_baseline_timeout:
ADDI r31, r0, 4
J hv6_fail

hv6_fail_gpu_baseline_data:
ADDI r31, r0, 5
J hv6_fail

hv6_fail_gpu_busy:
ADDI r31, r0, 6
J hv6_fail

hv6_fail_dma_busy:
ADDI r31, r0, 7
J hv6_fail

hv6_fail_cpu_contention:
ADDI r31, r0, 8
J hv6_fail

hv6_fail_gpu_contention_timeout:
ADDI r31, r0, 9
J hv6_fail

hv6_fail_dma_contention_timeout:
ADDI r31, r0, 10
J hv6_fail

hv6_fail_gpu_framebuffer_integrity:
ADDI r31, r0, 11
J hv6_fail

hv6_fail_dma_source_integrity:
ADDI r31, r0, 12
J hv6_fail

hv6_fail_dma_destination_integrity:
ADDI r31, r0, 13
J hv6_fail

hv6_fail_tilemap_integrity:
ADDI r31, r0, 14
J hv6_fail

hv6_fail_tiledata_integrity:
ADDI r31, r0, 15
J hv6_fail

hv6_fail_low_guard_integrity:
ADDI r31, r0, 16
J hv6_fail

hv6_fail_high_guard_integrity:
ADDI r31, r0, 17
J hv6_fail

hv6_fail_final_contention_word:
ADDI r31, r0, 18
J hv6_fail

hv6_fail_final_cpu_sanity:
ADDI r31, r0, 19
J hv6_fail



# ============================================================
# PASS — packed RGB565 green 0x07E007E0.
# ============================================================

hv6_pass:

ADDI r28, r0, 2016
ADD  r30, r28, r0

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r28, r28, r30

ADD r3, r2, r0

ADDI r29, r0, 75
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29

hv6_pass_fill:
STW  r28, r3, 0
ADDI r3, r3, 4
ADDI r29, r29, -1
BNE  r29, r0, hv6_pass_fill

J hv6_enable_video


# ============================================================
# FAIL — packed RGB565 red 0xF800F800.
#
# Then overwrite the first phase*8 scanlines WHITE.
# ============================================================

hv6_fail:

ADDI r28, r0, 248

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r30, r28, r0

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28
ADD r28, r28, r28

ADD r28, r28, r30

ADD r3, r2, r0

ADDI r29, r0, 75
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29
ADD r29, r29, r29

hv6_fail_red_fill:
STW  r28, r3, 0
ADDI r3, r3, 4
ADDI r29, r29, -1
BNE  r29, r0, hv6_fail_red_fill


# WHITE signature.
ADDI r28, r0, -1
ADD  r3, r2, r0
ADD  r30, r31, r0

hv6_fail_signature_outer:
ADDI r29, r0, 1280

hv6_fail_signature_inner:
STW  r28, r3, 0
ADDI r3, r3, 4
ADDI r29, r29, -1
BNE  r29, r0, hv6_fail_signature_inner

ADDI r30, r30, -1
BNE  r30, r0, hv6_fail_signature_outer


# ============================================================
# Enable production video only after final framebuffer exists.
# ============================================================

hv6_enable_video:

ADDI r21, r0, 1
STW  r21, r12, 0

HALT
