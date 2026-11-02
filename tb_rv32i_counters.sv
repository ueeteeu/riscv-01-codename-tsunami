`timescale 1ns/1ps

module tb_rv32i_counters;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic instruction_retired = 1'b0;
    logic [63:0] time_counter = 64'h0123_4567_89ab_cdef;
    logic [11:0] csr_address = 12'b0;
    logic csr_write_enable = 1'b0;
    logic [31:0] csr_write_data = 32'b0;
    logic trap_valid = 1'b0;
    logic [31:0] trap_pc = 32'b0;
    logic [31:0] trap_cause = 32'b0;
    logic [31:0] trap_value = 32'b0;
    logic mret = 1'b0;
    logic sret = 1'b0;
    logic [2:0] supervisor_interrupts = 3'b0;
    logic [31:0] fetch_address = 32'b0;
    logic [2:0] fetch_size = 3'd4;
    logic [31:0] data_access_address = 32'b0;
    logic [3:0] data_access_size = 4'b0;
    logic data_access_read = 1'b0;
    logic data_access_write = 1'b0;
    logic [31:0] pte_access_address = 32'b0;
    logic pte_access_enable = 1'b0;

    logic [31:0] csr_read_data;
    logic csr_access_valid;
    logic [31:0] trap_vector;
    logic [31:0] mret_address;
    logic [31:0] sret_address;
    logic interrupt_valid;
    logic [31:0] interrupt_cause;
    logic [1:0] current_privilege;
    logic [2:0] dynamic_rounding_mode;
    logic [31:0] floating_csr_state;
    logic [31:0] satp_state;
    logic status_sum;
    logic status_mxr;
    logic fetch_pmp_denied;
    logic data_pmp_denied;
    logic pte_pmp_denied;

    always #5 clk = ~clk;

    rv32i_machine_csrs dut (
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
        .trap_pc(trap_pc),
        .trap_cause(trap_cause),
        .trap_value(trap_value),
        .trap_vector(trap_vector),
        .mret(mret),
        .mret_address(mret_address),
        .sret(sret),
        .sret_address(sret_address),
        .external_interrupts(3'b0),
        .supervisor_interrupts(supervisor_interrupts),
        .interrupt_valid(interrupt_valid),
        .interrupt_cause(interrupt_cause),
        .current_privilege(current_privilege),
        .floating_flags_set(1'b0),
        .floating_flags(5'b0),
        .dynamic_rounding_mode(dynamic_rounding_mode),
        .floating_csr_state(floating_csr_state),
        .satp_state(satp_state),
        .status_sum(status_sum),
        .status_mxr(status_mxr),
        .fetch_address(fetch_address),
        .fetch_size(fetch_size),
        .fetch_pmp_denied(fetch_pmp_denied),
        .data_access_address(data_access_address),
        .data_access_size(data_access_size),
        .data_access_read(data_access_read),
        .data_access_write(data_access_write),
        .data_pmp_denied(data_pmp_denied),
        .pte_access_address(pte_access_address),
        .pte_access_enable(pte_access_enable),
        .pte_pmp_denied(pte_pmp_denied)
    );

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic write_csr(input logic [11:0] address,
                             input logic [31:0] value);
        csr_address = address;
        csr_write_data = value;
        csr_write_enable = 1'b1;
        tick();
        csr_write_enable = 1'b0;
    endtask

    initial begin
        tick();
        reset = 1'b0;
        instruction_retired = 1'b1;
        tick();

        csr_address = 12'hb02;
        #1;
        if (!csr_access_valid || csr_read_data != 32'd1)
            $fatal(1, "minstret did not count retired instructions");
        csr_address = 12'hc01;
        #1;
        if (!csr_access_valid || csr_read_data != 32'h89ab_cdef)
            $fatal(1, "time CSR did not expose the platform counter low word");
        csr_address = 12'hc81;
        #1;
        if (!csr_access_valid || csr_read_data != 32'h0123_4567)
            $fatal(1, "timeh CSR did not expose the platform counter high word");

        write_csr(12'hb00, 32'd40);
        csr_address = 12'hb00;
        #1;
        if (csr_read_data != 32'd40)
            $fatal(1, "mcycle write did not take effect");
        write_csr(12'hb80, 32'd7);
        csr_address = 12'hb80;
        #1;
        if (csr_read_data != 32'd7)
            $fatal(1, "mcycle high-half write did not take effect");

        write_csr(12'h320, 32'd5);
        instruction_retired = 1'b0;
        tick();
        csr_address = 12'hb00;
        #1;
        if (csr_read_data != 32'd42)
            $fatal(1, "mcycle inhibit did not hold the cycle counter");
        csr_address = 12'hb02;
        #1;
        if (csr_read_data != 32'd4)
            $fatal(1, "minstret inhibit or retirement count is incorrect");

        write_csr(12'h306, 32'd7);
        write_csr(12'h302, 32'h0000_0100);
        write_csr(12'h303, 32'h0000_0aaa);
        csr_address = 12'h303;
        #1;
        if (csr_read_data !== 32'h0000_0222)
            $fatal(1, "mideleg exposed non-delegable machine interrupts");
        write_csr(12'h303, 32'h0000_0222);
        write_csr(12'h304, 32'h0000_0220);
        write_csr(12'h300, 32'h0000_0800);
        mret = 1'b1;
        tick();
        mret = 1'b0;
        if (current_privilege != 2'b01)
            $fatal(1, "mret did not enter supervisor mode");

        write_csr(12'h144, 32'h0000_0002);
        csr_address = 12'h144;
        #1;
        if (csr_read_data !== 32'h0000_0002)
            $fatal(1, "supervisor software-pending CSR did not expose SSIP");
        write_csr(12'h144, 32'b0);

        write_csr(12'h100, 32'h0000_0002);
        supervisor_interrupts = 3'b110;
        #1;
        if (!interrupt_valid || interrupt_cause != 32'h8000_0009)
            $fatal(1, "supervisor interrupt priority or enable qualification failed");
        trap_valid = 1'b1;
        trap_cause = interrupt_cause;
        trap_pc = 32'h0000_1234;
        tick();
        trap_valid = 1'b0;
        supervisor_interrupts = 3'b0;
        if (current_privilege != 2'b01 ||
            dut.scause != 32'h8000_0009 || dut.sepc != 32'h0000_1234)
            $fatal(1, "delegated supervisor interrupt trap state was incorrect");

        write_csr(12'h106, 32'd1);
        write_csr(12'h100, 32'b0);
        sret = 1'b1;
        tick();
        sret = 1'b0;
        if (current_privilege != 2'b00)
            $fatal(1, "sret did not return to user mode");

        csr_address = 12'hc00;
        #1;
        if (!csr_access_valid || csr_read_data != 32'd42)
            $fatal(1, "user cycle alias or counter enable chain is incorrect");
        csr_address = 12'hc81;
        #1;
        if (csr_access_valid)
            $fatal(1, "scounteren failed to deny user time access");
        csr_address = 12'hc02;
        #1;
        if (csr_access_valid)
            $fatal(1, "scounteren failed to deny user instret access");
        csr_address = 12'h080;
        #1;
        if (csr_access_valid)
            $fatal(1, "unsupported counter CSR address was accepted");

        trap_valid = 1'b1;
        trap_cause = 32'd8;
        trap_pc = 32'h0000_2000;
        tick();
        trap_valid = 1'b0;
        if (current_privilege != 2'b01)
            $fatal(1, "delegated U-mode environment call did not enter S-mode");
        write_csr(12'h106, 32'd3);
        sret = 1'b1;
        tick();
        sret = 1'b0;
        csr_address = 12'hc81;
        #1;
        if (!csr_access_valid || csr_read_data != 32'h0123_4567)
            $fatal(1, "user timeh access did not honor enabled m/s counter bits");

        $display("Counter access, retirement, and delegated interrupt tests passed");
        $finish;
    end
endmodule
