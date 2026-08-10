# Jupiter Host Development Tools

## M9B Status

Milestone 9B implements the minimum host tools selected by `docs/BOOT_ARCHITECTURE.md`.

## Assembler

Tool: `software/devkit/jupiter_asm.py`

Example:

```text
python3 software/devkit/jupiter_asm.py program.asm -o program.hex --origin 0x400
```

The assembler supports the complete Milestone 2 ISA, registers `r0` through `r31`, symbolic labels, `#` and `;` comments, signed 14-bit immediates/branch offsets, and signed 24-bit jump offsets. Symbolic branches and jumps use the documented word-relative displacement from `PC + 4`.

Output is one 32-bit instruction per line as exactly eight hexadecimal digits. Invalid syntax, registers, labels, mnemonics, operands, or out-of-range values cause a nonzero exit.

## System Image Builder

Tool: `software/tools/build_system_image.py`

Example:

```text
python3 software/tools/build_system_image.py --bios bios.hex --app program.hex --output system.mem
```

Default placement:

- BIOS: `0x00000000`, maximum 256 words
- application: `0x00000400`, maximum 768 words

Successful output is exactly 1024 words with unused locations zero-filled. The builder rejects malformed words, misaligned or out-of-range bases, overflow, and overlapping BIOS/application content.

## Tests

Focused regression:

```text
make -C sim m9b-test
```

Full regression:

```text
make -C sim test
```

## Boundary

M9B implements source-to-word assembly and system-image construction. BIOS source, boot-image loading, BIOS execution, and BIOS-to-application transfer are M9C/M9D work.
