# Jinix Jupiter Milestone 9 integration application.
#
# Assemble with --origin 0x00000400.
# Prove BIOS transfer reached host-built application code by writing 42
# to the existing MMIO scratch register at 0x00001000, then halt.

ADDI r1, r0, 4096
ADDI r2, r0, 42
STW  r2, r1, 0
HALT
