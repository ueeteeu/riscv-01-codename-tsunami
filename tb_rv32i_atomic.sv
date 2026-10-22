// Smoke test for the single-hart RV32A word atomics in rv32i_single_cycle.
module tb_rv32i_atomic;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address;
    logic [31:0] instruction;
    logic [31:0] data_address;
    logic [31:0] data_write_data;
    logic data_write_enable;
    logic [31:0] data_read_data;
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
        input logic [11:0] immediate,
        input logic [4:0] source,
        input logic [2:0] operation,
        input logic [4:0] destination
    );
        encode_i = {immediate, source, operation, destination, 7'h13};
    endfunction

    function automatic logic [31:0] encode_s(
        input logic [11:0] immediate,
        input logic [4:0] source2,
        input logic [4:0] source1
    );
        encode_s = {immediate[11:5], source2, source1, 3'b010,
                    immediate[4:0], 7'h23};
    endfunction

    function automatic logic [31:0] encode_amo(
        input logic [4:0] operation,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [4:0] destination
    );
        encode_amo = {operation, 2'b00, source2, source1, 3'b010,
                      destination, 7'h2f};
    endfunction

    initial begin
        #1;
        memory.words[0] = encode_i(12'd256, 0, 3'b000, 1);         // base address
        memory.words[1] = encode_i(12'd41, 0, 3'b000, 2);          // initial/new value
        memory.words[2] = encode_s(0, 2, 1);                       // sw x2,0(x1)
        memory.words[3] = encode_amo(5'b00010, 0, 1, 3);           // lr.w x3,(x1)
        memory.words[4] = encode_i(12'd42, 0, 3'b000, 4);          // value for SC/AMOADD
        memory.words[5] = encode_amo(5'b00011, 4, 1, 5);           // sc.w x5,x4,(x1)
        memory.words[6] = encode_amo(5'b00000, 4, 1, 6);           // amoadd.w x6,x4,(x1)
        memory.words[7] = encode_amo(5'b00001, 2, 1, 7);           // amoswap.w x7,x2,(x1)
        memory.words[8] = encode_amo(5'b00011, 2, 1, 8);           // SC fails: reservation was consumed
        memory.words[9] = 32'h0000_006f;                            // jal x0,0

        #11 reset = 1'b0;
        repeat (14) @(negedge clk);

        if (cpu.registers[3] !== 32'd41 || cpu.registers[5] !== 32'd0 ||
            cpu.registers[6] !== 32'd42 || cpu.registers[7] !== 32'd84 ||
            cpu.registers[8] !== 32'd1 || memory.words[64] !== 32'd41) begin
            $fatal(1, "LR/SC or AMO result mismatch");
        end
        if (illegal_instruction !== 1'b0) begin
            $fatal(1, "A supported atomic instruction was marked illegal");
        end

        $display("RV32A word-atomic smoke test passed");
        $finish;
    end
endmodule
