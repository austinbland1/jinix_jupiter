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

## M9C Boot Integration

Run `make -C sim m9c-test` to assemble the BIOS at `0x00000000`, assemble the application at `0x00000400`, build the 1024-word image, load it with `$readmemh` before reset release, execute through the normal CPU/interconnect/RAM path, verify the MMIO scratch write of `42`, and verify `HALT` at `0x0000040C`.

Generated `.hex`, `.mem`, and `.vvp` files are temporary build products.

## M9D Reproducible End-to-End Workflow

From the repository root, the canonical Milestone 9 acceptance command is:

```text
make -C sim m9c-test
```

That target performs the complete reproducible path in order:

1. assemble `software/bios/bios.asm` at origin `0x00000000`;
2. assemble `software/bios/test_program.asm` at origin `0x00000400`;
3. build the exact 1024-word system image;
4. validate BIOS/application words, placement, image length, and zero filling;
5. load the generated image into internal RAM before reset release;
6. execute the BIOS through the normal CPU/interconnect/RAM path;
7. transfer to application entry `0x00000400`;
8. verify the application writes `42` to MMIO scratch;
9. verify execution reaches `HALT` at `0x0000040C`.

Expected assembled words are:

```text
BIOS:
320000FF

APPLICATION:
10081000
1010002A
21104000
FF000000
```

Host-tool correctness and deterministic error handling are exercised by `make -C sim m9b-test`. The full repository acceptance regression is `make -C sim test`. Generated `.hex`, `.mem`, and `.vvp` files are temporary and are removed by `make -C sim clean`.

## Boundary

Milestone 9 provides the selected minimum BIOS and host development workflow. It does not add a C compiler, relocatable object format, runtime library, cartridge/filesystem loader, HPS firmware-update transport, or synthesis-time BIOS-storage architecture.
