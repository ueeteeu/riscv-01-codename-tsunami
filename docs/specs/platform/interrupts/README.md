# Interrupt and platform controller references

This folder tracks the interrupt-related platform references that inform system behavior beyond the core CPU pipeline.

## Included documents

- riscv-interrupts.pdf
- riscv-plic.pdf

## Intended role

These specs define how interrupt sources are described, qualified, and routed through a platform controller. This is outside the scope of the current single-core RTL implementation but relevant to a larger SoC or platform model.

## Current repo status

- Implemented in RTL: direct external interrupt inputs and machine/supervisor interrupt qualification in the CSR block
- Not yet implemented: PLIC-style controller, platform interrupt routing, or a shared system interrupt fabric
