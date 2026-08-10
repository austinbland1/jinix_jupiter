# Jinix Jupiter Milestone 9 minimal BIOS.
#
# Reset execution begins at 0x00000000.
# The selected application entry point is 0x00000400.
#
# J uses a signed word offset relative to PC + 4:
#   (0x00000400 - 0x00000004) / 4 = 255

J 255
