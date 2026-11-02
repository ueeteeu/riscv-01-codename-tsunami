// Unit-level checks that each supported compressed FP memory form expands to
// the expected standard load/store instruction and immediate.
module tb_rv32c_fp;
    logic [31:0] fetched_instruction;
    logic [31:0] decoded_instruction;
    logic is_compressed;
    logic illegal_compressed;

    rv32c_decompressor decoder (
        .fetched_instruction(fetched_instruction),
        .decoded_instruction(decoded_instruction),
        .is_compressed(is_compressed),
        .illegal_compressed(illegal_compressed)
    );

    function automatic logic [31:0] encode_i(
        input logic [11:0] immediate,
        input logic [4:0] source1,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_i = {immediate, source1, function3, destination, 7'h07};
    endfunction

    function automatic logic [31:0] encode_s(
        input logic [11:0] immediate,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [2:0] function3
    );
        encode_s = {immediate[11:5], source2, source1, function3,
                    immediate[4:0], 7'h27};
    endfunction

    task automatic expect_decode(
        input logic [15:0] compressed,
        input logic [31:0] expected,
        input string name
    );
        begin
            fetched_instruction = {16'hffff, compressed};
            #1;
            if (!is_compressed || illegal_compressed ||
                decoded_instruction !== expected)
                $fatal(1, "%s decode mismatch: got %h expected %h illegal=%b",
                       name, decoded_instruction, expected, illegal_compressed);
        end
    endtask

    initial begin
        // Quadrant 0: prime registers x13 and f11, with nonzero offsets.
        expect_decode({3'b001, 3'b101, 3'b101, 2'b10, 3'b011, 2'b00},
                      encode_i(12'h0a8, 13, 3'b011, 11), "C.FLD");
        expect_decode({3'b011, 3'b101, 3'b101, 2'b10, 3'b011, 2'b00},
                      encode_i(12'h02c, 13, 3'b010, 11), "C.FLW");
        expect_decode({3'b101, 3'b101, 3'b101, 2'b10, 3'b011, 2'b00},
                      encode_s(12'h0a8, 11, 13, 3'b011), "C.FSD");
        expect_decode({3'b111, 3'b101, 3'b101, 2'b10, 3'b011, 2'b00},
                      encode_s(12'h02c, 11, 13, 3'b010), "C.FSW");

        // Quadrant 2: stack-relative forms use x2 as the base register.
        expect_decode({3'b001, 1'b1, 5'b01011, 5'b10101, 2'b10},
                      encode_i(12'h170, 2, 3'b011, 11), "C.FLDSP");
        expect_decode({3'b011, 1'b1, 5'b01011, 5'b10101, 2'b10},
                      encode_i(12'h074, 2, 3'b010, 11), "C.FLWSP");
        expect_decode({3'b101, 1'b1, 5'b01011, 5'b10101, 2'b10},
                      encode_s(12'h0e8, 21, 2, 3'b011), "C.FSDSP");
        expect_decode({3'b111, 1'b1, 5'b01011, 5'b10101, 2'b10},
                      encode_s(12'h0e8, 21, 2, 3'b010), "C.FSWSP");

        $display("Compressed floating-point decode test passed");
        $finish;
    end
endmodule
