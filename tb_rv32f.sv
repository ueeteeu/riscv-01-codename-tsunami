// Integration tests for the RV32F single-precision instructions listed on the
// project reference card, including floating-point memory operations.
module tb_rv32f;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address;
    logic [31:0] instruction;
    logic [31:0] data_address;
    logic [31:0] data_write_data;
    logic data_write_enable;
    logic [3:0] data_write_mask;
    logic [31:0] data_read_data;
    logic data_access_fault;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;

    rv32i_single_cycle cpu (
        .clk(clk),
        .reset(reset),
        .instruction_address(instruction_address),
        .instruction(instruction),
        .data_address(data_address),
        .data_write_data(data_write_data),
        .data_write_enable(data_write_enable),
        .data_write_mask(data_write_mask),
        .data_read_data(data_read_data),
        .data_access_fault(data_access_fault),
        .program_counter(program_counter),
        .illegal_instruction(illegal_instruction)
    );

    rv32i_memory #(.MEMORY_BYTES(512)) memory (
        .clk(clk),
        .reset(reset),
        .instruction_address(instruction_address),
        .instruction(instruction),
        .data_address(data_address),
        .data_write_data(data_write_data),
        .data_write_enable(data_write_enable),
        .data_write_mask(data_write_mask),
        .data_read_data(data_read_data),
        .data_access_fault(data_access_fault)
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
        encode_s = {immediate[11:5], source2, source1, 3'b010,
                    immediate[4:0], 7'h27};
    endfunction

    function automatic logic [31:0] encode_fp_r(
        input logic [6:0] function7,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_fp_r = {function7, source2, source1, function3, destination, 7'h53};
    endfunction

    function automatic logic [31:0] encode_csr(
        input logic [11:0] address,
        input logic [4:0] source,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_csr = {address, source, function3, destination, 7'h73};
    endfunction

    function automatic logic [31:0] encode_fp_fused(
        input logic [4:0] source3,
        input logic [2:0] rounding_mode,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_fp_fused = {source3, 2'b00, source2, source1, rounding_mode,
                           destination, opcode};
    endfunction

    task automatic apply_reset;
        begin
            reset = 1'b1;
            repeat (2) @(negedge clk);
            reset = 1'b0;
            repeat (10) @(negedge clk);
        end
    endtask

    initial begin
        #1;
        memory.words[64] = 32'h3fc0_0000; // 1.5
        memory.words[65] = 32'h4010_0000; // 2.25
        memory.words[67] = 32'h4020_0000; // 2.5
        memory.words[68] = 32'h3f80_0000; // 1.0
        memory.words[69] = 32'h3380_0000; // 2^-24, halfway at 1.0
        memory.words[70] = 32'h7fc0_0000; // quiet NaN
        memory.words[0] = encode_i(12'd256, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_i(12'd0, 1, 3'b010, 1, 7'h07); // flw f1,0(x1)
        memory.words[2] = encode_i(12'd4, 1, 3'b010, 2, 7'h07); // flw f2,4(x1)
        memory.words[3] = encode_fp_r(7'b0000000, 2, 1, 3'b000, 4); // fadd.s
        memory.words[4] = encode_fp_r(7'b0000100, 1, 2, 3'b000, 5); // fsub.s
        memory.words[5] = encode_fp_r(7'b0001000, 2, 1, 3'b000, 6); // fmul.s
        memory.words[6] = encode_fp_r(7'b0001100, 1, 2, 3'b000, 7); // fdiv.s
        memory.words[7] = encode_fp_r(7'b0101100, 0, 2, 3'b000, 8); // fsqrt.s
        memory.words[8] = encode_fp_r(7'b0010000, 2, 1, 3'b000, 9); // fsgnj.s
        memory.words[9] = encode_fp_r(7'b0010000, 2, 1, 3'b001, 10); // fsgnjn.s
        memory.words[10] = encode_fp_r(7'b0010000, 10, 1, 3'b010, 11); // fsgnjx.s
        memory.words[11] = encode_fp_r(7'b0010100, 2, 1, 3'b000, 12); // fmin.s
        memory.words[12] = encode_fp_r(7'b0010100, 2, 1, 3'b001, 13); // fmax.s
        memory.words[13] = encode_fp_r(7'b1100000, 0, 2, 3'b000, 2); // fcvt.w.s
        memory.words[14] = encode_fp_r(7'b1100000, 1, 2, 3'b000, 3); // fcvt.wu.s
        memory.words[15] = encode_fp_r(7'b1101000, 0, 2, 3'b000, 14); // fcvt.s.w
        memory.words[16] = encode_fp_r(7'b1101000, 1, 2, 3'b000, 15); // fcvt.s.wu
        memory.words[17] = encode_fp_r(7'b1110000, 0, 1, 3'b000, 4); // fmv.x.w
        memory.words[18] = encode_fp_r(7'b1111000, 0, 4, 3'b000, 16); // fmv.w.x
        memory.words[19] = encode_fp_r(7'b1010000, 1, 1, 3'b000, 5); // feq.s
        memory.words[20] = encode_fp_r(7'b1010000, 2, 1, 3'b001, 6); // flt.s
        memory.words[21] = encode_fp_r(7'b1010000, 1, 2, 3'b010, 7); // fle.s
        memory.words[22] = encode_fp_r(7'b1110000, 0, 1, 3'b001, 8); // fclass.s
        memory.words[23] = encode_fp_fused(1, 3'b000, 2, 1, 3, 7'b1000011); // fmadd.s
        memory.words[24] = encode_fp_fused(1, 3'b000, 2, 1, 18, 7'b1000111); // fmsub.s
        memory.words[25] = encode_fp_fused(1, 3'b000, 2, 1, 19, 7'b1001011); // fnmsub.s
        memory.words[26] = encode_fp_fused(1, 3'b000, 2, 1, 20, 7'b1001111); // fnmadd.s
        memory.words[27] = encode_s(12'd8, 3, 1); // fsw f3,8(x1)
        memory.words[28] = encode_i(12'd8, 1, 3'b010, 17, 7'h07); // flw f17,8(x1)
        memory.words[29] = encode_i(12'd12, 1, 3'b010, 21, 7'h07); // flw f21,12(x1)
        memory.words[30] = encode_fp_r(7'b1100000, 0, 21, 3'b000, 9); // round-near-even
        memory.words[31] = encode_fp_r(7'b1100000, 0, 21, 3'b100, 10); // round-near-max-magnitude
        memory.words[32] = encode_fp_r(7'b1100000, 0, 21, 3'b011, 11); // round-up
        memory.words[33] = encode_fp_r(7'b1100000, 0, 10, 3'b100, 12); // negative round-near-max-magnitude
        memory.words[34] = encode_i(12'd16, 1, 3'b010, 22, 7'h07); // flw f22,16(x1)
        memory.words[35] = encode_i(12'd20, 1, 3'b010, 23, 7'h07); // flw f23,20(x1)
        memory.words[36] = encode_fp_r(7'b0000000, 23, 22, 3'b000, 24); // tie rounds even
        memory.words[37] = encode_fp_r(7'b0000000, 23, 22, 3'b100, 25); // tie rounds away
        memory.words[38] = encode_fp_r(7'b0000000, 23, 22, 3'b011, 29); // round-up
        memory.words[39] = encode_fp_r(7'b0000000, 23, 22, 3'b001, 30); // truncate
        memory.words[40] = encode_fp_r(7'b0000000, 23, 22, 3'b010, 31); // round-down
        memory.words[41] = encode_i(12'd24, 1, 3'b010, 26, 7'h07); // flw f26,24(x1)
        memory.words[42] = encode_fp_r(7'b0010100, 2, 26, 3'b000, 27); // fmin.s ignores one NaN
        memory.words[43] = encode_fp_r(7'b0010100, 2, 26, 3'b001, 28); // fmax.s ignores one NaN
        memory.words[44] = encode_fp_r(7'b1010000, 2, 26, 3'b000, 13); // feq.s with NaN
        memory.words[45] = encode_fp_r(7'b1100000, 0, 26, 3'b000, 14); // fcvt.w.s NaN
        memory.words[46] = encode_fp_r(7'b1100000, 1, 26, 3'b000, 15); // fcvt.wu.s NaN
        memory.words[47] = encode_fp_r(7'b1100000, 1, 10, 3'b000, 16); // negative to unsigned
        memory.words[48] = 32'h0000_006f; // jal x0,0

        #11 reset = 1'b0;
        repeat (50) @(negedge clk);

        if (cpu.floating_registers[4] !== 32'h4070_0000 ||
            cpu.floating_registers[5] !== 32'h3f40_0000 ||
            cpu.floating_registers[6] !== 32'h4058_0000 ||
            cpu.floating_registers[7] !== 32'h3fc0_0000 ||
            cpu.floating_registers[8] !== 32'h3fc0_0000 ||
            cpu.floating_registers[9] !== 32'h3fc0_0000 ||
            cpu.floating_registers[10] !== 32'hbfc0_0000 ||
            cpu.floating_registers[11] !== 32'hbfc0_0000 ||
            cpu.floating_registers[12] !== 32'h3fc0_0000 ||
            cpu.floating_registers[13] !== 32'h4010_0000 ||
            cpu.floating_registers[14] !== 32'h4000_0000 ||
            cpu.floating_registers[15] !== 32'h4000_0000 ||
            cpu.floating_registers[16] !== 32'h3fc0_0000 ||
            cpu.floating_registers[17] !== 32'h409c_0000 ||
            cpu.floating_registers[18] !== 32'h3ff0_0000 ||
            cpu.floating_registers[19] !== 32'hbff0_0000 ||
            cpu.floating_registers[20] !== 32'hc09c_0000 ||
            cpu.floating_registers[24] !== 32'h3f80_0000 ||
            cpu.floating_registers[25] !== 32'h3f80_0001 ||
            cpu.floating_registers[29] !== 32'h3f80_0001 ||
            cpu.floating_registers[30] !== 32'h3f80_0000 ||
            cpu.floating_registers[31] !== 32'h3f80_0000 ||
            cpu.floating_registers[27] !== 32'h4010_0000 ||
            cpu.floating_registers[28] !== 32'h4010_0000 ||
            memory.words[66] !== 32'h409c_0000 ||
            cpu.registers[2] !== 32'd2 || cpu.registers[3] !== 32'd2 ||
            cpu.registers[4] !== 32'h3fc0_0000 || cpu.registers[5] !== 32'd1 ||
            cpu.registers[6] !== 32'd1 || cpu.registers[7] !== 32'd0 ||
            cpu.registers[8] !== 32'd64 || cpu.registers[9] !== 32'd2 ||
            cpu.registers[10] !== 32'd3 || cpu.registers[11] !== 32'd3 ||
            cpu.registers[12] !== 32'hffff_fffe ||
            cpu.registers[13] !== 32'd0 ||
            cpu.registers[14] !== 32'hffff_ffff ||
            cpu.registers[15] !== 32'hffff_ffff || cpu.registers[16] !== 32'b0 ||
            illegal_instruction !== 1'b0) begin
            $display("f4=%h f5=%h f6=%h f7=%h f8=%h f9=%h f10=%h f11=%h",
                     cpu.floating_registers[4], cpu.floating_registers[5],
                     cpu.floating_registers[6], cpu.floating_registers[7],
                     cpu.floating_registers[8], cpu.floating_registers[9],
                     cpu.floating_registers[10], cpu.floating_registers[11]);
            $display("f12=%h f13=%h f14=%h f15=%h f16=%h f17=%h f18=%h f19=%h f20=%h",
                     cpu.floating_registers[12], cpu.floating_registers[13],
                     cpu.floating_registers[14], cpu.floating_registers[15],
                     cpu.floating_registers[16], cpu.floating_registers[17],
                     cpu.floating_registers[18], cpu.floating_registers[19],
                     cpu.floating_registers[20]);
            $display("x2=%h x3=%h x4=%h x5=%h x6=%h x7=%h x8=%h data=%h illegal=%b",
                     cpu.registers[2], cpu.registers[3], cpu.registers[4],
                     cpu.registers[5], cpu.registers[6], cpu.registers[7],
                     cpu.registers[8], memory.words[66], illegal_instruction);
            $fatal(1, "RV32F arithmetic, conversion, comparison, or memory mismatch");
        end

        memory.words[32] = 32'h0000_006f; // Trap handler at mtvec=128
        memory.words[0] = encode_i(12'd257, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_i(12'd128, 0, 3'b000, 2, 7'h13);
        memory.words[2] = encode_csr(12'h305, 2, 3'b001, 0);
        memory.words[3] = encode_i(12'd0, 1, 3'b010, 3, 7'h07); // Misaligned FLW
        apply_reset();
        if (cpu.machine_csrs.mcause !== 32'd4 ||
            cpu.machine_csrs.mtval !== 32'd257 ||
            illegal_instruction !== 1'b0 ||
            cpu.floating_registers[3] !== 32'b0) begin
            $fatal(1, "Misaligned FLW did not trap precisely");
        end

        memory.words[0] = encode_i(12'd512, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_i(12'd128, 0, 3'b000, 2, 7'h13);
        memory.words[2] = encode_csr(12'h305, 2, 3'b001, 0);
        memory.words[3] = encode_i(12'd0, 1, 3'b010, 3, 7'h07); // Out-of-range FLW
        apply_reset();
        if (cpu.machine_csrs.mcause !== 32'd5 ||
            cpu.machine_csrs.mtval !== 32'd512 ||
            illegal_instruction !== 1'b0 ||
            cpu.floating_registers[3] !== 32'b0) begin
            $fatal(1, "Out-of-range FLW did not trap precisely");
        end

        memory.words[3] = encode_s(12'd0, 2, 1); // Out-of-range FSW
        apply_reset();
        if (cpu.machine_csrs.mcause !== 32'd7 ||
            cpu.machine_csrs.mtval !== 32'd512 ||
            illegal_instruction !== 1'b0) begin
            $fatal(1, "Out-of-range FSW did not trap precisely");
        end

        $display("RV32F single-precision smoke test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "RV32F test timed out at PC=%h", program_counter);
    end
endmodule
