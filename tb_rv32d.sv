// Integration test for RV32D arithmetic, conversion, and 64-bit memory access.
module tb_rv32d;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic [31:0] data_address, data_write_data, data_write_data_next_word;
    logic data_write_enable, data_write_enable_next_word;
    logic [3:0] data_write_mask, data_write_mask_next_word;
    logic [31:0] data_read_data, data_read_data_next_word;
    logic data_access_fault, data_access_fault_next_word;
    logic [2:0] external_interrupts = 3'b000;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;

    rv32i_single_cycle cpu (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_write_data_next_word(data_write_data_next_word),
        .data_write_enable_next_word(data_write_enable_next_word),
        .data_write_mask_next_word(data_write_mask_next_word),
        .data_read_data(data_read_data),
        .data_read_data_next_word(data_read_data_next_word),
        .data_access_fault(data_access_fault),
        .data_access_fault_next_word(data_access_fault_next_word),
        .external_interrupts(external_interrupts),
        .program_counter(program_counter), .illegal_instruction(illegal_instruction)
    );

    rv32i_memory #(.MEMORY_BYTES(512)) memory (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_write_data_next_word(data_write_data_next_word),
        .data_write_enable_next_word(data_write_enable_next_word),
        .data_write_mask_next_word(data_write_mask_next_word),
        .data_read_data(data_read_data),
        .data_read_data_next_word(data_read_data_next_word),
        .data_access_fault(data_access_fault),
        .data_access_fault_next_word(data_access_fault_next_word)
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
        encode_s = {immediate[11:5], source2, source1, 3'b011,
                    immediate[4:0], 7'h27};
    endfunction

    function automatic logic [31:0] encode_fp(
        input logic [6:0] function7,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_fp = {function7, source2, source1, function3, destination, 7'h53};
    endfunction

    function automatic logic [31:0] encode_fused(
        input logic [4:0] source3,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_fused = {source3, 2'b01, source2, source1, 3'b000,
                        destination, opcode};
    endfunction

    initial begin
        #1;
        memory.words[64] = 32'h0000_0000;
        memory.words[65] = 32'h4010_0000; // 4.0
        memory.words[66] = 32'h0000_0000;
        memory.words[67] = 32'h3ff8_0000; // 1.5
        memory.words[68] = 32'h3fc0_0000; // single 1.5
        memory.words[70] = 32'b0;
        memory.words[71] = 32'b0; // 0.0

        memory.words[0]  = encode_i(12'd256, 0, 3'b000, 1, 7'h13);
        memory.words[1]  = encode_i(12'd0, 1, 3'b011, 1, 7'h07); // fld f1,0(x1)
        memory.words[2]  = encode_i(12'd8, 1, 3'b011, 2, 7'h07); // fld f2,8(x1)
        memory.words[3]  = encode_fp(7'b0000001, 2, 1, 3'b000, 3); // fadd.d
        memory.words[4]  = encode_fp(7'b0000101, 2, 1, 3'b000, 4); // fsub.d
        memory.words[5]  = encode_fp(7'b0001001, 2, 1, 3'b000, 5); // fmul.d
        memory.words[6]  = encode_fp(7'b0001101, 2, 1, 3'b000, 6); // fdiv.d
        memory.words[7]  = encode_fp(7'b0101101, 0, 1, 3'b000, 7); // fsqrt.d
        memory.words[8]  = encode_fp(7'b0010001, 2, 1, 3'b000, 8); // fsgnj.d
        memory.words[9]  = encode_fp(7'b0010101, 2, 1, 3'b000, 9); // fmin.d
        memory.words[10] = encode_fp(7'b0010101, 2, 1, 3'b001, 10); // fmax.d
        memory.words[11] = encode_fp(7'b1010001, 2, 1, 3'b000, 2); // feq.d
        memory.words[12] = encode_fp(7'b1010001, 1, 2, 3'b001, 3); // flt.d (x3)
        memory.words[13] = encode_fp(7'b1010001, 2, 2, 3'b010, 4); // fle.d (x4)
        memory.words[14] = encode_fp(7'b1100001, 0, 2, 3'b000, 5); // fcvt.w.d
        memory.words[15] = encode_fp(7'b1100001, 1, 2, 3'b000, 6); // fcvt.wu.d
        memory.words[16] = encode_fp(7'b0100000, 1, 2, 3'b000, 11); // fcvt.s.d
        memory.words[17] = encode_i(12'd16, 1, 3'b010, 13, 7'h07); // flw f13
        memory.words[18] = encode_fp(7'b0100001, 0, 13, 3'b000, 12); // fcvt.d.s
        memory.words[19] = encode_i(12'd5, 0, 3'b000, 7, 7'h13);
        memory.words[20] = encode_fp(7'b1101001, 0, 7, 3'b000, 14); // fcvt.d.w
        memory.words[21] = encode_fp(7'b1101001, 1, 7, 3'b000, 15); // fcvt.d.wu
        memory.words[22] = encode_fp(7'b1110001, 0, 2, 3'b001, 8); // fclass.d
        memory.words[23] = encode_fused(2, 2, 1, 16, 7'b1000111); // fmsub.d
        memory.words[24] = encode_s(12'd32, 3, 1); // fsd f3,32(x1)
        memory.words[25] = encode_i(12'd32, 1, 3'b011, 17, 7'h07); // fld f17,32(x1)
        memory.words[26] = encode_i(12'd24, 1, 3'b011, 18, 7'h07); // fld f18
        memory.words[27] = encode_fp(7'b0001101, 18, 1, 3'b000, 19); // fdiv.d by zero
        memory.words[28] = 32'h0000_006f;

        #11 reset = 1'b0;
        repeat (40) @(negedge clk);

        if (cpu.floating_registers[3] !== 64'h4016_0000_0000_0000 ||
            cpu.floating_registers[4] !== 64'h4004_0000_0000_0000 ||
            cpu.floating_registers[5] !== 64'h4018_0000_0000_0000 ||
            cpu.floating_registers[6] !== 64'h4005_5555_5555_5555 ||
            cpu.floating_registers[7] !== 64'h4000_0000_0000_0000 ||
            cpu.floating_registers[8] !== 64'h4010_0000_0000_0000 ||
            cpu.floating_registers[9] !== 64'h3ff8_0000_0000_0000 ||
            cpu.floating_registers[10] !== 64'h4010_0000_0000_0000 ||
            cpu.floating_registers[11] !== 64'hffff_ffff_3fc0_0000 ||
            cpu.floating_registers[12] !== 64'h3ff8_0000_0000_0000 ||
            cpu.floating_registers[13] !== 64'hffff_ffff_3fc0_0000 ||
            cpu.floating_registers[14] !== 64'h4014_0000_0000_0000 ||
            cpu.floating_registers[15] !== 64'h4014_0000_0000_0000 ||
            cpu.floating_registers[16] !== 64'h4012_0000_0000_0000 ||
            cpu.floating_registers[17] !== 64'h4016_0000_0000_0000 ||
            cpu.floating_registers[19] !== 64'h7ff0_0000_0000_0000 ||
            cpu.registers[2] !== 32'd0 || cpu.registers[3] !== 32'd1 ||
            cpu.registers[4] !== 32'd1 || cpu.registers[5] !== 32'd2 ||
            cpu.registers[6] !== 32'd2 || cpu.registers[8] !== 32'd64 ||
            memory.words[72] !== 32'b0 || memory.words[73] !== 32'h4016_0000 ||
            cpu.machine_csrs.fflags[3] !== 1'b1 ||
            illegal_instruction !== 1'b0) begin
            $display("f3=%h f4=%h f5=%h f6=%h f7=%h f8=%h f9=%h f10=%h",
                     cpu.floating_registers[3], cpu.floating_registers[4],
                     cpu.floating_registers[5], cpu.floating_registers[6],
                     cpu.floating_registers[7], cpu.floating_registers[8],
                     cpu.floating_registers[9], cpu.floating_registers[10]);
            $display("f11=%h f12=%h f13=%h f14=%h f15=%h f16=%h f17=%h",
                     cpu.floating_registers[11], cpu.floating_registers[12],
                     cpu.floating_registers[13], cpu.floating_registers[14],
                     cpu.floating_registers[15], cpu.floating_registers[16],
                     cpu.floating_registers[17]);
            $display("x2=%h x3=%h x4=%h x5=%h x6=%h x8=%h mem72=%h mem73=%h illegal=%b pc=%h",
                     cpu.registers[2], cpu.registers[3], cpu.registers[4],
                     cpu.registers[5], cpu.registers[6], cpu.registers[8],
                     memory.words[72], memory.words[73], illegal_instruction,
                     program_counter);
            $fatal(1, "RV32D arithmetic, conversions, comparisons, or memory mismatch");
        end

        $display("RV32D smoke test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "RV32D test timed out at PC=%h", program_counter);
    end
endmodule
