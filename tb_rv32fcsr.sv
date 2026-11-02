// Integration test for dynamic rounding selection, fflags read/clear, and
// accrued divide-by-zero status through the FP CSR interface.
module tb_rv32fcsr;
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

    rv32i_memory #(.MEMORY_BYTES(512)) memory (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_write_mask(data_write_mask),
        .data_read_data(data_read_data), .data_access_fault(data_access_fault)
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

    function automatic logic [31:0] encode_fp(
        input logic [6:0] function7,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [2:0] rounding_mode,
        input logic [4:0] destination
    );
        encode_fp = {function7, source2, source1, rounding_mode, destination, 7'h53};
    endfunction

    function automatic logic [31:0] encode_csr(
        input logic [11:0] csr,
        input logic [4:0] source,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_csr = {csr, source, function3, destination, 7'h73};
    endfunction

    initial begin
        #1;
        // 1.0 + 2^-24 is a halfway case: round-up must advance one ULP.
        memory.words[64] = 32'h3f80_0000; // 1.0
        memory.words[65] = 32'h3380_0000; // 2^-24, exact halfway increment
        memory.words[66] = 32'h0000_0000; // +0.0

        memory.words[0]  = encode_i(12'd256, 0, 3'b000, 1, 7'h13);
        memory.words[1]  = encode_i(12'd0, 1, 3'b010, 1, 7'h07); // flw f1
        memory.words[2]  = encode_i(12'd4, 1, 3'b010, 2, 7'h07); // flw f2
        memory.words[3]  = encode_i(12'd96, 0, 3'b000, 3, 7'h13);
        // Set frm=RUP and clear flags before exercising dynamic rm=111.
        memory.words[4]  = encode_csr(12'h003, 3, 3'b001, 0); // frm=RUP, clear flags
        memory.words[5]  = encode_fp(7'b0000000, 2, 1, 3'b111, 3); // dynamic fadd.s
        memory.words[6]  = encode_csr(12'h001, 0, 3'b010, 4); // read fflags
        memory.words[7]  = encode_csr(12'h001, 0, 3'b001, 0); // clear fflags
        memory.words[8]  = encode_i(12'd8, 1, 3'b010, 2, 7'h07); // flw f2=0
        memory.words[9]  = encode_fp(7'b0001100, 2, 1, 3'b111, 5); // dynamic fdiv.s
        memory.words[10] = encode_csr(12'h001, 0, 3'b010, 6); // read fflags
        memory.words[11] = 32'h0000_006f;

        #11 reset = 1'b0;
        repeat (20) @(negedge clk);

        if (cpu.floating_registers[3] !== 64'hffff_ffff_3f80_0001 ||
            cpu.registers[4] !== 32'd1 ||
            cpu.floating_registers[5] !== 64'hffff_ffff_7f80_0000 ||
            cpu.registers[6] !== 32'd8 ||
            cpu.machine_csrs.frm !== 3'b011 ||
            illegal_instruction !== 1'b0)
            $fatal(1, "FCSR dynamic rounding or sticky exception flag test failed");

        $display("FCSR rounding and exception-flag smoke test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "FCSR test timed out at PC=%h", program_counter);
    end
endmodule
