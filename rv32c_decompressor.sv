// Decompress the RV32C integer instruction subset into canonical RV32I words.
// Floating-point compressed encodings are reported as illegal because this
// core does not implement F/D floating-point state or execution.
module rv32c_decompressor (
    input  logic [31:0] fetched_instruction,
    output logic [31:0] decoded_instruction,
    output logic        is_compressed,
    output logic        illegal_compressed
);
    logic [15:0] compressed_instruction;
    logic [1:0] quadrant;
    logic [2:0] function3;
    logic [4:0] rd;
    logic [4:0] rs2;
    logic [4:0] prime_rd;
    logic [4:0] prime_rs1;
    logic [4:0] prime_rs2;
    logic [11:0] immediate_i;
    logic [11:0] immediate_s;
    logic [12:0] immediate_b;
    logic [20:0] immediate_j;
    logic [5:0] immediate_ci;
    logic [4:0] shift_amount;

    function automatic logic [31:0] encode_i(
        input logic [11:0] immediate,
        input logic [4:0] source1,
        input logic [2:0] function_code,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_i = {immediate, source1, function_code, destination, opcode};
    endfunction

    function automatic logic [31:0] encode_r(
        input logic [6:0] function7,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [2:0] function_code,
        input logic [4:0] destination
    );
        encode_r = {function7, source2, source1, function_code, destination, 7'h33};
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
        input logic [2:0] function_code
    );
        encode_b = {immediate[12], immediate[10:5], source2, source1,
                    function_code, immediate[4:1], immediate[11], 7'h63};
    endfunction

    function automatic logic [31:0] encode_u(
        input logic [19:0] immediate,
        input logic [4:0] destination
    );
        encode_u = {immediate, destination, 7'h37};
    endfunction

    function automatic logic [31:0] encode_j(
        input logic [20:0] immediate,
        input logic [4:0] destination
    );
        encode_j = {immediate[20], immediate[10:1], immediate[11],
                    immediate[19:12], destination, 7'h6f};
    endfunction

    always_comb begin
        compressed_instruction = fetched_instruction[15:0];
        quadrant = compressed_instruction[1:0];
        function3 = compressed_instruction[15:13];
        rd = compressed_instruction[11:7];
        rs2 = compressed_instruction[6:2];
        prime_rd = {2'b01, compressed_instruction[4:2]};
        prime_rs1 = {2'b01, compressed_instruction[9:7]};
        prime_rs2 = {2'b01, compressed_instruction[4:2]};
        immediate_ci = {compressed_instruction[12], compressed_instruction[6:2]};
        shift_amount = {compressed_instruction[12], compressed_instruction[6:2]};
        immediate_i = 12'b0;
        immediate_s = 12'b0;
        immediate_b = 13'b0;
        immediate_j = 21'b0;
        decoded_instruction = fetched_instruction;
        is_compressed = (compressed_instruction[1:0] != 2'b11);
        illegal_compressed = 1'b0;

        if (is_compressed) begin
            // Default to an illegal base opcode; each valid encoding replaces it.
            decoded_instruction = 32'b0;
            case ({function3, quadrant})
                5'b00000: begin // C.ADDI4SPN
                    immediate_i = {2'b00, compressed_instruction[10:7],
                                   compressed_instruction[12:11], compressed_instruction[5],
                                   compressed_instruction[6], 2'b00};
                    if (immediate_i == 0) illegal_compressed = 1'b1;
                    else decoded_instruction = encode_i(immediate_i, 5'd2, 3'b000, prime_rd, 7'h13);
                end
                5'b01000: begin // C.LW
                    immediate_i = {5'b0, compressed_instruction[5], compressed_instruction[12:10],
                                   compressed_instruction[6], 2'b00};
                    decoded_instruction = encode_i(immediate_i, prime_rs1, 3'b010, prime_rd, 7'h03);
                end
                5'b11000: begin // C.SW
                    immediate_s = {5'b0, compressed_instruction[5], compressed_instruction[12:10],
                                   compressed_instruction[6], 2'b00};
                    decoded_instruction = encode_s(immediate_s, prime_rs2, prime_rs1);
                end

                5'b00001: begin // C.ADDI and C.NOP; rd=x0 forms are hints
                    immediate_i = {{6{immediate_ci[5]}}, immediate_ci};
                    decoded_instruction = encode_i(immediate_i, rd, 3'b000, rd, 7'h13);
                end
                5'b00101: begin // C.JAL (RV32)
                    immediate_j[11] = compressed_instruction[12];
                    immediate_j[4] = compressed_instruction[11];
                    immediate_j[9:8] = compressed_instruction[10:9];
                    immediate_j[10] = compressed_instruction[8];
                    immediate_j[6] = compressed_instruction[7];
                    immediate_j[7] = compressed_instruction[6];
                    immediate_j[3:1] = compressed_instruction[5:3];
                    immediate_j[5] = compressed_instruction[2];
                    immediate_j[20:12] = {9{immediate_j[11]}};
                    decoded_instruction = encode_j(immediate_j, 5'd1);
                end
                5'b01001: begin // C.LI; rd=x0 is a hint
                    immediate_i = {{6{immediate_ci[5]}}, immediate_ci};
                    decoded_instruction = encode_i(immediate_i, 5'd0, 3'b000, rd, 7'h13);
                end
                5'b01101: begin
                    if (rd == 5'd2) begin // C.ADDI16SP
                        immediate_i = {{2{compressed_instruction[12]}}, compressed_instruction[12],
                                       compressed_instruction[4:3], compressed_instruction[5],
                                       compressed_instruction[2], compressed_instruction[6], 4'b0};
                        if (immediate_i == 0) illegal_compressed = 1'b1;
                        else decoded_instruction = encode_i(immediate_i, 5'd2, 3'b000, 5'd2, 7'h13);
                    end else if (rd == 5'd0 || immediate_ci == 0) begin // reserved C.LUI forms
                        illegal_compressed = 1'b1;
                    end else begin // C.LUI sign-extends the six-bit immediate
                        decoded_instruction = encode_u({{14{immediate_ci[5]}}, immediate_ci}, rd);
                    end
                end
                5'b10001: begin // C.SRLI, C.SRAI, C.ANDI, and register ALU operations
                    case (compressed_instruction[11:10])
                        2'b00: begin // C.SRLI
                            if (compressed_instruction[12]) illegal_compressed = 1'b1;
                            else decoded_instruction = encode_i({7'b0000000, shift_amount[4:0]}, prime_rs1, 3'b101, prime_rs1, 7'h13);
                        end
                        2'b01: begin // C.SRAI
                            if (compressed_instruction[12]) illegal_compressed = 1'b1;
                            else decoded_instruction = encode_i({7'b0100000, shift_amount[4:0]}, prime_rs1, 3'b101, prime_rs1, 7'h13);
                        end
                        2'b10: begin // C.ANDI
                            immediate_i = {{6{immediate_ci[5]}}, immediate_ci};
                            decoded_instruction = encode_i(immediate_i, prime_rs1, 3'b111, prime_rs1, 7'h13);
                        end
                        2'b11: begin
                            if (compressed_instruction[12]) illegal_compressed = 1'b1; // RV64-only SUBW/ADDW space
                            else begin
                                case (compressed_instruction[6:5])
                                    2'b00: decoded_instruction = encode_r(7'b0100000, prime_rs2, prime_rs1, 3'b000, prime_rs1); // C.SUB
                                    2'b01: decoded_instruction = encode_r(7'b0000000, prime_rs2, prime_rs1, 3'b100, prime_rs1); // C.XOR
                                    2'b10: decoded_instruction = encode_r(7'b0000000, prime_rs2, prime_rs1, 3'b110, prime_rs1); // C.OR
                                    2'b11: decoded_instruction = encode_r(7'b0000000, prime_rs2, prime_rs1, 3'b111, prime_rs1); // C.AND
                                endcase
                            end
                        end
                    endcase
                end
                5'b10101: begin // C.J
                    immediate_j[11] = compressed_instruction[12];
                    immediate_j[4] = compressed_instruction[11];
                    immediate_j[9:8] = compressed_instruction[10:9];
                    immediate_j[10] = compressed_instruction[8];
                    immediate_j[6] = compressed_instruction[7];
                    immediate_j[7] = compressed_instruction[6];
                    immediate_j[3:1] = compressed_instruction[5:3];
                    immediate_j[5] = compressed_instruction[2];
                    immediate_j[20:12] = {9{immediate_j[11]}};
                    decoded_instruction = encode_j(immediate_j, 5'd0);
                end
                5'b11001, 5'b11101: begin // C.BEQZ and C.BNEZ
                    immediate_b[8] = compressed_instruction[12];
                    immediate_b[4:3] = compressed_instruction[11:10];
                    immediate_b[7:6] = compressed_instruction[6:5];
                    immediate_b[2:1] = compressed_instruction[4:3];
                    immediate_b[5] = compressed_instruction[2];
                    immediate_b[12:9] = {4{immediate_b[8]}};
                    decoded_instruction = encode_b(immediate_b, 5'd0, prime_rs1,
                                                   (function3 == 3'b110) ? 3'b000 : 3'b001);
                end

                5'b00010: begin // C.SLLI; rd=x0 is a hint
                    if (compressed_instruction[12]) illegal_compressed = 1'b1;
                    else decoded_instruction = encode_i({7'b0000000, shift_amount[4:0]}, rd, 3'b001, rd, 7'h13);
                end
                5'b01010: begin // C.LWSP
                    immediate_i = {4'b0, compressed_instruction[3:2], compressed_instruction[12],
                                   compressed_instruction[6:4], 2'b00};
                    if (rd == 5'd0) illegal_compressed = 1'b1;
                    else decoded_instruction = encode_i(immediate_i, 5'd2, 3'b010, rd, 7'h03);
                end
                5'b10010: begin // C.JR, C.MV, C.EBREAK, C.JALR, and C.ADD
                    if (!compressed_instruction[12]) begin
                        if (rs2 == 5'd0) begin
                            if (rd == 5'd0) illegal_compressed = 1'b1;
                            else decoded_instruction = encode_i(12'b0, rd, 3'b000, 5'd0, 7'h67); // C.JR
                        end else if (rd == 5'd0) illegal_compressed = 1'b1;
                        else decoded_instruction = encode_r(7'b0, rs2, 5'd0, 3'b000, rd); // C.MV
                    end else if (rd == 5'd0 && rs2 == 5'd0) begin
                        decoded_instruction = 32'h0010_0073; // C.EBREAK
                    end else if (rs2 == 5'd0) begin
                        decoded_instruction = encode_i(12'b0, rd, 3'b000, 5'd1, 7'h67); // C.JALR
                    end else if (rd == 5'd0) illegal_compressed = 1'b1;
                    else decoded_instruction = encode_r(7'b0, rs2, rd, 3'b000, rd); // C.ADD
                end
                5'b11010: begin // C.SWSP
                    immediate_s = {4'b0, compressed_instruction[8:7], compressed_instruction[12:9], 2'b00};
                    decoded_instruction = encode_s(immediate_s, rs2, 5'd2);
                end
                default: illegal_compressed = 1'b1;
            endcase
        end
    end
endmodule
