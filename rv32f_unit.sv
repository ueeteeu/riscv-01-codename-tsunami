// Simulation-oriented RV32F instruction subset from the RISC-V reference card.
// Arithmetic uses SystemVerilog real values and is not intended for synthesis.
module rv32f_unit (
    input  logic [31:0] instruction,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [31:0] operand_c,
    output logic        recognized,
    output logic        writes_fp_register,
    output logic [31:0] result
);
    logic [6:0] opcode;
    logic [6:0] function7;
    logic [2:0] function3;
    logic [4:0] source2;
    logic [2:0] rounding_mode;
    logic        sign_a;
    logic        sign_b;
    logic        sign_c;
    logic        nan_a;
    logic        nan_b;
    logic        nan_c;
    logic        infinity_a;
    logic        infinity_b;
    logic        infinity_c;
    real         real_a;
    real         real_b;
    real         real_c;
    real         real_result;
    real         integer_result;
    logic [31:0] fp_result;

    function automatic logic is_nan(input logic [31:0] value);
        is_nan = (value[30:23] == 8'hff) && (value[22:0] != 0);
    endfunction

    function automatic logic is_infinity(input logic [31:0] value);
        is_infinity = (value[30:23] == 8'hff) && (value[22:0] == 0);
    endfunction

    function automatic logic [31:0] quiet_nan;
        quiet_nan = 32'h7fc0_0000;
    endfunction

    function automatic real single_to_real(input logic [31:0] value);
        real magnitude;
        begin
            if (value[30:23] == 0) begin
                magnitude = $itor(value[22:0]) / 8388608.0;
                magnitude = magnitude * (2.0 ** -126);
            end else begin
                magnitude = (1.0 + ($itor(value[22:0]) / 8388608.0)) *
                            (2.0 ** ($itor(value[30:23]) - 127.0));
            end
            single_to_real = value[31] ? -magnitude : magnitude;
        end
    endfunction

    function automatic logic [31:0] real_to_single(
        input real value,
        input logic [2:0] mode
    );
        logic [63:0] bits;
        logic [63:0] significand;
        logic [63:0] retained;
        logic [24:0] rounded_normal;
        logic [23:0] rounded_subnormal;
        logic [7:0] exponent_field;
        logic sign;
        logic guard_bit;
        logic sticky_bit;
        logic discarded;
        logic increment;
        integer exponent;
        integer shift_amount;
        begin
            bits = $realtobits(value);
            sign = bits[63];
            exponent = bits[62:52] - 1023;
            significand = {1'b1, bits[51:0]};
            discarded = 1'b0;
            increment = 1'b0;
            guard_bit = 1'b0;
            sticky_bit = 1'b0;

            if (bits[62:52] == 11'h7ff) begin
                if (bits[51:0] == 0) begin
                    real_to_single = {sign, 8'hff, 23'b0};
                end else begin
                    real_to_single = quiet_nan();
                end
            end else if (bits[62:52] == 0 && bits[51:0] == 0) begin
                real_to_single = {sign, 31'b0};
            end else if (exponent > 127) begin
                case (mode)
                    3'b001: real_to_single = {sign, 8'hfe, 23'h7fffff};
                    3'b010: real_to_single = sign ? {1'b1, 8'hff, 23'b0} : {1'b0, 8'hfe, 23'h7fffff};
                    3'b011: real_to_single = sign ? {1'b1, 8'hfe, 23'h7fffff} : {1'b0, 8'hff, 23'b0};
                    default: real_to_single = {sign, 8'hff, 23'b0};
                endcase
            end else if (exponent >= -126) begin
                retained = significand >> 29;
                guard_bit = significand[28];
                sticky_bit = |significand[27:0];
                discarded = guard_bit | sticky_bit;
                case (mode)
                    3'b000: increment = guard_bit && (sticky_bit || retained[0]);
                    3'b001: increment = 1'b0;
                    3'b010: increment = sign && discarded;
                    3'b011: increment = !sign && discarded;
                    3'b100: increment = guard_bit;
                    default: increment = 1'b0;
                endcase
                rounded_normal = {1'b0, retained[23:0]} + increment;
                if (rounded_normal[24]) begin
                    exponent = exponent + 1;
                    exponent_field = exponent + 127;
                    if (exponent > 127) begin
                        case (mode)
                            3'b001: real_to_single = {sign, 8'hfe, 23'h7fffff};
                            3'b010: real_to_single = sign ? {1'b1, 8'hff, 23'b0} : {1'b0, 8'hfe, 23'h7fffff};
                            3'b011: real_to_single = sign ? {1'b1, 8'hfe, 23'h7fffff} : {1'b0, 8'hff, 23'b0};
                            default: real_to_single = {sign, 8'hff, 23'b0};
                        endcase
                    end else begin
                        real_to_single = {sign, exponent_field, 23'b0};
                    end
                end else begin
                    exponent_field = exponent + 127;
                    real_to_single = {sign, exponent_field, rounded_normal[22:0]};
                end
            end else begin
                shift_amount = -(exponent + 97);
                if (shift_amount >= 64) begin
                    retained = 0;
                    guard_bit = 1'b0;
                    sticky_bit = (significand != 0);
                end else begin
                    retained = significand >> shift_amount;
                    guard_bit = significand[shift_amount - 1];
                    sticky_bit = 1'b0;
                    for (integer bit_index = 0; bit_index < 64; bit_index = bit_index + 1) begin
                        if (bit_index < shift_amount - 1) sticky_bit = sticky_bit | significand[bit_index];
                    end
                end
                discarded = guard_bit | sticky_bit;
                case (mode)
                    3'b000: increment = guard_bit && (sticky_bit || retained[0]);
                    3'b001: increment = 1'b0;
                    3'b010: increment = sign && discarded;
                    3'b011: increment = !sign && discarded;
                    3'b100: increment = guard_bit;
                    default: increment = 1'b0;
                endcase
                rounded_subnormal = retained[23:0] + increment;
                if (rounded_subnormal[23]) begin
                    real_to_single = {sign, 8'h01, 23'b0};
                end else begin
                    real_to_single = {sign, 8'h00, rounded_subnormal[22:0]};
                end
            end
        end
    endfunction

    function automatic real round_to_integer(
        input real value,
        input logic [2:0] mode
    );
        real lower;
        real fraction;
        real rounded;
        integer lower_integer;
        begin
            lower = $floor(value);
            fraction = value - lower;
            rounded = lower;
            case (mode)
                3'b000: begin
                    if (fraction > 0.5) rounded = lower + 1.0;
                    else if (fraction == 0.5) begin
                        lower_integer = $rtoi(lower);
                        if (lower_integer[0]) rounded = lower + 1.0;
                    end
                end
                3'b001: rounded = value < 0.0 ? $ceil(value) : $floor(value);
                3'b010: rounded = $floor(value);
                3'b011: rounded = $ceil(value);
                3'b100: begin
                    if (fraction > 0.5 || (fraction == 0.5 && value >= 0.0))
                        rounded = lower + 1.0;
                end
                default: rounded = value;
            endcase
            round_to_integer = rounded;
        end
    endfunction

    function automatic logic [31:0] classify_single(input logic [31:0] value);
        begin
            classify_single = 32'b0;
            if (is_nan(value)) classify_single[value[22] ? 9 : 8] = 1'b1;
            else if (is_infinity(value)) classify_single[value[31] ? 0 : 7] = 1'b1;
            else if (value[30:0] == 0) classify_single[value[31] ? 3 : 4] = 1'b1;
            else if (value[30:23] == 0) classify_single[value[31] ? 2 : 5] = 1'b1;
            else classify_single[value[31] ? 1 : 6] = 1'b1;
        end
    endfunction

    always_comb begin
        opcode = instruction[6:0];
        function7 = instruction[31:25];
        function3 = instruction[14:12];
        source2 = instruction[24:20];
        rounding_mode = function3;
        sign_a = operand_a[31];
        sign_b = operand_b[31];
        sign_c = operand_c[31];
        nan_a = is_nan(operand_a);
        nan_b = is_nan(operand_b);
        nan_c = is_nan(operand_c);
        infinity_a = is_infinity(operand_a);
        infinity_b = is_infinity(operand_b);
        infinity_c = is_infinity(operand_c);
        real_a = single_to_real(operand_a);
        real_b = single_to_real(operand_b);
        real_c = single_to_real(operand_c);
        real_result = 0.0;
        integer_result = 0.0;
        fp_result = quiet_nan();
        recognized = 1'b0;
        writes_fp_register = 1'b0;
        result = 32'b0;

        case (opcode)
            7'b1010011: begin
                case (function7)
                    7'b0000000, 7'b0000100, 7'b0001000, 7'b0001100,
                    7'b0101100, 7'b1100000, 7'b1101000: begin
                        if (rounding_mode <= 3'b100 &&
                            ((function7 != 7'b0101100 && function7 != 7'b1100000 &&
                              function7 != 7'b1101000) || source2 <= 5'd1) &&
                            (function7 != 7'b0101100 || source2 == 0)) begin
                            recognized = 1'b1;
                            writes_fp_register = (function7 == 7'b0000000) ||
                                                 (function7 == 7'b0000100) ||
                                                 (function7 == 7'b0001000) ||
                                                 (function7 == 7'b0001100) ||
                                                 (function7 == 7'b0101100) ||
                                                 (function7 == 7'b1101000);
                            case (function7)
                                7'b0000000: begin // FADD.S
                                    if (nan_a || nan_b ||
                                        (infinity_a && infinity_b && (sign_a != sign_b))) fp_result = quiet_nan();
                                    else if (infinity_a) fp_result = {sign_a, 8'hff, 23'b0};
                                    else if (infinity_b) fp_result = {sign_b, 8'hff, 23'b0};
                                    else fp_result = real_to_single(real_a + real_b, rounding_mode);
                                end
                                7'b0000100: begin // FSUB.S
                                    if (nan_a || nan_b ||
                                        (infinity_a && infinity_b && (sign_a == sign_b))) fp_result = quiet_nan();
                                    else if (infinity_a) fp_result = {sign_a, 8'hff, 23'b0};
                                    else if (infinity_b) fp_result = {!sign_b, 8'hff, 23'b0};
                                    else fp_result = real_to_single(real_a - real_b, rounding_mode);
                                end
                                7'b0001000: begin // FMUL.S
                                    if (nan_a || nan_b ||
                                        ((infinity_a && operand_b[30:0] == 0) ||
                                         (infinity_b && operand_a[30:0] == 0))) fp_result = quiet_nan();
                                    else if (infinity_a || infinity_b) fp_result = {sign_a ^ sign_b, 8'hff, 23'b0};
                                    else fp_result = real_to_single(real_a * real_b, rounding_mode);
                                end
                                7'b0001100: begin // FDIV.S
                                    if (nan_a || nan_b ||
                                        ((operand_a[30:0] == 0) && (operand_b[30:0] == 0)) ||
                                        (infinity_a && infinity_b)) fp_result = quiet_nan();
                                    else if (infinity_a || operand_b[30:0] == 0)
                                        fp_result = {sign_a ^ sign_b, 8'hff, 23'b0};
                                    else if (infinity_b || operand_a[30:0] == 0)
                                        fp_result = {sign_a ^ sign_b, 31'b0};
                                    else fp_result = real_to_single(real_a / real_b, rounding_mode);
                                end
                                7'b0101100: begin // FSQRT.S
                                    if (nan_a || (sign_a && operand_a[30:0] != 0)) fp_result = quiet_nan();
                                    else if (infinity_a) fp_result = operand_a;
                                    else fp_result = real_to_single($sqrt(real_a), rounding_mode);
                                end
                                7'b1100000: begin // FCVT.W[U].S
                                    writes_fp_register = 1'b0;
                                    if (nan_a) fp_result = 32'hffff_ffff;
                                    else if (infinity_a) begin
                                        if (source2 == 0)
                                            fp_result = sign_a ? 32'h8000_0000 : 32'h7fff_ffff;
                                        else
                                            fp_result = sign_a ? 32'b0 : 32'hffff_ffff;
                                    end
                                    else begin
                                        integer_result = round_to_integer(real_a, rounding_mode);
                                        if (source2 == 0) begin
                                            if (integer_result < -2147483648.0)
                                                fp_result = 32'h8000_0000;
                                            else if (integer_result >= 2147483648.0)
                                                fp_result = 32'h7fff_ffff;
                                            else fp_result = $rtoi(integer_result);
                                        end else begin
                                            if (integer_result < 0.0)
                                                fp_result = 32'b0;
                                            else if (integer_result >= 4294967296.0)
                                                fp_result = 32'hffff_ffff;
                                            else if (integer_result >= 2147483648.0)
                                                fp_result = 32'h8000_0000 | $rtoi(integer_result - 2147483648.0);
                                            else fp_result = $rtoi(integer_result);
                                        end
                                    end
                                end
                                7'b1101000: begin // FCVT.S.W[U]
                                    if (source2 == 0) real_result = $itor($signed(operand_a));
                                    else real_result = $itor(operand_a[30:0]) +
                                                       (operand_a[31] ? 2147483648.0 : 0.0);
                                    fp_result = real_to_single(real_result, rounding_mode);
                                end
                                default: begin end
                            endcase
                            result = fp_result;
                        end
                    end
                    7'b0010000: begin // FSGNJ.S, FSGNJN.S, FSGNJX.S
                        if (function3 <= 3'b010) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            case (function3)
                                3'b000: result = {sign_b, operand_a[30:0]};
                                3'b001: result = {!sign_b, operand_a[30:0]};
                                3'b010: result = {sign_a ^ sign_b, operand_a[30:0]};
                                default: begin end
                            endcase
                        end
                    end
                    7'b0010100: begin // FMIN.S, FMAX.S
                        if (function3 <= 3'b001) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            if (nan_a && nan_b) result = quiet_nan();
                            else if (nan_a) result = operand_b;
                            else if (nan_b) result = operand_a;
                            else if (operand_a[30:0] == 0 && operand_b[30:0] == 0)
                                result = (function3 == 0) ? {sign_a | sign_b, 31'b0} :
                                                           {sign_a & sign_b, 31'b0};
                            else begin
                                real_result = (function3 == 0) ?
                                              ((real_a < real_b) ? real_a : real_b) :
                                              ((real_a > real_b) ? real_a : real_b);
                                result = real_to_single(real_result, 3'b000);
                            end
                        end
                    end
                    7'b1010000: begin // FEQ.S, FLT.S, FLE.S
                        if (function3 <= 3'b010) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b0;
                            if (!nan_a && !nan_b) begin
                                case (function3)
                                    3'b000: result = (real_a == real_b);
                                    3'b001: result = (real_a < real_b);
                                    3'b010: result = (real_a <= real_b);
                                    default: begin end
                                endcase
                            end
                        end
                    end
                    7'b1110000: begin // FMV.X.W and FCLASS.S
                        if (source2 == 0 && function3 <= 3'b001) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b0;
                            result = (function3 == 0) ? operand_a : classify_single(operand_a);
                        end
                    end
                    7'b1111000: begin // FMV.W.X
                        if (source2 == 0 && function3 == 0) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            result = operand_a;
                        end
                    end
                    default: begin end
                endcase
            end
            7'b1000011, 7'b1000111, 7'b1001011, 7'b1001111: begin
                if (rounding_mode <= 3'b100) begin
                    recognized = 1'b1;
                    writes_fp_register = 1'b1;
                    case (opcode)
                        7'b1000011: begin // FMADD.S
                            if (nan_a || nan_b || nan_c ||
                                ((infinity_a || infinity_b) && (operand_a[30:0] == 0 || operand_b[30:0] == 0)) ||
                                ((infinity_a || infinity_b) && infinity_c &&
                                 ((sign_a ^ sign_b) != (opcode == 7'b1001011 ? !sign_c : sign_c))))
                                fp_result = quiet_nan();
                            else if (infinity_a || infinity_b) fp_result = {sign_a ^ sign_b, 8'hff, 23'b0};
                            else if (infinity_c) fp_result = {sign_c, 8'hff, 23'b0};
                            else fp_result = real_to_single((real_a * real_b) + real_c, rounding_mode);
                        end
                        7'b1000111: begin // FMSUB.S
                            if (nan_a || nan_b || nan_c ||
                                ((infinity_a || infinity_b) &&
                                 (operand_a[30:0] == 0 || operand_b[30:0] == 0)) ||
                                ((infinity_a || infinity_b) && infinity_c &&
                                 ((sign_a ^ sign_b) == sign_c))) fp_result = quiet_nan();
                            else if (infinity_a || infinity_b) fp_result = {sign_a ^ sign_b, 8'hff, 23'b0};
                            else if (infinity_c) fp_result = {!sign_c, 8'hff, 23'b0};
                            else fp_result = real_to_single((real_a * real_b) - real_c, rounding_mode);
                        end
                        7'b1001011: begin // FNMSUB.S
                            if (nan_a || nan_b || nan_c ||
                                ((infinity_a || infinity_b) &&
                                 (operand_a[30:0] == 0 || operand_b[30:0] == 0)) ||
                                ((infinity_a || infinity_b) && infinity_c &&
                                 ((sign_a ^ sign_b) == sign_c))) fp_result = quiet_nan();
                            else if (infinity_a || infinity_b) fp_result = {!(sign_a ^ sign_b), 8'hff, 23'b0};
                            else if (infinity_c) fp_result = {sign_c, 8'hff, 23'b0};
                            else fp_result = real_to_single(-((real_a * real_b) - real_c), rounding_mode);
                        end
                        7'b1001111: begin // FNMADD.S
                            if (nan_a || nan_b || nan_c ||
                                ((infinity_a || infinity_b) &&
                                 (operand_a[30:0] == 0 || operand_b[30:0] == 0)) ||
                                ((infinity_a || infinity_b) && infinity_c &&
                                 ((sign_a ^ sign_b) != sign_c))) fp_result = quiet_nan();
                            else if (infinity_a || infinity_b) fp_result = {!(sign_a ^ sign_b), 8'hff, 23'b0};
                            else if (infinity_c) fp_result = {!sign_c, 8'hff, 23'b0};
                            else fp_result = real_to_single(-((real_a * real_b) + real_c), rounding_mode);
                        end
                        default: begin end
                    endcase
                    result = fp_result;
                end
            end
            default: begin end
        endcase

        if (!recognized) begin
            writes_fp_register = 1'b0;
            result = 32'b0;
        end
    end
endmodule
