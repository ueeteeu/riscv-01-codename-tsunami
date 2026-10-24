# RISC-V specification index

This repo keeps a lightweight, human-readable index for the reference documents that were provided for the project. The PDFs themselves remain in the Downloads folder; the directory here organizes them by domain so they are easy to review and map to the implemented core features.

## How the references are organized

- Core ISA and architecture: base unprivileged + privileged behavior, traps, memory models
- Platform/firmware: SBI, UEFI, interrupt controller, and system platform specifics
- Profiles and extensions: RVA23, RVB23, and broader platform/profile references
- Trace/debug: debug, trace, and related monitor/connector standards

## Master index

| Document | Category | Notes / repo mapping |
| --- | --- | --- |
| riscv-unprivileged.pdf | Core ISA | RV32I/E, immediate formats, execution model, base conventions |
| riscv-privileged.pdf | Core ISA | Machine/supervisor CSR model, traps, interrupts, PMP, virtual memory |
| riscv-interrupts.pdf | Platform / interrupts | External interrupt semantics and architectural expectations |
| riscv-plic.pdf | Platform / interrupts | Platform interrupt controller model |
| riscv-iommu.pdf | Platform / memory mgmt | IOMMU and memory-translation interactions |
| riscv-server-soc.pdf | Platform / SoC | Server-class SoC integration patterns |
| riscv-server-platform.pdf | Platform / platform | Server platform profile and board expectations |
| riscv-abi.pdf | Firmware / runtime | ABI conventions and software calling conventions |
| riscv-sbi.pdf | Firmware / runtime | Supervisor Binary Interface for M-mode firmware |
| RISCV_UEFI_PROTOCOL-spec.pdf | Firmware / runtime | UEFI protocol layer over RISC-V platform assumptions |
| riscv-rqsc.pdf | Platform / security | Runtime quality and security considerations |
| riscv-rpmi.pdf | Platform / firmware | RISC-V platform management integration |
| riscv-reri.pdf | Platform / reliability | Reliability and error-handling requirements |
| rvb23-profile.pdf | Profiles | RVB23 profile, broader platform profile set |
| rva23-profile.pdf | Profiles | RVA23 application profile |
| RISC-V_Profiles.pdf | Profiles | General profile guidance and profile model |
| riscv-debug-specification.pdf | Debug / trace | Debug architecture and debug state |
| RISC-V-N-Trace.pdf | Trace | N-Trace extension and trace streams |
| RISC-V-Trace-Connectors.pdf | Trace | Trace connector specification |
| RISC-V-Trace-Control-Interface.pdf | Trace | Trace control interface |
| riscv-hart-trace-interface.pdf | Trace | Hart-level trace interface |
| e-trace-encap.pdf | Trace | Encapsulation format for trace streams |
| riscv-trace-spec.pdf | Trace | High-level trace architecture |
| riscv-semihosting.pdf | Firmware / debug | Semihosting/platform debug support |
| riscv-ffh.pdf | Platform / firmware | Firmware-friendly implementation hooks |
| riscv-brs-spec.pdf | Platform / boot | Boot/reset / firmware startup semantics |
| riscv-cbqri.pdf | Platform / reliability | RAS / quality-of-implementation references |
| riscv-riscv-ffh.pdf | Platform / firmware | Duplicate/related firmware hook reference (kept as provided) |
| riscv-privileged.pdf | Core ISA | See above; duplicate reference intentionally retained in the list |

## Implementation status in this repo

The current codebase already models the core RV32 subset in the code under the project root:

- [rv32i_machine_csrs.sv](../../rv32i_machine_csrs.sv): machine/supervisor CSR, trap state, counters, PMP, and FCSR state
- [rv32i_single_cycle.sv](../../rv32i_single_cycle.sv): core fetch/execute flow and privileged trap plumbing
- [rv32i_sv32_mmu.sv](../../rv32i_sv32_mmu.sv): Sv32 translation and page-fault handling
- [tb_rv32i_privileged.sv](../../tb_rv32i_privileged.sv): privileged CSR smoke tests
- [tb_rv32i_supervisor.sv](../../tb_rv32i_supervisor.sv): supervisor delegation and SRET tests
- [tb_rv32i_counters.sv](../../tb_rv32i_counters.sv): counter access behavior tests

The remaining platform/firmware-spec docs are tracked as reference material for future firmware, SBI, UEFI, and OS integration work rather than implemented RTL in this repo.

## Recommended next steps

1. Keep the architectural core logic in the current RTL files.
2. Add a firmware layer under the `platform/` and `firmware/` docs when a boot stack or SBI/UEFI model is implemented.
3. Use the trace/debug docs only when adding instrumentation or platform validation tools.
