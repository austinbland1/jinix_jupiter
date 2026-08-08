# Jinix Jupiter — ISA Specification

## 1. Scope

This document defines the instruction-set subset implemented during
Milestone 2 of Jinix Jupiter.

Milestone 2 establishes the smallest useful custom 32-bit RISC CPU capable
of executing a deterministic test program containing:

- register-register arithmetic and logic;
- immediate arithmetic;
- memory loads and stores;
- conditional branches;
- unconditional control flow;
- deterministic program termination.

This document is the architectural contract for the Milestone 2 CPU RTL.

Features not explicitly defined here are not part of the Milestone 2 ISA.

## 2. Architectural State

The Milestone 2 CPU contains:

- 32 general-purpose 32-bit registers, `r0` through `r31`;
- one 32-bit program counter (`PC`);
- a halted execution state.

### 2.1 General-Purpose Registers

`r0` is permanently hardwired to zero.

Reads of `r0` always return:

    0x00000000

Writes targeting `r0` are discarded.

Registers `r1` through `r31` are ordinary 32-bit general-purpose registers.

The ISA does not assign stack-pointer, link-register, frame-pointer, or other
ABI meanings to any register during Milestone 2.

### 2.2 Program Counter

`PC` contains the byte address of the current instruction.

Instructions are 32 bits wide and must be aligned to a 4-byte boundary.

Normal sequential execution advances:

    PC = PC + 4

There are no branch delay slots.

### 2.3 Reset State

The Milestone 2 CPU uses synchronous active-high reset.

When reset is sampled high on a rising clock edge:

- `PC` becomes `0x00000000`;
- `r1` through `r31` become zero;
- `r0` remains zero;
- any in-progress CPU memory transaction is abandoned;
- the CPU leaves the halted state;
- execution restarts with an instruction fetch from address zero.

## 3. Data and Address Model

Jupiter uses a 32-bit byte-addressed address space.

Memory byte order is little-endian.

For a 32-bit word stored at address `A`:

- bits 7:0 are stored at `A + 0`;
- bits 15:8 are stored at `A + 1`;
- bits 23:16 are stored at `A + 2`;
- bits 31:24 are stored at `A + 3`.

Milestone 2 defines only aligned 32-bit word loads and stores.

Programs using `LDW` or `STW` must provide addresses for which:

    address[1:0] == 2'b00

Misaligned accesses are outside the defined Milestone 2 ISA subset.

## 4. Instruction Encoding

Every instruction is exactly 32 bits.

Bits 31:24 contain an 8-bit opcode.

The remaining fields depend on the instruction format.

### 4.1 R Format

Used for register-register ALU instructions.

| Bits | Field | Meaning |
| --- | --- | --- |
| 31:24 | opcode | Instruction opcode |
| 23:19 | rd | Destination register |
| 18:14 | rs1 | First source register |
| 13:9 | rs2 | Second source register |
| 8:0 | reserved | Must be encoded as zero |

Conceptually:

    opcode | rd | rs1 | rs2 | 000000000
       8      5     5     5       9

### 4.2 I Format

Used for immediate arithmetic and loads.

| Bits | Field | Meaning |
| --- | --- | --- |
| 31:24 | opcode | Instruction opcode |
| 23:19 | rd | Destination register |
| 18:14 | rs1 | Source/base register |
| 13:0 | imm14 | Signed 14-bit immediate |

`imm14` is sign-extended to 32 bits before use.

### 4.3 S Format

Used for stores.

| Bits | Field | Meaning |
| --- | --- | --- |
| 31:24 | opcode | Instruction opcode |
| 23:19 | rs2 | Register containing store data |
| 18:14 | rs1 | Base-address register |
| 13:0 | imm14 | Signed 14-bit byte offset |

### 4.4 B Format

Used for conditional branches.

| Bits | Field | Meaning |
| --- | --- | --- |
| 31:24 | opcode | Instruction opcode |
| 23:19 | rs1 | First comparison register |
| 18:14 | rs2 | Second comparison register |
| 13:0 | off14 | Signed 14-bit word offset |

The branch displacement is multiplied by four before being added to the
sequential next PC.

Taken branch target:

    PC + 4 + (sign_extend(off14) << 2)

