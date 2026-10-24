// Focused tests for the selected Zbb/Zbs decoder and execution operations.
module tb_rv32i_bitmanip;
    logic [31:0] instruction;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic recognized;
    logic [31:0] result;

    rv32i_bitmanip dut (
        .instruction(instruction),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .recognized(recognized),
        .result(result)
    );

    function automatic logic [31:0] encode_r(
        input logic [6:0] function7,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [2:0] function3,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_r = {function7, source2, source1, function3, destination, opcode};
    endfunction

    function automatic logic [31:0] encode_i(
        input logic [11:0] immediate,
        input logic [4:0] source1,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_i = {immediate, source1, function3, destination, 7'h13};
    endfunction

    task automatic check_result(input logic [31:0] expected);
        begin
            #1;
            if (recognized !== 1'b1 || result !== expected) begin
                $fatal(1, "Bitmanip result mismatch: got %h expected %h", result, expected);
            end
        end
    endtask

    initial begin
        operand_a = 32'h8000_0100;
        operand_b = 32'd4;

        instruction = encode_i(12'h600, 1, 3'b001, 2); // clz
        check_result(32'd0);
        instruction = encode_i(12'h601, 1, 3'b001, 2); // ctz
        check_result(32'd8);
        instruction = encode_i(12'h602, 1, 3'b001, 2); // cpop
        check_result(32'd2);
        instruction = encode_i(12'h604, 1, 3'b001, 2); // sext.b
        check_result(32'h0000_0000);
        instruction = encode_i(12'h605, 1, 3'b001, 2); // sext.h
        check_result(32'h0000_0100);
        instruction = encode_i(12'h603, 1, 3'b001, 2); // invalid unary encoding
        #1;
        if (recognized !== 1'b0) $fatal(1, "Reserved unary encoding was recognized");

        instruction = encode_r(7'b0110000, 4, 1, 3'b001, 2, 7'h33); // rol
        check_result(32'h0000_1008);
        instruction = encode_r(7'b0110000, 4, 1, 3'b101, 2, 7'h33); // ror
        check_result(32'h0800_0010);
        instruction = encode_i(12'h604, 1, 3'b101, 2); // rori 4
        check_result(32'h0800_0010);

        operand_a = 32'hffff_00f0;
        operand_b = 32'h0000_00ff;
        instruction = encode_r(7'b0100000, 2, 1, 3'b111, 3, 7'h33); // andn
        check_result(32'hffff_0000);
        instruction = encode_r(7'b0100000, 2, 1, 3'b110, 3, 7'h33); // orn
        check_result(32'hffff_fff0);
        instruction = encode_r(7'b0100000, 2, 1, 3'b100, 3, 7'h33); // xnor
        check_result(32'h0000_fff0);

        operand_a = 32'hffff_ffff;
        operand_b = 32'h0000_0001;
        instruction = encode_r(7'b0000101, 2, 1, 3'b100, 3, 7'h33); // min signed
        check_result(32'hffff_ffff);
        instruction = encode_r(7'b0000101, 2, 1, 3'b110, 3, 7'h33); // minu
        check_result(32'h0000_0001);

        operand_a = 32'b0;
        instruction = encode_r(7'b0010100, 5, 1, 3'b001, 3, 7'h33); // bset
        check_result(32'h0000_0020);
        instruction = encode_r(7'b0100100, 5, 1, 3'b001, 3, 7'h33); // bclr
        check_result(32'b0);
        instruction = encode_r(7'b0110100, 5, 1, 3'b001, 3, 7'h33); // binv
        check_result(32'h0000_0020);
        instruction = encode_i(12'h285, 1, 3'b001, 3); // bseti bit 5
        check_result(32'h0000_0020);
        operand_a = 32'h0000_0020;
        instruction = encode_i(12'h485, 1, 3'b101, 3); // bexti bit 5
        check_result(32'h1);

        operand_a = 32'h0100_0080;
        instruction = encode_i(12'h287, 1, 3'b101, 3); // orc.b
        check_result(32'hff00_00ff);
        instruction = encode_i(12'h698, 1, 3'b101, 3); // rev8
        check_result(32'h8000_0001);

        operand_a = 32'habcd_ef00;
        instruction = encode_r(7'b0000100, 0, 1, 3'b100, 3, 7'h33); // zext.h
        check_result(32'h0000_ef00);

        operand_a = 32'h1234_5678;
        operand_b = 32'd7;
        instruction = encode_r(7'b0010000, 2, 1, 3'b010, 3, 7'h33); // sh1add
        check_result(32'h2468_acf7);
        instruction = encode_r(7'b0010000, 2, 1, 3'b100, 3, 7'h33); // sh2add
        check_result(32'h48d1_59e7);
        instruction = encode_r(7'b0010000, 2, 1, 3'b110, 3, 7'h33); // sh3add
        check_result(32'h91a2_b3c7);

        operand_b = 0;
        instruction = encode_r(7'b0000111, 0, 1, 3'b101, 3, 7'h33); // czero.eqz, zero condition
        check_result(32'b0);
        operand_b = 1;
        instruction = encode_r(7'b0000111, 1, 1, 3'b101, 3, 7'h33); // czero.eqz, nonzero condition
        check_result(32'h1234_5678);
        operand_b = 0;
        instruction = encode_r(7'b0000111, 0, 1, 3'b111, 3, 7'h33); // czero.nez, zero condition
        check_result(32'h1234_5678);
        operand_b = 1;
        instruction = encode_r(7'b0000111, 1, 1, 3'b111, 3, 7'h33); // czero.nez, nonzero condition
        check_result(32'b0);

        $display("Zba/Zbb/Zbs/Zicond bitmanip smoke test passed");
        $finish;
    end
endmodule
