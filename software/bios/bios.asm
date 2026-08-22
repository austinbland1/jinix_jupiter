# Jinix Jupiter Milestone 9 minimal BIOS.
#
# Reset execution begins at 0x00000000.
# The selected application entry point is 0x00000400.
#
# J uses a signed word offset relative to PC + 4:
#   (0x00000400 - 0x00000004) / 4 = 255

J m12e_cartridge_handoff
J 255

# M12E exact existing-ISA add-doubling cartridge handoff.
m12e_cartridge_handoff:
    ADDI r20, r0, 0x1500

m12e_wait_loader_done:
    LDW r21, r20, 0
    ADDI r22, r0, 1
    AND r22, r21, r22
    BEQ r22, r0, m12e_wait_loader_done

    LDW r21, r20, 0
    ADDI r22, r0, 2
    AND r22, r21, r22
    BNE r22, r0, m12e_cartridge_error

    LDW r23, r20, 8
    LDW r24, r23, 0

    ADDI r25, r0, 0x31
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADDI r27, r0, 0x50
    ADD r25, r25, r27
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADDI r27, r0, 0x55
    ADD r25, r25, r27
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADD r25, r25, r25
    ADDI r27, r0, 0x4A
    ADD r25, r25, r27

    BNE r24, r25, m12e_cartridge_error

    LDW r24, r23, 12
    ADD r24, r23, r24
    JMPR r0, r24, 0

m12e_cartridge_error:
    J m12e_cartridge_error
