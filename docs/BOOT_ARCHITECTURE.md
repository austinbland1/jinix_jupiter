# Jupiter Milestone 9 Boot and Development-Tool Architecture

## Status

This document records the architecture selected by **M9A** for the minimum
Milestone 9 BIOS and host-development-tool path.

It is intentionally a small deterministic build-to-simulation architecture.
It is not a final cartridge, filesystem, removable-media, runtime HPS-loading,
or firmware-update design.

`docs/ISA_SPEC.md` remains the normative source for Jupiter instruction
encoding and architectural instruction behavior.

---

## 1. Design Goals

The initial Milestone 9 path must make it possible to:

1. write original Jupiter BIOS source;
2. write a small Jupiter application in assembly source;
3. assemble both with host-side Jupiter tooling;
4. construct a deterministic boot/application memory image;
5. start the simulated CPU through the selected BIOS path;
6. transfer from BIOS to the host-built application;
7. execute that application successfully;
8. reject invalid source or invalid image layouts deterministically.

No historical BIOS or firmware is reproduced.

---

## 2. Existing Hardware Constraints

M9A deliberately reuses the verified hardware topology rather than adding a
new boot bus target.

The relevant existing architecture is:

- CPU reset PC: `0x00000000`;
- internal RAM aperture: `0x00000000–0x00000FFF`;
- internal RAM capacity: 4096 bytes / 1024 32-bit words;
- instruction fetches use the ordinary CPU memory transaction path.

Therefore the initial BIOS can begin naturally at the existing reset vector
without changing the CPU reset architecture or interconnect memory map.

---

## 3. Selected Initial Memory Layout

The 4 KiB internal RAM is divided for the minimum M9 build path as follows:

| Address range | Size | Initial M9 purpose |
|---|---:|---|
| `0x00000000–0x000003FF` | 1 KiB | BIOS / boot firmware |
| `0x00000400–0x00000FFF` | 3 KiB | Host-built application |

The selected entry points are:

- BIOS entry: `0x00000000`;
- application entry: `0x00000400`.

The BIOS region therefore contains at most 256 32-bit words.

The application region contains at most 768 32-bit words.

M9 does not claim that this partition is the final Jupiter software-memory
layout.

---

## 4. Initial Boot Process

The initial deterministic boot sequence is:

1. host tools assemble the BIOS;
2. host tools assemble the application;
3. the image builder validates both outputs and constructs one complete
   1024-word internal-RAM image;
4. that generated image initializes Jupiter internal RAM before CPU reset is
   released in the selected simulation path;
5. reset places the CPU PC at `0x00000000`;
6. the CPU fetches and executes the BIOS through the normal memory path;
7. the BIOS performs only intentionally selected minimum startup behavior;
8. the BIOS transfers control to `0x00000400`;
9. the host-built application executes normally.

The minimum BIOS is not required to initialize GPU, audio, DMA, controllers,
SDRAM, a vector table, or any other subsystem unless later M9 work
intentionally adds such behavior.

---

## 5. Firmware Storage and Loading Model

For Milestone 9, the authoritative build artifact is a **1024-word textual
memory-initialization image**.

Each populated line represents one 32-bit Jupiter memory word as exactly eight
hexadecimal digits.

Word order is ascending byte address:

- word 0 -> `0x00000000`;
- word 1 -> `0x00000004`;
- ...
- word 1023 -> `0x00000FFC`.

Unused words are zero-filled by the image builder.

The generated image is a build-time/simulation initialization mechanism.
Changing software therefore requires rebuilding the image.

Runtime firmware replacement, runtime game loading, removable media,
filesystem semantics, and HPS-assisted loading are outside the minimum M9
contract.

---

## 6. Minimum Assembler

The initial assembler lives under `software/devkit/`.

M9A selects a dependency-light Python 3 two-pass assembler because that is
sufficient for the documented ISA and keeps the host dependency surface small.

The assembler must:

- use `docs/ISA_SPEC.md` as the source of truth;
- support the implemented Milestone 2 instruction set;
- accept registers `r0` through `r31`;
- support symbolic labels;
- resolve PC-relative branch/jump targets according to the ISA;
- support decimal and hexadecimal integer literals where an instruction
  operand permits an immediate;
- emit deterministic flat 32-bit word output;
- reject duplicate labels;
- reject unknown labels;
- reject unknown mnemonics;
- reject malformed operands;
- reject invalid register numbers;
- reject immediate/displacement values that cannot be represented by the
  documented encoding;
