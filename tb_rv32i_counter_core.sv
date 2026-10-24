module tb_rv32i_counter_core;
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

    rv32i_memory #(.MEMORY_BYTES(256)) memory (
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

    initial begin
        memory.words[0] = 32'h0050_0093; // addi x1,x0,5
        memory.words[1] = 32'h0010_8113; // addi x2,x1,1
        memory.words[2] = 32'h0000_006f; // jal x0,0

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        if (cpu.machine_csrs.minstret !== 64'd3 ||
            cpu.registers[1] !== 32'd5 || cpu.registers[2] !== 32'd6)
            $fatal(1, "Core retirement counter did not count executed instructions");

        @(negedge clk);
        memory.words[2] = 32'hffff_ffff;
        @(posedge clk);
        #1;
        if (cpu.machine_csrs.minstret !== 64'd3 ||
            cpu.machine_csrs.mcause !== 32'd2 ||
            cpu.machine_csrs.mepc !== 32'd8)
            $fatal(1, "Trapping illegal instruction incorrectly retired");

        $display("Core instruction-retirement counter integration test passed");
        $finish;
    end
endmodule
