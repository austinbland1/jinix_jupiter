# Jupiter External SDRAM Architecture

## 1. Scope

Milestone 4 establishes Jupiter's external SDRAM architecture.

This document records:

- verified MiSTer-facing SDRAM interfaces available to Jupiter;
- the distinction between external SDR SDRAM and the HPS DDR3 path;
- the selected Jupiter Milestone 4 controller architecture;
- the CPU-visible SDRAM address region;
- installed-memory-size handling;
- transaction width conversion;
- initialization and refresh responsibilities;
- arbitration and scheduling rules for Milestone 4;
- simulation requirements.

Milestone 4 prioritizes functional correctness and deterministic simulation.

It does not claim Quartus timing closure, FPGA resource usage, a final SDRAM
clock frequency, or successful operation on physical hardware unless those
results are actually obtained separately.

## 2. Verified MiSTer Framework Facts

### 2.1 Primary External SDRAM Interface

`sys/emu_ports.vh` exposes a primary low-latency SDRAM interface to the
`emu` module.

The interface consists of:

- `SDRAM_CLK`
- `SDRAM_CKE`
- `SDRAM_A[12:0]`
- `SDRAM_BA[1:0]`
- `SDRAM_DQ[15:0]`
- `SDRAM_DQML`
- `SDRAM_DQMH`
- `SDRAM_nCS`
- `SDRAM_nCAS`
- `SDRAM_nRAS`
- `SDRAM_nWE`

This is a direct physical SDR SDRAM-style interface rather than a
transaction-level memory service supplied to the core.

The current `Template.sv` does not use this interface. It drives the external
SDRAM signals to high impedance as part of the template's unused-port
defaults.

Milestone 4 will eventually replace that unused-port treatment with
Jupiter-controlled SDRAM signals when the controller reaches top-level
integration.

### 2.2 Primary SDRAM Pin Assignments

`sys/sys.tcl` contains the MiSTer framework's primary SDRAM FPGA pin
assignments.

It also applies framework-level electrical and I/O implementation properties
to the primary SDRAM signals, including:

- 3.3-V LVTTL I/O standard;
- maximum output-current setting;
- fast output registers;
- fast output-enable registers for `SDRAM_DQ`;
- fast input registers for `SDRAM_DQ`;
- SDRAM-specific synchronous-control restrictions.

These assignments belong to the MiSTer framework.

Jupiter must not duplicate or replace these physical pin assignments merely
to implement its memory controller.

### 2.3 Secondary SDRAM

The framework contains conditional support for a second SDRAM interface when
`MISTER_DUAL_SDRAM` is defined.

`sys/sys_dual_sdram.tcl` contains the secondary SDRAM pin assignments and
enables the `MISTER_DUAL_SDRAM` macro.

Milestone 4 does not select dual-SDRAM operation.

Jupiter will initially use only the primary `SDRAM_*` interface.

Secondary SDRAM may be reconsidered in a later milestone if an implemented
feature creates a demonstrated need for it.

### 2.4 HPS DDR3 Is a Separate Memory Path

`sys/emu_ports.vh` also exposes a `DDRAM_*` transaction interface.

The framework describes this interface as the high-latency DDR3 RAM path for
non-critical-time use.

That interface is separate from the lower-latency external `SDRAM_*` pins
selected for Jupiter Milestone 4.

The `sys/sysmem.sv` and `f2sdram_safe_terminator.sv` sources concern the
FPGA-to-HPS SDRAM/DDR controller interfaces used by the MiSTer framework.

They are not selected as Jupiter's external SDR SDRAM controller.

Jupiter Milestone 4 therefore requires Jupiter-owned controller RTL under
`rtl/memory/`.

### 2.5 Installed SDRAM Size Reporting

`hps_io` provides `sdram_sz[15:0]`.

The framework documents:

