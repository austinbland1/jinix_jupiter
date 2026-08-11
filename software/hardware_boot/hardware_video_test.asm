# Jinix Jupiter first deterministic physical-video test.
#
# Assemble at 0x00000400.
#
# Fill a 320x240 RGB565 framebuffer at 0x10000000 with
# bright green (RGB565 0x07E0), then configure production
# framebuffer scanout and halt.

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

ADDI r3, r0, 2016
ADD  r4, r3, r0

ADD r3, r3, r3
ADD r3, r3, r3
ADD r3, r3, r3
ADD r3, r3, r3

ADD r3, r3, r3
ADD r3, r3, r3
ADD r3, r3, r3
ADD r3, r3, r3

ADD r3, r3, r3
ADD r3, r3, r3
ADD r3, r3, r3
ADD r3, r3, r3

ADD r3, r3, r3
ADD r3, r3, r3
ADD r3, r3, r3
ADD r3, r3, r3

ADD r3, r3, r4

ADDI r5, r0, 75

ADD r5, r5, r5
ADD r5, r5, r5
ADD r5, r5, r5

ADD r5, r5, r5
ADD r5, r5, r5
ADD r5, r5, r5

ADD r5, r5, r5
ADD r5, r5, r5
ADD r5, r5, r5

fill_loop:
STW  r3, r1, 0
ADDI r1, r1, 4
ADDI r5, r5, -1
BNE  r5, r0, fill_loop

ADDI r6, r0, 4480

STW r2, r6, 8

ADDI r7, r0, 240

ADD r7, r7, r7
ADD r7, r7, r7
ADD r7, r7, r7
ADD r7, r7, r7

ADD r7, r7, r7
ADD r7, r7, r7
ADD r7, r7, r7
ADD r7, r7, r7

ADD r7, r7, r7
ADD r7, r7, r7
ADD r7, r7, r7
ADD r7, r7, r7

ADD r7, r7, r7
ADD r7, r7, r7
ADD r7, r7, r7
ADD r7, r7, r7

ADDI r7, r7, 320

STW r7, r6, 12

ADDI r8, r0, 1
STW  r8, r6, 0

HALT
