// A blocking Sv32 page-table walker with a small fully associative TLB.
// Physical addresses are 32 bits at the core/memory interface.
module rv32i_sv32_mmu (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] satp,
    input  logic [1:0]  privilege,
    input  logic        sum,
    input  logic        mxr,
    input  logic        sfence_vma,
    input  logic        sfence_vma_address_valid,
    input  logic [31:0] sfence_vma_address,
    input  logic        sfence_vma_asid_valid,
    input  logic [8:0]  sfence_vma_asid,
    input  logic [31:0] fetch_virtual_address,
    output logic [31:0] fetch_physical_address,
    output logic        fetch_ready,
    output logic        fetch_page_fault,
    output logic        fetch_access_fault,
    input  logic [31:0] data_virtual_address,
    input  logic        data_read,
    input  logic        data_write,
    output logic [31:0] data_physical_address,
    output logic        data_ready,
    output logic        data_page_fault,
    output logic        data_access_fault,
    output logic        pte_read_enable,
    output logic [31:0] pte_read_address,
    input  logic [31:0] pte_read_data,
    input  logic        pte_access_fault
);
    localparam logic [1:0] PRIV_USER = 2'b00;
    localparam logic [1:0] PRIV_SUPERVISOR = 2'b01;
    localparam integer TLB_ENTRIES = 4;

    typedef enum logic [1:0] {WALK_IDLE, WALK_LEVEL1, WALK_LEVEL0} walk_state_t;
    walk_state_t state;

    logic [19:0] tlb_vpn [0:TLB_ENTRIES-1];
    logic [19:0] tlb_ppn [0:TLB_ENTRIES-1];
    logic [31:0] tlb_satp [0:TLB_ENTRIES-1];
    logic [7:0] tlb_flags [0:TLB_ENTRIES-1];
    logic tlb_superpage [0:TLB_ENTRIES-1];
    logic tlb_valid [0:TLB_ENTRIES-1];
    logic [1:0] replacement_index;

    logic [31:0] walk_virtual_address;
    logic [31:0] walk_pte_address;
    logic [31:0] walk_satp;
    logic walk_global;
    logic walk_execute;
    logic walk_read;
    logic walk_write;
    logic fetch_hit;
    logic data_hit;
    logic [1:0] fetch_hit_index;
    logic [1:0] data_hit_index;
    logic fetch_access_permitted;
    logic data_access_permitted;
    logic [31:0] fetch_translated_address;
    logic [31:0] data_translated_address;
    logic request_active;
    logic [31:0] request_address;
    logic request_execute;
    logic request_read;
    logic request_write;
    logic [1:0] request_privilege;
    logic request_sum;
    logic request_mxr;
    logic [31:0] pte;
    logic [21:0] pte_ppn;
    logic pte_leaf;
    logic pte_permissions_valid;
    logic pte_superpage_valid;
    logic fault_valid;
    logic fault_is_access_fault;
    logic [31:0] fault_virtual_address;
    logic [31:0] fault_satp;
    logic fault_execute;
    logic fault_read;
    logic fault_write;
    logic [1:0] fault_privilege;
    logic fault_sum;
    logic fault_mxr;
    logic fetch_fault_match;
    logic data_fault_match;

    function automatic logic permissions_allow(
        input logic [7:0] flags,
        input logic execute_access,
        input logic read_access,
        input logic write_access,
        input logic [1:0] access_privilege,
        input logic access_sum,
        input logic access_mxr
    );
        logic permitted;
        begin
            permitted = 1'b1;
            if (execute_access && !flags[3]) permitted = 1'b0;
            if (read_access && !(flags[1] || (access_mxr && flags[3]))) permitted = 1'b0;
            if (write_access && !flags[2]) permitted = 1'b0;
            if (!flags[6] || (write_access && !flags[7])) permitted = 1'b0;
            if (access_privilege == PRIV_USER && !flags[4]) permitted = 1'b0;
            if (access_privilege == PRIV_SUPERVISOR && flags[4] &&
                (execute_access || !access_sum)) permitted = 1'b0;
            permissions_allow = permitted;
        end
    endfunction

    function automatic logic satp_tag_matches(
        input logic [31:0] entry_satp,
        input logic [31:0] current_satp,
        input logic global_mapping
    );
        begin
            satp_tag_matches =
                entry_satp[31] == current_satp[31] &&
                entry_satp[19:0] == current_satp[19:0] &&
                (global_mapping || entry_satp[30:22] == current_satp[30:22]);
        end
    endfunction

    always_comb begin
        fetch_hit = 1'b0;
        data_hit = 1'b0;
        fetch_hit_index = 2'b0;
        data_hit_index = 2'b0;
        fetch_translated_address = fetch_virtual_address;
        data_translated_address = data_virtual_address;
        fetch_access_permitted = 1'b1;
        data_access_permitted = 1'b1;
        fetch_fault_match = fault_valid &&
            (fault_virtual_address == fetch_virtual_address) &&
            (fault_satp == satp) && (fault_privilege == privilege) &&
            (fault_sum == sum) && (fault_mxr == mxr) && fault_execute;
        data_fault_match = fault_valid &&
            (fault_virtual_address == data_virtual_address) &&
            (fault_satp == satp) && (fault_privilege == privilege) &&
            (fault_sum == sum) && (fault_mxr == mxr) &&
            (fault_read == data_read) && (fault_write == data_write);

        for (integer index = 0; index < TLB_ENTRIES; index = index + 1) begin
            if (tlb_valid[index] &&
                satp_tag_matches(tlb_satp[index], satp, tlb_flags[index][5]) &&
                (tlb_superpage[index] ?
                 (tlb_vpn[index][19:10] == fetch_virtual_address[31:22]) :
                 (tlb_vpn[index] == fetch_virtual_address[31:12]))) begin
                fetch_hit = 1'b1;
                fetch_hit_index = index[1:0];
            end
            if (tlb_valid[index] &&
                satp_tag_matches(tlb_satp[index], satp, tlb_flags[index][5]) &&
                (tlb_superpage[index] ?
                 (tlb_vpn[index][19:10] == data_virtual_address[31:22]) :
                 (tlb_vpn[index] == data_virtual_address[31:12]))) begin
                data_hit = 1'b1;
                data_hit_index = index[1:0];
            end
        end

        if (satp[31] && privilege != 2'b11) begin
            fetch_ready = fetch_hit || fetch_fault_match;
            data_ready = !(data_read || data_write) || data_hit || data_fault_match;
            if (fetch_hit) begin
                fetch_access_permitted = permissions_allow(
                    tlb_flags[fetch_hit_index], 1'b1, 1'b0, 1'b0,
                    privilege, sum, mxr
                );
                if (tlb_superpage[fetch_hit_index])
                    fetch_translated_address = {
                        tlb_ppn[fetch_hit_index][19:10],
                        fetch_virtual_address[21:12],
                        fetch_virtual_address[11:0]
                    };
                else
                    fetch_translated_address = {
                        tlb_ppn[fetch_hit_index], fetch_virtual_address[11:0]
                    };
            end
            if (data_hit) begin
                data_access_permitted = permissions_allow(
                    tlb_flags[data_hit_index], 1'b0, data_read, data_write,
                    privilege, sum, mxr
                );
                if (tlb_superpage[data_hit_index])
                    data_translated_address = {
                        tlb_ppn[data_hit_index][19:10],
                        data_virtual_address[21:12],
                        data_virtual_address[11:0]
                    };
                else
                    data_translated_address = {
                        tlb_ppn[data_hit_index], data_virtual_address[11:0]
                    };
            end
        end else begin
            fetch_ready = 1'b1;
            data_ready = 1'b1;
        end

        fetch_physical_address = fetch_translated_address;
        data_physical_address = data_translated_address;
        fetch_page_fault = (satp[31] && privilege != 2'b11 &&
                            ((fetch_hit && !fetch_access_permitted) ||
                             (fetch_fault_match && !fault_is_access_fault)));
        data_page_fault = (satp[31] && privilege != 2'b11 &&
                           ((data_hit && !data_access_permitted) ||
                            (data_fault_match && !fault_is_access_fault)));
        fetch_access_fault = satp[31] && privilege != 2'b11 &&
                             fetch_fault_match && fault_is_access_fault;
        data_access_fault = satp[31] && privilege != 2'b11 &&
                            data_fault_match && fault_is_access_fault;

        request_active = 1'b0;
        request_address = 32'b0;
        request_execute = 1'b0;
        request_read = 1'b0;
        request_write = 1'b0;
        if (satp[31] && privilege != 2'b11 && !fetch_hit && !fetch_fault_match) begin
            request_active = 1'b1;
            request_address = fetch_virtual_address;
            request_execute = 1'b1;
        end else if (satp[31] && privilege != 2'b11 &&
                     (data_read || data_write) && !data_hit && !data_fault_match) begin
            request_active = 1'b1;
            request_address = data_virtual_address;
            request_read = data_read;
            request_write = data_write;
        end

        pte = pte_read_data;
        pte_ppn = pte[31:10];
        pte_leaf = pte[1] || pte[3];
        pte_permissions_valid = pte[0] &&
            !(pte[2] && !pte[1]) &&
            !((walk_execute && !(pte[3])) ||
              (walk_read && !(pte[1] || (request_mxr && pte[3]))) ||
              (walk_write && !pte[2])) &&
            !(request_privilege == PRIV_USER && !pte[4]) &&
            !(request_privilege == PRIV_SUPERVISOR && pte[4] &&
              (walk_execute || !request_sum)) &&
            pte[6] && (!walk_write || pte[7]);
        pte_superpage_valid = (state != WALK_LEVEL1 || !pte_leaf) ||
                              pte_ppn[9:0] == 10'b0;
        pte_read_enable = (state == WALK_LEVEL1 || state == WALK_LEVEL0);
        pte_read_address = walk_pte_address;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= WALK_IDLE;
            walk_virtual_address <= 32'b0;
            walk_pte_address <= 32'b0;
            walk_satp <= 32'b0;
            walk_global <= 1'b0;
            walk_execute <= 1'b0;
            walk_read <= 1'b0;
            walk_write <= 1'b0;
            request_privilege <= 2'b0;
            request_sum <= 1'b0;
            request_mxr <= 1'b0;
            fault_valid <= 1'b0;
            fault_is_access_fault <= 1'b0;
            fault_virtual_address <= 32'b0;
            fault_satp <= 32'b0;
            fault_execute <= 1'b0;
            fault_read <= 1'b0;
            fault_write <= 1'b0;
            fault_privilege <= 2'b0;
            fault_sum <= 1'b0;
            fault_mxr <= 1'b0;
            replacement_index <= 2'b0;
            for (integer index = 0; index < TLB_ENTRIES; index = index + 1) begin
                tlb_valid[index] <= 1'b0;
                tlb_vpn[index] <= 20'b0;
                tlb_ppn[index] <= 20'b0;
                tlb_satp[index] <= 32'b0;
                tlb_flags[index] <= 8'b0;
                tlb_superpage[index] <= 1'b0;
            end
        end else begin
            case (state)
                WALK_IDLE: begin
                    if (request_active) begin
                        walk_virtual_address <= request_address;
                        walk_execute <= request_execute;
                        walk_read <= request_read;
                        walk_write <= request_write;
                        request_privilege <= privilege;
                        request_sum <= sum;
                        request_mxr <= mxr;
                        walk_global <= 1'b0;
                        walk_satp <= satp;
                        fault_valid <= 1'b0;
                        if (satp[21:20] != 2'b00) begin
                            fault_valid <= 1'b1;
                            fault_is_access_fault <= 1'b1;
                            fault_virtual_address <= request_address;
                            fault_satp <= satp;
                            fault_execute <= request_execute;
                            fault_read <= request_read;
                            fault_write <= request_write;
                            fault_privilege <= privilege;
                            fault_sum <= sum;
                            fault_mxr <= mxr;
                            state <= WALK_IDLE;
                        end else begin
                            walk_pte_address <= {satp[19:0], 12'b0} +
                                {20'b0, request_address[31:22], 2'b0};
                            state <= WALK_LEVEL1;
                        end
                    end
                end
                WALK_LEVEL1: begin
                    if (satp != walk_satp) begin
                        state <= WALK_IDLE;
                    end else if (pte_access_fault || pte[0] !== 1'b1 ||
                        (pte[2] && !pte[1])) begin
                        fault_valid <= 1'b1;
                        fault_is_access_fault <= pte_access_fault;
                        fault_virtual_address <= walk_virtual_address;
                        fault_satp <= walk_satp;
                        fault_execute <= walk_execute;
                        fault_read <= walk_read;
                        fault_write <= walk_write;
                        fault_privilege <= request_privilege;
                        fault_sum <= request_sum;
                        fault_mxr <= request_mxr;
                        state <= WALK_IDLE;
                    end else if (pte_leaf) begin
                        if (pte_ppn[21:20] != 2'b00) begin
                            fault_valid <= 1'b1;
                            fault_is_access_fault <= 1'b1;
                            fault_virtual_address <= walk_virtual_address;
                            fault_satp <= walk_satp;
                            fault_execute <= walk_execute;
                            fault_read <= walk_read;
                            fault_write <= walk_write;
                            fault_privilege <= request_privilege;
                            fault_sum <= request_sum;
                            fault_mxr <= request_mxr;
                            state <= WALK_IDLE;
                        end else if (!pte_permissions_valid || !pte_superpage_valid) begin
                            fault_valid <= 1'b1;
                            fault_is_access_fault <= 1'b0;
                            fault_virtual_address <= walk_virtual_address;
                            fault_satp <= walk_satp;
                            fault_execute <= walk_execute;
                            fault_read <= walk_read;
                            fault_write <= walk_write;
                            fault_privilege <= request_privilege;
                            fault_sum <= request_sum;
                            fault_mxr <= request_mxr;
                            state <= WALK_IDLE;
                        end else begin
                            tlb_valid[replacement_index] <= 1'b1;
                            tlb_vpn[replacement_index] <= walk_virtual_address[31:12];
                            tlb_ppn[replacement_index] <= pte_ppn[19:0];
                            tlb_satp[replacement_index] <= walk_satp;
                            tlb_flags[replacement_index] <= pte[7:0];
                            tlb_superpage[replacement_index] <= 1'b1;
                            replacement_index <= replacement_index + 1'b1;
                            state <= WALK_IDLE;
                        end
                    end else if (pte[9:8] != 2'b00 || pte[4] ||
                                 pte[6] || pte[7]) begin
                        fault_valid <= 1'b1;
                        fault_is_access_fault <= 1'b0;
                        fault_virtual_address <= walk_virtual_address;
                        fault_satp <= walk_satp;
                        fault_execute <= walk_execute;
                        fault_read <= walk_read;
                        fault_write <= walk_write;
                        fault_privilege <= request_privilege;
                        fault_sum <= request_sum;
                        fault_mxr <= request_mxr;
                        state <= WALK_IDLE;
                    end else if (pte_ppn[21:20] != 2'b00) begin
                        fault_valid <= 1'b1;
                        fault_is_access_fault <= 1'b1;
                        fault_virtual_address <= walk_virtual_address;
                        fault_satp <= walk_satp;
                        fault_execute <= walk_execute;
                        fault_read <= walk_read;
                        fault_write <= walk_write;
                        fault_privilege <= request_privilege;
                        fault_sum <= request_sum;
                        fault_mxr <= request_mxr;
                        state <= WALK_IDLE;
                    end else begin
                        walk_global <= walk_global | pte[5];
                        walk_pte_address <= {pte_ppn[19:0], 12'b0} +
                            {20'b0, walk_virtual_address[21:12], 2'b0};
                        state <= WALK_LEVEL0;
                    end
                end
                WALK_LEVEL0: begin
                    if (satp != walk_satp) begin
                        state <= WALK_IDLE;
                    end else if (pte_access_fault || pte[0] !== 1'b1 ||
                        !pte_leaf || (pte[2] && !pte[1]) ||
                        !pte_permissions_valid || pte_ppn[21:20] != 2'b00) begin
                        fault_valid <= 1'b1;
                        fault_is_access_fault <= pte_access_fault ||
                                                 (pte[0] === 1'b1 &&
                                                  pte_leaf &&
                                                  pte_ppn[21:20] != 2'b00);
                        fault_virtual_address <= walk_virtual_address;
                        fault_satp <= walk_satp;
                        fault_execute <= walk_execute;
                        fault_read <= walk_read;
                        fault_write <= walk_write;
                        fault_privilege <= request_privilege;
                        fault_sum <= request_sum;
                        fault_mxr <= request_mxr;
                        state <= WALK_IDLE;
                    end else begin
                        tlb_valid[replacement_index] <= 1'b1;
                        tlb_vpn[replacement_index] <= walk_virtual_address[31:12];
                        tlb_ppn[replacement_index] <= pte_ppn[19:0];
                        tlb_satp[replacement_index] <= walk_satp;
                        tlb_flags[replacement_index] <=
                            {pte[7:6], pte[5] | walk_global, pte[4:0]};
                        tlb_superpage[replacement_index] <= 1'b0;
                        replacement_index <= replacement_index + 1'b1;
                        state <= WALK_IDLE;
                    end
                end
                default: state <= WALK_IDLE;
            endcase

            if (sfence_vma) begin
                state <= WALK_IDLE;
                if (fault_valid &&
                    (!sfence_vma_address_valid ||
                     fault_virtual_address[31:12] ==
                         sfence_vma_address[31:12]) &&
                    (!sfence_vma_asid_valid ||
                     fault_satp[30:22] == sfence_vma_asid))
                    fault_valid <= 1'b0;
                for (integer index = 0; index < TLB_ENTRIES; index = index + 1) begin
                    if ((!sfence_vma_address_valid ||
                         (tlb_superpage[index] ?
                          tlb_vpn[index][19:10] == sfence_vma_address[31:22] :
                          tlb_vpn[index] == sfence_vma_address[31:12])) &&
                        (!sfence_vma_asid_valid ||
                         (!tlb_flags[index][5] &&
                          tlb_satp[index][30:22] == sfence_vma_asid)))
                        tlb_valid[index] <= 1'b0;
                end
            end else if (state != WALK_IDLE && satp != walk_satp) begin
                state <= WALK_IDLE;
                fault_valid <= 1'b0;
            end
        end
    end
endmodule
