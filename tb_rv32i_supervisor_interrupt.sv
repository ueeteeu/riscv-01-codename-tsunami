module tb_rv32i_supervisor_interrupt;
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
    logic [2:0] supervisor_interrupts = 3'b0;
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
        .supervisor_interrupts(supervisor_interrupts),
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

    function automatic logic [31:0] encode_csr(
        input logic [11:0] csr,
        input logic [4:0] source,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_csr = {csr, source, function3, destination, 7'h73};
    endfunction

    function automatic logic [31:0] encode_r(
        input logic [6:0] function7,
        input logic [4:0] source2,
        input logic [4:0] source1,
        input logic [2:0] function3,
        input logic [4:0] destination
    );
        encode_r = {function7, source2, source1, function3, destination, 7'h33};
    endfunction

    initial begin
        memory.words[0] = 32'h0800_0093; // addi x1,x0,128
        memory.words[1] = encode_csr(12'h105, 1, 3'b001, 0); // stvec
        memory.words[2] = 32'h2000_0093; // addi x1,x0,512
        memory.words[3] = encode_csr(12'h303, 1, 3'b001, 0); // delegate SEIP
        memory.words[4] = encode_csr(12'h304, 1, 3'b001, 0); // enable SEIE
        memory.words[5] = 32'h0000_10b7; // lui x1,1
        memory.words[6] = 32'h8000_8093; // addi x1,x1,-2048 (MPP=S)
        memory.words[7] = encode_csr(12'h300, 1, 3'b001, 0); // mstatus
        memory.words[8] = 32'h02c0_0093; // addi x1,x0,44
        memory.words[9] = encode_csr(12'h341, 1, 3'b001, 0); // mepc
        memory.words[10] = 32'h3020_0073; // mret
        memory.words[11] = 32'h0020_0093; // addi x1,x0,2 (SIE)
        memory.words[12] = encode_csr(12'h100, 1, 3'b001, 0); // sstatus
        memory.words[13] = 32'h0000_006f; // interruptible loop

        memory.words[32] = encode_csr(12'h142, 0, 3'b010, 3); // read scause
        memory.words[33] = 32'h0040_0213; // addi x4,x0,4
        memory.words[34] = encode_csr(12'h141, 0, 3'b010, 5); // read sepc
        memory.words[35] = encode_r(7'b0, 4, 5, 3'b000, 5); // advance sepc
        memory.words[36] = encode_csr(12'h141, 5, 3'b001, 0); // write sepc
        memory.words[37] = 32'h1020_0073; // sret
        memory.words[14] = 32'h0000_006f; // return target loop

        #11 reset = 1'b0;
        wait (program_counter == 32'd52);
        @(negedge clk);
        supervisor_interrupts[2] = 1'b1; // SEIP
        wait (program_counter == 32'd128);
        @(negedge clk);
        supervisor_interrupts[2] = 1'b0;
        wait (program_counter == 32'd56);
        #1;

        if (cpu.machine_csrs.scause !== 32'h8000_0009 ||
            cpu.machine_csrs.sepc !== 32'd56 ||
            cpu.registers[3] !== 32'h8000_0009 ||
            cpu.machine_csrs.current_privilege !== 2'b01 ||
            illegal_instruction !== 1'b0)
            $fatal(1, "Supervisor external-interrupt/SRET integration failed");

        $display("Supervisor external-interrupt integration test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "Supervisor interrupt test timed out at PC=%h",
                     program_counter);
    end
endmodule