### 4.5 J Format

Used for unconditional PC-relative jumps.

| Bits | Field | Meaning |
| --- | --- | --- |
| 31:24 | opcode | Instruction opcode |
| 23:0 | off24 | Signed 24-bit word offset |

Jump target:

    PC + 4 + (sign_extend(off24) << 2)

### 4.6 N Format

Used for instructions without register or immediate operands.

| Bits | Field | Meaning |
| --- | --- | --- |
| 31:24 | opcode | Instruction opcode |
| 23:0 | reserved | Must be encoded as zero |

## 5. Milestone 2 Opcode Table

| Opcode | Mnemonic | Format | Operation |
| --- | --- | --- | --- |
| `0x00` | `NOP` | N | No operation |
| `0x01` | `ADD` | R | `rd = rs1 + rs2` |
| `0x02` | `SUB` | R | `rd = rs1 - rs2` |
| `0x03` | `AND` | R | `rd = rs1 & rs2` |
| `0x04` | `OR` | R | `rd = rs1 | rs2` |
| `0x05` | `XOR` | R | `rd = rs1 ^ rs2` |
| `0x10` | `ADDI` | I | `rd = rs1 + sign_extend(imm14)` |
| `0x20` | `LDW` | I | Load aligned 32-bit word |
| `0x21` | `STW` | S | Store aligned 32-bit word |
| `0x30` | `BEQ` | B | Branch when `rs1 == rs2` |
| `0x31` | `BNE` | B | Branch when `rs1 != rs2` |
| `0x32` | `J` | J | Unconditional PC-relative jump |
| `0xFF` | `HALT` | N | Stop instruction execution |

All other opcodes are reserved for future ISA expansion.

Behavior of reserved opcodes is not architecturally defined during
Milestone 2 and test programs must not execute them.

## 6. Instruction Semantics

### 6.1 NOP

`NOP` changes no architectural register state.

Execution continues at:

    PC + 4

### 6.2 ADD

    rd = rs1 + rs2

Addition is modulo 2^32.

No arithmetic flags are generated.

### 6.3 SUB

    rd = rs1 - rs2

Subtraction is modulo 2^32.

No arithmetic flags are generated.

### 6.4 AND

    rd = rs1 & rs2

Performs a bitwise AND.

### 6.5 OR

    rd = rs1 | rs2

Performs a bitwise OR.

### 6.6 XOR

    rd = rs1 ^ rs2

Performs a bitwise XOR.

### 6.7 ADDI

    rd = rs1 + sign_extend(imm14)

The 14-bit immediate is interpreted as a signed two's-complement value and
sign-extended to 32 bits.

Arithmetic wraps modulo 2^32.

### 6.8 LDW

Effective address:

    address = rs1 + sign_extend(imm14)

The CPU reads one aligned 32-bit little-endian word from `address` and writes
the returned value to `rd`.

If `rd` is `r0`, the memory transaction still occurs but the returned value
is discarded.

### 6.9 STW

Effective address:

    address = rs1 + sign_extend(imm14)

The CPU writes the complete 32-bit value from `rs2` to the aligned word at
`address`.

### 6.10 BEQ

If:

    rs1 == rs2

then:

    PC = PC + 4 + (sign_extend(off14) << 2)

otherwise:

    PC = PC + 4

### 6.11 BNE

If:

    rs1 != rs2

then:

    PC = PC + 4 + (sign_extend(off14) << 2)

otherwise:

    PC = PC + 4

### 6.12 J

Execution continues at:

    PC = PC + 4 + (sign_extend(off24) << 2)

`J` does not write a link register.

Subroutine-call conventions are outside Milestone 2.

### 6.13 HALT

`HALT` places the CPU into its halted state.

After entering the halted state:

- no additional instructions are fetched;
- no new memory transactions are initiated;
- architectural register state remains unchanged;
- the CPU remains halted until reset.

The CPU RTL exposes this state to the simulation environment so deterministic
program completion can be detected.

## 7. CPU Memory Interface

Milestone 2 defines a simple CPU-facing transaction interface.

This is not yet the final Jupiter system-bus protocol. Milestone 3 may place
an interconnect or adapter between this CPU interface and other system blocks.

