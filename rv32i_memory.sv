// A simple behavioral memory for rv32i_single_cycle.
//
// Capacity is 8 MiB: 2,097,152 words of 32 bits each. Addresses from the CPU
// are byte addresses, while this module stores complete 32-bit words with byte lanes.
// Instruction and load reads are asynchronous to match the single-cycle core;
// stores take effect on the rising clock edge.
module rv32i_memory #(
    // Optional hexadecimal file with one 32-bit word per line, for example
    // "program.hex". The first line is placed at byte address zero.
    parameter INIT_FILE = "",
    parameter integer MEMORY_BYTES = 8 * 1024 * 1024
) (
    input  logic        clk,
    input  logic        reset,

    input  logic [31:0] instruction_address,
    output logic [31:0] instruction,
    output logic        instruction_access_fault,
    output logic        instruction_access_fault_next_halfword,

    input  logic [31:0] data_address,
    input  logic [31:0] data_write_data,
    input  logic        data_write_enable,
    input  logic [3:0]  data_write_mask,
    input  logic [31:0] data_write_data_next_word,
    input  logic        data_write_enable_next_word,
    input  logic [3:0]  data_write_mask_next_word,
    output logic [31:0] data_read_data,
    output logic [31:0] data_read_data_next_word,
    output logic        data_access_fault,
    output logic        data_access_fault_next_word
);
    localparam integer WORD_COUNT   = MEMORY_BYTES / 4;

    // Each array entry corresponds to four consecutive byte addresses.
    logic [31:0] words [0:WORD_COUNT - 1];

    // Give uninitialized locations deterministic values in simulation and
    // FPGA flows. An optional program image then replaces the needed words.
    initial begin
        for (integer index = 0; index < WORD_COUNT; index = index + 1) begin
            words[index] = 32'b0;
        end
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, words);
        end
    end

    // Instruction fetch returns a halfword-aligned 32-bit window so compressed
    // instructions and 32-bit instructions at PC+2 both decode correctly.
    // Data reads return their containing word so LB can select a byte.
    always_comb begin
        instruction = 32'b0;
        instruction_access_fault = (instruction_address >= MEMORY_BYTES);
        instruction_access_fault_next_halfword =
            (instruction_address >= MEMORY_BYTES - 2);
        if (instruction_address[0] == 1'b0 && instruction_address < MEMORY_BYTES) begin
            if (instruction_address[1] == 1'b0) begin
                instruction = words[instruction_address[22:2]];
            end else begin
                // Present a 32-bit fetch window beginning at the upper
                // halfword, spanning two words when a 32-bit op starts here.
                instruction[15:0] = words[instruction_address[22:2]][31:16];
                if (instruction_address < MEMORY_BYTES - 2) begin
                    instruction[31:16] = words[instruction_address[22:2] + 1'b1][15:0];
                end
            end
        end
    end

    always_comb begin
        data_read_data = 32'b0;
        data_read_data_next_word = 32'b0;
        data_access_fault = (data_address >= MEMORY_BYTES);
        data_access_fault_next_word = (data_address >= MEMORY_BYTES - 4);
        // Data reads return the containing word; the CPU selects and extends
        // the addressed byte or halfword.
        if (data_address < MEMORY_BYTES) begin
            data_read_data = words[data_address[22:2]];
        end
        if (data_address < MEMORY_BYTES - 4) begin
            data_read_data_next_word = words[data_address[22:2] + 1'b1];
        end
    end

    // Store writes are committed at the end of the executing instruction's
    // cycle, synchronized with the CPU's PC and register-file updates.
    always_ff @(posedge clk) begin
        if (!reset && data_write_enable && !data_access_fault) begin
            for (integer lane = 0; lane < 4; lane = lane + 1) begin
                if (data_write_mask[lane]) begin
                    words[data_address[22:2]][lane * 8 +: 8] <= data_write_data[lane * 8 +: 8];
                end
            end
            if (!reset && data_write_enable_next_word &&
                data_address < MEMORY_BYTES - 4) begin
                for (integer lane = 0; lane < 4; lane = lane + 1) begin
                    if (data_write_mask_next_word[lane]) begin
                        words[data_address[22:2] + 1'b1][lane * 8 +: 8]
                            <= data_write_data_next_word[lane * 8 +: 8];
                    end
                end
            end
        end
    end
endmodule
