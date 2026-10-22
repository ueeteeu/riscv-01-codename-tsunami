// A small, educational single-cycle RV32I CPU.
//
// The instruction and data memories are outside this module. Instruction
// memory is expected to return the instruction at instruction_address in the
// same cycle. Data memory is word-wide; this core accepts only aligned LW/SW.
module rv32i_single_cycle (
    input  logic        clk,
    input  logic        reset,

    output logic [31:0] instruction_address,
    input  logic [31:0] instruction,

    output logic [31:0] data_address,
    output logic [31:0] data_write_data,
    output logic        data_write_enable,
    input  logic [31:0] data_read_data,

    output logic [31:0] program_counter,
    output logic        illegal_instruction
);
    // The register file has 32 architectural registers. x0 is represented
    // by a constant read value and is never allowed to be written.
    logic [31:0] registers [0:31];

    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [31:0] rs1_value;
    logic [31:0] rs2_value;

    logic [31:0] immediate_i;
    logic [31:0] immediate_s;
    logic [31:0] immediate_b;
    logic [31:0] immediate_u;
    logic [31:0] immediate_j;

    logic [31:0] next_pc;
    logic [31:0] writeback_value;
    logic        register_write_enable;

    // The instruction address is the current PC; memory supplies the
    // instruction combinationally for this single-cycle design.
    always_comb begin
        instruction_address = program_counter;
    end

    // These fields occupy the same bit positions in the standard RISC-V
    // instruction formats, so they can be decoded directly from the word.
    always_comb begin
        opcode = instruction[6:0];
        rd     = instruction[11:7];
        funct3 = instruction[14:12];
        rs1    = instruction[19:15];
        rs2    = instruction[24:20];
        funct7 = instruction[31:25];

        // Each immediate is assembled separately because the ISA rearranges
        // immediate bits in branch, store, and jump instruction formats.
        immediate_i = {{20{instruction[31]}}, instruction[31:20]};
        immediate_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
        immediate_b = {{19{instruction[31]}}, instruction[31], instruction[7],
                        instruction[30:25], instruction[11:8], 1'b0};
        immediate_u = {instruction[31:12], 12'b0};
        immediate_j = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                        instruction[20], instruction[30:21], 1'b0};

        // x0 always reads as zero, regardless of the contents of the array.
        rs1_value = (rs1 == 5'd0) ? 32'b0 : registers[rs1];
        rs2_value = (rs2 == 5'd0) ? 32'b0 : registers[rs2];
    end

    // Decode the instruction and build the combinational datapath results.
    // Defaults describe a harmless sequential advance (a NOP-like behavior)
    // and ensure every output has a value for every instruction encoding.
    always_comb begin
        next_pc              = program_counter + 32'd4;
        writeback_value      = 32'b0;
        register_write_enable = 1'b0;
        data_address          = 32'b0;
        data_write_data       = rs2_value;
        data_write_enable     = 1'b0;
        illegal_instruction   = 1'b0;

        case (opcode)
            7'b0110011: begin // R-type register-register arithmetic
                register_write_enable = 1'b1;
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: writeback_value = rs1_value + rs2_value; // ADD
                    {7'b0100000, 3'b000}: writeback_value = rs1_value - rs2_value; // SUB
                    {7'b0000000, 3'b100}: writeback_value = rs1_value ^ rs2_value; // XOR
                    {7'b0000000, 3'b110}: writeback_value = rs1_value | rs2_value; // OR
                    {7'b0000000, 3'b111}: writeback_value = rs1_value & rs2_value; // AND
                    {7'b0000000, 3'b010}: begin // SLT, signed comparison
                        writeback_value = ($signed(rs1_value) < $signed(rs2_value)) ? 32'd1 : 32'd0;
                    end
                    default: begin
                        register_write_enable = 1'b0;
                        illegal_instruction = 1'b1;
                    end
                endcase
            end

            7'b0010011: begin // I-type immediate arithmetic
                register_write_enable = 1'b1;
                case (funct3)
                    3'b000: writeback_value = rs1_value + immediate_i; // ADDI
                    3'b100: writeback_value = rs1_value ^ immediate_i; // XORI
                    3'b110: writeback_value = rs1_value | immediate_i; // ORI
                    3'b111: writeback_value = rs1_value & immediate_i; // ANDI
                    3'b010: begin // SLTI, signed comparison
                        writeback_value = ($signed(rs1_value) < $signed(immediate_i)) ? 32'd1 : 32'd0;
                    end
                    default: begin
                        register_write_enable = 1'b0;
                        illegal_instruction = 1'b1;
                    end
                endcase
            end

            7'b0000011: begin // Loads: this core implements aligned LW only
                data_address = rs1_value + immediate_i;
                if (funct3 == 3'b010 && data_address[1:0] == 2'b00) begin
                    register_write_enable = 1'b1;
                    writeback_value = data_read_data;
                end else begin
                    illegal_instruction = 1'b1;
                end
            end

            7'b0100011: begin // Stores: this core implements aligned SW only
                data_address = rs1_value + immediate_s;
                if (funct3 == 3'b010 && data_address[1:0] == 2'b00) begin
                    data_write_enable = 1'b1;
                end else begin
                    illegal_instruction = 1'b1;
                end
            end

            7'b1100011: begin // Conditional branches
                case (funct3)
                    3'b000: if (rs1_value == rs2_value) next_pc = program_counter + immediate_b; // BEQ
                    3'b001: if (rs1_value != rs2_value) next_pc = program_counter + immediate_b; // BNE
                    default: illegal_instruction = 1'b1;
                endcase
            end

            7'b1101111: begin // JAL: save the return address and jump
                register_write_enable = 1'b1;
                writeback_value = program_counter + 32'd4;
                next_pc = program_counter + immediate_j;
            end

            7'b0110111: begin // LUI: place the upper immediate in rd
                register_write_enable = 1'b1;
                writeback_value = immediate_u;
            end

            7'b0010111: begin // AUIPC: add the upper immediate to the PC
                register_write_enable = 1'b1;
                writeback_value = program_counter + immediate_u;
            end

            default: illegal_instruction = 1'b1;
        endcase

        // The architecture discards writes to x0, even when the instruction
        // otherwise decodes as a valid register-writing operation.
        if (rd == 5'd0) begin
            register_write_enable = 1'b0;
        end
    end

    // State changes happen at the clock edge. Reset clears the PC and all
    // general-purpose registers; x0 still reads as zero through the logic above.
    always_ff @(posedge clk) begin
        if (reset) begin
            program_counter <= 32'b0;
            for (integer index = 0; index < 32; index = index + 1) begin
                registers[index] <= 32'b0;
            end
        end else begin
            program_counter <= next_pc;
            if (register_write_enable) begin
                registers[rd] <= writeback_value;
            end
        end
    end
endmodule
