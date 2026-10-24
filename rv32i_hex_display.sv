// Multiplexed eight-digit hexadecimal display for a 32-bit CPU value.
//
// Outputs use active-low polarity, common on FPGA seven-segment boards:
// segment_n[6:0] is ordered {a, b, c, d, e, f, g}, digit_n selects a digit,
// and dp_n controls the decimal point. Digit zero is the rightmost digit.
module rv32i_hex_display #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer DISPLAY_REFRESH_HZ = 60
) (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] display_value,

    output logic [6:0]  segment_n,
    output logic        dp_n,
    output logic [7:0]  digit_n
);
    // Advance the selected digit often enough that all eight appear steady.
    localparam integer SCAN_DIVIDER = CLOCK_HZ / (DISPLAY_REFRESH_HZ * 8);
    localparam integer COUNTER_WIDTH = (SCAN_DIVIDER <= 1) ? 1 : $clog2(SCAN_DIVIDER);

    logic [COUNTER_WIDTH - 1:0] divider_counter;
    logic [2:0] digit_index;
    logic [3:0] current_nibble;

    // Translate one hexadecimal nibble into active-low {a,b,c,d,e,f,g} lines.
    function automatic logic [6:0] hex_to_segments(input logic [3:0] nibble);
        case (nibble)
            4'h0: hex_to_segments = 7'b0000001;
            4'h1: hex_to_segments = 7'b1001111;
            4'h2: hex_to_segments = 7'b0010010;
            4'h3: hex_to_segments = 7'b0000110;
            4'h4: hex_to_segments = 7'b1001100;
            4'h5: hex_to_segments = 7'b0100100;
            4'h6: hex_to_segments = 7'b0100000;
            4'h7: hex_to_segments = 7'b0001111;
            4'h8: hex_to_segments = 7'b0000000;
            4'h9: hex_to_segments = 7'b0000100;
            4'hA: hex_to_segments = 7'b0001000;
            4'hB: hex_to_segments = 7'b1100000;
            4'hC: hex_to_segments = 7'b0110001;
            4'hD: hex_to_segments = 7'b1000010;
            4'hE: hex_to_segments = 7'b0110000;
            4'hF: hex_to_segments = 7'b0111000;
            default: hex_to_segments = 7'b1111111;
        endcase
    endfunction

    // Rotate through one of the eight hexadecimal nibbles of the input word.
    always_comb begin
        case (digit_index)
            3'd0: current_nibble = display_value[3:0];
            3'd1: current_nibble = display_value[7:4];
            3'd2: current_nibble = display_value[11:8];
            3'd3: current_nibble = display_value[15:12];
            3'd4: current_nibble = display_value[19:16];
            3'd5: current_nibble = display_value[23:20];
            3'd6: current_nibble = display_value[27:24];
            3'd7: current_nibble = display_value[31:28];
            default: current_nibble = 4'h0;
        endcase

        // Only the selected digit is enabled; the decimal point stays off.
        digit_n = ~(8'b00000001 << digit_index);
        segment_n = hex_to_segments(current_nibble);
        dp_n = 1'b1;
    end

    // A refresh counter and digit index share the clock; no derived clock is
    // created, which keeps the design straightforward for FPGA timing tools.
    always_ff @(posedge clk) begin
        if (reset) begin
            divider_counter <= '0;
            digit_index <= 3'd0;
        end else if (divider_counter >= SCAN_DIVIDER - 1) begin
            divider_counter <= '0;
            digit_index <= digit_index + 3'd1;
        end else begin
            divider_counter <= divider_counter + 1'b1;
        end
    end
endmodule
