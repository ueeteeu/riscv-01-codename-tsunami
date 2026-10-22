# RISC-V 01: Codename Tsunami

An educational 32-bit RISC-V processor implemented as a single-cycle SystemVerilog
core. Instruction and data memories are separate interfaces in the CPU, with
`rv32i_memory` providing an 8 MiB behavioral memory for simulation.

## Implemented instruction sets

- **RV32I:** integer register and immediate arithmetic, shifts and comparisons;
  all conditional branches, `JAL`/`JALR`, `LUI`/`AUIPC`; `LB`, `LH`, `LW`,
  `LBU`, `LHU`; and `SB`, `SH`, `SW`.
- **RV32M:** multiply, divide and remainder instructions, including the
  architectural divide-by-zero and signed-overflow results.
- **RV32A:** word `LR`/`SC` and the word AMO operations.
- **RV32C:** compressed integer instructions are expanded to their RV32I forms.
- **Zbb/Zbs subset:** Boolean operations, rotates, min/max, bit counts,
  sign/zero extension, byte OR, byte reversal, and bit set/clear/invert/extract
  operations.
- **Machine-mode system instructions:** `ECALL`, `EBREAK`, `MRET`, CSR
  register/immediate operations for `mstatus`, `mtvec`, `mscratch`, `mepc`,
  `mcause`, and `mtval`. `WFI` is accepted as a no-op.
- `FENCE` and `FENCE.I` are accepted as no-ops for this single-hart core.

The core traps on misaligned halfword/word data accesses and on out-of-range
data-memory accesses. The byte-write mask lets the memory preserve unaffected
bytes for `SB` and `SH`.

## Current limitations

- The privileged implementation is machine-mode only. There is no supervisor
  mode, virtual memory, asynchronous interrupt delivery, or interrupt-controller
  interface.
- `WFI` does not suspend execution because interrupts and sleep/wake state are
  not implemented.
- `FENCE` and `FENCE.I` do not provide inter-hart ordering or instruction-cache
  synchronization; this implementation has one hart and no instruction cache.
- The atomic reservation model is for a single hart. `aq`/`rl` ordering and
  interactions with other harts are not modeled.
- The compressed floating-point encodings and the RV32F/RV32D floating-point
  instruction sets are not implemented; the core has no floating-point
  registers, rounding state, or arithmetic datapath.
- Instruction-fetch access faults and a complete privileged architecture are
  not yet implemented.

## Source and tests

- `rv32i_single_cycle.sv`: processor, decoder and datapath.
- `rv32i_memory.sv`: 8 MiB simulation memory with byte-lane stores.
- `rv32c_decompressor.sv`: compressed integer instruction expansion.
- `rv32i_bitmanip.sv`: selected Zbb/Zbs operations.
- `rv32i_machine_csrs.sv`: machine CSR and synchronous trap state.
- `rv32i_hex_display.sv`: optional multiplexed hexadecimal display.
- `tb_*.sv`: focused SystemVerilog testbenches for the decoder, integer,
  atomic, bit-manipulation, load/store, and machine-mode behavior.

Compile the relevant source modules together with a testbench using a
SystemVerilog simulator. The load/store testbench also checks misaligned and
out-of-range memory traps.