- bit 15: size information is set/valid;
- bits 1:0 = 0: no external SDRAM;
- bits 1:0 = 1: 32 MiB;
- bits 1:0 = 2: 64 MiB;
- bits 1:0 = 3: 128 MiB.

Milestone 4 will use this information to determine the CPU-visible usable
portion of Jupiter's SDRAM aperture.

The current template does not yet consume `sdram_sz`.

Connecting it is a later Milestone 4 integration change.

## 3. Selected Milestone 4 Architecture

Jupiter will implement its own external-SDRAM controller/interface under
`rtl/memory/`.

The controller will have two conceptual sides:

1. Jupiter transaction side
2. physical SDR SDRAM side

The Jupiter side will preserve the transaction mechanism established in
Milestone 3.

The physical side will drive the primary MiSTer `SDRAM_*` signals.

No HPS CPU or HPS DDR3 memory service will execute Jupiter game-memory
transactions on behalf of the Jupiter CPU.

## 4. Jupiter Transaction Side

The SDRAM target will use the existing Milestone 3 transaction semantics:

- 32-bit byte address;
- 32-bit read data;
- 32-bit write data;
- four byte write strobes;
- `valid`;
- `write`;
- `ready`;
- one outstanding CPU transaction.

The CPU must not require a new load/store instruction or a separate
SDRAM-specific bus operation.

The interconnect will select the external-memory target based solely on the
documented system memory map.

The SDRAM target may hold `ready` low while a physical SDRAM operation is in
progress.

The CPU already supports such wait states.

## 5. Physical Data Width Conversion

The MiSTer-facing external SDRAM data bus is 16 bits wide while Jupiter's
current CPU transaction width is 32 bits.

Milestone 4 therefore selects explicit 32-to-16-bit width conversion.

A normal aligned Jupiter 32-bit access consists logically of two 16-bit SDRAM
halves:

1. low halfword: Jupiter bits 15:0;
2. high halfword: Jupiter bits 31:16.

For writes:

- `wstrb[0]` controls the low byte of the low 16-bit transfer;
- `wstrb[1]` controls the high byte of the low 16-bit transfer;
- `wstrb[2]` controls the low byte of the high 16-bit transfer;
- `wstrb[3]` controls the high byte of the high 16-bit transfer.

For reads, the two returned 16-bit halves are combined into one 32-bit
Jupiter response before `ready` completes the CPU transaction.

The exact SDRAM row/bank/column address transformation will be defined with
the controller implementation and supported module-size geometry.

It must not be guessed independently of the physical SDRAM organization.

## 6. CPU-Visible SDRAM Address Region

Milestone 3 reserved:

    0x10000000 - 0x1FFFFFFF

as a provisional 256 MiB external-memory window.

Milestone 4 narrows the implemented maximum SDRAM aperture to:

    0x10000000 - 0x17FFFFFF

which represents a maximum of 128 MiB and matches the largest SDRAM size
reported through the current MiSTer `sdram_sz` interface.

The usable range depends on detected SDRAM size:

| Reported size | CPU-visible usable range |
|---|---|
| none | no implemented external-memory addresses |
| 32 MiB | `0x10000000` - `0x11FFFFFF` |
| 64 MiB | `0x10000000` - `0x13FFFFFF` |
| 128 MiB | `0x10000000` - `0x17FFFFFF` |

Addresses inside the maximum aperture but beyond installed capacity must not
silently alias lower physical memory.

They will receive deterministic invalid/unavailable-memory behavior.

The unused remainder of the former Milestone 3 reservation:

    0x18000000 - 0x1FFFFFFF

returns to unmapped address space in Milestone 4 unless assigned by a later
documented architecture decision.

## 7. Deterministic Unavailable-Memory Behavior

If external SDRAM is absent, its size has not been reported as valid, or a
transaction addresses memory beyond the installed capacity, the operation
must complete deterministically rather than hanging the CPU.

For Milestone 4:

- unavailable reads complete and return `0x00000000`;
- unavailable writes complete with no state change.

