// Simulation-oriented RV32D execution subset using the simulator's real type.
// The implementation follows IEEE encodings for state and special values but
// is not synthesizable or a substitute for a hardware floating-point unit.
module rv32d_unit (
    input  logic [31:0] instruction,
    input  logic [63:0] operand_a,
    input  logic [63:0] operand_b,
    input  logic [63:0] operand_c,
    input  logic [31:0] integer_operand,
    input  logic [2:0]  dynamic_rounding_mode,
    output logic        recognized,
    output logic        writes_fp_register,
    output logic [63:0] result,
    output logic [4:0]  exception_flags
);
    logic [6:0] opcode;
    logic [6:0] function7;
    logic [2:0] function3;
    logic [4:0] source2;
    logic [2:0] rounding_mode;
    logic nan_a, nan_b, nan_c;
    logic infinity_a, infinity_b, infinity_c;
    logic [63:0] bits_result;
    logic [31:0] single_result;
    logic [63:0] integer_bits;
    real real_a, real_b, real_c, real_result, rounded_integer;

    // Decode NaN-boxed single values from their IEEE-754 fields rather than
    // interpreting the 32-bit encoding as the simulator's 64-bit real layout.

    function automatic logic is_nan(input logic [63:0] value);
        is_nan = (value[62:52] == 11'h7ff) && (value[51:0] != 0);
    endfunction

    function automatic logic is_infinity(input logic [63:0] value);
        is_infinity = (value[62:52] == 11'h7ff) && (value[51:0] == 0);
    endfunction

    function automatic real round_integer(input real value, input logic [2:0] mode);
        real lower;
        real fraction;
        integer low_integer;
        begin
            lower = $floor(value);
            fraction = value - lower;
            case (mode)
                3'b000: begin
                    if (fraction > 0.5) round_integer = lower + 1.0;
                    else if (fraction == 0.5) begin
                        low_integer = $rtoi(lower);
                        round_integer = low_integer[0] ? lower + 1.0 : lower;
                    end else round_integer = lower;
                end
                3'b001: round_integer = value < 0.0 ? $ceil(value) : $floor(value);
                3'b010: round_integer = $floor(value);
                3'b011: round_integer = $ceil(value);
                3'b100: round_integer = (fraction > 0.5 ||
                                           (fraction == 0.5 && value >= 0.0)) ?
                                          lower + 1.0 : lower;
                default: round_integer = value;
            endcase
        end
    endfunction

    function automatic logic [31:0] pack_single(input real value);
        logic [63:0] raw;
        logic [31:0] encoded;
        real magnitude;
        integer exponent;
        begin
            // Convert host binary64 to the single-precision encoding used by
            // FCVT.S.D; the simulator real API limits exact rounding guarantees.
            raw = $realtobits(value);
            if (raw[62:52] == 11'h7ff) begin
                encoded = raw[51:0] == 0 ? {raw[63], 8'hff, 23'b0} : 32'h7fc0_0000;
            end else if (raw[62:52] == 0 && raw[51:0] == 0) begin
                encoded = {raw[63], 31'b0};
            end else begin
                magnitude = value < 0.0 ? -value : value;
                exponent = $rtoi($floor($ln(magnitude) / $ln(2.0)));
                encoded = 32'b0;
                encoded[31] = raw[63];
                encoded[30:23] = exponent + 127;
                encoded[22:0] = $rtoi((magnitude / (2.0 ** exponent) - 1.0) * 8388608.0);
            end
            pack_single = encoded;
        end
    endfunction

    function automatic logic [31:0] classify_double(input logic [63:0] value);
        begin
            classify_double = 32'b0;
            if (is_nan(value)) classify_double[value[51] ? 9 : 8] = 1'b1;
            else if (is_infinity(value)) classify_double[value[63] ? 0 : 7] = 1'b1;
            else if (value[62:0] == 0) classify_double[value[63] ? 3 : 4] = 1'b1;
            else if (value[62:52] == 0) classify_double[value[63] ? 2 : 5] = 1'b1;
            else classify_double[value[63] ? 1 : 6] = 1'b1;
        end
    endfunction

    function automatic real single_to_real(input logic [31:0] value);
        real magnitude;
        integer exponent;
        begin
            exponent = value[30:23];
            if (exponent == 8'hff) begin
                single_to_real = $bitstoreal({value[31], 11'h7ff,
                                             value[22:0], 29'b0});
            end else if (exponent == 0) begin
                magnitude = ($itor(value[22:0]) / 8388608.0) * (2.0 ** -126);
                single_to_real = value[31] ? -magnitude : magnitude;
            end else begin
                magnitude = (1.0 + ($itor(value[22:0]) / 8388608.0)) *
                            (2.0 ** (exponent - 127));
                single_to_real = value[31] ? -magnitude : magnitude;
            end
        end
    endfunction

    always_comb begin
        opcode = instruction[6:0];
        function7 = instruction[31:25];
        function3 = instruction[14:12];
        source2 = instruction[24:20];
        // Rounding mode 111 selects frm; only recognized modes 000-100 execute.
        rounding_mode = function3 == 3'b111 ? dynamic_rounding_mode : function3;
        nan_a = is_nan(operand_a);
        nan_b = is_nan(operand_b);
        nan_c = is_nan(operand_c);
        infinity_a = is_infinity(operand_a);
        infinity_b = is_infinity(operand_b);
        infinity_c = is_infinity(operand_c);
        real_a = $bitstoreal(operand_a);
        real_b = $bitstoreal(operand_b);
        real_c = $bitstoreal(operand_c);
        real_result = 0.0;
        rounded_integer = 0.0;
        bits_result = 64'h7ff8_0000_0000_0000;
        single_result = 32'h7fc0_0000;
        integer_bits = 0;
        recognized = 1'b0;
        writes_fp_register = 1'b0;
        result = 64'b0;
        exception_flags = 5'b0;

        case (opcode)
            7'b1010011: begin
                case (function7)
                    7'b0000001, 7'b0000101, 7'b0001001, 7'b0001101,
                    7'b0101101: begin
                        if (rounding_mode <= 3'b100 &&
                            (function7 != 7'b0101101 || source2 == 0)) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            case (function7)
                                7'b0000001: begin
                                    if (nan_a || nan_b ||
                                        (infinity_a && infinity_b && (operand_a[63] != operand_b[63]))) begin
                                        bits_result = 64'h7ff8_0000_0000_0000;
                                        exception_flags[4] = !nan_a && !nan_b;
                                    end else if (infinity_a) bits_result = {operand_a[63], 11'h7ff, 52'b0};
                                    else if (infinity_b) bits_result = {operand_b[63], 11'h7ff, 52'b0};
                                    else bits_result = $realtobits(real_a + real_b);
                                end
                                7'b0000101: begin
                                    if (nan_a || nan_b ||
                                        (infinity_a && infinity_b && (operand_a[63] == operand_b[63]))) begin
                                        bits_result = 64'h7ff8_0000_0000_0000;
                                        exception_flags[4] = !nan_a && !nan_b;
                                    end else if (infinity_a) bits_result = {operand_a[63], 11'h7ff, 52'b0};
                                    else if (infinity_b) bits_result = {!operand_b[63], 11'h7ff, 52'b0};
                                    else bits_result = $realtobits(real_a - real_b);
                                end
                                7'b0001001: begin
                                    if (nan_a || nan_b ||
                                        ((infinity_a && operand_b[62:0] == 0) ||
                                         (infinity_b && operand_a[62:0] == 0))) begin
                                        bits_result = 64'h7ff8_0000_0000_0000;
                                        exception_flags[4] = !nan_a && !nan_b;
                                    end else if (infinity_a || infinity_b)
                                        bits_result = {operand_a[63] ^ operand_b[63], 11'h7ff, 52'b0};
                                    else bits_result = $realtobits(real_a * real_b);
                                end
                                7'b0001101: begin
                                    if (nan_a || nan_b ||
                                        ((operand_a[62:0] == 0) && (operand_b[62:0] == 0)) ||
                                        (infinity_a && infinity_b)) begin
                                        bits_result = 64'h7ff8_0000_0000_0000;
                                        exception_flags[4] = !nan_a && !nan_b;
                                    end else if (operand_b[62:0] == 0) begin
                                        bits_result = {operand_a[63] ^ operand_b[63], 11'h7ff, 52'b0};
                                        exception_flags[3] = 1'b1;
                                    end else if (infinity_a)
                                        bits_result = {operand_a[63] ^ operand_b[63], 11'h7ff, 52'b0};
                                    else if (infinity_b || operand_a[62:0] == 0)
                                        bits_result = {operand_a[63] ^ operand_b[63], 63'b0};
                                    else bits_result = $realtobits(real_a / real_b);
                                end
                                7'b0101101: begin
                                    if (nan_a || (operand_a[63] && operand_a[62:0] != 0)) begin
                                        bits_result = 64'h7ff8_0000_0000_0000;
                                        exception_flags[4] = !nan_a;
                                    end else if (infinity_a) bits_result = operand_a;
                                    else bits_result = $realtobits($sqrt(real_a));
                                end
                                default: begin end
                            endcase
                            if (!nan_a && !nan_b && !infinity_a && !infinity_b &&
                                bits_result[62:52] == 11'h7ff &&
                                bits_result[51:0] == 0 &&
                                !(function7 == 7'b0001101 && operand_b[62:0] == 0)) begin
                                exception_flags[2] = 1'b1;
                                exception_flags[0] = 1'b1;
                            end
                            result = bits_result;
                        end
                    end
                    7'b0010001: begin
                        if (function3 <= 3'b010) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            case (function3)
                                3'b000: result = {operand_b[63], operand_a[62:0]};
                                3'b001: result = {!operand_b[63], operand_a[62:0]};
                                3'b010: result = {operand_a[63] ^ operand_b[63], operand_a[62:0]};
                                default: begin end
                            endcase
                        end
                    end
                    7'b0010101: begin
                        if (function3 <= 3'b001) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            if (nan_a && nan_b) result = 64'h7ff8_0000_0000_0000;
                            else if (nan_a) result = operand_b;
                            else if (nan_b) result = operand_a;
                            else result = $realtobits((function3 == 0) ?
                                                       ((real_a < real_b) ? real_a : real_b) :
                                                       ((real_a > real_b) ? real_a : real_b));
                            if ((nan_a && operand_a[51]) || (nan_b && operand_b[51]))
                                exception_flags[4] = 1'b1;
                        end
                    end
                    7'b1010001: begin
                        if (function3 <= 3'b010) begin
                            recognized = 1'b1;
                            if (!nan_a && !nan_b) begin
                                case (function3)
                                    3'b000: result = (real_a == real_b);
                                    3'b001: result = (real_a < real_b);
                                    3'b010: result = (real_a <= real_b);
                                    default: begin end
                                endcase
                            end else if (function3 != 0 ||
                                         (operand_a[51] && nan_a) || (operand_b[51] && nan_b))
                                exception_flags[4] = 1'b1;
                        end
                    end
                    7'b1110001: begin
                        if (source2 == 0 && function3 <= 3'b001) begin
                            recognized = 1'b1;
                            result = function3 == 0 ? operand_a : {32'b0, classify_double(operand_a)};
                        end
                    end
                    7'b0100000: begin // FCVT.S.D
                        if (source2 == 1 && rounding_mode <= 3'b100) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            single_result = pack_single(real_a);
                            result = {32'hffff_ffff, single_result};
                            if (is_nan(operand_a)) exception_flags[4] = operand_a[51];
                            else if (!infinity_a &&
                                     single_to_real(single_result) != real_a) begin
                                exception_flags[0] = 1'b1;
                                if (single_result[30:23] == 8'hff)
                                    exception_flags[2] = 1'b1;
                                if (single_result[30:23] == 0)
                                    exception_flags[1] = 1'b1;
                            end
                        end
                    end
                    7'b0100001: begin // FCVT.D.S
                        if (source2 == 0 && rounding_mode <= 3'b100) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            if (operand_a[63:32] != 32'hffff_ffff) begin
                                result = 64'h7ff8_0000_0000_0000;
                            end else if (operand_a[30:23] == 8'hff &&
                                         operand_a[22:0] != 0) begin
                                result = 64'h7ff8_0000_0000_0000;
                                exception_flags[4] = !operand_a[22];
                            end else begin
                                real_result = single_to_real(operand_a[31:0]);
                                result = $realtobits(real_result);
                            end
                        end
                    end
                    7'b1100001: begin // FCVT.W[U].D
                        if (source2 <= 1 && rounding_mode <= 3'b100) begin
                            recognized = 1'b1;
                            if (nan_a || infinity_a) begin
                                if (source2 == 0) result = operand_a[63] ? 64'hffff_ffff_8000_0000 :
                                                                          64'h0000_0000_7fff_ffff;
                                else result = operand_a[63] ? 64'b0 : 64'h0000_0000_ffff_ffff;
                                exception_flags[4] = 1'b1;
                            end else begin
                                rounded_integer = round_integer(real_a, rounding_mode);
                                if (source2 == 0) begin
                                    if (rounded_integer < -2147483648.0) begin
                                        result = 64'hffff_ffff_8000_0000;
                                        exception_flags[4] = 1'b1;
                                    end else if (rounded_integer >= 2147483648.0) begin
                                        result = 64'h0000_0000_7fff_ffff;
                                        exception_flags[4] = 1'b1;
                                    end else begin
                                        result = $rtoi(rounded_integer);
                                        if (real_a != rounded_integer) exception_flags[0] = 1'b1;
                                    end
                                end else begin
                                    if (rounded_integer < 0.0) begin
                                        result = 0;
                                        exception_flags[4] = 1'b1;
                                    end else if (rounded_integer >= 4294967296.0) begin
                                        result = 64'h0000_0000_ffff_ffff;
                                        exception_flags[4] = 1'b1;
                                    end else begin
                                        result = $rtoi(rounded_integer);
                                        if (real_a != rounded_integer) exception_flags[0] = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                    7'b1101001: begin // FCVT.D.W[U]
                        if (source2 <= 1 && rounding_mode <= 3'b100) begin
                            recognized = 1'b1;
                            writes_fp_register = 1'b1;
                            if (source2 == 0)
                                real_result = $itor($signed(integer_operand));
                            else
                                real_result = $itor(integer_operand[30:0]) +
                                              (integer_operand[31] ? 2147483648.0 : 0.0);
                            result = $realtobits(real_result);
                        end
                    end
                    7'b1111001: begin // FMV.D.X is not defined in RV32
                        recognized = 1'b0;
                    end
                    default: begin end
                endcase
            end
            7'b1000011, 7'b1000111, 7'b1001011, 7'b1001111: begin
                if (instruction[26:25] == 2'b01 && rounding_mode <= 3'b100) begin
                    recognized = 1'b1;
                    writes_fp_register = 1'b1;
                    case (opcode)
                        7'b1000011: real_result = (real_a * real_b) + real_c;
                        7'b1000111: real_result = (real_a * real_b) - real_c;
                        7'b1001011: real_result = -((real_a * real_b) - real_c);
                        7'b1001111: real_result = -((real_a * real_b) + real_c);
                        default: begin end
                    endcase
                    result = $realtobits(real_result);
                    if ((nan_a || nan_b || nan_c) ||
                        ((infinity_a || infinity_b) &&
                         (operand_a[62:0] == 0 || operand_b[62:0] == 0)))
                        exception_flags[4] = 1'b1;
                end
            end
            default: begin end
        endcase

        if (!recognized) begin
            writes_fp_register = 1'b0;
            result = 64'b0;
            exception_flags = 5'b0;
        end
    end
endmodule
