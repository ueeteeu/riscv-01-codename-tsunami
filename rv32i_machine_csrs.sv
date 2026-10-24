// Machine/supervisor privilege and floating-point CSR state for the RV32 core.
// Translation, counters, and debug state are intentionally outside this model.
module rv32i_machine_csrs (
    input  logic        clk,
    input  logic        reset,
    input  logic [11:0] csr_address,
    input  logic        csr_write_enable,
    input  logic [31:0] csr_write_data,
    output logic [31:0] csr_read_data,
    output logic        csr_access_valid,
    input  logic        trap_valid,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_value,
    output logic [31:0] trap_vector,
    input  logic        mret,
    output logic [31:0] mret_address,
    input  logic        sret,
    output logic [31:0] sret_address,
    input  logic [2:0]  external_interrupts,
    output logic        interrupt_valid,
    output logic [31:0] interrupt_cause,
    output logic [1:0]  current_privilege,
    input  logic        floating_flags_set,
    input  logic [4:0]  floating_flags,
    output logic [2:0]  dynamic_rounding_mode,
    output logic [31:0] floating_csr_state,
    input  logic [31:0] fetch_address,
    input  logic [2:0]  fetch_size,
    output logic        fetch_pmp_denied,
    input  logic [31:0] data_access_address,
    input  logic [3:0]  data_access_size,
    input  logic        data_access_read,
    input  logic        data_access_write,
    output logic        data_pmp_denied
);
    localparam logic [1:0] PRIV_USER = 2'b00;
    localparam logic [1:0] PRIV_SUPERVISOR = 2'b01;
    localparam logic [1:0] PRIV_MACHINE = 2'b11;

    // mstatus carries the privilege-stack bits and MPP; the remaining modeled
    // CSR storage is kept separately to make supported state explicit.
    logic [1:0] privilege;
    logic [31:0] mstatus;
    logic [31:0] mtvec;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;
    logic [31:0] medeleg;
    logic [31:0] mideleg;
    logic [31:0] mie;
    logic [31:0] mip_software;
    logic [31:0] stvec;
    logic [31:0] sscratch;
    logic [31:0] sepc;
    logic [31:0] scause;
    logic [31:0] stval;
    logic [31:0] satp;
    logic [7:0] pmpcfg [0:3];
    logic [29:0] pmpaddr [0:3];
    logic [4:0] fflags;
    logic [2:0] frm;
    logic [31:0] mip;
    logic delegated_trap;
    logic [31:0] selected_cause;
    logic [31:0] selected_vector;
    logic [1:0] required_privilege;
    logic supported_csr;

    function automatic logic pmp_access_allowed(
        input logic [31:0] address,
        input logic [3:0] access_size,
        input logic [2:0] access_type,
        input logic [1:0] access_privilege
    );
        logic any_active;
        logic matched;
        logic allowed;
        logic [32:0] access_start;
        logic [32:0] access_end;
        logic [32:0] region_start;
        logic [32:0] region_end;
        logic [32:0] region_size;
        logic [32:0] encoded_address;
        logic [7:0] config;
        integer trailing_ones;
        begin
            access_start = {1'b0, address};
            access_end = access_start + access_size;
            any_active = 1'b0;
            matched = 1'b0;
            allowed = 1'b0;
            for (integer entry = 0; entry < 4; entry = entry + 1) begin
                config = pmpcfg[entry];
                if (config[4:3] != 2'b00) any_active = 1'b1;
                region_start = 33'b0;
                region_end = 33'b0;
                encoded_address = {3'b0, pmpaddr[entry], 2'b00};
                case (config[4:3])
                    2'b01: begin
                        region_start = entry == 0 ? 33'b0 :
                            {3'b0, pmpaddr[entry-1], 2'b00};
                        region_end = encoded_address;
                    end
                    2'b10: begin
                        region_start = encoded_address;
                        region_end = encoded_address + 33'd4;
                    end
                    2'b11: begin
                        trailing_ones = 0;
                        for (integer bit_index = 0; bit_index < 30; bit_index = bit_index + 1) begin
                            if (bit_index == trailing_ones && pmpaddr[entry][bit_index])
                                trailing_ones = trailing_ones + 1;
                        end
                        region_size = 33'd1 << (trailing_ones + 3);
                        region_start = encoded_address & ~(region_size - 1'b1);
                        region_end = region_start + region_size;
                    end
                    default: begin end
                endcase
                if (!matched && config[4:3] != 2'b00 &&
                    access_start < region_end && access_end > region_start) begin
                    matched = 1'b1;
                    if (access_start >= region_start && access_end <= region_end) begin
                        if (access_privilege == PRIV_MACHINE && !config[7])
                            allowed = 1'b1;
                        else if ((access_type[0] == 1'b0 || config[0]) &&
                                 (access_type[1] == 1'b0 || config[1]) &&
                                 (access_type[2] == 1'b0 || config[2]))
                            allowed = 1'b1;
                    end
                end
            end
            if (!matched)
                allowed = (access_privilege == PRIV_MACHINE) || !any_active;
            pmp_access_allowed = allowed;
        end
    endfunction

    // External interrupt pins map to MEIP, MTIP, and MSIP. Check priority in
    // the architectural order (external, software, then timer).
    always_comb begin
        mip = mip_software;
        mip[3] = external_interrupts[0] === 1'b1;
        mip[7] = external_interrupts[1] === 1'b1;
        mip[11] = external_interrupts[2] === 1'b1;

        interrupt_valid = 1'b0;
        interrupt_cause = 32'b0;
        if (mip[11] && mie[11] &&
            (!mideleg[11] ? (privilege != PRIV_MACHINE || mstatus[3]) :
                            (privilege == PRIV_USER || (privilege == PRIV_SUPERVISOR && mstatus[1])))) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_000b;
        end else if (mip[3] && mie[3] &&
                     (!mideleg[3] ? (privilege != PRIV_MACHINE || mstatus[3]) :
                                     (privilege == PRIV_USER || (privilege == PRIV_SUPERVISOR && mstatus[1])))) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_0003;
        end else if (mip[7] && mie[7] &&
                     (!mideleg[7] ? (privilege != PRIV_MACHINE || mstatus[3]) :
                                     (privilege == PRIV_USER || (privilege == PRIV_SUPERVISOR && mstatus[1])))) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_0007;
        end
    end

    // Synchronous exceptions are delegated only from below M-mode. Vectored
    // trap mode offsets asynchronous interrupt targets by cause number.
    always_comb begin
        selected_cause = trap_valid ? trap_cause : interrupt_cause;
        delegated_trap = (privilege != PRIV_MACHINE) &&
                         ((selected_cause[31] && mideleg[selected_cause[4:0]]) ||
                          (!selected_cause[31] && medeleg[selected_cause[4:0]]));
        selected_vector = delegated_trap ? stvec : mtvec;
        trap_vector = selected_vector[31:2] << 2;
        if (selected_cause[31] && selected_vector[1:0] == 2'b01)
            trap_vector = trap_vector + {selected_cause[29:0], 2'b00};
        mret_address = {mepc[31:1], 1'b0};
        sret_address = {sepc[31:1], 1'b0};
        current_privilege = privilege;
        dynamic_rounding_mode = frm;
        floating_csr_state = {24'b0, frm, 2'b0, fflags};

        required_privilege = csr_address[9:8];
        supported_csr = 1'b1;
        case (csr_address)
            12'h001, 12'h002, 12'h003, 12'h100, 12'h104, 12'h105,
            12'h140, 12'h141, 12'h142, 12'h143, 12'h144, 12'h180,
            12'h300, 12'h301, 12'h302, 12'h303, 12'h304, 12'h305,
            12'h3a0, 12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3,
            12'h340, 12'h341, 12'h342, 12'h343, 12'h344: begin end
            default: supported_csr = 1'b0;
        endcase
        // CSR address bits [9:8] encode the minimum privilege level.
        csr_access_valid = supported_csr && privilege >= required_privilege;
        csr_read_data = 32'b0;
        fetch_pmp_denied = !pmp_access_allowed(
            fetch_address, {1'b0, fetch_size},
            3'b100, privilege
        );
        data_pmp_denied = 1'b0;
        if (data_access_read || data_access_write) begin
            data_pmp_denied = !pmp_access_allowed(
                data_access_address, data_access_size,
                {1'b0, data_access_write, data_access_read}, privilege
            );
        end
        if (csr_access_valid) begin
            case (csr_address)
                12'h001: csr_read_data = {27'b0, fflags};
                12'h002: csr_read_data = {29'b0, frm};
                12'h003: csr_read_data = floating_csr_state;
                12'h100: csr_read_data = mstatus & 32'h0000_0122;
                12'h104: csr_read_data = mie & mideleg;
                12'h105: csr_read_data = stvec;
                12'h140: csr_read_data = sscratch;
                12'h141: csr_read_data = sepc;
                12'h142: csr_read_data = scause;
                12'h143: csr_read_data = stval;
                12'h144: csr_read_data = mip & mideleg;
                12'h180: csr_read_data = satp;
                12'h300: csr_read_data = mstatus;
                12'h301: csr_read_data = 32'h4000_112d; // RV32IMAFDC, XLEN=32
                12'h302: csr_read_data = medeleg;
                12'h303: csr_read_data = mideleg;
                12'h304: csr_read_data = mie;
                12'h305: csr_read_data = mtvec;
                12'h340: csr_read_data = mscratch;
                12'h341: csr_read_data = mepc;
                12'h342: csr_read_data = mcause;
                12'h343: csr_read_data = mtval;
                12'h344: csr_read_data = mip;
                12'h3a0: csr_read_data = {pmpcfg[3], pmpcfg[2], pmpcfg[1], pmpcfg[0]};
                12'h3b0: csr_read_data = {2'b0, pmpaddr[0]};
                12'h3b1: csr_read_data = {2'b0, pmpaddr[1]};
                12'h3b2: csr_read_data = {2'b0, pmpaddr[2]};
                12'h3b3: csr_read_data = {2'b0, pmpaddr[3]};
                default: begin end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            privilege <= PRIV_MACHINE;
            mstatus <= 32'b0;
            mtvec <= 32'b0;
            mscratch <= 32'b0;
            mepc <= 32'b0;
            mcause <= 32'b0;
            mtval <= 32'b0;
            medeleg <= 32'b0;
            mideleg <= 32'b0;
            mie <= 32'b0;
            mip_software <= 32'b0;
            stvec <= 32'b0;
            sscratch <= 32'b0;
            sepc <= 32'b0;
            scause <= 32'b0;
            stval <= 32'b0;
            satp <= 32'b0;
            for (integer entry = 0; entry < 4; entry = entry + 1) begin
                pmpcfg[entry] <= 8'b0;
                pmpaddr[entry] <= 30'b0;
            end
            fflags <= 5'b0;
            frm <= 3'b0;
        end else if (trap_valid || interrupt_valid) begin
            if (delegated_trap) begin
                sepc <= {trap_pc[31:1], 1'b0};
                scause <= selected_cause;
                stval <= trap_valid ? trap_value : 32'b0;
                mstatus[8] <= (privilege == PRIV_SUPERVISOR);
                mstatus[5] <= mstatus[1];
                mstatus[1] <= 1'b0;
                privilege <= PRIV_SUPERVISOR;
            end else begin
                mepc <= {trap_pc[31:1], 1'b0};
                mcause <= selected_cause;
                mtval <= trap_valid ? trap_value : 32'b0;
                mstatus[7] <= mstatus[3];
                mstatus[3] <= 1'b0;
                mstatus[12:11] <= privilege;
                privilege <= PRIV_MACHINE;
            end
        end else if (mret) begin
            case (mstatus[12:11])
                2'b00: privilege <= PRIV_USER;
                2'b01: privilege <= PRIV_SUPERVISOR;
                default: privilege <= PRIV_MACHINE;
            endcase
            mstatus[3] <= mstatus[7];
            mstatus[7] <= 1'b1;
            mstatus[12:11] <= PRIV_USER;
        end else if (sret) begin
            privilege <= mstatus[8] ? PRIV_SUPERVISOR : PRIV_USER;
            mstatus[1] <= mstatus[5];
            mstatus[5] <= 1'b1;
            mstatus[8] <= 1'b0;
        end else begin
            // FP exception flags accrue by OR; software writes to fflags/fcsr
            // replace them, allowing explicit clearing as well as setting.
            if (floating_flags_set) fflags <= fflags | floating_flags;
            if (csr_write_enable && csr_access_valid) begin
                case (csr_address)
                    12'h001: fflags <= csr_write_data[4:0];
                    12'h002: frm <= csr_write_data[2:0];
                    12'h003: begin
                        fflags <= csr_write_data[4:0];
                        frm <= csr_write_data[7:5];
                    end
                    12'h100: begin
                        mstatus[8] <= csr_write_data[8];
                        mstatus[5] <= csr_write_data[5];
                        mstatus[1] <= csr_write_data[1];
                    end
                    12'h104: mie <= (mie & ~mideleg) | (csr_write_data & mideleg);
                    12'h105: stvec <= {csr_write_data[31:2], 1'b0,
                                         (csr_write_data[1:0] == 2'b01)};
                    12'h140: sscratch <= csr_write_data;
                    12'h141: sepc <= {csr_write_data[31:1], 1'b0};
                    12'h142: scause <= csr_write_data;
                    12'h143: stval <= csr_write_data;
                    12'h144: mip_software[3] <= csr_write_data[3];
                    12'h180: satp <= csr_write_data;
                    12'h300: begin
                        mstatus[3] <= csr_write_data[3];
                        mstatus[7] <= csr_write_data[7];
                        case (csr_write_data[12:11])
                            2'b00: mstatus[12:11] <= PRIV_USER;
                            2'b01: mstatus[12:11] <= PRIV_SUPERVISOR;
                            default: mstatus[12:11] <= PRIV_MACHINE;
                        endcase
                        mstatus[8] <= csr_write_data[8];
                        mstatus[5] <= csr_write_data[5];
                        mstatus[1] <= csr_write_data[1];
                    end
                    12'h302: medeleg <= csr_write_data & 32'h0000_0bff;
                    12'h303: mideleg <= csr_write_data & 32'h0000_0888;
                    12'h304: mie <= (mie & mideleg) | (csr_write_data & ~mideleg);
                    12'h305: mtvec <= {csr_write_data[31:2], 1'b0,
                                         (csr_write_data[1:0] == 2'b01)};
                    12'h340: mscratch <= csr_write_data;
                    12'h341: mepc <= {csr_write_data[31:1], 1'b0};
                    12'h342: mcause <= csr_write_data;
                    12'h343: mtval <= csr_write_data;
                    12'h344: mip_software[3] <= csr_write_data[3];
                    12'h3a0: begin
                        for (integer entry = 0; entry < 4; entry = entry + 1) begin
                            if (!pmpcfg[entry][7]) begin
                                pmpcfg[entry] <= {
                                    csr_write_data[entry * 8 + 7],
                                    csr_write_data[entry * 8 + 6:entry * 8 + 5],
                                    csr_write_data[entry * 8 + 4:entry * 8 + 3],
                                    csr_write_data[entry * 8 + 2],
                                    (csr_write_data[entry * 8 + 1] &&
                                     csr_write_data[entry * 8]),
                                    csr_write_data[entry * 8]
                                };
                            end
                        end
                    end
                    12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3: begin
                        for (integer entry = 0; entry < 4; entry = entry + 1) begin
                            if (csr_address == 12'h3b0 + entry &&
                                !pmpcfg[entry][7] &&
                                !(entry < 3 && pmpcfg[entry + 1][7] &&
                                  pmpcfg[entry + 1][4:3] == 2'b01))
                                pmpaddr[entry] <= csr_write_data[29:0];
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
