# RISC-V 01: Codename Tsunami

An educational 32-bit RISC-V processor implemented as a single-cycle
SystemVerilog core. Instruction and data memories are separate interfaces;
`rv32i_memory` provides behavioral memory for simulation. With Sv32 enabled,
integrations must also connect the core's PTE-read sideband to physical memory.

## Implemented instruction sets

- **RV32I:** integer arithmetic and shifts, comparisons, conditional branches,
  `JAL`/`JALR`, `LUI`/`AUIPC`, and byte/halfword/word loads and stores.
- **RV32M:** multiply, divide, and remainder operations, including architectural
  divide-by-zero and signed-overflow results.
- **RV32A:** word `LR`/`SC` and word AMO operations.
- **RV32C:** compressed integer instructions expanded to their RV32I forms,
  plus `C.FLD`, `C.FSD`, `C.FLW`, `C.FSW`, and stack-relative variants.
- **RV32F:** single-precision loads/stores, arithmetic, square root, sign
  injection, min/max, fused operations, integer conversions, moves, comparisons,
  and classification. Rounding selection and accrued `fflags` are modeled.
- **RV32D simulation subset:** double-precision loads/stores, arithmetic,
  square root, sign injection, min/max, fused operations, comparisons,
  classification, and conversions between the supported integer, single, and
  double formats.
- **Zba/Zbb/Zbs/Zicond subset:** shifted adds, Boolean operations, rotates,
  min/max, bit counts, sign/zero extension, byte OR/reversal, bit
  set/clear/invert/extract, and conditional-zero operations.
- **Machine/supervisor privileged subset:** implemented trap state, delegated
  exceptions and interrupts, `ECALL`, `EBREAK`, `MRET`, `SRET`, and supported
  machine/supervisor CSR register/immediate operations. `external_interrupts`
  supplies machine software, timer, and external pending bits; the separate
  `supervisor_interrupts` input supplies supervisor software, timer, and
  external pending bits.
- **Performance counters:** writable 64-bit `mcycle`/`minstret` counters with
  RV32 high/low CSR halves, read-only `cycle`/`instret` aliases, and a
  platform-supplied read-only 64-bit `time` counter. `mcounteren`/`scounteren`
  control U/S access to all three counter aliases, while `mcountinhibit`
  controls cycle and instruction-retirement counting. Integrations must drive
  the core's `time_counter` input.
- **PMP subset:** four machine-mode entries expose `pmpcfg0` and `pmpaddr0`-
  `pmpaddr3`, with OFF/TOR/NA4/NAPOT matching, first-overlap priority,
  permissions, lock bits, and S/U-mode access checks for instruction fetches
  and data reads/writes. Unmatched S/U accesses are denied when any entry is
  active; unlocked matching entries do not restrict M-mode accesses.
- **Sv32 subset:** `satp.MODE=1` enables a blocking two-level page-table walker
  and four-entry TLB for S/U instruction fetches and data accesses. Leaf
  permissions, U/S rules, `SUM`, `MXR`, superpages, A/D checks, `SFENCE.VMA`
  address/ASID-selective invalidation (including inherited global mappings and
  global-entry preservation for ASID-specific fences), page-fault causes/
  `mtval`, and PMP checks on PTE reads are modeled. Walks are canceled if
  `satp` changes mid-translation. M-mode accesses bypass translation.
- **Floating-point CSRs:** `fflags`, `frm`, and `fcsr` support accrued flags,
  software flag clearing, and dynamic rounding-mode selection.
- `FENCE`, `FENCE.I`, and `WFI` are accepted as no-ops.

The core traps on misaligned halfword, word, and doubleword accesses, on
out-of-range data-memory accesses, and on instruction fetches outside memory
(including a 32-bit instruction that straddles the end of memory).
Byte-write masks preserve unaffected bytes for narrow stores; adjacent-word
memory ports support aligned 64-bit transfers.

## Reference spec pack

The project includes a structured reference catalog for the RISC-V PDFs and
related platform docs that were provided with the task. The index is kept in
[docs/specs/README.md](./docs/specs/README.md) and is grouped by architecture,
platform, firmware, trace, and profile references so the material is easy to
navigate while the RTL remains focused on the implemented RV32 subset.

For the implemented CPU block diagram, RTL responsibilities, and memory
connections, see [docs/architecture/CPU_LAYOUT.md](./docs/architecture/CPU_LAYOUT.md).

The current codebase implements the core RV32 privileged and virtual-memory
subset, while the firmware/platform references (including the UEFI and SBI
material) are tracked as future integration work rather than a completed boot
stack.

## Immediates

The decoder reconstructs the standard RV32 instruction immediate formats:

