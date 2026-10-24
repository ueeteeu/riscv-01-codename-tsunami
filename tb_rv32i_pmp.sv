module tb_rv32i_pmp;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic [31:0] data_address, data_write_data, data_read_data;
    logic [3:0] data_write_mask;
    logic data_write_enable, data_access_fault;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;
    rv32i_single_cycle cpu (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault),
        .program_counter(program_counter), .illegal_instruction(illegal_instruction)
    );

    rv32i_memory #(.MEMORY_BYTES(1024)) memory (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault)
    );

    function automatic logic [31:0] encode_i(
        input logic [11:0] immediate,
        input logic [4:0] source,
        input logic [2:0] operation,
        input logic [4:0] destination,
        input logic [6:0] opcode
    );
        encode_i = {immediate, source, operation, destination, opcode};
    endfunction

    function automatic logic [31:0] encode_csr(
        input logic [11:0] csr,
        input logic [4:0] source,
        input logic [2:0] operation,
        input logic [4:0] destination
    );
        encode_csr = {csr, source, operation, destination, 7'h73};
    endfunction

    function automatic logic [31:0] encode_s(
        input logic [11:0] immediate,
        input logic [4:0] source1,
        input logic [4:0] source2,
        input logic [2:0] operation,
        input logic [6:0] opcode
    );
        encode_s = {immediate[11:5], source2, source1, operation,
                    immediate[4:0], opcode};
    endfunction

    initial begin
        #1;
        memory.words[0] = encode_i(12'd128, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_csr(12'h105, 1, 3'b001, 0); // stvec = 128
        memory.words[2] = encode_i(12'd128, 0, 3'b000, 1, 7'h13);
        memory.words[3] = encode_csr(12'h302, 1, 3'b001, 0); // delegate store fault
        memory.words[4] = encode_i(12'd64, 0, 3'b000, 1, 7'h13);
        memory.words[5] = encode_csr(12'h3b0, 1, 3'b001, 0); // pmpaddr0
        memory.words[6] = encode_i(12'd95, 0, 3'b000, 1, 7'h13);
        memory.words[7] = encode_csr(12'h3b1, 1, 3'b001, 0); // pmpaddr1, NAPOT
        memory.words[8] = encode_i(12'd128, 0, 3'b000, 1, 7'h13);
        memory.words[9] = encode_csr(12'h3b2, 1, 3'b001, 0); // pmpaddr2, NA4
        memory.words[10] = 32'h0013_20b7;                    // lui x1,0x132
        memory.words[11] = encode_i(12'hb8d, 1, 3'b000, 1, 7'h13);
        memory.words[12] = encode_csr(12'h3a0, 1, 3'b001, 0); // TOR+lock, NAPOT, NA4
        memory.words[13] = encode_i(12'd0, 0, 3'b000, 1, 7'h13);
        memory.words[14] = encode_csr(12'h3b0, 1, 3'b001, 0); // locked address stays unchanged
        memory.words[15] = encode_i(12'd240, 0, 3'b000, 4, 7'h13);
        memory.words[16] = encode_i(12'd256, 0, 3'b000, 5, 7'h13);
        memory.words[17] = encode_i(12'd512, 0, 3'b000, 6, 7'h13);
        memory.words[18] = encode_i(12'd84, 0, 3'b000, 2, 7'h13);
        memory.words[19] = encode_csr(12'h341, 2, 3'b001, 0); // mepc = 84
        memory.words[20] = 32'h3020_0073;                     // mret to U-mode
        memory.words[21] = encode_i(12'd0, 5, 3'b010, 3, 7'h03); // lw x3,0(x5)
        memory.words[22] = encode_i(12'd0, 6, 3'b010, 7, 7'h03); // lw x7,0(x6)
        memory.words[23] = encode_s(12'd0, 4, 3, 3'b010, 7'h23); // sw x3,0(x4)
        memory.words[24] = 32'h0000_006f;

        memory.words[32] = encode_csr(12'h142, 0, 3'b010, 5); // read scause
        memory.words[33] = encode_csr(12'h143, 0, 3'b010, 6); // read stval
        memory.words[34] = 32'h0000_006f;
        memory.words[60] = 32'h1122_3344;
        memory.words[64] = 32'haabb_ccdd;
        memory.words[128] = 32'h5566_7788;

        #11 reset = 1'b0;
        repeat (40) @(negedge clk);

        if (cpu.machine_csrs.pmpaddr[0] !== 30'd64 ||
            cpu.machine_csrs.pmpaddr[1] !== 30'd95 ||
            cpu.machine_csrs.pmpaddr[2] !== 30'd128 ||
            cpu.machine_csrs.pmpcfg[0] !== 8'h8d ||
            cpu.machine_csrs.pmpcfg[1] !== 8'h1b ||
            cpu.machine_csrs.pmpcfg[2] !== 8'h13 ||
            cpu.machine_csrs.scause !== 32'd7 ||
            cpu.machine_csrs.stval !== 32'd240 ||
            cpu.machine_csrs.sepc !== 32'd92 ||
            cpu.registers[3] !== 32'haabb_ccdd ||
            cpu.registers[7] !== 32'h5566_7788 ||
            memory.words[60] !== 32'h1122_3344 ||
            cpu.registers[5] !== 32'd7 ||
            cpu.registers[6] !== 32'd240 ||
            cpu.machine_csrs.current_privilege !== 2'b01 ||
            illegal_instruction)
            $fatal(1, "PMP denied-store trap failed at PC=%h", program_counter);

        $display("PMP TOR/NA4/NAPOT and lock tests passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "PMP test timed out at PC=%h", program_counter);
    end
endmodule
