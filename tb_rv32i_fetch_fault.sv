// Verify that an unmapped instruction fetch traps with cause 1 and reports the
// faulting PC in mtval while the machine handler can inspect the saved state.
module tb_rv32i_fetch_fault;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic instruction_access_fault;
    logic instruction_access_fault_next_halfword;
    logic [31:0] data_address, data_write_data, data_read_data;
    logic [3:0] data_write_mask;
    logic data_write_enable, data_access_fault;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;

    rv32i_single_cycle cpu (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .instruction_access_fault(instruction_access_fault),
        .instruction_access_fault_next_halfword(instruction_access_fault_next_halfword),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault),
        .program_counter(program_counter), .illegal_instruction(illegal_instruction)
    );

    rv32i_memory #(.MEMORY_BYTES(64)) memory (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .instruction_access_fault(instruction_access_fault),
        .instruction_access_fault_next_halfword(instruction_access_fault_next_halfword),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault)
    );

    function automatic logic [31:0] encode_i(
        input logic [11:0] immediate,
        input logic [4:0] source,
        input logic [2:0] function3,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_i = {immediate, source, function3, destination, opcode};
    endfunction

    function automatic logic [31:0] encode_csr(
        input logic [11:0] csr,
        input logic [4:0] source,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_csr = {csr, source, function3, destination, 7'h73};
    endfunction

    function automatic logic [31:0] encode_j(
        input logic [20:0] immediate,
        input logic [4:0] destination
    );
        encode_j = {immediate[20], immediate[10:1], immediate[11],
                    immediate[19:12], destination, 7'h6f};
    endfunction

    initial begin
        #1;
        memory.words[0] = encode_i(12'd32, 0, 3'b000, 1, 7'h13); // mtvec value
        memory.words[1] = encode_csr(12'h305, 1, 3'b001, 0); // csrw mtvec,x1
        memory.words[2] = encode_j(21'd54, 0); // jump from PC 8 to final halfword at PC 62
        memory.words[15][31:16] = 16'h006f; // 32-bit instruction starts but crosses memory end
        memory.words[8] = encode_csr(12'h342, 0, 3'b010, 3); // read mcause
        memory.words[9] = encode_csr(12'h343, 0, 3'b010, 4); // read mtval
        memory.words[10] = encode_csr(12'h341, 0, 3'b010, 5); // read mepc
        memory.words[11] = encode_j(21'b0, 0); // hold in trap handler

        #11 reset = 1'b0;
        repeat (12) @(negedge clk);

        if (cpu.machine_csrs.mcause !== 32'd1 ||
            cpu.machine_csrs.mtval !== 32'd64 ||
            cpu.machine_csrs.mepc !== 32'd62 ||
            cpu.registers[3] !== 32'd1 ||
            cpu.registers[4] !== 32'd64 ||
            cpu.registers[5] !== 32'd62 ||
            program_counter !== 32'd44 ||
            illegal_instruction !== 1'b0)
            $fatal(1, "Instruction access-fault trap mismatch at PC=%h", program_counter);

        $display("Instruction access-fault smoke test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "Instruction access-fault test timed out at PC=%h", program_counter);
    end
endmodule
