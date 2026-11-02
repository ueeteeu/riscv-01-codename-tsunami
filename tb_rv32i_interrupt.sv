// Integration test for machine external-interrupt qualification, trap entry,
// cause reporting, and resumption through MRET.
module tb_rv32i_interrupt;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic [31:0] data_address, data_write_data, data_read_data;
    logic [3:0] data_write_mask;
    logic data_write_enable, data_access_fault;
    logic [2:0] external_interrupts = 3'b000;
    logic [2:0] supervisor_interrupts = 3'b000;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;
    rv32i_single_cycle cpu (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault),
        .external_interrupts(external_interrupts),
        .supervisor_interrupts(supervisor_interrupts),
        .program_counter(program_counter), .illegal_instruction(illegal_instruction)
    );

    rv32i_memory #(.MEMORY_BYTES(512)) memory (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
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

    initial begin
        #1;
        // Enable MEIE and MIE, then wait at a loop for an asserted MEIP input.
        memory.words[0] = encode_i(12'd64, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_csr(12'h305, 1, 3'b001, 0); // mtvec
        memory.words[2] = encode_i(12'd2048, 0, 3'b000, 1, 7'h13);
        memory.words[3] = encode_csr(12'h304, 1, 3'b001, 0); // enable MEIE
        memory.words[4] = encode_i(12'd8, 0, 3'b000, 1, 7'h13);
        memory.words[5] = encode_csr(12'h300, 1, 3'b001, 0); // enable MIE
        memory.words[6] = 32'h0000_006f;                     // interrupt resumes here
        memory.words[16] = encode_csr(12'h342, 0, 3'b010, 4); // read mcause
        memory.words[17] = encode_i(12'd1, 5, 3'b000, 5, 7'h13);
        memory.words[18] = 32'h3020_0073;                    // mret

        #11 reset = 1'b0;
        wait (program_counter == 32'd24);
        @(negedge clk);
        external_interrupts[2] = 1'b1; // drive MEIP after global enable is set
        wait (program_counter == 32'd64);
        @(negedge clk);
        external_interrupts[2] = 1'b0;
        repeat (12) @(negedge clk);

        if (cpu.machine_csrs.mcause !== 32'h8000_000b ||
            cpu.machine_csrs.mepc !== 32'd24 ||
            cpu.registers[4] !== 32'h8000_000b ||
            cpu.registers[5] !== 32'd1 ||
            program_counter !== 32'd24 ||
            illegal_instruction !== 1'b0)
            $fatal(1, "Machine external-interrupt delivery/MRET test failed");

        $display("Machine external-interrupt smoke test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "Interrupt test timed out at PC=%h", program_counter);
    end
endmodule
