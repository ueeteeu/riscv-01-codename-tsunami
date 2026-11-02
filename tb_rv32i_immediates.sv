// Integration coverage for signed I/S immediates and the split B/U/J formats.
module tb_rv32i_immediates;
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
        input logic [2:0] function3,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_i = {immediate, source, function3, destination, opcode};
    endfunction

    function automatic logic [31:0] encode_s(
        input logic [11:0] immediate,
        input logic [4:0] source2,
        input logic [4:0] source1
    );
        encode_s = {immediate[11:5], source2, source1, 3'b010,
                    immediate[4:0], 7'h23};
    endfunction

    function automatic logic [31:0] encode_b(
        input logic [12:0] immediate,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [2:0] function3
    );
        encode_b = {immediate[12], immediate[10:5], source2, source1,
                    function3, immediate[4:1], immediate[11], 7'h63};
    endfunction

    function automatic logic [31:0] encode_u(
        input logic [19:0] immediate,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_u = {immediate, destination, opcode};
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
        memory.words[0]  = encode_i(12'hfff, 0, 3'b000, 1, 7'h13); // addi x1,x0,-1
        memory.words[1]  = encode_i(12'hfff, 1, 3'b010, 2, 7'h13); // slti x2,x1,-1
        memory.words[2]  = encode_i(12'h000, 1, 3'b010, 3, 7'h13); // slti x3,x1,0
        memory.words[3]  = encode_i(12'hfff, 0, 3'b011, 4, 7'h13); // sltiu x4,x0,-1
        memory.words[4]  = encode_i(12'h800, 0, 3'b110, 5, 7'h13); // ori x5,x0,-2048
        memory.words[5]  = encode_i(12'h7ff, 5, 3'b111, 6, 7'h13); // andi x6,x5,2047
        memory.words[6]  = encode_i(12'hfff, 0, 3'b100, 7, 7'h13); // xori x7,x0,-1
        memory.words[7]  = encode_i(12'h01f, 1, 3'b101, 8, 7'h13); // srli x8,x1,31
        memory.words[8]  = encode_i(12'h41f, 1, 3'b101, 9, 7'h13); // srai x9,x1,31
        memory.words[9]  = encode_i(12'h01f, 3, 3'b001, 10, 7'h13); // slli x10,x3,31
        memory.words[10] = encode_i(12'd256, 0, 3'b000, 11, 7'h13); // base address
        memory.words[11] = encode_s(12'hffc, 1, 11); // sw x1,-4(x11)
        memory.words[12] = encode_i(12'hffc, 11, 3'b010, 12, 7'h03); // lw x12,-4(x11)
        memory.words[13] = encode_b(13'd8, 4, 3, 3'b000); // beq: skip next instruction
        memory.words[14] = encode_i(12'd99, 0, 3'b000, 13, 7'h13); // skipped
        memory.words[15] = encode_i(12'h800, 0, 3'b000, 13, 7'h13); // addi x13,x0,-2048
        memory.words[16] = encode_u(20'hfffff, 14, 7'h37); // lui x14,0xfffff
        memory.words[17] = encode_u(20'h00001, 15, 7'h17); // auipc x15,1
        memory.words[18] = encode_j(21'd8, 16); // jal: skip next instruction
        memory.words[19] = encode_i(12'd99, 0, 3'b000, 17, 7'h13); // skipped
        memory.words[20] = encode_i(12'd7, 0, 3'b000, 17, 7'h13);
        memory.words[21] = encode_j(21'b0, 0); // stable loop

        #11 reset = 1'b0;
        repeat (28) @(negedge clk);

        if (cpu.registers[1] !== 32'hffff_ffff ||
            cpu.registers[2] !== 32'd0 ||
            cpu.registers[3] !== 32'd1 ||
            cpu.registers[4] !== 32'd1 ||
            cpu.registers[5] !== 32'hffff_f800 ||
            cpu.registers[6] !== 32'd0 ||
            cpu.registers[7] !== 32'hffff_ffff ||
            cpu.registers[8] !== 32'd1 ||
            cpu.registers[9] !== 32'hffff_ffff ||
            cpu.registers[10] !== 32'h8000_0000 ||
            cpu.registers[12] !== 32'hffff_ffff ||
            cpu.registers[13] !== 32'hffff_f800 ||
            cpu.registers[14] !== 32'hffff_f000 ||
            cpu.registers[15] !== 32'h0000_1044 ||
            cpu.registers[16] !== 32'h0000_004c ||
            cpu.registers[17] !== 32'd7 ||
            memory.words[63] !== 32'hffff_ffff ||
            illegal_instruction !== 1'b0)
            $fatal(1, "RV32 immediate decode/execution mismatch at PC=%h", program_counter);

        $display("RV32 immediate-format smoke test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "Immediate test timed out at PC=%h", program_counter);
    end
endmodule
