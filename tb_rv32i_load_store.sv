// Tests every integer load/store width, WFI, and memory alignment/access traps.
module tb_rv32i_load_store;
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

    rv32i_memory memory (
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
        input logic [4:0] source1,
        input logic [2:0] function3
    );
        encode_s = {immediate[11:5], source2, source1, function3,
                    immediate[4:0], 7'h23};
    endfunction

    function automatic logic [31:0] encode_u(
        input logic [19:0] immediate,
        input logic [4:0] destination
    );
        encode_u = {immediate, destination, 7'h37};
    endfunction

    function automatic logic [31:0] encode_csr(
        input logic [11:0] address,
        input logic [4:0] source,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_csr = {address, source, function3, destination, 7'h73};
    endfunction

    task automatic apply_reset;
        begin
            reset = 1'b1;
            repeat (2) @(negedge clk);
            reset = 1'b0;
            repeat (8) @(negedge clk);
        end
    endtask

    task automatic check_trap(input logic [31:0] cause, input logic [31:0] value);
        begin
            if (cpu.machine_csrs.mcause !== cause || cpu.machine_csrs.mtval !== value) begin
                $fatal(1, "Trap mismatch: mcause=%0d mtval=%h, expected %0d and %h",
                       cpu.machine_csrs.mcause, cpu.machine_csrs.mtval, cause, value);
            end
            if (illegal_instruction !== 1'b0) begin
                $fatal(1, "A synchronous memory fault was reported as illegal instruction");
            end
        end
    endtask

    initial begin
        #1;
        memory.words[32] = 32'h0000_006f; // Trap handler at mtvec=128
        memory.words[64] = 32'h80ff_7f01;
        memory.words[0] = encode_i(12'd256, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_i(12'd90, 0, 3'b000, 2, 7'h13);
        memory.words[2] = encode_i(12'hf80, 0, 3'b000, 3, 7'h13);
        memory.words[3] = encode_s(12'd1, 2, 1, 3'b000); // sb x2,1(x1)
        memory.words[4] = encode_s(12'd2, 3, 1, 3'b001); // sh x3,2(x1)
        memory.words[5] = encode_i(12'd3, 1, 3'b000, 4, 7'h03); // lb x4,3(x1)
        memory.words[6] = encode_i(12'd3, 1, 3'b100, 5, 7'h03); // lbu x5,3(x1)
        memory.words[7] = encode_i(12'd2, 1, 3'b001, 6, 7'h03); // lh x6,2(x1)
        memory.words[8] = encode_i(12'd2, 1, 3'b101, 7, 7'h03); // lhu x7,2(x1)
        memory.words[9] = encode_i(12'd0, 1, 3'b010, 8, 7'h03); // lw x8,0(x1)
        memory.words[10] = encode_s(12'd0, 2, 1, 3'b000); // sb x2,0(x1)
        memory.words[11] = encode_s(12'd3, 2, 1, 3'b000); // sb x2,3(x1)
        memory.words[12] = encode_s(12'd0, 2, 1, 3'b001); // sh x2,0(x1)
        memory.words[13] = encode_i(12'd0, 1, 3'b101, 9, 7'h03); // lhu x9,0(x1)
        memory.words[14] = encode_s(12'd2, 2, 1, 3'b001); // sh x2,2(x1)
        memory.words[15] = encode_i(12'd2, 1, 3'b001, 10, 7'h03); // lh x10,2(x1)
        memory.words[16] = encode_s(12'd4, 3, 1, 3'b010); // sw x3,4(x1)
        memory.words[17] = encode_i(12'd4, 1, 3'b010, 11, 7'h03); // lw x11,4(x1)
        memory.words[18] = 32'h1050_0073; // wfi
        memory.words[19] = 32'h0000_006f; // jal x0,0

        #11 reset = 1'b0;
        repeat (28) @(negedge clk);

        if (memory.words[64] !== 32'h005a_005a || memory.words[65] !== 32'hffff_ff80 ||
            cpu.registers[4] !== 32'hffff_ffff || cpu.registers[5] !== 32'h0000_00ff ||
            cpu.registers[6] !== 32'hffff_ff80 || cpu.registers[7] !== 32'h0000_ff80 ||
            cpu.registers[8] !== 32'hff80_5a01 || cpu.registers[9] !== 32'h0000_005a ||
            cpu.registers[10] !== 32'h0000_005a || cpu.registers[11] !== 32'hffff_ff80 ||
            illegal_instruction !== 1'b0) begin
            $fatal(1, "Byte/halfword/word load-store or WFI result mismatch");
        end

        memory.words[0] = encode_i(12'd257, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_i(12'd128, 0, 3'b000, 2, 7'h13);
        memory.words[2] = encode_csr(12'h305, 2, 3'b001, 0);
        memory.words[3] = encode_i(12'd0, 1, 3'b001, 3, 7'h03); // misaligned lh
        apply_reset();
        check_trap(32'd4, 32'd257);

        memory.words[0] = encode_i(12'd257, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_i(12'd90, 0, 3'b000, 2, 7'h13);
        memory.words[2] = encode_i(12'd128, 0, 3'b000, 3, 7'h13);
        memory.words[3] = encode_csr(12'h305, 3, 3'b001, 0);
        memory.words[4] = encode_s(12'd0, 2, 1, 3'b001); // misaligned sh
        apply_reset();
        check_trap(32'd6, 32'd257);

        memory.words[0] = encode_u(20'h00800, 1); // 8 MiB, first invalid address
        memory.words[1] = encode_i(12'd128, 0, 3'b000, 2, 7'h13);
        memory.words[2] = encode_csr(12'h305, 2, 3'b001, 0);
        memory.words[3] = encode_i(12'd0, 1, 3'b010, 3, 7'h03); // access-faulting lw
        apply_reset();
        check_trap(32'd5, 32'h0080_0000);

        memory.words[0] = encode_u(20'h00800, 1);
        memory.words[1] = encode_i(12'd128, 0, 3'b000, 2, 7'h13);
        memory.words[2] = encode_csr(12'h305, 2, 3'b001, 0);
        memory.words[3] = encode_s(12'd0, 2, 1, 3'b010); // access-faulting sw
        apply_reset();
        check_trap(32'd7, 32'h0080_0000);

        $display("RV32I load/store smoke test passed");
        $finish;
    end
endmodule