- exit nonzero on failure and never silently substitute another encoding.

No relocatable object format is selected.

---

## 7. Flat Assembler Output

Assembler output is an ordered textual stream of 32-bit instruction words.

Each instruction is exactly eight hexadecimal digits.

The stream does not contain relocation records, symbols, section tables, or
executable headers.

Placement is supplied explicitly to the system-image builder:

- BIOS stream base: `0x00000000`;
- application stream base: `0x00000400`.

This keeps the first M9 toolchain intentionally smaller than a conventional
assembler/linker toolchain.

---

## 8. System-Image Builder

The image-generation utility lives under `software/tools/`.

It combines the BIOS and application streams into the complete 1024-word
internal-RAM image.

It must deterministically reject:

- a BIOS larger than 256 words;
- an application larger than 768 words;
- content outside the 4 KiB RAM aperture;
- overlapping regions;
- malformed word text;
- non-32-bit word values;
- invalid or non-word-aligned placement.

Successful output is always exactly 1024 words, with unused locations zero.

---

## 9. Initial BIOS Behavior

The minimum valid BIOS may be extremely small.

For M9 acceptance it is sufficient for the BIOS to:

1. begin executing at `0x00000000`;
2. execute valid Jupiter machine code produced by the selected toolchain;
3. transfer control to the application entry at `0x00000400`.

Additional startup behavior must be intentionally specified before it becomes
part of the BIOS contract.

---

## 10. Verification Strategy

Milestone 9 implementation should add automated evidence for:

### Assembler encoding

- golden machine-code checks against `docs/ISA_SPEC.md`;
- forward and backward labels;
- boundary immediates/displacements;
- every selected instruction form.

### Deterministic failures

- unknown instruction;
- invalid register;
- duplicate label;
- unknown label;
- malformed operand count or syntax;
- immediate/displacement overflow.

### Image generation

- exact BIOS placement;
- exact application placement;
- zero padding;
- maximum valid sizes;
- overflow rejection;
- malformed input rejection.

### Boot-to-program execution

An integration simulation must prove that:

1. the generated system image is loaded;
2. reset begins fetch at `0x00000000`;
3. BIOS code executes;
4. control reaches `0x00000400`;
5. a program assembled by the M9 devkit executes successfully;
6. the program reaches a deterministic observable success condition.

The initial success condition may be a register or memory value followed by
`HALT`, provided the test verifies the expected result rather than merely
observing that the CPU stopped.

---

## 11. Planned M9 Checkpoints

### M9A — Architecture selection

This document and related architecture status updates.

### M9B — Minimum host tools

Implemented and verified:

- `software/devkit/jupiter_asm.py`: complete Milestone 2 two-pass assembler;
- symbolic labels with documented `PC + 4` word-relative control flow;
- signed 14-bit immediate/branch and signed 24-bit jump validation;
- deterministic flat eight-hex-digit-per-word output;
- `software/tools/build_system_image.py`: deterministic 1024-word image builder;
- BIOS/application size, alignment, bounds, overlap, and input validation;
- automated tests through `make -C sim m9b-test` and the full regression.

See `docs/HOST_TOOLS.md`.

### M9C — BIOS and boot-image integration

Implemented and verified:

- `software/bios/bios.asm` transfers execution from `0x00000000` to application entry `0x00000400`;
- the M9B tools build the complete 1024-word internal-RAM image;
- `sim/jupiter_boot_image_tb.sv` loads it with `$readmemh` before reset release;
- the loading mechanism is simulation-only and leaves synthesizable RAM/CPU-subsystem RTL unchanged;
- simulation verifies application execution, MMIO scratch write of `42`, and `HALT` at `0x0000040C`;
- `make -C sim m9c-test` deterministically rebuilds and executes the path.

### M9D — End-to-end workflow and acceptance

Verify and document:

- source -> assembler -> image builder -> simulated boot -> application result;
- all Milestone 9 acceptance criteria;
- full repository regression;
- formal M9 closeout.

---

## 12. Deferred Work

M9A does not select or require:

- a C compiler;
- a relocatable linker;
- an object-file ABI;
- a runtime library;
- a graphical debugger;
- an HPS debugger transport;
- runtime HPS firmware loading;
- removable-media or cartridge semantics;
- a filesystem;
- firmware update;
- dynamic executable loading;
- physical-hardware validation.

Those remain available for later milestones.
