// Simulation system wrapper joining the RV32 core to behavioral memory.
//
// This is an integration top for simulation and simple demonstrations; it is
// not a bus fabric, FPGA board top, firmware environment, or physical layout.
module rv32i_system #(
    parameter INIT_FILE = "",
    parameter integer MEMORY_BYTES = 8 * 1024 * 1024
) (
    input  logic        clk,
    input  logic        reset,
    input  logic [63:0] time_counter,
    input  logic [2:0]  external_interrupts,
    input  logic [2:0]  supervisor_interrupts,
    output logic [31:0] program_counter,
    output logic        illegal_instruction
);
    logic [31:0] instruction_address;
    logic [31:0] instruction;
    logic instruction_access_fault;
    logic instruction_access_fault_next_halfword;

    logic [31:0] data_address;
    logic [31:0] data_write_data;
    logic data_write_enable;
    logic [3:0] data_write_mask;
    logic [31:0] data_write_data_next_word;
    logic data_write_enable_next_word;
    logic [3:0] data_write_mask_next_word;
    logic [31:0] data_read_data;
    logic [31:0] data_read_data_next_word;
    logic data_access_fault;
    logic data_access_fault_next_word;

    logic pte_read_enable;
    logic [31:0] pte_read_address;
    logic [31:0] pte_read_data;
    logic pte_access_fault;

    rv32i_single_cycle cpu (
        .clk(clk),
        .reset(reset),
        .time_counter(time_counter),
        .instruction_address(instruction_address),
        .instruction(instruction),
        .instruction_access_fault(instruction_access_fault),
        .instruction_access_fault_next_halfword(instruction_access_fault_next_halfword),
        .data_address(data_address),
        .data_write_data(data_write_data),
        .data_write_enable(data_write_enable),
        .data_write_mask(data_write_mask),
        .data_write_data_next_word(data_write_data_next_word),
        .data_write_enable_next_word(data_write_enable_next_word),
        .data_write_mask_next_word(data_write_mask_next_word),
        .data_read_data(data_read_data),
        .data_read_data_next_word(data_read_data_next_word),
        .data_access_fault(data_access_fault),
        .data_access_fault_next_word(data_access_fault_next_word),
        .external_interrupts(external_interrupts),
        .supervisor_interrupts(supervisor_interrupts),
        .pte_read_enable(pte_read_enable),
        .pte_read_address(pte_read_address),
        .pte_read_data(pte_read_data),
        .pte_access_fault(pte_access_fault),
        .program_counter(program_counter),
        .illegal_instruction(illegal_instruction)
    );

    rv32i_memory #(
        .INIT_FILE(INIT_FILE),
        .MEMORY_BYTES(MEMORY_BYTES)
    ) memory (
        .clk(clk),
        .reset(reset),
        .instruction_address(instruction_address),
        .instruction(instruction),
        .instruction_access_fault(instruction_access_fault),
        .instruction_access_fault_next_halfword(instruction_access_fault_next_halfword),
        .data_address(data_address),
        .data_write_data(data_write_data),
        .data_write_enable(data_write_enable),
        .data_write_mask(data_write_mask),
        .data_write_data_next_word(data_write_data_next_word),
        .data_write_enable_next_word(data_write_enable_next_word),
        .data_write_mask_next_word(data_write_mask_next_word),
        .data_read_data(data_read_data),
        .data_read_data_next_word(data_read_data_next_word),
        .data_access_fault(data_access_fault),
        .data_access_fault_next_word(data_access_fault_next_word),
        .pte_read_enable(pte_read_enable),
        .pte_read_address(pte_read_address),
        .pte_read_data(pte_read_data),
        .pte_access_fault(pte_access_fault)
    );
endmodule
