# UEFI reference notes

This folder tracks the UEFI protocol material for a RISC-V platform.

## Source document

- RISCV_UEFI_PROTOCOL-spec.pdf

## Intended role

UEFI is a firmware/runtime layer above the core CPU and CSR model. It defines service contracts, boot assumptions, and runtime interfaces that are not implemented by the current RTL project.

## Current repo status

- Implemented in RTL: RV32 execution and privileged CSR state, page translation, and counters
- Not implemented yet: UEFI boot services, EFI runtime services, firmware handoff, and platform abstraction layer

## Notes

This document is intentionally kept as a reference map so the platform and firmware work can be added later without confusing it with the core ISA implementation.