| Format | Instructions | Decoding |
| --- | --- | --- |
| I | arithmetic/load/JALR/CSR immediates | Sign-extend bits `[31:20]` from 12 to 32 bits. |
| S | stores | Join bits `[31:25]` and `[11:7]`, then sign-extend the 12-bit value. |
| B | conditional branches | Reorder the encoded fields, append a low zero bit, and sign-extend the 13-bit offset. |
| U | `LUI`, `AUIPC` | Place bits `[31:12]` in the upper 20 bits and clear the low 12 bits. |
| J | `JAL` | Reorder the encoded fields, append a low zero bit, and sign-extend the 21-bit offset. |

RV32 shift amounts use the low five instruction bits. The supported B-extension
immediate operations likewise select a bit using a five-bit index. Assembler
pseudoinstructions such as `li` and `la` expand into one or more base
instructions; they do not have independent hardware encodings.

## Current limitations

- The privileged implementation is not a complete Privileged Architecture
  implementation. Sv32 is limited to the 32-bit physical memory interface and
  a four-entry TLB; A/D bits must be maintained by software, `MPRV`, `TVM`,
  platform PMA behavior, and instruction fetches straddling virtual-page
  boundaries are not implemented. The page-table read sideband must be
  connected to physical memory by any integration. Debug state, user-level
  trap CSRs, and several privilege controls are absent. `WFI` does not suspend
  execution.
- Interrupt sources are direct simulation inputs, not a platform interrupt
  controller or timer/software-interrupt device. Machine and supervisor
  pending/enable/delegation, privilege qualification, and prioritized trap
  behavior are modeled only for the six standard software/timer/external
  interrupt classes.
- `FENCE` and `FENCE.I` provide no inter-hart ordering or instruction-cache
  synchronization. The atomic reservation model is single-hart; `aq`/`rl`
  ordering and interactions with other harts are not modeled.
- The RV32F and RV32D execution units use SystemVerilog `real` arithmetic for
  simulation and are not synthesizable hardware FPUs. RV32F supports rounding
  selection and common exception cases, but not every IEEE-754 corner case has
  been verified. RV32D uses host binary64 arithmetic: directed rounding for D
  arithmetic, correctly fused operations, and complete D exception-flag
  behavior are not guaranteed. `FCVT.S.D` does not yet apply all directed
  rounding modes. Treat these units as functional simulation models, not
  bit-exact conformance implementations.
- The compressed floating-point decoder covers the listed memory encodings;
  unrelated compressed extensions and assembler pseudoinstructions are not
  implemented.
- Assembly aliases such as `li`, `la`, `mv`, `neg`, `seqz`, `not`, and `ret`
  are not distinct hardware opcodes; they must be expanded by an assembler to
  the base instructions implemented by the core.
- PMP implements four entries only; machine protection bypass controls,
  machine previous-privilege data accesses, and additional platform-specific
  protection mechanisms are not modeled. Complete virtual-memory and
  privileged-architecture conformance are not implemented. The behavioral
  memory reports fetch faults for addresses outside its configured capacity;
  it is not a complete bus-fault or page-boundary model.

## Source and tests

- `rv32i_system.sv`: simulation integration top that connects the CPU to
  behavioral memory and exposes clock/reset, timer, and interrupt inputs.
- `rv32i_single_cycle.sv`: processor, decoder, and datapath.
- `rv32i_memory.sv`: behavioral memory with byte-lane stores and adjacent-word
  data ports.
- `rv32c_decompressor.sv`: compressed integer and supported floating-point
  memory-instruction expansion.
- `rv32i_bitmanip.sv`: selected Zba/Zbb/Zbs/Zicond operations.
- `rv32f_unit.sv`, `rv32d_unit.sv`: simulation-oriented floating-point units.
- `rv32i_machine_csrs.sv`: machine/supervisor CSR, trap, interrupt, PMP,
  counter, and FCSR state.
- `rv32i_sv32_mmu.sv`: blocking Sv32 page-table walker and small TLB.
- `rv32i_hex_display.sv`: optional multiplexed hexadecimal display.
- `tb_rv32i_system.sv`: end-to-end smoke test for fetch, integer execution,
  store, and load through the system wrapper.
- `tb_*.sv`: focused tests for integer, atomic, counters/time, PMP, bit-manipulation, compressed
  decode/execution, RV32F/RV32D, FCSR, instruction/data access faults, machine
  traps/interrupts, delegated supervisor interrupts/traps, and Sv32
  translation/page faults, superpages, inherited global mappings, selective
  `SFENCE.VMA`, ASID switching during walks, `SUM`, `MXR`, and A/D-bit
  enforcement.

Compile a testbench and its source modules with a SystemVerilog simulator. For
example, using Icarus Verilog from the project directory:

```powershell
iverilog -g2012 -s tb_rv32f -o tb_rv32f.vvp *.sv
vvp tb_rv32f.vvp
```

Replace `tb_rv32f` with another `tb_*` module to run its focused testbench.
