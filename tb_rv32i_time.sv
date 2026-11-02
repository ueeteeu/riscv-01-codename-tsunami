module tb_rv32i_time;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [63:0] time_counter = 64'h0123_4567_89ab_cdef;
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
        .time_counter(time_counter),
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

    rv32i_memory #(.MEMORY_BYTES(128)) memory (
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
        memory.words[0] = 32'hc010_20f3; // csrrs x1,time,x0
        memory.words[1] = 32'h0000_006f; // jal x0,0

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;
        wait (cpu.registers[1] == time_counter[31:0]);
        #1;
        if (cpu.machine_csrs.minstret !== 64'd1 ||
            program_counter !== 32'd4 ||
            illegal_instruction !== 1'b0)
            $fatal(1, "Core time CSR read did not complete correctly");

        $display("Core time CSR read test passed");
        $finish;
    end

    initial begin
        #500 $fatal(1, "Time CSR test timed out at PC=%h", program_counter);
    end
endmodule
