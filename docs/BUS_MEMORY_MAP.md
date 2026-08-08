# Jinix Jupiter — Internal Bus and Initial Memory Map

## 1. Scope

Milestone 3 establishes Jupiter's first internal transaction mechanism and
initial memory map.

This document defines only the behavior required for Milestone 3. External
SDRAM, DMA arbitration, graphics, audio, and later peripheral mappings are
not implemented here.

## 2. Selected Internal Transaction Protocol

Jupiter adopts the existing Milestone 2 CPU memory transaction interface as
the initial internal transaction protocol.

The CPU therefore connects directly to the Milestone 3 interconnect without
a second CPU-side protocol adapter.

The transaction signals are:

| Signal | Width | Meaning |
| --- | ---: | --- |
| `mem_valid` | 1 | Master request is active |
| `mem_write` | 1 | Write when 1, read when 0 |
| `mem_addr` | 32 | Byte address |
| `mem_wdata` | 32 | Write data |
| `mem_wstrb` | 4 | Byte write enables |
| `mem_rdata` | 32 | Read response data |
| `mem_ready` | 1 | Current transaction completes |

Addresses are byte addresses.

`mem_wstrb[0]` corresponds to bits 7:0, `mem_wstrb[1]` to bits 15:8,
`mem_wstrb[2]` to bits 23:16, and `mem_wstrb[3]` to bits 31:24.

Milestone 2 CPU stores currently generate `4'b1111`. Carrying four byte
strobes through the interconnect leaves room for later masters or ISA
extensions without changing the bus width.

## 3. Transaction Rules

Only one transaction may be outstanding from the Milestone 3 CPU.

A request is active while `mem_valid` is high.

If `mem_ready` is low, the master must keep `mem_write`, `mem_addr`,
`mem_wdata`, and `mem_wstrb` stable.

A transaction completes on a rising clock edge where:

    mem_valid == 1
    mem_ready == 1

For reads, `mem_rdata` is sampled on that completion edge.

Targets may insert wait states by keeping `mem_ready` low. The internal
protocol therefore does not require every target to have identical latency.

Writes take effect only for a completed write transaction.

## 4. Arbitration

The CPU is the only implemented Milestone 3 bus master.

Therefore Milestone 3 requires no arbitration or grant logic. The CPU owns
the transaction path whenever it presents a request.

Adding DMA or another master in a later milestone will require an explicit
documented arbitration policy before that master shares the interconnect.

## 5. Initial Memory Map

| Start | End | Size | Region | M3 status |
| --- | --- | ---: | --- | --- |
| `0x00000000` | `0x00000FFF` | 4 KiB | Internal/test RAM | Implemented in M3 |
| `0x00001000` | `0x00001003` | 4 B | MMIO scratch register | Implemented in M3 |
| `0x10000000` | `0x1FFFFFFF` | 256 MiB window | External SDRAM reservation | Reserved for M4 |

These regions do not overlap.

All addresses not listed as implemented targets are unmapped during
Milestone 3.

The external-SDRAM window is only an address-space reservation. It does not
claim that the eventual hardware contains 256 MiB of physical SDRAM.
Milestone 4 will define the implemented SDRAM capacity and controller
behavior.

Until Milestone 4 provides the SDRAM target, accesses to the reserved SDRAM
window receive the Milestone 3 unmapped-access response.

## 6. Internal/Test RAM

The Milestone 3 internal RAM occupies:

    0x00000000 - 0x00000FFF

It contains 4096 bytes, or 1024 32-bit words.

The region is readable and writable.

Because the Jupiter reset PC is `0x00000000`, the same RAM may contain the
deterministic Milestone 3 test program as well as test data.

This RAM is simulation/integration memory for the current milestone. It is
not a claim about final Jupiter main-memory capacity or FPGA memory usage.

## 7. MMIO Scratch Register

A single 32-bit read/write scratch register is implemented at:

    0x00001000

Reset value:

    0x00000000

Reads return the current register value.

Writes update the enabled byte lanes according to `mem_wstrb`.

The low address is intentional: the current minimal ISA can construct
`0x00001000` directly with its existing `ADDI` instruction, allowing the
Milestone 3 CPU integration program to exercise MMIO without adding an ISA
feature solely for address construction.

Addresses above `0x00001003` are not part of this register.

## 8. Invalid and Unmapped Accesses

Milestone 3 requires deterministic behavior rather than hanging the CPU.

An access is invalid when no implemented target owns its address.

A misaligned 32-bit CPU access is also treated as invalid for Milestone 3.

For an invalid or unmapped read:

    mem_ready = 1
    mem_rdata = 0x00000000

For an invalid or unmapped write:

    mem_ready = 1
    no state is modified

Thus an invalid transaction completes rather than stalling forever.

The reserved external-SDRAM window uses this behavior until Milestone 4
implements its target.

## 9. Milestone 3 Target Selection

The interconnect selects exactly one implemented target for a valid aligned
request:

1. internal RAM for `0x00000000` through `0x00000FFF`;
2. MMIO scratch register for `0x00001000` through `0x00001003`;
3. otherwise the deterministic unmapped response.

Multiple targets must never acknowledge the same transaction.

## 10. Verification Requirements

Milestone 3 simulation must verify at least:

- CPU instruction fetch through the interconnect from internal RAM;
- CPU reads and writes to internal RAM;
- CPU write and readback of the MMIO scratch register;
- correct RAM-versus-MMIO address decoding;
- deterministic unmapped read behavior;
- deterministic unmapped write behavior;
- no overlapping target selection;
- clear automated PASS/FAIL output.

External SDRAM is not required to function during Milestone 3.
