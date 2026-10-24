// Selected RV32 Zba/Zbb/Zbs/Zicond operations for the teaching CPU.
// This module is combinational and reports unrecognized encodings to the
// ordinary integer decoder so standard instructions keep their normal path.
module rv32i_bitmanip (
    input  logic [31:0] instruction,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    output logic        recognized,
    output logic [31:0] result
);
    logic [6:0] opcode;
    logic [6:0] function7;
    logic [2:0] function3;
    logic [4:0] register_index;
    logic [4:0] immediate_index;

    function automatic logic [31:0] count_leading_zeroes(input logic [31:0] value);
        logic found_one;
        begin
            count_leading_zeroes = 32;
            found_one = 1'b0;
            for (integer bit_index = 31; bit_index >= 0; bit_index = bit_index - 1) begin
                if (!found_one && value[bit_index]) begin
                    count_leading_zeroes = 31 - bit_index;
                    found_one = 1'b1;
                end
            end
        end
    endfunction

    function automatic logic [31:0] count_trailing_zeroes(input logic [31:0] value);
        logic found_one;
        begin
            count_trailing_zeroes = 32;
            found_one = 1'b0;
            for (integer bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
                if (!found_one && value[bit_index]) begin
                    count_trailing_zeroes = bit_index;
                    found_one = 1'b1;
                end
            end
        end
    endfunction

    function automatic logic [31:0] population_count(input logic [31:0] value);
        begin
            population_count = 0;
            for (integer bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
                population_count = population_count + value[bit_index];
            end
        end
    endfunction

    always_comb begin
        opcode = instruction[6:0];
        function3 = instruction[14:12];
        function7 = instruction[31:25];
        register_index = instruction[24:20];
        immediate_index = instruction[24:20];
        recognized = 1'b0;
        result = 32'b0;

        case (opcode)
            7'b0110011: begin // Register-register Zbb and Zbs operations
                case ({function7, function3})
                    {7'b0010000, 3'b010}: begin recognized = 1'b1; result = (operand_a << 1) + operand_b; end // SH1ADD
                    {7'b0010000, 3'b100}: begin recognized = 1'b1; result = (operand_a << 2) + operand_b; end // SH2ADD
                    {7'b0010000, 3'b110}: begin recognized = 1'b1; result = (operand_a << 3) + operand_b; end // SH3ADD
                    {7'b0000111, 3'b101}: begin recognized = 1'b1; result = (operand_b == 0) ? 32'b0 : operand_a; end // CZERO.EQZ
                    {7'b0000111, 3'b111}: begin recognized = 1'b1; result = (operand_b != 0) ? 32'b0 : operand_a; end // CZERO.NEZ
                    {7'b0110000, 3'b001}: begin
                        recognized = 1'b1;
                        result = (operand_a << register_index) | (operand_a >> (32 - register_index)); // ROL
                    end
                    {7'b0110000, 3'b101}: begin recognized = 1'b1; result = (operand_a >> register_index) | (operand_a << (32 - register_index)); end // ROR
                    {7'b0100000, 3'b100}: begin recognized = 1'b1; result = ~(operand_a ^ operand_b); end // XNOR
                    {7'b0100000, 3'b110}: begin recognized = 1'b1; result = operand_a | ~operand_b; end // ORN
                    {7'b0100000, 3'b111}: begin recognized = 1'b1; result = operand_a & ~operand_b; end // ANDN
                    {7'b0000101, 3'b100}: begin recognized = 1'b1; result = ($signed(operand_a) < $signed(operand_b)) ? operand_a : operand_b; end // MIN
                    {7'b0000101, 3'b101}: begin recognized = 1'b1; result = ($signed(operand_a) > $signed(operand_b)) ? operand_a : operand_b; end // MAX
                    {7'b0000101, 3'b110}: begin recognized = 1'b1; result = (operand_a < operand_b) ? operand_a : operand_b; end // MINU
                    {7'b0000101, 3'b111}: begin recognized = 1'b1; result = (operand_a > operand_b) ? operand_a : operand_b; end // MAXU
                    {7'b0010100, 3'b001}: begin recognized = 1'b1; result = operand_a | (32'b1 << register_index); end // BSET
                    {7'b0100100, 3'b001}: begin recognized = 1'b1; result = operand_a & ~(32'b1 << register_index); end // BCLR
                    {7'b0110100, 3'b001}: begin recognized = 1'b1; result = operand_a ^ (32'b1 << register_index); end // BINV
                    {7'b0100100, 3'b101}: begin recognized = 1'b1; result = (operand_a >> register_index) & 32'b1; end // BEXT
                    {7'b0000100, 3'b100}: begin
                        if (instruction[24:20] == 5'b0) begin
                            recognized = 1'b1;
                            result = {16'b0, operand_a[15:0]};
                        end
                    end // ZEXT.H (PACK with rs2=x0)
                    default: begin end
                endcase
            end

            7'b0010011: begin // Immediate Zbb and Zbs operations
                case (function3)
                    3'b001: begin
                        case (function7)
                            7'b0110000: begin
                                case (register_index)
                                    5'd0: begin recognized = 1'b1; result = count_leading_zeroes(operand_a); end // CLZ
                                    5'd1: begin recognized = 1'b1; result = count_trailing_zeroes(operand_a); end // CTZ
                                    5'd2: begin recognized = 1'b1; result = population_count(operand_a); end // CPOP
                                    5'd4: begin recognized = 1'b1; result = {{24{operand_a[7]}}, operand_a[7:0]}; end // SEXT.B
                                    5'd5: begin recognized = 1'b1; result = {{16{operand_a[15]}}, operand_a[15:0]}; end // SEXT.H
                                    default: begin end
                                endcase
                            end
                            7'b0010100: begin recognized = 1'b1; result = operand_a | (32'b1 << immediate_index); end // BSETI
                            7'b0100100: begin recognized = 1'b1; result = operand_a & ~(32'b1 << immediate_index); end // BCLRI
                            7'b0110100: begin recognized = 1'b1; result = operand_a ^ (32'b1 << immediate_index); end // BINVI
                            default: begin end
                        endcase
                    end
                    3'b101: begin
                        if (function7 == 7'b0110000) begin // RORI
                            recognized = 1'b1;
                            result = (operand_a >> immediate_index) | (operand_a << (32 - immediate_index));
                        end else if (function7 == 7'b0100100) begin // BEXTI
                            recognized = 1'b1;
                            result = (operand_a >> immediate_index) & 32'b1;
                        end else if (function7 == 7'b0010100 && immediate_index == 5'd7) begin // ORC.B
                            recognized = 1'b1;
                            result = {
                                {8{(|operand_a[31:24])}},
                                {8{(|operand_a[23:16])}},
                                {8{(|operand_a[15:8])}},
                                {8{(|operand_a[7:0])}}
                            };
                        end else if (function7 == 7'b0110100 && immediate_index == 5'd24) begin // REV8
                            recognized = 1'b1;
                            result = {operand_a[7:0], operand_a[15:8], operand_a[23:16], operand_a[31:24]};
                        end
                    end
                    default: begin end
                endcase
            end
            default: begin end
        endcase
    end
endmodule
