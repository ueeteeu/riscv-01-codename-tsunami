// Test representative base RV32I and RV32M instructions.
module tb_rv32i_integer;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic [31:0] data_address, data_write_data, data_read_data;
    logic data_write_enable;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;

    rv32i_single_cycle cpu (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_read_data(data_read_data),
        .program_counter(program_counter), .illegal_instruction(illegal_instruction)
    );

    rv32i_memory memory (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_read_data(data_read_data)
    );

    function automatic logic [31:0] encode_i(
        input logic [11:0] immediate, input logic [4:0] source,
        input logic [2:0] operation, input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_i = {immediate, source, operation, destination, opcode};
    endfunction

    function automatic logic [31:0] encode_r(
        input logic [6:0] function7, input logic [4:0] source2,
        input logic [4:0] source1, input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_r = {function7, source2, source1, function3, destination, 7'h33};
    endfunction

    function automatic logic [31:0] encode_s(
        input logic [11:0] immediate, input logic [4:0] source2,
        input logic [4:0] source1
    );
        encode_s = {immediate[11:5], source2, source1, 3'b010, immediate[4:0], 7'h23};
    endfunction

    function automatic logic [31:0] encode_b(
        input logic [12:0] immediate, input logic [4:0] source2,
        input logic [4:0] source1, input logic [2:0] function3
    );
        encode_b = {immediate[12], immediate[10:5], source2, source1,
                    function3, immediate[4:1], immediate[11], 7'h63};
    endfunction

    function automatic logic [31:0] encode_u(
        input logic [19:0] immediate, input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_u = {immediate, destination, opcode};
    endfunction

    function automatic logic [31:0] encode_j(
        input logic [20:0] immediate, input logic [4:0] destination
    );
        encode_j = {immediate[20], immediate[10:1], immediate[11],
                    immediate[19:12], destination, 7'h6f};
    endfunction

    initial begin
        #1;
        memory.words[0]  = encode_i(12'hffc, 0, 3'b000, 1, 7'h13);  // addi x1,x0,-4
        memory.words[1]  = encode_i(12'd3, 0, 3'b000, 2, 7'h13);     // addi x2,x0,3
        memory.words[2]  = encode_r(0, 2, 1, 3'b000, 3);             // add
        memory.words[3]  = encode_r(7'h20, 1, 2, 3'b000, 4);         // sub
        memory.words[4]  = encode_r(0, 2, 1, 3'b111, 5);             // and
        memory.words[5]  = encode_r(0, 2, 1, 3'b110, 6);             // or
        memory.words[6]  = encode_r(0, 2, 1, 3'b100, 7);             // xor
        memory.words[7]  = encode_i(12'd2, 2, 3'b001, 8, 7'h13);     // slli
        memory.words[8]  = encode_i(12'h001, 1, 3'b101, 9, 7'h13);   // srli
        memory.words[9]  = encode_i(12'h401, 1, 3'b101, 10, 7'h13);  // srai
        memory.words[10] = encode_r(0, 2, 1, 3'b010, 11);            // slt
        memory.words[11] = encode_r(0, 2, 1, 3'b011, 12);            // sltu
        memory.words[12] = encode_i(12'd1, 1, 3'b011, 13, 7'h13);   // sltiu
        memory.words[13] = encode_r(1, 2, 1, 3'b000, 14);            // mul
        memory.words[14] = encode_r(1, 2, 1, 3'b001, 15);            // mulh
        memory.words[15] = encode_r(1, 2, 1, 3'b010, 16);            // mulhsu
        memory.words[16] = encode_r(1, 2, 1, 3'b011, 17);            // mulhu
        memory.words[17] = encode_r(1, 2, 1, 3'b100, 18);            // div
        memory.words[18] = encode_r(1, 2, 1, 3'b101, 19);            // divu
        memory.words[19] = encode_r(1, 2, 1, 3'b110, 20);            // rem
        memory.words[20] = encode_r(1, 2, 1, 3'b111, 21);            // remu
        memory.words[21] = encode_u(20'h12345, 22, 7'h37);           // lui
        memory.words[22] = encode_u(20'h00001, 23, 7'h17);           // auipc
        memory.words[23] = encode_i(12'd256, 0, 3'b000, 24, 7'h13); // data address
        memory.words[24] = encode_i(12'd124, 0, 3'b000, 25, 7'h13); // jalr target
        memory.words[25] = encode_s(0, 3, 24);                       // sw
        memory.words[26] = encode_i(12'd1, 24, 3'b000, 26, 7'h03);  // lb
        memory.words[27] = encode_b(13'd8, 2, 1, 3'b001);           // bne
        memory.words[28] = encode_i(12'd99, 0, 3'b000, 27, 7'h13);  // skipped
        memory.words[29] = encode_j(21'd8, 28);                     // jal
        memory.words[30] = encode_i(12'd99, 0, 3'b000, 27, 7'h13);  // skipped
        memory.words[31] = encode_i(12'd0, 25, 3'b000, 29, 7'h67); // jalr self-loop

        #11 reset = 1'b0;
        repeat (40) @(negedge clk);

        if (cpu.registers[3] !== 32'hffff_ffff || cpu.registers[4] !== 32'd7 ||
            cpu.registers[8] !== 32'd12 || cpu.registers[9] !== 32'h7fff_fffe ||
            cpu.registers[10] !== 32'hffff_fffe || cpu.registers[11] !== 32'd1 ||
            cpu.registers[12] !== 32'd0 || cpu.registers[13] !== 32'd0) begin
            $fatal(1, "RV32I arithmetic, shift, or comparison result mismatch");
        end
        if (cpu.registers[14] !== 32'hffff_fff4 || cpu.registers[15] !== 32'hffff_ffff ||
            cpu.registers[16] !== 32'hffff_ffff || cpu.registers[17] !== 32'd2 ||
            cpu.registers[18] !== 32'hffff_ffff || cpu.registers[19] !== 32'h5555_5554 ||
            cpu.registers[20] !== 32'hffff_ffff || cpu.registers[21] !== 32'd0) begin
            $fatal(1, "RV32M multiply/divide result mismatch");
        end
        if (cpu.registers[22] !== 32'h1234_5000 || cpu.registers[23] !== 32'h0000_1058 ||
            cpu.registers[26] !== 32'hffff_ffff || cpu.registers[27] !== 32'd0 ||
            cpu.registers[28] !== 32'd120 || cpu.registers[29] !== 32'd128 ||
            memory.words[64] !== 32'hffff_ffff || illegal_instruction !== 1'b0) begin
            $fatal(1, "Load/store, upper-immediate, branch, or jump result mismatch");
        end
        $display("RV32I/RV32M smoke test passed");
        $finish;
    end
endmodule
