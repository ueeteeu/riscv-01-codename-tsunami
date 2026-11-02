# SBI reference notes

This folder tracks the Supervisor Binary Interface references for a RISC-V system.

## Source document

- riscv-sbi.pdf

## Intended role

SBI provides the M-mode-to-S-mode firmware contract. It is a natural next layer above the low-level RTL model in this project and is relevant to a future platform runtime or firmware environment.

## Current repo status

- Implemented in RTL: privileged trap logic and core execution
- Not implemented yet: SBI call layer, runtime firmware services, and platform-provided service handlers

## Notes

The firmware docs are intentionally separated from the core ISA docs so the project can remain easy to debug while platform integration work is still future-facing.
