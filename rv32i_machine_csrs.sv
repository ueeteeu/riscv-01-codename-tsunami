// Machine/supervisor privilege, PMP, counters, and floating-point CSR state for
// the RV32 core. The Sv32 walker is a separate block; debug state is not modeled.
// Privileged CSR and trap model for the RV32 core.
//
// Supported subset (kept intentionally explicit):
//   - Machine and supervisor trap state: mstatus, mtvec, stvec, mepc, sepc,
//     mcause, scause, mtval, stval, mie, mip, medeleg, mideleg, mret/sret.
//   - ECALL/EBREAK handling is done in the core; this block only provides
//     trap entry, cause delivery, and return-state bookkeeping.
//   - Performance counters: mcycle/minstret, read-only aliases, mcounteren,
//     scounteren, and mcountinhibit behavior.
//   - PMP: OFF/TOR/NA4/NAPOT matching, first-overlap priority, lock bits,
//     permissions, and S/U-mode checks for fetch/data/PTE access.
//   - FCSR support: fflags, frm, and floating_csr_state with accrued flags.
//   - satp, SUM, MXR, and privilege tracking for the Sv32 page-walker.
//
// Non-goals intentionally left outside this block:
//   - Debug state, user-level trap CSRs, platform timers/interrupt devices,
//     PMA/other platform-specific policy, complete privileged-architecture
//     compliance, and full RV32 privilege state beyond the modeled subset.
module rv32i_machine_csrs (
    input  logic        clk,
    input  logic        reset,
    input  logic        instruction_retired,
    input  logic [63:0] time_counter,
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
    input  logic [2:0]  supervisor_interrupts,
    output logic        interrupt_valid,
    output logic [31:0] interrupt_cause,
    output logic [1:0]  current_privilege,
    input  logic        floating_flags_set,
    input  logic [4:0]  floating_flags,
    output logic [2:0]  dynamic_rounding_mode,
    output logic [31:0] floating_csr_state,
    output logic [31:0] satp_state,
    output logic        status_sum,
    output logic        status_mxr,
    input  logic [31:0] fetch_address,
    input  logic [2:0]  fetch_size,
    output logic        fetch_pmp_denied,
    input  logic [31:0] data_access_address,
    input  logic [3:0]  data_access_size,
    input  logic        data_access_read,
    input  logic        data_access_write,
    output logic        data_pmp_denied,
    input  logic [31:0] pte_access_address,
    input  logic        pte_access_enable,
    output logic        pte_pmp_denied
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
    logic [63:0] mcycle;
    logic [63:0] minstret;
    logic [31:0] mcounteren;
    logic [31:0] scounteren;
    logic [31:0] mcountinhibit;
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
    logic counter_access_enabled;

    function automatic logic interrupt_is_enabled(input logic [4:0] cause);
        begin
            interrupt_is_enabled = mip[cause] && mie[cause] &&
                (mideleg[cause] ?
                 (privilege == PRIV_USER ||
                  (privilege == PRIV_SUPERVISOR && mstatus[1])) :
                 (privilege != PRIV_MACHINE || mstatus[3]));
        end
    endfunction

    // PMP rule selection and permission checks.
    //
    // The hardware follows the simple RISC-V policy used by this project:
    //   1. Walk the PMP entries in ascending index order.
    //   2. The first matching entry whose region overlaps the access wins.
    //   3. If a match is found, deny any byte that falls outside the matched
    //      region instead of falling through to a later entry.
    //   4. If no entry matches, allow M-mode accesses and deny S/U-mode access
    //      whenever any entry is active.
    //
    // This matches the project's design intent for a small educational model and
    // keeps the permission logic easy to audit when debugging privileged access
    // failures.
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
        logic [7:0] cfg_byte;
        integer trailing_ones;
        begin
            access_start = {1'b0, address};
            access_end = access_start + access_size;
            any_active = 1'b0;
            matched = 1'b0;
            allowed = 1'b0;
            for (integer entry = 0; entry < 4; entry = entry + 1) begin
                cfg_byte = pmpcfg[entry];
                if (cfg_byte[4:3] != 2'b00) any_active = 1'b1;
                region_start = 33'b0;
                region_end = 33'b0;
                encoded_address = {1'b0, pmpaddr[entry], 2'b00};
                case (cfg_byte[4:3])
                    2'b01: begin
                        region_start = entry == 0 ? 33'b0 :
                            {1'b0, pmpaddr[entry-1], 2'b00};
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
                if (!matched && cfg_byte[4:3] != 2'b00 &&
                    access_start < region_end && access_end > region_start) begin
                    matched = 1'b1;
                    if (access_start >= region_start && access_end <= region_end) begin
                        if (access_privilege == PRIV_MACHINE && !cfg_byte[7])
                            allowed = 1'b1;
                        else if ((access_type[0] == 1'b0 || cfg_byte[0]) &&
                                 (access_type[1] == 1'b0 || cfg_byte[1]) &&
                                 (access_type[2] == 1'b0 || cfg_byte[2]))
                            allowed = 1'b1;
                    end
                end
            end
            if (!matched)
                allowed = (access_privilege == PRIV_MACHINE) || !any_active;
            pmp_access_allowed = allowed;
        end
    endfunction

    always_comb begin
        fetch_pmp_denied = !pmp_access_allowed(
            fetch_address, {1'b0, fetch_size}, 3'b100, privilege
        );
        data_pmp_denied = 1'b0;
        if (data_access_read || data_access_write) begin
            data_pmp_denied = !pmp_access_allowed(
                data_access_address, data_access_size,
                {1'b0, data_access_write, data_access_read}, privilege
            );
        end
        pte_pmp_denied = 1'b0;
        if (pte_access_enable === 1'b1)
            pte_pmp_denied = !pmp_access_allowed(
                pte_access_address, 4'd4, 3'b001, privilege
            );
    end

    // Each interrupt-class input vector is ordered software, timer, external.
    always_comb begin
        mip = mip_software;
        mip[1] = mip_software[1] || (supervisor_interrupts[0] === 1'b1);
        mip[3] = mip_software[3] || (external_interrupts[0] === 1'b1);
        mip[5] = supervisor_interrupts[1] === 1'b1;
        mip[7] = external_interrupts[1] === 1'b1;
        mip[9] = supervisor_interrupts[2] === 1'b1;
        mip[11] = external_interrupts[2] === 1'b1;

        interrupt_valid = 1'b0;
        interrupt_cause = 32'b0;
        if (interrupt_is_enabled(5'd11)) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_000b;
        end else if (interrupt_is_enabled(5'd3)) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_0003;
        end else if (interrupt_is_enabled(5'd7)) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_0007;
        end else if (interrupt_is_enabled(5'd9)) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_0009;
        end else if (interrupt_is_enabled(5'd1)) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_0001;
        end else if (interrupt_is_enabled(5'd5)) begin
            interrupt_valid = 1'b1;
            interrupt_cause = 32'h8000_0005;
        end
    end

    // Synchronous exceptions are delegated only from below M-mode. Vectored
    // trap mode offsets asynchronous interrupt targets by cause number.
    always_comb begin
        // The core arbitrates synchronous traps and interrupts into
        // trap_cause; using that value directly keeps trap-vector selection
        // from feeding back through the core's trap_valid combinational logic.
        selected_cause = trap_cause;
        delegated_trap = (privilege != PRIV_MACHINE) &&
                         ((selected_cause[31] && mideleg[selected_cause[4:0]]) ||
                          (!selected_cause[31] && medeleg[selected_cause[4:0]]));
        selected_vector = delegated_trap ? stvec : mtvec;
        trap_vector = selected_vector[31:2] << 2;
        if (selected_cause[31] && selected_vector[1:0] == 2'b01)
            trap_vector = trap_vector + ({27'b0, selected_cause[4:0]} << 2);
        mret_address = {mepc[31:1], 1'b0};
        sret_address = {sepc[31:1], 1'b0};
        current_privilege = privilege;
        dynamic_rounding_mode = frm;
        floating_csr_state = {24'b0, frm, 2'b0, fflags};
        satp_state = satp;
        status_sum = mstatus[18];
        status_mxr = mstatus[19];

        required_privilege = csr_address[9:8];
        supported_csr = 1'b1;
        case (csr_address)
            12'h001, 12'h002, 12'h003, 12'h0c0, 12'h0c1,
            12'h0c2, 12'h100, 12'h104, 12'h105, 12'h106,
            12'h140, 12'h141, 12'h142, 12'h143, 12'h144, 12'h180,
            12'h300, 12'h301, 12'h302, 12'h303, 12'h304, 12'h305,
            12'h306, 12'h320, 12'hb00, 12'hb02, 12'hb80, 12'hb82,
            12'hc00, 12'hc01, 12'hc02, 12'hc80, 12'hc81, 12'hc82,
            12'h3a0, 12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3,
            12'h340, 12'h341, 12'h342, 12'h343, 12'h344: begin end
            default: supported_csr = 1'b0;
        endcase
        counter_access_enabled = 1'b1;
        case (csr_address)
            12'hc00, 12'hc80:
                counter_access_enabled = privilege == PRIV_MACHINE ||
                    (mcounteren[0] &&
                     (privilege == PRIV_SUPERVISOR || scounteren[0]));
            12'hc01, 12'hc81:
                counter_access_enabled = privilege == PRIV_MACHINE ||
                    (mcounteren[1] &&
                     (privilege == PRIV_SUPERVISOR || scounteren[1]));
            12'hc02, 12'hc82:
                counter_access_enabled = privilege == PRIV_MACHINE ||
                    (mcounteren[2] &&
                     (privilege == PRIV_SUPERVISOR || scounteren[2]));
            default: begin end
        endcase
        // CSR address bits [9:8] encode the minimum privilege level.
        csr_access_valid = supported_csr &&
                           privilege >= required_privilege &&
                           counter_access_enabled;
        csr_read_data = 32'b0;
        if (csr_access_valid) begin
            case (csr_address)
                12'h001: csr_read_data = {27'b0, fflags};
                12'h002: csr_read_data = {29'b0, frm};
                12'h003: csr_read_data = floating_csr_state;
                12'h0c0: csr_read_data = mcycle[31:0];
                12'h0c1: csr_read_data = time_counter[31:0];
                12'h0c2: csr_read_data = minstret[31:0];
                12'h100: csr_read_data = mstatus & 32'h000c_0122;
                12'h104: csr_read_data = mie & mideleg;
                12'h105: csr_read_data = stvec;
                12'h140: csr_read_data = sscratch;
                12'h141: csr_read_data = sepc;
                12'h142: csr_read_data = scause;
                12'h143: csr_read_data = stval;
                12'h144: csr_read_data = mip & mideleg;
                12'h180: csr_read_data = satp;
                12'h306: csr_read_data = mcounteren;
                12'h300: csr_read_data = mstatus;
                12'h301: csr_read_data = 32'h4000_112d; // RV32IMAFDC, XLEN=32
                12'h302: csr_read_data = medeleg;
                12'h303: csr_read_data = mideleg;
                12'h304: csr_read_data = mie;
                12'h305: csr_read_data = mtvec;
                12'h320: csr_read_data = mcountinhibit;
                12'hb00: csr_read_data = mcycle[31:0];
                12'hb02: csr_read_data = minstret[31:0];
                12'hb80: csr_read_data = mcycle[63:32];
                12'hb82: csr_read_data = minstret[63:32];
                12'hc00: csr_read_data = mcycle[31:0];
                12'hc01: csr_read_data = time_counter[31:0];
                12'hc02: csr_read_data = minstret[31:0];
                12'hc80: csr_read_data = mcycle[63:32];
                12'hc81: csr_read_data = time_counter[63:32];
                12'hc82: csr_read_data = minstret[63:32];
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
            mcycle <= 64'b0;
            minstret <= 64'b0;
        end else begin
            if (!mcountinhibit[0]) mcycle <= mcycle + 64'd1;
            if (instruction_retired && !mcountinhibit[2])
                minstret <= minstret + 64'd1;

            if (csr_write_enable && csr_access_valid) begin
                case (csr_address)
                    12'hb00: mcycle[31:0] <= csr_write_data;
                    12'hb02: minstret[31:0] <= csr_write_data;
                    12'hb80: mcycle[63:32] <= csr_write_data;
                    12'hb82: minstret[63:32] <= csr_write_data;
                    default: begin end
                endcase
            end
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
            mcounteren <= 32'b0;
            scounteren <= 32'b0;
            mcountinhibit <= 32'b0;
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
                        mstatus[18] <= csr_write_data[18];
                        mstatus[19] <= csr_write_data[19];
                    end
                    12'h104: mie <= (mie & ~mideleg) |
                                         (csr_write_data & mideleg & 32'h0000_0aaa);
                    12'h105: stvec <= {csr_write_data[31:2], 1'b0,
                                         (csr_write_data[1:0] == 2'b01)};
                    12'h140: sscratch <= csr_write_data;
                    12'h141: sepc <= {csr_write_data[31:1], 1'b0};
                    12'h142: scause <= csr_write_data;
                    12'h143: stval <= csr_write_data;
                    12'h144: mip_software[1] <= csr_write_data[1];
                    12'h180: satp <= csr_write_data;
                    12'h106: scounteren <= csr_write_data & 32'h0000_0007;
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
                        mstatus[18] <= csr_write_data[18];
                        mstatus[19] <= csr_write_data[19];
                    end
                    12'h302: medeleg <= csr_write_data & 32'h0000_0bff;
                    12'h303: mideleg <= csr_write_data & 32'h0000_0222;
                    12'h304: mie <= csr_write_data & 32'h0000_0aaa;
                    12'h305: mtvec <= {csr_write_data[31:2], 1'b0,
                                         (csr_write_data[1:0] == 2'b01)};
                    12'h306: mcounteren <= csr_write_data & 32'h0000_0007;
                    12'h320: mcountinhibit <= csr_write_data & 32'h0000_0005;
                    12'h340: mscratch <= csr_write_data;
                    12'h341: mepc <= {csr_write_data[31:1], 1'b0};
                    12'h342: mcause <= csr_write_data;
                    12'h343: mtval <= csr_write_data;
                    12'h344: begin
                        mip_software[1] <= csr_write_data[1];
                        mip_software[3] <= csr_write_data[3];
                    end
                    12'h3a0: begin
                        for (integer entry = 0; entry < 4; entry = entry + 1) begin
                            if (!pmpcfg[entry][7]) begin
                                pmpcfg[entry] <= (csr_write_data >> (entry * 8));
                                if (((csr_write_data >> (entry * 8)) & 32'h2) != 0 &&
                                    ((csr_write_data >> (entry * 8)) & 32'h1) == 0)
                                    pmpcfg[entry][1] <= 1'b0;
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
