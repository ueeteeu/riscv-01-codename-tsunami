// Integration smoke test for compressed execution and a 32-bit instruction
// crossing a word boundary at address PC+2.
module tb_rv32c;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic [31:0] data_address, data_write_data, data_read_data;
    logic [3:0] data_write_mask;
    logic data_write_enable;
    logic data_access_fault;
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

    task automatic set_halfword(input integer byte_address, input logic [15:0] value);
        begin
            if (byte_address[1] == 1'b0) memory.words[byte_address / 4][15:0] = value;
            else memory.words[byte_address / 4][31:16] = value;
        end
    endtask

    initial begin
        #1;
        // C.NOP at 0, then a 32-bit ADDI starting at address 2.
        set_halfword(0, 16'h0001);
        set_halfword(2, 16'h0093); // low half of addi x1,x0,5
        set_halfword(4, 16'h0050); // high half of addi x1,x0,5
        set_halfword(6, 16'h008d); // c.addi x1,3
        set_halfword(8, 16'h4461); // c.li x8,24
        set_halfword(10, 16'h44d5); // c.li x9,21
        set_halfword(12, 16'hc004); // c.sw x9,0(x8)
        set_halfword(14, 16'h4008); // c.lw x10,0(x8)
        set_halfword(16, 16'he111); // c.bnez x10,+4
        set_halfword(18, 16'h45b5); // c.li x11,13, skipped by branch
        set_halfword(20, 16'h0085); // c.addi x1,1
        set_halfword(22, 16'ha001); // c.j 0

        #11 reset = 1'b0;
        repeat (20) @(negedge clk);

        if (cpu.registers[1] !== 32'd9 || cpu.registers[8] !== 32'd24 ||
            cpu.registers[9] !== 32'd21 || cpu.registers[10] !== 32'd21 ||
            cpu.registers[11] !== 32'd0 || memory.words[6] !== 32'd21) begin
            $fatal(1, "Compressed arithmetic, memory, or branch result mismatch");
        end
        if (program_counter !== 32'd22 || illegal_instruction !== 1'b0) begin
            $fatal(1, "Compressed PC advance/loop or decode error");
        end

        $display("RV32C integration smoke test passed");
        $finish;
    end

    initial begin
        #2000 $fatal(1, "RV32C test timed out at PC=%h", program_counter);
    end
endmodule
// Integration smoke test for compressed execution and a 32-bit instruction
// crossing a word boundary at address PC+2.
module tb_rv32c;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] instruction_address, instruction;
    logic [31:0] data_address, data_write_data, data_read_data;
    logic data_write_enable;
    logic [31:0] program_counter;
    logic illegal_instruction;

    always #5 clk = ~clk;

    rv32i_single_cycle cpu (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_read_data(data_read_data),
        .program_counter(program_counter), .illegal_instruction(illegal_instruction)
    );

    rv32i_memory memory (
        .clk(clk), .reset(reset),
        .instruction_address(instruction_address), .instruction(instruction),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_write_enable(data_write_enable), .data_read_data(data_read_data)
    );

    task automatic set_halfword(input integer byte_address, input logic [15:0] value);
        begin
            if (byte_address[1] == 1'b0) memory.words[byte_address / 4][15:0] = value;
            else memory.words[byte_address / 4][31:16] = value;
        end
    endtask

    initial begin
        #1;
        // C.NOP at 0, then a 32-bit ADDI starting at address 2.
        set_halfword(0, 16'h0001);
        set_halfword(2, 16'h0093); // low half of addi x1,x0,5
        set_halfword(4, 16'h0050); // high half of addi x1,x0,5
        set_halfword(6, 16'h008d); // c.addi x1,3
        set_halfword(8, 16'h4441); // c.li x8,16
        set_halfword(10, 16'h44d5); // c.li x9,21
        set_halfword(12, 16'hc004); // c.sw x9,0(x8)
        set_halfword(14, 16'h4008); // c.lw x10,0(x8)
        set_halfword(16, 16'he111); // c.bnez x10,+4
        set_halfword(18, 16'h45b5); // c.li x11,13, skipped by branch
        set_halfword(20, 16'h0085); // c.addi x1,1
        set_halfword(22, 16'ha001); // c.j 0

        #11 reset = 1'b0;
        repeat (20) @(negedge clk);

        if (cpu.registers[1] !== 32'd9 || cpu.registers[8] !== 32'd16 ||
            cpu.registers[9] !== 32'd21 || cpu.registers[10] !== 32'd21 ||
            cpu.registers[11] !== 32'd0 || memory.words[4] !== 32'd21) begin
            $fatal(1, "Compressed arithmetic, memory, or branch result mismatch");
        end
        if (program_counter !== 32'd22 || illegal_instruction !== 1'b0) begin
            $fatal(1, "Compressed PC advance/loop or decode error");
        end

        $display("RV32C integration smoke test passed");
        $finish;
    end
endmodule
