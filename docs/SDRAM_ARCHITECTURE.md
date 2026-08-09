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

Milestone 4 prioritizes functional correctness and deterministic
simulation. It does not claim Quartus timing closure, FPGA resource
usage, or successful operation on physical hardware unless those
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

Milestone 4 uses this information to determine the CPU-visible usable
portion of Jupiter's SDRAM aperture.

`Template.sv` receives `sdram_sz` from `hps_io` and passes it through
`jupiter_system` into `jupiter_cpu_subsystem` and the SDRAM frontend.

The primary MiSTer `SDRAM_*` command/data pins are now owned by Jupiter
at the top level. The previous blanket high-impedance assignment for
primary SDRAM has been removed.

`SDRAM_CLK` is generated separately at the top level with the selected
Cyclone V `altddio_out` method. The SDRAM controller itself remains
synchronous to `clk_sys`.

This top-level integration establishes the RTL physical interface only.
It does not establish Quartus timing closure or successful operation on
physical SDRAM hardware.

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

### 8.1 MiSTer-Compatible Physical Address Mapping

The official MiSTer MemTest SDRAM controller provides the compatibility
reference for mapping the external SDRAM address space onto the primary
MiSTer SDRAM pins.

The current 128 MiB MiSTer module is a two-chip arrangement using 64 MiB
32M x 16 SDR SDRAM devices.

Let `H[25:0]` be Jupiter's 26-bit halfword address from
`jupiter_sdram_frontend`.

The selected physical address permutation is:

    SDRAM_nCS       = H[25]
    column[9:0]     = {H[24:17], H[1:0]}
    row[12:0]       = H[16:4]
    bank[1:0]       = H[3:2]

For a row-activate command, `SDRAM_A[12:0]` carries `row[12:0]`.

For a read or write command, `SDRAM_A[9:0]` carries `column[9:0]`.
`SDRAM_A[10]` may be used for auto-precharge according to the controller
command sequence.

The Jupiter byte write strobes remain independent of the address mapping and
will drive `SDRAM_DQML` and `SDRAM_DQMH` through the physical controller.

For 32 MiB and 64 MiB configurations, the installed-size gating established
by the frontend prevents accesses above reported capacity. Jupiter does not
create aliases for unavailable upper memory.

This mapping defines the address-bit permutation only. It does not by itself
establish initialization timing, refresh timing, CAS latency, SDRAM clock
phase, or successful operation on physical hardware.

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

### 9.1 Selected Initial Controller Clock

The initial physical Milestone 4 SDRAM implementation uses the
existing 20 MHz `clk_sys`.

The current PLL derives `clk_sys` from the 50 MHz `CLK_50M` input.
At 20 MHz, one controller cycle is 50 ns.

A later optimized implementation may introduce a dedicated memory
clock if Quartus timing analysis or physical-hardware testing
demonstrates a need for one.

### 9.2 Selected Physical SDRAM Clock Method

`SDRAM_CLK` will be generated at the MiSTer top level with a
Cyclone V `altddio_out` primitive following the clock-generation
method used by the official MiSTer MemTest SDRAM controller.

The selected primitive inputs are:

- `datain_h = 1'b0`;
- `datain_l = 1'b1`;
- `outclock = clk_sys`;
- output enable asserted.

The Jupiter SDRAM controller itself remains synchronous to
`clk_sys`.

This defines the intended initial physical clock architecture. It
does not by itself demonstrate Quartus timing closure or correct
operation on a physical SDRAM module.

### 9.3 Current Controller Timing Parameters

The correctness-oriented defaults in
`rtl/memory/jupiter_sdram_controller.sv` are:

| Parameter | Cycles | Nominal interpretation at 20 MHz |
|---|---:|---:|
| `POWERUP_CYCLES` | 4000 | 200 us |
| `TRP_CYCLES` | 1 | 50 ns |
| `TRFC_CYCLES` | 2 | 100 ns |
| `TMRD_CYCLES` | 1 | 50 ns |
| `TRCD_CYCLES` | 1 | 50 ns |
| `CAS_CYCLES` | 3 | CAS latency 3 |
| `READ_RECOVERY_CYCLES` | 2 | 100 ns |
| `WRITE_RECOVERY_CYCLES` | 3 | 150 ns |
| `REFRESH_INTERVAL_CYCLES` | 120 | 6 us |

