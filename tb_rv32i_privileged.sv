// Smoke test for the initial machine-mode privileged implementation.
// Run with a SystemVerilog simulator after compiling the CPU, CSR block,
// memory, and this testbench together.
module tb_rv32i_privileged;
    logic clk = 1'b0;
    logic reset = 1'b1;

    logic [31:0] instruction_address;
    logic [31:0] instruction;
    logic [31:0] data_address;
    logic [31:0] data_write_data;
    logic [3:0] data_write_mask;
    logic data_write_enable;
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

    initial begin
        // Configure mtvec, enable machine interrupts in mstatus, and ECALL.
        // Interrupt delivery itself is not part of this first implementation.
        #1;
        memory.words[0]  = encode_i(12'd64, 5'd0, 3'b000, 5'd1, 7'h13); // addi x1,x0,64
        memory.words[1]  = encode_csr(12'h305, 5'd1, 3'b001, 5'd0);      // csrw mtvec,x1
        memory.words[2]  = encode_i(12'd8, 5'd0, 3'b000, 5'd5, 7'h13);  // addi x5,x0,8
        memory.words[3]  = encode_csr(12'h300, 5'd5, 3'b001, 5'd0);      // csrw mstatus,x5
        memory.words[4]  = 32'h00000073;                                 // ecall
        memory.words[5]  = encode_i(12'd1, 5'd0, 3'b000, 5'd2, 7'h13);  // addi x2,x0,1

        // Handler at address 64 reads the saved PC, skips ECALL, then MRETs.
        memory.words[16] = encode_csr(12'h341, 5'd0, 3'b010, 5'd3);     // csrrs x3,mepc,x0
        memory.words[17] = encode_i(12'd20, 5'd0, 3'b000, 5'd4, 7'h13); // addi x4,x0,20
        memory.words[18] = encode_csr(12'h341, 5'd4, 3'b001, 5'd0);     // csrw mepc,x4
        memory.words[19] = 32'h30200073;                                 // mret

        #11 reset = 1'b0;
        repeat (10) @(negedge clk);

        if (program_counter !== 32'd24) begin
            $fatal(1, "Expected PC 24 after MRET, got %0d", program_counter);
        end
        if (cpu.registers[2] !== 32'd1 || cpu.registers[3] !== 32'd16) begin
            $fatal(1, "Expected handler to save mepc=16 and resume at x2=1");
        end
        if (cpu.machine_csrs.mcause !== 32'd11 || cpu.machine_csrs.mepc !== 32'd20) begin
            $fatal(1, "Expected ECALL cause 11 and resumed mepc 20");
        end
        if (cpu.machine_csrs.mstatus_mie !== 1'b1 ||
            cpu.machine_csrs.mstatus_mpie !== 1'b1) begin
            $fatal(1, "Expected MRET to restore MIE and set MPIE");
        end
        if (illegal_instruction !== 1'b0) begin
            $fatal(1, "Unexpected illegal-instruction indication");
        end

        $display("Machine-mode ECALL/MRET smoke test passed");
        $finish;
    end
endmodule
