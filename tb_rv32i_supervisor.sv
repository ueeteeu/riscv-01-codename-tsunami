module tb_rv32i_supervisor;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic [31:0] data_address, data_write_data, data_read_data;
    logic [3:0] data_write_mask;
    logic data_write_enable, data_access_fault;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;

    rv32i_single_cycle cpu (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault),
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
        input logic [2:0] operation,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_i = {immediate, source, operation, destination, opcode};
    endfunction

    function automatic logic [31:0] encode_csr(
        input logic [11:0] csr,
        input logic [4:0] source,
        input logic [2:0] operation,
        input logic [4:0] destination
    );
        encode_csr = {csr, source, operation, destination, 7'h73};
    endfunction

    initial begin
        #1;
        memory.words[0] = encode_i(12'd128, 0, 3'b000, 1, 7'h13); 
        memory.words[1] = encode_csr(12'h105, 1, 3'b001, 0); // stvec = 128
        memory.words[2] = encode_i(12'd256, 0, 3'b000, 1, 7'h13);
        memory.words[3] = encode_csr(12'h302, 1, 3'b001, 0); // delegate U-ECALL
        memory.words[4] = encode_i(12'd32, 0, 3'b000, 2, 7'h13);
        memory.words[5] = encode_csr(12'h341, 2, 3'b001, 0); // mepc = 32
        memory.words[6] = 32'h3020_0073;                     // mret to U-mode
        memory.words[8] = 32'h0000_0073;                     // U-mode ecall
        memory.words[9] = encode_i(12'd7, 0, 3'b000, 5, 7'h13);
        memory.words[10] = 32'h0000_006f;                    // loop

        memory.words[32] = encode_csr(12'h141, 0, 3'b010, 3); // read sepc
        memory.words[33] = encode_i(12'd4, 3, 3'b000, 3, 7'h13);
        memory.words[34] = encode_csr(12'h141, 3, 3'b001, 0); // sepc += 4
        memory.words[35] = encode_csr(12'h142, 0, 3'b010, 4); // read scause
        memory.words[36] = 32'h1020_0073;                     // sret to U-mode

        #11 reset = 1'b0;
        repeat (24) @(negedge clk);

        if (cpu.machine_csrs.scause !== 32'd8 ||
            cpu.machine_csrs.sepc !== 32'd36 ||
            cpu.registers[3] !== 32'd36 ||
            cpu.registers[4] !== 32'd8 ||
            cpu.registers[5] !== 32'd7 ||
            cpu.machine_csrs.current_privilege !== 2'b00 ||
            program_counter !== 32'd40 ||
            illegal_instruction !== 1'b0)
            $fatal(1, "Delegated U-ECALL/SRET test failed at PC=%h", program_counter);

        $display("Supervisor delegation and SRET smoke test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "Supervisor test timed out at PC=%h", program_counter);
    end
endmodule
