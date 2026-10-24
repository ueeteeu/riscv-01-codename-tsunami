// Educational single-cycle RV32 core with integer, M/A, simulation-oriented
// F/D, compressed FP memory operations, bit manipulation, M/S-mode, PMP, and
// separately wired machine/supervisor interrupt-pending inputs.
//
// Instruction/data address outputs are physical addresses; program_counter is
// virtual when Sv32 is active. Instruction reads are same-cycle; data memory
// uses word lanes with adjacent-word ports for FLD/FSD.
module rv32i_single_cycle (
    input  logic        clk,
    input  logic        reset,
    input  logic [63:0] time_counter, // Platform source exposed through the time/timeh CSRs.

    output logic [31:0] instruction_address,
    input  logic [31:0] instruction,
    input  logic        instruction_access_fault,
    input  logic        instruction_access_fault_next_halfword,

    output logic [31:0] data_address,
    output logic [31:0] data_write_data,
    output logic        data_write_enable,
    output logic [3:0]  data_write_mask,
    output logic [31:0] data_write_data_next_word,
    output logic        data_write_enable_next_word,
    output logic [3:0]  data_write_mask_next_word,
    input  logic [31:0] data_read_data,
    input  logic [31:0] data_read_data_next_word,
    input  logic        data_access_fault,
    input  logic        data_access_fault_next_word,
    input  logic [2:0]  external_interrupts, // [0] MSIP, [1] MTIP, [2] MEIP
    input  logic [2:0]  supervisor_interrupts, // [0] SSIP, [1] STIP, [2] SEIP
    output logic        pte_read_enable,
    output logic [31:0] pte_read_address,
    input  logic [31:0] pte_read_data,
    input  logic        pte_access_fault,

    output logic [31:0] program_counter,
    output logic        illegal_instruction
);
    // The register file has 32 architectural registers. x0 is represented
    // by a constant read value and is never allowed to be written.
    logic [31:0] registers [0:31];
    logic [63:0] floating_registers [0:31];

    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [31:0] rs1_value;
    logic [31:0] rs2_value;
    logic [31:0] floating_rs1_value;
    logic [31:0] floating_rs2_value;
    logic [31:0] floating_rs3_value;
    logic [31:0] floating_unit_operand_a;
    logic [31:0] floating_result;
    logic [63:0] double_result;
    logic [4:0]  floating_exception_flags;
    logic [4:0]  double_exception_flags;
    logic [2:0]  dynamic_rounding_mode;
    logic [31:0] floating_csr_state;
    logic [31:0] satp_state;
    logic status_sum;
    logic status_mxr;
    logic [2:0]  fetch_pmp_size;
    logic        fetch_pmp_denied;
    logic [3:0]  data_pmp_size;
    logic        data_pmp_read;
    logic        data_pmp_write;
    logic        data_pmp_denied;
    logic [31:0] virtual_data_address;
    logic fetch_translation_ready;
    logic fetch_page_fault;
    logic fetch_translation_access_fault;
    logic data_translation_ready;
    logic data_page_fault;
    logic data_translation_access_fault;
    logic [31:0] translated_fetch_address;
    logic [31:0] translated_data_address;
    logic translation_stall;
    logic sfence_vma;
    logic sfence_vma_address_valid;
    logic [31:0] sfence_vma_address;
    logic sfence_vma_asid_valid;
    logic [8:0] sfence_vma_asid;
    logic        data_translation_request;
    logic        pte_pmp_denied;

    logic [31:0] immediate_i;
    logic [31:0] immediate_s;
    logic [31:0] immediate_b;
    logic [31:0] immediate_u;
    logic [31:0] immediate_j;

    logic [31:0] next_pc;
    logic [31:0] decoded_next_pc;
    logic [31:0] writeback_value;
    logic        register_write_enable;
    logic        floating_register_write_enable;
    logic        floating_unit_recognized;
    logic        floating_result_to_fp;
    logic        double_unit_recognized;
    logic        double_result_to_fp;
    logic        floating_flags_write_enable;
    logic [4:0]  floating_flags_write_data;
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
    logic        sret;
    logic [31:0] mret_address;
    logic [31:0] sret_address;
    logic        interrupt_valid;
    logic [31:0] interrupt_cause;
    logic [1:0]  current_privilege;
    logic [31:0] csr_source_value;
    logic [31:0] csr_new_value;
    logic        csr_write_attempt;
    logic        instruction_retired;
    logic [63:0] product_unsigned;
    logic signed [63:0] product_signed;
    logic signed [63:0] product_signed_unsigned;
    logic [31:0] shifted_load_data;
    logic [63:0] floating_writeback_value;
    logic        bitmanip_recognized;
    logic [31:0] bitmanip_result;
    logic [31:0] decoded_instruction;
    logic        is_compressed;
    logic        illegal_compressed;
    logic [31:0] pc_increment;
        logic        reservation_valid;
        logic [31:0] reservation_address;
        logic        reservation_set;
        logic        reservation_clear;

    rv32i_machine_csrs machine_csrs (
        .clk(clk),
        .reset(reset),
        .instruction_retired(instruction_retired),
        .time_counter(time_counter),
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
        .mret_address(mret_address),
        .sret(sret),
        .sret_address(sret_address),
        .external_interrupts(external_interrupts),
        .supervisor_interrupts(supervisor_interrupts),
        .interrupt_valid(interrupt_valid),
        .interrupt_cause(interrupt_cause),
        .current_privilege(current_privilege),
        .floating_flags_set(floating_flags_write_enable),
        .floating_flags(floating_flags_write_data),
        .dynamic_rounding_mode(dynamic_rounding_mode),
        .floating_csr_state(floating_csr_state),
        .satp_state(satp_state),
        .status_sum(status_sum),
        .status_mxr(status_mxr),
        .fetch_address(instruction_address),
        .fetch_size(fetch_pmp_size),
        .fetch_pmp_denied(fetch_pmp_denied),
        .data_access_address(data_address),
        .data_access_size(data_pmp_size),
        .data_access_read(data_pmp_read),
        .data_access_write(data_pmp_write),
        .data_pmp_denied(data_pmp_denied),
        .pte_access_address(pte_read_address),
        .pte_access_enable(pte_read_enable),
        .pte_pmp_denied(pte_pmp_denied)
    );

    rv32i_sv32_mmu address_translation (
        .clk(clk),
        .reset(reset),
        .satp(satp_state),
        .privilege(current_privilege),
        .sum(status_sum),
        .mxr(status_mxr),
        .sfence_vma(sfence_vma),
        .sfence_vma_address_valid(sfence_vma_address_valid),
        .sfence_vma_address(sfence_vma_address),
        .sfence_vma_asid_valid(sfence_vma_asid_valid),
        .sfence_vma_asid(sfence_vma_asid),
        .fetch_virtual_address(program_counter),
        .fetch_physical_address(translated_fetch_address),
        .fetch_ready(fetch_translation_ready),
        .fetch_page_fault(fetch_page_fault),
        .fetch_access_fault(fetch_translation_access_fault),
        .data_virtual_address(virtual_data_address),
        .data_read(data_pmp_read && fetch_translation_ready &&
                   !fetch_page_fault && !fetch_translation_access_fault),
        .data_write(data_pmp_write && fetch_translation_ready &&
                    !fetch_page_fault && !fetch_translation_access_fault),
        .data_physical_address(translated_data_address),
        .data_ready(data_translation_ready),
        .data_page_fault(data_page_fault),
        .data_access_fault(data_translation_access_fault),
        .pte_read_enable(pte_read_enable),
        .pte_read_address(pte_read_address),
        .pte_read_data(pte_read_data),
        .pte_access_fault(pte_access_fault || pte_pmp_denied)
    );

    rv32i_bitmanip bitmanip_unit (
        .instruction(decoded_instruction),
        .operand_a(rs1_value),
        .operand_b(rs2_value),
        .recognized(bitmanip_recognized),
        .result(bitmanip_result)
    );

    rv32f_unit floating_point_unit (
        .instruction(decoded_instruction),
        .operand_a(floating_unit_operand_a),
        .operand_b(floating_rs2_value),
        .operand_c(floating_rs3_value),
        .recognized(floating_unit_recognized),
        .writes_fp_register(floating_result_to_fp),
        .result(floating_result),
        .dynamic_rounding_mode(dynamic_rounding_mode),
        .exception_flags(floating_exception_flags)
    );

    rv32d_unit double_precision_unit (
        .instruction(decoded_instruction),
        .operand_a(floating_registers[rs1]),
        .operand_b(floating_registers[rs2]),
        .operand_c(floating_registers[decoded_instruction[31:27]]),
        .integer_operand(rs1_value),
        .dynamic_rounding_mode(dynamic_rounding_mode),
        .recognized(double_unit_recognized),
        .writes_fp_register(double_result_to_fp),
        .result(double_result),
        .exception_flags(double_exception_flags)
    );

    rv32c_decompressor compressed_decoder (
        .fetched_instruction(instruction),
        .decoded_instruction(decoded_instruction),
        .is_compressed(is_compressed),
        .illegal_compressed(illegal_compressed)
    );

    // Memory supplies physical instruction/data reads combinationally.
    always_comb begin
        shifted_load_data = data_read_data >> {data_address[1:0], 3'b000};
    end

    // Keep address generation independent of memory responses so access-fault
    // feedback cannot create a combinational path back into the address.
    always_comb begin
        instruction_address = translated_fetch_address;
        virtual_data_address = 32'b0;
        case (decoded_instruction[6:0])
            7'b0000011, 7'b0000111: virtual_data_address = rs1_value + immediate_i;
            7'b0100011, 7'b0100111: virtual_data_address = rs1_value + immediate_s;
            7'b0101111: virtual_data_address = rs1_value;
            default: begin end
        endcase
        data_address = translated_data_address;
    end

    always_comb begin
        data_translation_request = (data_pmp_read || data_pmp_write) &&
            fetch_translation_ready && !fetch_page_fault &&
            !fetch_translation_access_fault;
        translation_stall = !fetch_translation_ready ||
            (data_translation_request && !data_translation_ready);
    end

    always_comb begin
        fetch_pmp_size = (instruction[1:0] == 2'b11) ? 3'd4 : 3'd2;
        data_pmp_size = 4'd0;
        data_pmp_read = 1'b0;
        data_pmp_write = 1'b0;
        case (decoded_instruction[6:0])
            7'b0000011, 7'b0000111: begin
                data_pmp_read = 1'b1;
                case (decoded_instruction[14:12])
                    3'b000, 3'b100: data_pmp_size = 4'd1;
                    3'b001, 3'b101: data_pmp_size = 4'd2;
                    3'b010: data_pmp_size = 4'd4;
                    3'b011: data_pmp_size = 4'd8;
                    default: data_pmp_size = 4'd0;
                endcase
            end
            7'b0100011, 7'b0100111: begin
                data_pmp_write = 1'b1;
                case (decoded_instruction[14:12])
                    3'b000: data_pmp_size = 4'd1;
                    3'b001: data_pmp_size = 4'd2;
                    3'b010: data_pmp_size = 4'd4;
                    3'b011: data_pmp_size = 4'd8;
                    default: data_pmp_size = 4'd0;
                endcase
            end
            7'b0101111: begin
                data_pmp_read = 1'b1;
                data_pmp_write = 1'b1;
                data_pmp_size = 4'd4;
            end
            default: begin end
        endcase
    end

    // These fields occupy the same bit positions in the standard RISC-V
    // instruction formats, so they can be decoded directly from the word.
    always_comb begin
        opcode = decoded_instruction[6:0];
        rd     = decoded_instruction[11:7];
        funct3 = decoded_instruction[14:12];
        rs1    = decoded_instruction[19:15];
        rs2    = decoded_instruction[24:20];
        funct7 = decoded_instruction[31:25];

        // Reconstruct I/S/B/U/J-format immediates. I and S sign-extend 12 bits;
        // B and J also restore their implicit low zero bit, while U shifts the
        // encoded upper 20 bits into position.
        immediate_i = {{20{decoded_instruction[31]}}, decoded_instruction[31:20]};
        immediate_s = {{20{decoded_instruction[31]}}, decoded_instruction[31:25], decoded_instruction[11:7]};
        immediate_b = {{19{decoded_instruction[31]}}, decoded_instruction[31], decoded_instruction[7],
                decoded_instruction[30:25], decoded_instruction[11:8], 1'b0};
        immediate_u = {decoded_instruction[31:12], 12'b0};
        immediate_j = {{11{decoded_instruction[31]}}, decoded_instruction[31], decoded_instruction[19:12],
                decoded_instruction[20], decoded_instruction[30:21], 1'b0};

        // x0 always reads as zero, regardless of the contents of the array.
        rs1_value = (rs1 == 5'd0) ? 32'b0 : registers[rs1];
        rs2_value = (rs2 == 5'd0) ? 32'b0 : registers[rs2];
        floating_rs1_value = floating_registers[rs1];
        floating_rs2_value = floating_registers[rs2];
        floating_rs3_value = floating_registers[decoded_instruction[31:27]];
        floating_unit_operand_a = ((opcode == 7'b1010011) &&
                                   (funct7 == 7'b1101000 || funct7 == 7'b1111000)) ?
                                  rs1_value : floating_rs1_value;

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
        pc_increment         = is_compressed ? 32'd2 : 32'd4;
        decoded_next_pc      = program_counter + pc_increment;
        writeback_value      = 32'b0;
        register_write_enable = 1'b0;
        floating_register_write_enable = 1'b0;
        floating_writeback_value = 32'b0;
        data_write_data_next_word = 32'b0;
        data_write_enable_next_word = 1'b0;
        data_write_mask_next_word = 4'b0;
        floating_flags_write_enable = 1'b0;
        floating_flags_write_data = 5'b0;
        data_write_data       = rs2_value;
        data_write_enable     = 1'b0;
        data_write_mask       = 4'b0000;
        illegal_instruction   = 1'b0;
        csr_address           = decoded_instruction[31:20];
        csr_write_enable      = 1'b0;
        csr_write_data        = 32'b0;
        csr_source_value      = rs1_value;
        csr_new_value         = 32'b0;
        csr_write_attempt    = 1'b0;
        trap_valid            = 1'b0;
        trap_cause            = 32'b0;
        trap_value            = 32'b0;
        mret                  = 1'b0;
        sret                  = 1'b0;
            reservation_set       = 1'b0;
            reservation_clear     = 1'b0;
            sfence_vma            = 1'b0;
            sfence_vma_address_valid = 1'b0;
            sfence_vma_address    = 32'b0;
            sfence_vma_asid_valid = 1'b0;
            sfence_vma_asid       = 9'b0;

        case (opcode)
            7'b0110011: begin // R-type register-register arithmetic
                register_write_enable = 1'b1;
                if (bitmanip_recognized) begin
                    writeback_value = bitmanip_result;
                end else begin
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
            end

            7'b0010011: begin // I-type immediate arithmetic
                register_write_enable = 1'b1;
                if (bitmanip_recognized) begin
                    writeback_value = bitmanip_result;
                end else begin
                case (funct3)
                    3'b000: writeback_value = rs1_value + immediate_i; // ADDI
                    3'b001: begin // SLLI; upper immediate bits encode the operation
                        if (decoded_instruction[31:25] == 7'b0000000) writeback_value = rs1_value << decoded_instruction[24:20];
                        else begin register_write_enable = 1'b0; illegal_instruction = 1'b1; end
                    end
                    3'b011: writeback_value = (rs1_value < immediate_i) ? 32'd1 : 32'd0; // SLTIU
                    3'b100: writeback_value = rs1_value ^ immediate_i; // XORI
                    3'b101: begin // SRLI/SRAI
                        if (decoded_instruction[31:25] == 7'b0000000) writeback_value = rs1_value >> decoded_instruction[24:20];
                        else if (decoded_instruction[31:25] == 7'b0100000) writeback_value = $signed(rs1_value) >>> decoded_instruction[24:20];
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
            end

            7'b0000011: begin // Integer loads
                case (funct3)
                    3'b000: begin // LB sign-extends the selected byte
                        register_write_enable = 1'b1;
                        writeback_value = {{24{shifted_load_data[7]}}, shifted_load_data[7:0]};
                    end
                    3'b100: begin // LBU
                        register_write_enable = 1'b1;
                        writeback_value = {24'b0, shifted_load_data[7:0]};
                    end
                    3'b101: begin // LHU
                        if (!data_address[0]) begin
                            register_write_enable = 1'b1;
                            writeback_value = {16'b0, shifted_load_data[15:0]};
                        end else begin
                            trap_valid = 1'b1;
                            trap_cause = 32'd4;
                            trap_value = virtual_data_address;
                        end
                    end
                    3'b001: begin // LH
                        if (!data_address[0]) begin
                            register_write_enable = 1'b1;
                            writeback_value = {{16{shifted_load_data[15]}}, shifted_load_data[15:0]};
                        end else begin
                            trap_valid = 1'b1;
                            trap_cause = 32'd4;
                            trap_value = virtual_data_address;
                        end
                    end
                    3'b010: begin // LW requires a word-aligned address
                        if (data_address[1:0] == 2'b00) begin
                            register_write_enable = 1'b1;
                            writeback_value = data_read_data;
                        end else begin
                            trap_valid = 1'b1;
                            trap_cause = 32'd4;
                            trap_value = virtual_data_address;
                        end
                    end
                    default: illegal_instruction = 1'b1;
                endcase
            end

            7'b0100011: begin // Integer stores
                if (funct3 == 3'b000) begin // SB
                    data_write_enable = 1'b1;
                    data_write_mask = 4'b0001 << data_address[1:0];
                    data_write_data = rs2_value << {data_address[1:0], 3'b000};
                end else if (funct3 == 3'b001) begin // SH
                    if (!data_address[0]) begin
                        data_write_enable = 1'b1;
                        data_write_mask = 4'b0011 << data_address[1:0];
                        data_write_data = rs2_value << {data_address[1:0], 3'b000};
                    end else begin
                        trap_valid = 1'b1;
                        trap_cause = 32'd6;
                        trap_value = virtual_data_address;
                    end
                end else if (funct3 == 3'b010) begin // SW
                    if (data_address[1:0] == 2'b00) begin
                        data_write_enable = 1'b1;
                        data_write_mask = 4'b1111;
                    end else begin
                        trap_valid = 1'b1;
                        trap_cause = 32'd6;
                        trap_value = virtual_data_address;
                    end
                end else begin
                    illegal_instruction = 1'b1;
                end
            end

            7'b0000111: begin // FLW
                if (funct3 == 3'b010) begin // FLW
                    if (data_address[1:0] == 2'b00) begin
                        floating_register_write_enable = 1'b1;
                        floating_writeback_value = {32'hffff_ffff, data_read_data};
                    end else begin
                        trap_valid = 1'b1;
                        trap_cause = 32'd4;
                        trap_value = virtual_data_address;
                    end
                end else if (funct3 == 3'b011) begin // FLD
                    // The aligned 64-bit value is assembled little-endian from
                    // the addressed word and the following word.
                    if (data_address[2:0] == 3'b000) begin
                        floating_register_write_enable = 1'b1;
                        floating_writeback_value = {data_read_data_next_word, data_read_data};
                    end else begin
                        trap_valid = 1'b1;
                        trap_cause = 32'd4;
                        trap_value = virtual_data_address;
                    end
                end else begin
                    illegal_instruction = 1'b1;
                end
            end

            7'b0100111: begin // FSW
                if (funct3 == 3'b010) begin
                    if (data_address[1:0] == 2'b00) begin
                        data_write_enable = 1'b1;
                        data_write_mask = 4'b1111;
                        data_write_data = floating_rs2_value;
                    end else begin
                        trap_valid = 1'b1;
                        trap_cause = 32'd6;
                        trap_value = virtual_data_address;
                    end
                end else if (funct3 == 3'b011) begin // FSD
                    if (data_address[2:0] == 3'b000) begin
                        // Split the FP register into the two little-endian
                        // memory words; both lanes commit on this clock edge.
                        data_write_enable = 1'b1;
                        data_write_mask = 4'b1111;
                        data_write_data = floating_registers[rs2][31:0];
                        data_write_enable_next_word = 1'b1;
                        data_write_mask_next_word = 4'b1111;
                        data_write_data_next_word = floating_registers[rs2][63:32];
                    end else begin
                        trap_valid = 1'b1;
                        trap_cause = 32'd6;
                        trap_value = virtual_data_address;
                    end
                end else begin
                    illegal_instruction = 1'b1;
                end
            end

            7'b1010011, 7'b1000011, 7'b1000111, 7'b1001011, 7'b1001111: begin
                if (floating_unit_recognized || double_unit_recognized) begin
                    if (double_unit_recognized) begin
                        floating_flags_write_enable = |double_exception_flags;
                        floating_flags_write_data = double_exception_flags;
                        if (double_result_to_fp) begin
                            floating_register_write_enable = 1'b1;
                            floating_writeback_value = double_result;
                        end else begin
                            register_write_enable = 1'b1;
                            writeback_value = double_result[31:0];
                        end
                    end else if (floating_result_to_fp) begin
                        floating_flags_write_enable = |floating_exception_flags;
                        floating_flags_write_data = floating_exception_flags;
                        floating_register_write_enable = 1'b1;
                        floating_writeback_value = {32'hffff_ffff, floating_result};
                    end else begin
                        register_write_enable = 1'b1;
                        writeback_value = floating_result;
                        floating_flags_write_enable = |floating_exception_flags;
                        floating_flags_write_data = floating_exception_flags;
                    end
                end else begin
                    illegal_instruction = 1'b1;
                end
            end

            7'b1100011: begin // Conditional branches
                case (funct3)
                    3'b000: if (rs1_value == rs2_value) decoded_next_pc = program_counter + immediate_b; // BEQ
                    3'b001: if (rs1_value != rs2_value) decoded_next_pc = program_counter + immediate_b; // BNE
                    3'b100: if ($signed(rs1_value) < $signed(rs2_value)) decoded_next_pc = program_counter + immediate_b; // BLT
                    3'b101: if ($signed(rs1_value) >= $signed(rs2_value)) decoded_next_pc = program_counter + immediate_b; // BGE
                    3'b110: if (rs1_value < rs2_value) decoded_next_pc = program_counter + immediate_b; // BLTU
                    3'b111: if (rs1_value >= rs2_value) decoded_next_pc = program_counter + immediate_b; // BGEU
                    default: illegal_instruction = 1'b1;
                endcase
                if (decoded_next_pc[0] != 1'b0 && decoded_next_pc != program_counter + pc_increment) begin
                    trap_valid = 1'b1;
                    trap_cause = 32'd0;
                    trap_value = decoded_next_pc;
                end
            end

            7'b1101111: begin // JAL: save the return address and jump
                register_write_enable = 1'b1;
                writeback_value = program_counter + pc_increment;
                decoded_next_pc = program_counter + immediate_j;
                if (decoded_next_pc[0] != 1'b0) begin
                    trap_valid = 1'b1;
                    trap_cause = 32'd0;
                    trap_value = decoded_next_pc;
                end
            end

            7'b1100111: begin // JALR: clear target bit zero as specified
                if (funct3 == 3'b000) begin
                    register_write_enable = 1'b1;
                    writeback_value = program_counter + pc_increment;
                    decoded_next_pc = (rs1_value + immediate_i) & 32'hffff_fffe;
                    if (decoded_next_pc[0] != 1'b0) begin
                        trap_valid = 1'b1;
                        trap_cause = 32'd0;
                        trap_value = decoded_next_pc;
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
                    if (funct3 != 3'b010) begin
                        illegal_instruction = 1'b1;
                    end else if (data_access_fault) begin
                        trap_valid = 1'b1;
                        trap_cause = (decoded_instruction[31:27] == 5'b00010) ? 32'd5 : 32'd7;
                        trap_value = virtual_data_address;
                    end else if (data_address[1:0] != 2'b00) begin
                        trap_valid = 1'b1;
                        trap_cause = (decoded_instruction[31:27] == 5'b00010) ? 32'd4 : 32'd6;
                        trap_value = virtual_data_address;
                    end else begin
                        register_write_enable = 1'b1;
                        writeback_value = data_read_data;
                        case (decoded_instruction[31:27])
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
                        if (data_write_enable) data_write_mask = 4'b1111;
                        if (decoded_instruction[31:27] != 5'b00010) reservation_clear = 1'b1;
                    end
                end

            7'b1110011: begin // Machine-mode SYSTEM instructions and CSR access
                case (funct3)
                    3'b000: begin
                        case (decoded_instruction[31:20])
                            12'h000: begin // ECALL
                                if (rd == 0 && rs1 == 0) begin
                                    trap_valid = 1'b1;
                                    case (current_privilege)
                                        2'b00: trap_cause = 32'd8;
                                        2'b01: trap_cause = 32'd9;
                                        default: trap_cause = 32'd11;
                                    endcase
                                end else illegal_instruction = 1'b1;
                            end
                            12'h001: begin // EBREAK
                                if (rd == 0 && rs1 == 0) begin
                                    trap_valid = 1'b1;
                                    trap_cause = 32'd3;
                                end else illegal_instruction = 1'b1;
                            end
                            12'h105: begin // WFI is a legal no-op without interrupt delivery
                                if (rd != 0 || rs1 != 0) illegal_instruction = 1'b1;
                            end
                            12'h302: begin // MRET
                                if (rd == 0 && rs1 == 0 && current_privilege == 2'b11) begin
                                    mret = 1'b1;
                                    decoded_next_pc = mret_address;
                                end else illegal_instruction = 1'b1;
                            end
                            12'h102: begin // SRET
                                if (rd == 0 && rs1 == 0 && current_privilege >= 2'b01) begin
                                    sret = 1'b1;
                                    decoded_next_pc = sret_address;
                                end else illegal_instruction = 1'b1;
                            end
                            default: begin
                                if (decoded_instruction[31:25] == 7'b0001001 &&
                                    rd == 0 && current_privilege >= 2'b01) begin
                                    sfence_vma = 1'b1;
                                    sfence_vma_address_valid = (rs1 != 0);
                                    sfence_vma_address = rs1_value;
                                    sfence_vma_asid_valid = (rs2 != 0);
                                    sfence_vma_asid = rs2_value[8:0];
                                end else
                                    illegal_instruction = 1'b1;
                            end
                        endcase
                    end
                    3'b001, 3'b010, 3'b011, 3'b101, 3'b110, 3'b111: begin
                        csr_source_value = funct3[2] ? {27'b0, rs1} : rs1_value;
                        csr_write_attempt = (funct3[1:0] == 2'b01) ||
                                            ((funct3[1:0] == 2'b10 ||
                                              funct3[1:0] == 2'b11) &&
                                             csr_source_value != 0);
                        if (csr_access_valid &&
                            !(decoded_instruction[31:30] == 2'b11 && csr_write_attempt)) begin
                            register_write_enable = 1'b1;
                            writeback_value = csr_read_data;
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

        // Synchronous faults override normal execution; otherwise an enabled
        // interrupt redirects the PC before the architectural state is updated.
        if (fetch_translation_ready && !fetch_page_fault &&
            !fetch_translation_access_fault &&
            (instruction_access_fault === 1'b1 ||
            (instruction[1:0] === 2'b11 &&
             instruction_access_fault_next_halfword === 1'b1) ||
            (!illegal_instruction && fetch_pmp_denied))) begin
            trap_valid = 1'b1;
            trap_cause = 32'd1;
            trap_value = (instruction_access_fault === 1'b1) ?
                         program_counter :
                         ((instruction[1:0] === 2'b11 &&
                           instruction_access_fault_next_halfword === 1'b1) ?
                          program_counter + 32'd2 : program_counter);
        end
        if (fetch_translation_ready && fetch_translation_access_fault) begin
            trap_valid = 1'b1;
            trap_cause = 32'd1;
            trap_value = program_counter;
        end
        if (fetch_translation_ready && fetch_page_fault) begin
            trap_valid = 1'b1;
            trap_cause = 32'd12;
            trap_value = program_counter;
        end
        if (fetch_translation_ready && !fetch_page_fault &&
            !fetch_translation_access_fault && illegal_compressed &&
            instruction_access_fault !== 1'b1 &&
            !(instruction[1:0] === 2'b11 &&
              instruction_access_fault_next_halfword === 1'b1)) begin
            illegal_instruction = 1'b1;
        end
        if (fetch_translation_ready && !fetch_page_fault &&
            !fetch_translation_access_fault && illegal_instruction &&
            instruction_access_fault !== 1'b1 &&
            !(instruction[1:0] === 2'b11 &&
              instruction_access_fault_next_halfword === 1'b1)) begin
            trap_valid = 1'b1;
            trap_cause = 32'd2;
            trap_value = is_compressed ? {16'b0, instruction[15:0]} : decoded_instruction;
        end
        if (fetch_page_fault || fetch_translation_access_fault ||
            instruction_access_fault === 1'b1 ||
            (instruction[1:0] === 2'b11 &&
             instruction_access_fault_next_halfword === 1'b1))
            illegal_instruction = 1'b0;
        if (data_translation_request && data_translation_ready &&
            !data_page_fault && !data_translation_access_fault &&
            !illegal_instruction && data_access_fault &&
            (opcode == 7'b0000011 || opcode == 7'b0000111)) begin
            trap_valid = 1'b1;
            trap_cause = 32'd5;
            trap_value = virtual_data_address;
        end
        if (data_translation_request && data_translation_ready && !illegal_instruction &&
            data_translation_access_fault && data_pmp_read) begin
            trap_valid = 1'b1;
            trap_cause = 32'd5;
            trap_value = virtual_data_address;
        end
        if (data_translation_request && data_translation_ready && !illegal_instruction &&
            data_translation_access_fault && data_pmp_write) begin
            trap_valid = 1'b1;
            trap_cause = 32'd7;
            trap_value = virtual_data_address;
        end
        if (data_translation_request && data_translation_ready && !illegal_instruction &&
            data_page_fault && data_pmp_read) begin
            trap_valid = 1'b1;
            trap_cause = 32'd13;
            trap_value = virtual_data_address;
        end
        if (data_translation_request && data_translation_ready && !illegal_instruction &&
            data_page_fault && data_pmp_write) begin
            trap_valid = 1'b1;
            trap_cause = 32'd15;
            trap_value = virtual_data_address;
        end
        if (data_translation_request && data_translation_ready && !illegal_instruction &&
            !data_page_fault && !data_translation_access_fault &&
            data_pmp_denied && data_pmp_read) begin
            trap_valid = 1'b1;
            trap_cause = 32'd5;
            trap_value = virtual_data_address;
        end
        if (data_translation_ready && !illegal_instruction &&
            !data_page_fault && !data_translation_access_fault &&
            data_pmp_denied && data_pmp_write) begin
            trap_valid = 1'b1;
            trap_cause = 32'd7;
            trap_value = virtual_data_address;
        end
        if (data_translation_request && data_translation_ready &&
            !data_page_fault && !data_translation_access_fault &&
            !illegal_instruction && data_access_fault &&
            (opcode == 7'b0100011 || opcode == 7'b0100111)) begin
            trap_valid = 1'b1;
            trap_cause = 32'd7;
            trap_value = virtual_data_address;
        end
        if (data_translation_request && data_translation_ready &&
            !data_page_fault && !data_translation_access_fault && !illegal_instruction &&
            opcode == 7'b0000111 && funct3 == 3'b011 &&
            data_access_fault_next_word) begin
            trap_valid = 1'b1;
            trap_cause = 32'd5;
            trap_value = virtual_data_address + 32'd4;
        end
        if (data_translation_request && data_translation_ready &&
            !data_page_fault && !data_translation_access_fault && !illegal_instruction &&
            opcode == 7'b0100111 && funct3 == 3'b011 &&
            data_access_fault_next_word) begin
            trap_valid = 1'b1;
            trap_cause = 32'd7;
            trap_value = virtual_data_address + 32'd4;
        end
        if (!trap_valid && !illegal_instruction && interrupt_valid) begin
            trap_valid = 1'b1;
            trap_cause = interrupt_cause;
            trap_value = 32'b0;
        end
        if (translation_stall) begin
            trap_valid = 1'b0;
            illegal_instruction = 1'b0;
            register_write_enable = 1'b0;
            floating_register_write_enable = 1'b0;
            data_write_enable = 1'b0;
            data_write_enable_next_word = 1'b0;
            csr_write_enable = 1'b0;
            reservation_set = 1'b0;
            reservation_clear = 1'b0;
        end else if (trap_valid) begin
            register_write_enable = 1'b0;
            floating_register_write_enable = 1'b0;
            data_write_enable = 1'b0;
            data_write_enable_next_word = 1'b0;
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

    // Keep trap-vector feedback outside instruction decode to avoid a
    // combinational cycle between exception arbitration and next-PC selection.
    always_comb begin
        next_pc = trap_valid ? trap_vector :
                  (translation_stall ? program_counter : decoded_next_pc);
        instruction_retired = !reset && !translation_stall && !trap_valid;
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
                floating_registers[index] <= 32'b0;
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
            if (floating_register_write_enable) begin
                floating_registers[rd] <= floating_writeback_value;
            end
        end
    end
endmodule
