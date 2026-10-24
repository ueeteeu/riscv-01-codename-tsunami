// Smoke test for the CPU plus behavioral-memory system wrapper.
module tb_rv32i_system;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;

    rv32i_system #(.MEMORY_BYTES(256)) system (
        .clk(clk),
        .reset(reset),
        .time_counter(64'b0),
        .external_interrupts(3'b0),
        .supervisor_interrupts(3'b0),
        .program_counter(program_counter),
        .illegal_instruction(illegal_instruction)
    );

    initial begin
        #1;
        // addi x1,x0,5; addi x2,x0,7; add x3,x1,x2
        // addi x4,x0,128; sw x3,0(x4); lw x5,0(x4); jal x0,0
        system.memory.words[0] = 32'h0050_0093;
        system.memory.words[1] = 32'h0070_0113;
        system.memory.words[2] = 32'h0020_81b3;
        system.memory.words[3] = 32'h0800_0213;
        system.memory.words[4] = 32'h0032_2023;
        system.memory.words[5] = 32'h0002_2283;
        system.memory.words[6] = 32'h0000_006f;

        repeat (2) @(negedge clk);
        reset = 1'b0;
        repeat (10) @(negedge clk);

        if (illegal_instruction)
            $fatal(1, "System smoke program raised illegal_instruction");
        if (system.cpu.registers[1] !== 32'd5 ||
            system.cpu.registers[2] !== 32'd7 ||
            system.cpu.registers[3] !== 32'd12 ||
            system.cpu.registers[5] !== 32'd12)
            $fatal(1, "System smoke program register results were incorrect");
        if (system.memory.words[32] !== 32'd12)
            $fatal(1, "System smoke program store did not reach memory");

        $display("PASS: rv32i_system fetch, execute, store, and load");
        $finish;
    end
endmodule
