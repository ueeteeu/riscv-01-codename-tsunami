# Firmware and runtime references

This folder groups the documents that describe ABI, SBI, UEFI, semihosting, and other software-layer assumptions for a RISC-V platform.

## Included documents

- riscv-abi.pdf
- riscv-sbi.pdf
- RISCV_UEFI_PROTOCOL-spec.pdf
- riscv-semihosting.pdf
- riscv-rqsc.pdf (platform/security tie-in)
- riscv-ffh.pdf
- riscv-brs-spec.pdf

## UEFI and platform notes

The UEFI-related reference is tracked here because it affects firmware startup, runtime service contracts, and boot-time platform assumptions. This repo does not yet implement a UEFI firmware stack or SBI-backed runtime environment; the documents are tracked as design references for future work.

## Current status

- Modelled in RTL: core execution and privileged control state
- Not yet implemented: SBI layer, UEFI runtime, boot services, firmware handoff, and platform service stack
