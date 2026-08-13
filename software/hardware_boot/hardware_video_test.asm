# ============================================================
# Jinix Jupiter HV7 physical raw-controller visualizer.
#
# Assemble at 0x00000400.
#
# End-to-end physical purpose:
#
#   physical controller
#       -> MiSTer hps_io joystick_N[31:0]
#       -> Template.sv
#       -> jupiter_system
#       -> jupiter_cpu_subsystem
#       -> jupiter_controllers MMIO
#       -> Jupiter CPU LDW
#       -> external-SDRAM framebuffer
#       -> physical video
#
# No semantic button mapping is assumed.
#
# MMIO:
#
#   controller 0 = 0x00001400
#   controller 1 = 0x00001404
#   controller 2 = 0x00001408
#   controller 3 = 0x0000140C
#   controller 4 = 0x00001410
#   controller 5 = 0x00001414
#
# Display:
#
#   320 x 240 RGB565
#   32 columns x 6 rows
#   one bit cell = 10 x 40 pixels
#
#   clear bit = black
#   set bit   = green
#
# The first complete frame is drawn while scanout is disabled.
# Video is enabled only after that frame exists.
# Thereafter all six controller words are continuously repolled
# and the entire 192-cell display is refreshed.
# ============================================================


# ============================================================
# r1 = production framebuffer 0x10000000.
#
# Begin with 0x00001000 and shift left 16 by doubling.
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


# ============================================================
# r3  = video MMIO base       0x00001180
# r18 = controller MMIO base  0x00001400
# ============================================================

ADDI r3,  r0, 4480
ADDI r18, r0, 5120


# ============================================================
# r4 = packed green RGB565 = 0x07E007E0.
#
# r5 retains 0x000007E0.
# ============================================================

ADDI r4, r0, 2016
ADD  r5, r4, r0

ADD r4, r4, r4
ADD r4, r4, r4
ADD r4, r4, r4
ADD r4, r4, r4

ADD r4, r4, r4
ADD r4, r4, r4
ADD r4, r4, r4
ADD r4, r4, r4

ADD r4, r4, r4
ADD r4, r4, r4
ADD r4, r4, r4
ADD r4, r4, r4

ADD r4, r4, r4
ADD r4, r4, r4
ADD r4, r4, r4
ADD r4, r4, r4

ADD r4, r4, r5


# ============================================================
# r15 = one controller-row framebuffer increment.
#
# 320 pixels * 2 bytes/pixel * 40 scanlines = 25600 bytes.
#
# 100 << 8 = 25600.
# ============================================================

ADDI r15, r0, 100

ADD r15, r15, r15
ADD r15, r15, r15
ADD r15, r15, r15
ADD r15, r15, r15

ADD r15, r15, r15
ADD r15, r15, r15
ADD r15, r15, r15
ADD r15, r15, r15


# ============================================================
# r19 = video SIZE = {height=240,width=320}
#     = 0x00F00140.
# ============================================================

ADDI r19, r0, 240

ADD r19, r19, r19
ADD r19, r19, r19
ADD r19, r19, r19
ADD r19, r19, r19

ADD r19, r19, r19
ADD r19, r19, r19
ADD r19, r19, r19
ADD r19, r19, r19

ADD r19, r19, r19
ADD r19, r19, r19
ADD r19, r19, r19
ADD r19, r19, r19

ADD r19, r19, r19
ADD r19, r19, r19
ADD r19, r19, r19
ADD r19, r19, r19

ADDI r19, r19, 320


# ============================================================
# Configure production scanout but keep CONTROL=0 initially.
# ============================================================

STW r1,  r3, 8
STW r19, r3, 12
STW r0,  r3, 0


# ============================================================
# r20 = video-enabled flag.
# ============================================================

ADDI r20, r0, 0


# ============================================================
# Draw one complete 320x240 controller frame.
# ============================================================

hv7_frame_loop:

# r6  = framebuffer base for current controller row.
# r18 = controller MMIO pointer.
# r14 = six controller ports.

ADD  r6,  r1, r0
ADDI r18, r0, 5120
ADDI r14, r0, 6


hv7_controller_loop:

# Read exact raw current 32-bit controller word.

LDW r9, r18, 0

# r7  = current bit-cell base.
# r10 = one-hot bit mask.
# r24 = bit count.

ADD  r7,  r6, r0
ADDI r10, r0, 1
ADDI r24, r0, 32


hv7_bit_loop:

# r11 = state & mask.
# r12 = packed cell color.

AND r11, r9, r10

ADD r12, r0, r0
BEQ r11, r0, hv7_color_ready

ADD r12, r4, r0


hv7_color_ready:

# Fill one 10 x 40 pixel cell.
#
# RGB565 is packed two pixels per 32-bit word.
# Five stores therefore cover exactly 10 horizontal pixels.
#
# r8  = drawing pointer.
# r13 = 40 scanlines.

ADD  r8,  r7, r0
ADDI r13, r0, 40


hv7_cell_scanline_loop:

STW r12, r8, 0
STW r12, r8, 4
STW r12, r8, 8
STW r12, r8, 12
STW r12, r8, 16

# One physical scanline = 320 * 2 = 640 bytes.

ADDI r8, r8, 640

ADDI r13, r13, -1
BNE  r13, r0, hv7_cell_scanline_loop


# Next 10-pixel bit cell = 20 framebuffer bytes.

ADDI r7, r7, 20

# Next raw controller bit.

ADD r10, r10, r10

ADDI r24, r24, -1
BNE  r24, r0, hv7_bit_loop


# Next controller row and next raw controller MMIO word.

ADD  r6,  r6, r15
ADDI r18, r18, 4

ADDI r14, r14, -1
BNE  r14, r0, hv7_controller_loop


# ============================================================
# One complete six-port / 192-bit frame now exists.
#
# This label is also used as a deterministic simulation
# checkpoint. The first arrival occurs before scanout has been
# enabled.
# ============================================================

hv7_frame_complete:

BNE r20, r0, hv7_frame_loop

# Enable production video exactly once, after initial frame.

ADDI r20, r0, 1
STW  r20, r3, 0

J hv7_frame_loop