These values define the initial RTL implementation rather than a
performance target.

Simulation verifies command sequencing and functional data integrity.
Physical timing remains subject to Quartus timing analysis and actual
MiSTer-compatible SDRAM hardware testing.

### 9.4 Initialization and Maintenance Responsibility

The Jupiter controller is responsible for SDRAM initialization and
periodic refresh.

The implementation must:

- complete initialization before external memory is operational;
- prevent required refresh from being permanently starved;
- finish an already-started logical 32-bit transaction before
  maintenance;
- service a pending refresh before accepting the next logical
  transaction.

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

Milestone 4 uses deterministic host-side Icarus Verilog regression.

The implemented verification layers are:

1. interconnect SDRAM target decoding and request forwarding;
2. 32-bit Jupiter to paired 16-bit SDRAM transfer conversion;
3. installed-size gating and out-of-range behavior;
4. behavioral SDRAM storage and physical address reconstruction;
5. initialization command sequencing;
6. recurring refresh and maintenance behavior;
7. byte-mask and partial-write behavior;
8. refresh deferral so maintenance does not split one logical 32-bit
   Jupiter transaction;
9. deterministic write/read round trips on both MiSTer SDRAM
   selections;
10. CPU-visible external-memory access through the Milestone 3
    interconnect;
11. sustained repeated-access integrity while periodic refresh occurs;
12. continued system-wrapper and earlier-milestone regression.

`make -C sim m4-test` runs the Milestone 4 aggregate regression.

`make -C sim test` runs the complete currently applicable Milestone 1
through Milestone 4 host-side regression.

The sustained-access path test writes 16 distinct aligned 32-bit words
and performs eight complete read/verify passes across that working set
while ordinary periodic refresh remains enabled.

All implemented testbenches report deterministic PASS/FAIL status and
terminate with failure status when checks fail.

The behavioral SDRAM model and host simulation validate functional RTL
behavior only. They do not establish Quartus synthesis, timing closure,
FPGA resource usage, physical SDRAM timing, or successful operation on
SuperStation One / MiSTer-compatible hardware.

## 13. Milestone 4 Integration Boundary

The Milestone 4 functional RTL and host-side simulation integration is
complete.

Implemented integration includes:

- the external SDRAM target in `jupiter_interconnect`;
- CPU-visible external SDRAM through `jupiter_cpu_subsystem`;
- 32-bit Jupiter transactions converted to paired 16-bit physical
  transfers by `jupiter_sdram_frontend`;
- SDRAM initialization, read/write command sequencing, and periodic
  refresh in `jupiter_sdram_controller`;
- a behavioral SDRAM model under `sim/`;
- installed-size propagation from `hps_io` through the Jupiter
  hierarchy;
- physical primary `SDRAM_*` command/data ownership in `Template.sv`;
- top-level `SDRAM_CLK` generation using the selected `altddio_out`
  method;
- Quartus source registration for the implemented CPU, interconnect,
  RAM, MMIO, SDRAM frontend/controller, subsystem, and system wrapper;
- deterministic CPU-driven external-memory simulation;
- repeated sustained read/write integrity testing while periodic
  refresh occurs;
- an automated `m4-test` aggregate and complete M1-M4 regression.

At Milestone 4 there is one transaction master: the CPU.
Refresh is controller maintenance rather than a second transaction
master, so no runtime multi-master arbiter is required at this stage.

Still outside the claims of Milestone 4:

- Quartus synthesis/resource/timing results unless actually run;
- physical SDRAM timing validation;
- successful operation on SuperStation One / MiSTer hardware;
- performance guarantees;
- DMA or other additional transaction masters.

## 14. Deferred Questions

The following details remain intentionally deferred beyond the initial
correctness-oriented Milestone 4 implementation:

- whether a later optimized controller uses SDRAM bursts;
- whether later performance work introduces a dedicated memory clock;
- whether Quartus timing analysis or physical testing requires changes
  to the selected clock relationship or conservative timing values;
- whether future masters justify bank-aware or priority scheduling;
- whether Jupiter eventually makes use of secondary SDRAM.

The controller module, initial 20 MHz controller clock,
`altddio_out` physical-clock method, current initialization delays,
refresh interval, and CAS latency are no longer deferred architecture
questions.
