# Platform and SoC references

This folder groups the platform-level references that define interrupt controllers, SoC integration expectations, memory-management hardware, and server-platform assumptions.

## Included documents

- riscv-plic.pdf
- riscv-iommu.pdf
- riscv-server-soc.pdf
- riscv-server-platform.pdf
- riscv-rqsc.pdf
- riscv-rpmi.pdf
- riscv-reri.pdf
- riscv-brs-spec.pdf
- riscv-cbqri.pdf
- riscv-riscv-ffh.pdf
- riscv-ffh.pdf

## Notes

These documents are reference material for system-level integration rather than direct RTL implementation in the current educational core. They are especially relevant if the project moves toward a complete SoC, platform management block, or firmware runtime.

## Current repo mapping

- Current RTL remains focused on the core pipeline and privileged CSR model.
- Platform integrations are still conceptual and require a higher-level firmware or SoC wrapper before implementation.
