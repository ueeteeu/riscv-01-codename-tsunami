module tb_rv32i_sv32;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic [31:0] data_address, data_write_data, data_read_data;
    logic [3:0] data_write_mask;
    logic data_write_enable, data_access_fault;
    logic pte_read_enable, pte_access_fault;
    logic [31:0] pte_read_address, pte_read_data;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;

    rv32i_single_cycle cpu (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault),
        .pte_read_enable(pte_read_enable), .pte_read_address(pte_read_address),
        .pte_read_data(pte_read_data), .pte_access_fault(pte_access_fault),
        .program_counter(program_counter), .illegal_instruction(illegal_instruction)
    );

    rv32i_memory #(.MEMORY_BYTES(16384)) memory (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault),
        .pte_read_enable(pte_read_enable), .pte_read_address(pte_read_address),
        .pte_read_data(pte_read_data), .pte_access_fault(pte_access_fault)
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
        memory.words[0] = encode_i(12'd256, 0, 3'b000, 1, 7'h13);
        memory.words[1] = encode_csr(12'h305, 1, 3'b001, 0); // mtvec
        memory.words[2] = 32'h8000_00b7;                     // satp MODE=Sv32
        memory.words[3] = encode_i(12'd1, 1, 3'b000, 1, 7'h13);
        memory.words[4] = encode_csr(12'h180, 1, 3'b001, 0); // satp root PPN=1
        memory.words[5] = 32'h1200_0073;                     // sfence.vma
        memory.words[6] = 32'h0040_0137;                     // virtual entry PC
        memory.words[7] = encode_csr(12'h341, 2, 3'b001, 0); // mepc
        memory.words[8] = encode_i(12'd0, 0, 3'b000, 1, 7'h13);
        memory.words[9] = encode_csr(12'h300, 1, 3'b001, 0); // MPP=U, SUM=MXR=0
        memory.words[10] = 32'h3020_0073;                    // mret

        memory.words[64] = encode_csr(12'h342, 0, 3'b010, 5); // mcause
        memory.words[65] = encode_csr(12'h343, 0, 3'b010, 6); // mtval
        memory.words[66] = 32'h0000_006f;

        memory.words[1025] = 32'h0000_0801; // root VPN[1]=1 -> table at 0x2000
        memory.words[2048] = 32'h0000_0cdf; // VPN[0]=0 -> user RWX page at 0x3000
        memory.words[3072] = encode_i(12'd42, 0, 3'b000, 1, 7'h13);
        memory.words[3073] = 32'h0040_0137; // x2 = virtual data page
        memory.words[3074] = encode_i(12'h080, 2, 3'b000, 2, 7'h13);
        memory.words[3075] = encode_s(12'd0, 2, 1, 3'b010, 7'h23);
        memory.words[3076] = 32'h0040_11b7; // x3 = unmapped virtual page 0x00401000
        memory.words[3077] = encode_i(12'd0, 3, 3'b010, 4, 7'h03);
        memory.words[3104] = 32'b0;

        #11 reset = 1'b0;
        repeat (80) @(negedge clk);

        if (cpu.machine_csrs.satp !== 32'h8000_0001 ||
            cpu.machine_csrs.mcause !== 32'd13 ||
            cpu.machine_csrs.mtval !== 32'h0040_1000 ||
            cpu.machine_csrs.mepc !== 32'h0040_0014 ||
            cpu.registers[1] !== 32'd42 ||
            cpu.registers[4] !== 32'b0 ||
            cpu.registers[5] !== 32'd13 ||
            cpu.registers[6] !== 32'h0040_1000 ||
            memory.words[3104] !== 32'd42 ||
            program_counter !== 32'h0000_0108 ||
            illegal_instruction)
            $fatal(1, "Sv32 translation/page-fault test failed at PC=%h", program_counter);

        @(negedge clk);
        reset = 1'b1;
        memory.words[3072] = 32'h0000_106f; // Jump from mapped page to unmapped page.
        @(negedge clk);
        reset = 1'b0;
        repeat (80) @(negedge clk);

        if (cpu.machine_csrs.mcause !== 32'd12 ||
            cpu.machine_csrs.mtval !== 32'h0040_1000 ||
            cpu.machine_csrs.mepc !== 32'h0040_1000 ||
            cpu.registers[5] !== 32'd12 ||
            cpu.registers[6] !== 32'h0040_1000 ||
            program_counter !== 32'h0000_0108 ||
            illegal_instruction)
            $fatal(1, "Sv32 instruction-page-fault test failed at PC=%h", program_counter);

        $display("Sv32 page walks, data translation, and instruction/load page faults passed");
        $finish;
    end

    initial begin
        #5000 $fatal(1, "Sv32 test timed out at PC=%h", program_counter);
    end
endmodule
