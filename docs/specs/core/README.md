# Core ISA and architecture references

This folder groups the base architectural documents that define the execution model used by the RV32 core in this repo.

## Included documents

- riscv-unprivileged.pdf
- riscv-privileged.pdf
- riscv-interrupts.pdf

## Why they matter here

These specs define the behavior used by:

- [rv32i_single_cycle.sv](../../../rv32i_single_cycle.sv)
- [rv32i_machine_csrs.sv](../../../rv32i_machine_csrs.sv)
- [rv32i_sv32_mmu.sv](../../../rv32i_sv32_mmu.sv)

The implementation in this repo intentionally covers a focused, educational RV32 subset instead of a full architectural-compliance model.

## Repo status

- Implemented: integer core behavior, trap/interrupt flow, privileged CSR subset, counters, PMP, and Sv32 translation
- Planned: broader privilege compliance, extra debug state, and more complete platform behavior
