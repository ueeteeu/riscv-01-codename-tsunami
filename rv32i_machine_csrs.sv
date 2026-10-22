// Machine-mode CSR and synchronous-trap state for the educational RV32 core.
// This first privileged-ISA stage supports machine mode only, direct mtvec
// traps, and no asynchronous interrupts or lower privilege levels.
module rv32i_machine_csrs (
    input  logic        clk,
    input  logic        reset,

    // CSR instruction interface. Reads are combinational; writes commit at
    // the clock edge unless a trap or MRET takes priority.
    input  logic [11:0] csr_address,
    input  logic        csr_write_enable,
    input  logic [31:0] csr_write_data,
    output logic [31:0] csr_read_data,
    output logic        csr_access_valid,

    // Synchronous exception entry and return control from the CPU decoder.
    input  logic        trap_valid,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_value,
    output logic [31:0] trap_vector,
    input  logic        mret,
    output logic [31:0] mret_address
);
    logic        mstatus_mie;
    logic        mstatus_mpie;
    logic [31:0] mtvec_base;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;

    // Only the machine CSRs used by this initial implementation are exposed.
    always_comb begin
        csr_access_valid = 1'b1;
        csr_read_data = 32'b0;

        case (csr_address)
            12'h300: begin // mstatus: MIE and MPIE; MPP is fixed to machine mode
                csr_read_data = {19'b0, 2'b11, 3'b0, mstatus_mpie,
                                 3'b0, mstatus_mie, 3'b0};
            end
            12'h305: csr_read_data = {mtvec_base[31:2], 2'b00}; // mtvec, direct mode
            12'h340: csr_read_data = mscratch;
            12'h341: csr_read_data = mepc;
            12'h342: csr_read_data = mcause;
            12'h343: csr_read_data = mtval;
            default: begin
                csr_access_valid = 1'b0;
            end
        endcase

        // mtvec mode is fixed to direct (00), and mepc is word-aligned because
        // this core does not implement compressed instructions.
        trap_vector = {mtvec_base[31:2], 2'b00};
        mret_address = mepc;
    end

    // Traps save the faulting instruction address and cause. MRET restores
    // the prior global interrupt-enable bit; interrupts are not yet implemented.
    always_ff @(posedge clk) begin
        if (reset) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
            mtvec_base   <= 32'b0;
            mscratch     <= 32'b0;
            mepc         <= 32'b0;
            mcause       <= 32'b0;
            mtval        <= 32'b0;
        end else if (trap_valid) begin
            mepc         <= {trap_pc[31:2], 2'b00};
            mcause       <= trap_cause;
            mtval        <= trap_value;
            mstatus_mpie <= mstatus_mie;
            mstatus_mie  <= 1'b0;
        end else if (mret) begin
            mstatus_mie  <= mstatus_mpie;
            mstatus_mpie <= 1'b1;
        end else if (csr_write_enable && csr_access_valid) begin
            case (csr_address)
                12'h300: begin
                    mstatus_mie  <= csr_write_data[3];
                    mstatus_mpie <= csr_write_data[7];
                end
                12'h305: mtvec_base <= {csr_write_data[31:2], 2'b00};
                12'h340: mscratch <= csr_write_data;
                12'h341: mepc <= {csr_write_data[31:2], 2'b00};
                12'h342: mcause <= csr_write_data;
                12'h343: mtval <= csr_write_data;
                default: begin
                    // Unsupported CSR writes are filtered by csr_access_valid.
                end
            endcase
        end
    end
endmodule