This extends the deterministic invalid-access philosophy established in
Milestone 3.

## 8. Controller Organization

The first Jupiter SDRAM controller is correctness-oriented rather than
performance-oriented.

Milestone 4 does not require:

- pipelining;
- multiple outstanding transactions;
- high-performance burst scheduling;
- bank-interleaving optimization;
- request reordering;
- caches;
- speculative accesses.

The initial implementation may serialize physical operations.

A CPU transaction remains outstanding until both required 16-bit halves of a
32-bit access have completed.

Performance optimization belongs after functional correctness has been
demonstrated.

## 9. SDRAM Initialization and Maintenance

The Jupiter controller is responsible for all physical SDRAM initialization
and maintenance required by the selected SDR SDRAM organization.

This includes an initialization sequence and periodic refresh behavior.

The implementation must keep initialization and refresh timing expressed in a
way that is derived from the selected controller clock and documented timing
parameters.

Milestone 4 must not invent a physical-memory timing guarantee merely from
simulation success.

Exact clock frequency, clock phase relationship, and final timing parameters
are implementation decisions that must be established before hardware claims
are made.

## 10. Refresh Scheduling Policy

The CPU is the only Jupiter transaction master implemented during
Milestone 4.

Therefore no multi-master transaction arbiter is required in this milestone.

Refresh is controller maintenance rather than a second external bus master.

The selected scheduling rule is:

- an already-started Jupiter 32-bit transaction completes as one logical
  transaction;
- a pending required refresh is serviced before accepting the next CPU
  transaction;
- while refresh is executing, the SDRAM target keeps the CPU request stalled
  by withholding `ready`;
- after refresh completes, normal CPU transactions resume.

Simulation must demonstrate that sustained CPU activity does not permanently
starve required refresh operations.

## 11. DMA and Future Masters

Milestone 4 does not implement the Jupiter DMA engine.

No artificial DMA master is required merely to create an arbitration problem
that does not yet exist.

When DMA is implemented in a later milestone, the SDRAM request architecture
and arbitration policy must be extended and documented before CPU and DMA
share the external-memory controller.

## 12. Simulation Strategy

Milestone 4 simulation will be built incrementally.

The intended verification layers are:

1. SDRAM target/interface transaction behavior;
2. 32-bit Jupiter to 16-bit physical-transfer conversion;
3. behavioral SDRAM storage model;
4. initialization behavior;
5. refresh scheduling/maintenance behavior;
6. repeated and sustained read/write integrity tests;
7. CPU-visible integration through the Milestone 3 interconnect;
8. installed-size and out-of-range behavior.

All tests must produce deterministic automated PASS/FAIL output.

A simulation behavioral model is verification infrastructure and is not a
claim that a particular FPGA SDRAM timing implementation has been proven on
hardware.

## 13. Milestone 4 Integration Boundary

Milestone 4 will eventually require changes above the controller itself.

Expected later integration work includes:

- adding the SDRAM target to `jupiter_interconnect`;
- connecting `sdram_sz` from `hps_io`;
- connecting the CPU subsystem to the external-memory target;
- replacing the current top-level high-impedance SDRAM defaults with
  controller-driven signals;
- adding the selected synthesizable SDRAM RTL to `files.qip`;
- extending the automated simulation regression.

These are later Milestone 4 checkpoints.

M4A-1 documents the architecture only and does not perform those integration
changes.

## 14. Deferred Questions

The following details remain intentionally deferred until the relevant
implementation checkpoint:

- exact controller module filename;
- exact row/bank/column mapping for each supported module geometry;
- controller clock frequency;
- SDRAM clock phase relationship;
- numeric initialization delays expressed in controller cycles;
- numeric refresh interval expressed in controller cycles;
- CAS latency;
- whether a later optimized implementation uses bursts;
- whether future masters justify bank-aware or priority scheduling;
- whether Jupiter eventually makes use of secondary SDRAM.

None of these deferred items may be represented as already verified.
