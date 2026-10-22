// A small, educational single-cycle RV32 CPU with integer, M/A, and initial
// machine-mode privileged instruction support.
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
    logic [11:0] csr_address;
    logic        csr_write_enable;
    logic [31:0] csr_write_data;
    logic [31:0] csr_read_data;
    logic        csr_access_valid;
    logic        trap_valid;
    logic [31:0] trap_cause;
    logic [31:0] trap_value;
    logic [31:0] trap_vector;
    logic        mret;
    logic [31:0] mret_address;
    logic [31:0] csr_source_value;
    logic [31:0] csr_new_value;
    logic [63:0] product_unsigned;
    logic signed [63:0] product_signed;
    logic signed [63:0] product_signed_unsigned;
    logic [31:0] shifted_load_data;
        logic        reservation_valid;
        logic [31:0] reservation_address;
        logic        reservation_set;
        logic        reservation_clear;

    rv32i_machine_csrs machine_csrs (
        .clk(clk),
        .reset(reset),
        .csr_address(csr_address),
        .csr_write_enable(csr_write_enable),
        .csr_write_data(csr_write_data),
        .csr_read_data(csr_read_data),
        .csr_access_valid(csr_access_valid),
        .trap_valid(trap_valid),
        .trap_pc(program_counter),
        .trap_cause(trap_cause),
        .trap_value(trap_value),
        .trap_vector(trap_vector),
        .mret(mret),
        .mret_address(mret_address)
    );

    // The instruction address is the current PC; memory supplies the
    // instruction combinationally for this single-cycle design.
    always_comb begin
        instruction_address = program_counter;
        shifted_load_data = data_read_data >> {data_address[1:0], 3'b000};
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

        // Extend operands before multiplying so all high-half products retain
        // the correct signed or unsigned 64-bit result.
        product_unsigned = {32'b0, rs1_value} * {32'b0, rs2_value};
        product_signed = $signed({{32{rs1_value[31]}}, rs1_value}) *
                 $signed({{32{rs2_value[31]}}, rs2_value});
        product_signed_unsigned = $signed({{32{rs1_value[31]}}, rs1_value}) *
                      $signed({32'b0, rs2_value});
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
        csr_address           = instruction[31:20];
        csr_write_enable      = 1'b0;
        csr_write_data        = 32'b0;
        csr_source_value      = rs1_value;
        csr_new_value         = 32'b0;
        trap_valid            = 1'b0;
        trap_cause            = 32'b0;
        trap_value            = 32'b0;
        mret                  = 1'b0;
            reservation_set       = 1'b0;
            reservation_clear     = 1'b0;

        case (opcode)
            7'b0110011: begin // R-type register-register arithmetic
                register_write_enable = 1'b1;
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: writeback_value = rs1_value + rs2_value; // ADD
                    {7'b0100000, 3'b000}: writeback_value = rs1_value - rs2_value; // SUB
                    {7'b0000000, 3'b001}: writeback_value = rs1_value << rs2_value[4:0]; // SLL
                    {7'b0000000, 3'b010}: writeback_value = ($signed(rs1_value) < $signed(rs2_value)) ? 32'd1 : 32'd0; // SLT
                    {7'b0000000, 3'b011}: writeback_value = (rs1_value < rs2_value) ? 32'd1 : 32'd0; // SLTU
                    {7'b0000000, 3'b100}: writeback_value = rs1_value ^ rs2_value; // XOR
                    {7'b0000000, 3'b101}: writeback_value = rs1_value >> rs2_value[4:0]; // SRL
                    {7'b0100000, 3'b101}: writeback_value = $signed(rs1_value) >>> rs2_value[4:0]; // SRA
                    {7'b0000000, 3'b110}: writeback_value = rs1_value | rs2_value; // OR
                    {7'b0000000, 3'b111}: writeback_value = rs1_value & rs2_value; // AND
                    {7'b0000001, 3'b000}: writeback_value = product_unsigned[31:0]; // MUL
                    {7'b0000001, 3'b001}: writeback_value = product_signed[63:32]; // MULH
                    {7'b0000001, 3'b010}: writeback_value = product_signed_unsigned[63:32]; // MULHSU
                    {7'b0000001, 3'b011}: writeback_value = product_unsigned[63:32]; // MULHU
                    {7'b0000001, 3'b100}: begin // DIV, including architectural edge cases
                        if (rs2_value == 32'b0) writeback_value = 32'hffff_ffff;
                        else if (rs1_value == 32'h8000_0000 && rs2_value == 32'hffff_ffff)
                            writeback_value = 32'h8000_0000;
                        else writeback_value = $signed(rs1_value) / $signed(rs2_value);
                    end
                    {7'b0000001, 3'b101}: writeback_value = (rs2_value == 32'b0) ? 32'hffff_ffff : rs1_value / rs2_value; // DIVU
                    {7'b0000001, 3'b110}: begin // REM, including architectural edge cases
                        if (rs2_value == 32'b0) writeback_value = rs1_value;
                        else if (rs1_value == 32'h8000_0000 && rs2_value == 32'hffff_ffff)
                            writeback_value = 32'b0;
                        else writeback_value = $signed(rs1_value) % $signed(rs2_value);
                    end
                    {7'b0000001, 3'b111}: writeback_value = (rs2_value == 32'b0) ? rs1_value : rs1_value % rs2_value; // REMU
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
                    3'b001: begin // SLLI; upper immediate bits encode the operation
                        if (instruction[31:25] == 7'b0000000) writeback_value = rs1_value << instruction[24:20];
                        else begin register_write_enable = 1'b0; illegal_instruction = 1'b1; end
                    end
                    3'b011: writeback_value = (rs1_value < immediate_i) ? 32'd1 : 32'd0; // SLTIU
                    3'b100: writeback_value = rs1_value ^ immediate_i; // XORI
                    3'b101: begin // SRLI/SRAI
                        if (instruction[31:25] == 7'b0000000) writeback_value = rs1_value >> instruction[24:20];
                        else if (instruction[31:25] == 7'b0100000) writeback_value = $signed(rs1_value) >>> instruction[24:20];
                        else begin register_write_enable = 1'b0; illegal_instruction = 1'b1; end
                    end
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

            7'b0000011: begin // LB and LW; the data port returns the containing word
                data_address = rs1_value + immediate_i;
                case (funct3)
                    3'b000: begin // LB sign-extends the selected byte
                        register_write_enable = 1'b1;
                        writeback_value = {{24{shifted_load_data[7]}}, shifted_load_data[7:0]};
                    end
                    3'b010: begin // LW requires a word-aligned address
                        if (data_address[1:0] == 2'b00) begin
                            register_write_enable = 1'b1;
                            writeback_value = data_read_data;
                        end else begin
                            trap_valid = 1'b1;
                            trap_cause = 32'd4;
                            trap_value = data_address;
                        end
                    end
                    default: illegal_instruction = 1'b1;
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
                    3'b100: if ($signed(rs1_value) < $signed(rs2_value)) next_pc = program_counter + immediate_b; // BLT
                    3'b101: if ($signed(rs1_value) >= $signed(rs2_value)) next_pc = program_counter + immediate_b; // BGE
                    3'b110: if (rs1_value < rs2_value) next_pc = program_counter + immediate_b; // BLTU
                    3'b111: if (rs1_value >= rs2_value) next_pc = program_counter + immediate_b; // BGEU
                    default: illegal_instruction = 1'b1;
                endcase
                if (next_pc[1:0] != 2'b00 && next_pc != program_counter + 32'd4) begin
                    trap_valid = 1'b1;
                    trap_cause = 32'd0;
                    trap_value = next_pc;
                end
            end

            7'b1101111: begin // JAL: save the return address and jump
                register_write_enable = 1'b1;
                writeback_value = program_counter + 32'd4;
                next_pc = program_counter + immediate_j;
                if (next_pc[1:0] != 2'b00) begin
                    trap_valid = 1'b1;
                    trap_cause = 32'd0;
                    trap_value = next_pc;
                end
            end

            7'b1100111: begin // JALR: clear target bit zero as specified
                if (funct3 == 3'b000) begin
                    register_write_enable = 1'b1;
                    writeback_value = program_counter + 32'd4;
                    next_pc = (rs1_value + immediate_i) & 32'hffff_fffe;
                    if (next_pc[1:0] != 2'b00) begin
                        trap_valid = 1'b1;
                        trap_cause = 32'd0;
                        trap_value = next_pc;
                    end
                end else begin
                    illegal_instruction = 1'b1;
                end
            end

            7'b0110111: begin // LUI: place the upper immediate in rd
                register_write_enable = 1'b1;
                writeback_value = immediate_u;
            end

            7'b0010111: begin // AUIPC: add the upper immediate to the PC
                register_write_enable = 1'b1;
                writeback_value = program_counter + immediate_u;
            end

            7'b0001111: begin // FENCE and FENCE.I are no-ops in this single-hart core
                if (funct3 != 3'b000 && funct3 != 3'b001) illegal_instruction = 1'b1;
            end

                7'b0101111: begin // A extension: word LR/SC and AMO operations
                    data_address = rs1_value;
                    if (funct3 != 3'b010) begin
                        illegal_instruction = 1'b1;
                    end else if (data_address[1:0] != 2'b00) begin
                        trap_valid = 1'b1;
                        trap_cause = (instruction[31:27] == 5'b00010) ? 32'd4 : 32'd6;
                        trap_value = data_address;
                    end else begin
                        register_write_enable = 1'b1;
                        writeback_value = data_read_data;
                        case (instruction[31:27])
                            5'b00010: begin // LR.W requires rs2=x0
                                if (rs2 == 5'd0) reservation_set = 1'b1;
                                else illegal_instruction = 1'b1;
                            end
                            5'b00011: begin // SC.W returns 0 on success, 1 on failure
                                writeback_value = 32'd1;
                                reservation_clear = 1'b1;
                                if (reservation_valid && reservation_address == data_address) begin
                                    data_write_enable = 1'b1;
                                    data_write_data = rs2_value;
                                    writeback_value = 32'd0;
                                end
                            end
                            5'b00001: begin data_write_enable = 1'b1; data_write_data = rs2_value; end // AMOSWAP.W
                            5'b00000: begin data_write_enable = 1'b1; data_write_data = data_read_data + rs2_value; end // AMOADD.W
                            5'b00100: begin data_write_enable = 1'b1; data_write_data = data_read_data ^ rs2_value; end // AMOXOR.W
                            5'b01100: begin data_write_enable = 1'b1; data_write_data = data_read_data & rs2_value; end // AMOAND.W
                            5'b01000: begin data_write_enable = 1'b1; data_write_data = data_read_data | rs2_value; end // AMOOR.W
                            5'b10000: begin data_write_enable = 1'b1; data_write_data = ($signed(data_read_data) < $signed(rs2_value)) ? data_read_data : rs2_value; end // AMOMIN.W
                            5'b10100: begin data_write_enable = 1'b1; data_write_data = ($signed(data_read_data) > $signed(rs2_value)) ? data_read_data : rs2_value; end // AMOMAX.W
                            5'b11000: begin data_write_enable = 1'b1; data_write_data = (data_read_data < rs2_value) ? data_read_data : rs2_value; end // AMOMINU.W
                            5'b11100: begin data_write_enable = 1'b1; data_write_data = (data_read_data > rs2_value) ? data_read_data : rs2_value; end // AMOMAXU.W
                            default: illegal_instruction = 1'b1;
                        endcase
                        if (instruction[31:27] != 5'b00010) reservation_clear = 1'b1;
                    end
                end

            7'b1110011: begin // Machine-mode SYSTEM instructions and CSR access
                case (funct3)
                    3'b000: begin
                        case (instruction[31:20])
                            12'h000: begin // ECALL from machine mode
                                if (rd == 0 && rs1 == 0) begin
                                    trap_valid = 1'b1;
                                    trap_cause = 32'd11;
                                end else illegal_instruction = 1'b1;
                            end
                            12'h001: begin // EBREAK
                                if (rd == 0 && rs1 == 0) begin
                                    trap_valid = 1'b1;
                                    trap_cause = 32'd3;
                                end else illegal_instruction = 1'b1;
                            end
                            12'h302: begin // MRET
                                if (rd == 0 && rs1 == 0) begin
                                    mret = 1'b1;
                                    next_pc = mret_address;
                                end else illegal_instruction = 1'b1;
                            end
                            default: illegal_instruction = 1'b1;
                        endcase
                    end
                    3'b001, 3'b010, 3'b011, 3'b101, 3'b110, 3'b111: begin
                        if (csr_access_valid) begin
                            register_write_enable = 1'b1;
                            writeback_value = csr_read_data;
                            if (funct3[2]) csr_source_value = {27'b0, rs1};
                            case (funct3[1:0])
                                2'b01: begin // CSRRW[I]
                                    csr_new_value = csr_source_value;
                                    csr_write_enable = 1'b1;
                                end
                                2'b10: begin // CSRRS[I]; source zero suppresses the write
                                    csr_new_value = csr_read_data | csr_source_value;
                                    csr_write_enable = (csr_source_value != 0);
                                end
                                2'b11: begin // CSRRC[I]
                                    csr_new_value = csr_read_data & ~csr_source_value;
                                    csr_write_enable = (csr_source_value != 0);
                                end
                                default: illegal_instruction = 1'b1;
                            endcase
                            csr_write_data = csr_new_value;
                        end else illegal_instruction = 1'b1;
                    end
                    default: illegal_instruction = 1'b1;
                endcase
            end

            default: illegal_instruction = 1'b1;
        endcase

        // Route unsupported encodings to machine mode and suppress their
        // architectural side effects. Synchronous exceptions take PC priority.
        if (illegal_instruction) begin
            trap_valid = 1'b1;
            trap_cause = 32'd2;
            trap_value = instruction;
        end
        if (trap_valid) begin
            next_pc = trap_vector;
            register_write_enable = 1'b0;
            data_write_enable = 1'b0;
            csr_write_enable = 1'b0;
                reservation_set = 1'b0;
                reservation_clear = 1'b1;
        end

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
                reservation_valid <= 1'b0;
                reservation_address <= 32'b0;
            for (integer index = 0; index < 32; index = index + 1) begin
                registers[index] <= 32'b0;
            end
        end else begin
            program_counter <= next_pc;
                if (reservation_clear || data_write_enable) begin
                    reservation_valid <= 1'b0;
                end
                if (reservation_set) begin
                    reservation_valid <= 1'b1;
                    reservation_address <= data_address;
                end
            if (register_write_enable) begin
                registers[rd] <= writeback_value;
            end
        end
    end
endmodule
