// A simple behavioral memory for rv32i_single_cycle.
//
// Capacity is 8 MiB: 2,097,152 words of 32 bits each. Addresses from the CPU
// are byte addresses, while this module stores complete 32-bit words.
// Instruction and load reads are asynchronous to match the single-cycle core;
// stores take effect on the rising clock edge.
module rv32i_memory #(
    // Optional hexadecimal file with one 32-bit word per line, for example
    // "program.hex". The first line is placed at byte address zero.
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        reset,

    input  logic [31:0] instruction_address,
    output logic [31:0] instruction,

    input  logic [31:0] data_address,
    input  logic [31:0] data_write_data,
    input  logic        data_write_enable,
    output logic [31:0] data_read_data
);
    localparam integer MEMORY_BYTES = 8 * 1024 * 1024;
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

    // Instruction fetches must be word-aligned. Data reads return their
    // containing word so LB can select a byte; the CPU checks LW/AMO alignment.
    // Out-of-range reads return zero and out-of-range writes are ignored.
    always_comb begin
        instruction = 32'b0;
        data_read_data = 32'b0;

        if (instruction_address[1:0] == 2'b00 && instruction_address < MEMORY_BYTES) begin
            instruction = words[instruction_address[22:2]];
        end

        // Data reads return the containing word; the CPU selects the addressed
        // byte for LB. Word alignment is checked by the CPU for LW.
        if (data_address < MEMORY_BYTES) begin
            data_read_data = words[data_address[22:2]];
        end
    end

    // Store writes are committed at the end of the executing instruction's
    // cycle, synchronized with the CPU's PC and register-file updates.
    always_ff @(posedge clk) begin
        if (!reset &&
            data_write_enable &&
            data_address[1:0] == 2'b00 &&
            data_address < MEMORY_BYTES) begin
            words[data_address[22:2]] <= data_write_data;
        end
    end
endmodule