The CPU interface consists conceptually of:

| Signal | Direction | Width | Meaning |
| --- | --- | ---: | --- |
| `mem_valid` | CPU output | 1 | Transaction request is active |
| `mem_write` | CPU output | 1 | 1 for write, 0 for read |
| `mem_addr` | CPU output | 32 | Byte address |
| `mem_wdata` | CPU output | 32 | Write data |
| `mem_wstrb` | CPU output | 4 | Byte write enables |
| `mem_rdata` | CPU input | 32 | Read response data |
| `mem_ready` | CPU input | 1 | Current transaction completes |

The same interface is used for:

- instruction fetches;
- `LDW`;
- `STW`.

Milestone 2 permits only one outstanding transaction at a time.

### 7.1 Request/Completion Rules

A transaction begins when the CPU asserts:

    mem_valid = 1

The CPU must keep the request information stable while `mem_valid` is high
and `mem_ready` is low.

The transaction completes on a rising clock edge for which both are high:

    mem_valid == 1
    mem_ready == 1

For a read transaction, `mem_rdata` is sampled on that completion edge.

After completion, the CPU may deassert `mem_valid` or begin the next
transaction as allowed by its implementation state machine.

### 7.2 Instruction Fetch

Instruction fetch is a read transaction with:

    mem_write = 0
    mem_addr  = PC
    mem_wstrb = 4'b0000

The returned 32-bit word is interpreted according to the instruction formats
defined in this document.

### 7.3 LDW Transaction

`LDW` uses:

    mem_write = 0
    mem_addr  = effective_address
    mem_wstrb = 4'b0000

### 7.4 STW Transaction

`STW` uses:

    mem_write = 1
    mem_addr  = effective_address
    mem_wdata = value_from_rs2
    mem_wstrb = 4'b1111

Partial-width stores are not defined during Milestone 2.

## 8. Control-Flow Model

All branches and jumps are PC-relative.

There are no delay slots.

Branch targets are relative to `PC + 4`.

Instruction addresses must remain 4-byte aligned.

The Milestone 2 ISA does not provide indirect jumps, calls, returns, or link
instructions.

Those may be introduced by a later ISA revision if required.

## 9. Interrupts, Exceptions, and Privilege

Milestone 2 defines:

- no interrupt architecture;
- no exception-vector architecture;
- no privilege levels;
- no supervisor mode;
- no system-call instruction.

Programs used for Milestone 2 verification must contain only defined
instructions and aligned accesses.

Exception and interrupt behavior may be added by a later documented ISA
revision.

## 10. Implementation Freedom

The ISA does not mandate whether the CPU is:

- single-cycle;
- multi-cycle;
- pipelined;
- microcoded;
- implemented using another simple internal organization.

The Milestone 2 implementation is expected to favor clarity and deterministic
simulation over performance.

The implementation must produce the architectural behavior specified here.

## 11. Explicit Milestone 2 Non-Features

The Milestone 2 CPU does not require:

- caches;
- branch prediction;
- speculative execution;
- out-of-order execution;
- register bypass/forwarding;
- multiplication or division;
- floating-point arithmetic;
- SIMD;
- atomic instructions;
- byte or halfword loads/stores;
- unaligned memory access;
- virtual memory;
- privilege levels;
- interrupts;
- exception vectors;
- a final system-bus implementation;
- a final hardware clock frequency.

## 12. Required Milestone 2 Verification Categories

The deterministic Milestone 2 program must demonstrate at least:

1. `ADD`
2. `SUB`
3. `AND`
4. `OR`
5. `XOR`
6. `ADDI`
7. `LDW`
8. `STW`
9. a taken conditional branch
10. a not-taken conditional branch
11. `J`
12. `HALT`

Verification must demonstrate that:

- register results match expected values;
- `r0` remains zero;
- memory reads return expected values;
- memory writes contain expected values;
- taken and untaken control flow behave as documented;
- the program reaches `HALT`;
- automated simulation reports pass or fail.

## 13. Future ISA Revisions

Later milestones may extend the ISA.

Any extension that changes architectural behavior must update this document
before or together with the corresponding RTL implementation.

Existing Milestone 2 instruction encodings should not be changed casually
once software begins depending on them.
