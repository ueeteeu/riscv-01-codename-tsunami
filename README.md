# RISC-V 01: Codename Tsunami

An educational project exploring how a basic CPU works using the RISC-V
instruction set architecture. The goal is to build up a small processor one
component at a time and make the path from an instruction to its result easy
to understand.

## CPU Overview

The initial design is a simple 32-bit RISC-V processor. Its main components
are:

- **Program counter (PC):** holds the address of the next instruction.
- **Instruction memory:** supplies the instruction at the PC address.
- **Control unit:** decodes the instruction and selects the operations to run.
- **Register file:** stores the values used by instructions. The RISC-V `x0`
	register always reads as zero.
- **Arithmetic logic unit (ALU):** performs arithmetic and logical operations
	and compares values for branches.
- **Data memory:** provides storage for load and store instructions.

An instruction moves through a basic sequence: fetch it from instruction
memory, decode it, read its register operands, execute its operation, access
data memory if needed, and write a result back to a register. Branches and
jumps can change the next PC instead of advancing to the following
instruction.

## Initial Scope

The first version is intended to focus on a small subset of RV32I, such as
register and immediate arithmetic, loads and stores, conditional branches,
and jumps. This keeps the design approachable while covering the core CPU
datapath. The exact supported instructions will be documented as the
implementation takes shape.

## Project Status

This repository currently contains the project overview. CPU source code,
tests, and build instructions can be added as the design develops.
