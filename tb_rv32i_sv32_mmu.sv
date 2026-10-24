module tb_rv32i_sv32_mmu;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] satp = 32'h8000_0001;
    logic [1:0] privilege = 2'b00;
    logic sum = 1'b0;
    logic mxr = 1'b0;
    logic sfence_vma = 1'b0;
    logic sfence_vma_address_valid = 1'b0;
    logic [31:0] sfence_vma_address = 32'b0;
    logic sfence_vma_asid_valid = 1'b0;
    logic [8:0] sfence_vma_asid = 9'b0;
    logic [31:0] fetch_virtual_address = 32'h0000_0200;
    logic [31:0] fetch_physical_address;
    logic fetch_ready, fetch_page_fault, fetch_access_fault;
    logic [31:0] data_virtual_address = 32'h0000_0400;
    logic data_read = 1'b0, data_write = 1'b0;
    logic [31:0] data_physical_address;
    logic data_ready, data_page_fault, data_access_fault;
    logic pte_read_enable, pte_access_fault = 1'b0;
    logic [31:0] pte_read_address, pte_read_data;
    logic [31:0] pte_leaf = 32'h0000_00df;
    logic use_two_level = 1'b0;
    logic [31:0] pte_root = 32'h0000_0821;
    logic [31:0] pte_level0 = 32'h0000_00df;

    always #5 clk = ~clk;

    always_comb begin
        if (use_two_level)
            pte_read_data = (pte_read_address == 32'h0000_1000) ? pte_root :
                            (pte_read_address == 32'h0000_2000) ? pte_level0 :
                            32'b0;
        else
            pte_read_data = (pte_read_address == 32'h0000_1000) ? pte_leaf : 32'b0;
    end

    rv32i_sv32_mmu dut (
        .clk(clk), .reset(reset), .satp(satp), .privilege(privilege),
        .sum(sum), .mxr(mxr), .sfence_vma(sfence_vma),
        .sfence_vma_address_valid(sfence_vma_address_valid),
        .sfence_vma_address(sfence_vma_address),
        .sfence_vma_asid_valid(sfence_vma_asid_valid),
        .sfence_vma_asid(sfence_vma_asid),
        .fetch_virtual_address(fetch_virtual_address),
        .fetch_physical_address(fetch_physical_address),
        .fetch_ready(fetch_ready), .fetch_page_fault(fetch_page_fault),
        .fetch_access_fault(fetch_access_fault),
        .data_virtual_address(data_virtual_address),
        .data_read(data_read),
        .data_write(data_write), .data_physical_address(data_physical_address),
        .data_ready(data_ready), .data_page_fault(data_page_fault),
        .data_access_fault(data_access_fault),
        .pte_read_enable(pte_read_enable), .pte_read_address(pte_read_address),
        .pte_read_data(pte_read_data), .pte_access_fault(pte_access_fault)
    );

    task automatic flush_tlb;
        begin
            @(negedge clk);
            sfence_vma_address_valid = 1'b0;
            sfence_vma_asid_valid = 1'b0;
            sfence_vma = 1'b1;
            @(negedge clk);
            sfence_vma = 1'b0;
        end
    endtask

    task automatic flush_virtual_address(input logic [31:0] address);
        begin
            @(negedge clk);
            sfence_vma_address = address;
            sfence_vma_address_valid = 1'b1;
            sfence_vma_asid_valid = 1'b0;
            sfence_vma = 1'b1;
            @(negedge clk);
            sfence_vma = 1'b0;
            sfence_vma_address_valid = 1'b0;
        end
    endtask

    task automatic flush_asid(input logic [8:0] asid);
        begin
            @(negedge clk);
            sfence_vma_address_valid = 1'b0;
            sfence_vma_asid = asid;
            sfence_vma_asid_valid = 1'b1;
            sfence_vma = 1'b1;
            @(negedge clk);
            sfence_vma = 1'b0;
            sfence_vma_asid_valid = 1'b0;
        end
    endtask

    initial begin
        #12 reset = 1'b0;
        wait (fetch_ready);
        #1;
        if (fetch_physical_address !== 32'h0000_0200 ||
            fetch_page_fault || fetch_access_fault)
            $fatal(1, "Sv32 superpage fetch translation failed");

        data_read = 1'b1;
        #1;
        if (!data_ready || data_page_fault ||
            data_physical_address !== 32'h0000_0400)
            $fatal(1, "Sv32 superpage data translation failed");

        privilege = 2'b01;
        sum = 1'b0;
        #1;
        if (!data_page_fault)
            $fatal(1, "SUM=0 failed to deny supervisor load from a user page");
        sum = 1'b1;
        #1;
        if (data_page_fault)
            $fatal(1, "SUM=1 failed to allow supervisor load from a user page");

        privilege = 2'b00;
        sum = 1'b0;
        data_read = 1'b0;
        pte_leaf = 32'h0010_00df;
        flush_virtual_address(32'h0000_1000);
        wait (fetch_ready);
        #1;
        if (fetch_page_fault || fetch_physical_address !== 32'h0040_0200)
            $fatal(1, "SFENCE.VMA superpage result was %h (ready=%b)",
                   fetch_physical_address, fetch_ready);

        pte_leaf = 32'h0000_00df;
        flush_tlb();
        wait (fetch_ready);
        #1;
        pte_leaf = 32'h0010_00df;
        flush_asid(9'd1);
        #1;
        if (fetch_physical_address !== 32'h0000_0200)
            $fatal(1, "ASID-specific SFENCE.VMA invalidated another ASID");
        flush_asid(9'd0);
        wait (fetch_ready);
        #1;
        if (fetch_page_fault || fetch_physical_address !== 32'h0040_0200)
            $fatal(1, "ASID-specific SFENCE.VMA failed to invalidate its ASID");

        pte_leaf = 32'h0000_00ff; // Global superpage translation.
        flush_tlb();
        wait (fetch_ready);
        #1;
        pte_leaf = 32'h0010_00ff;
        flush_asid(9'd0);
        #1;
        if (fetch_page_fault || fetch_physical_address !== 32'h0000_0200)
            $fatal(1, "ASID-specific SFENCE.VMA invalidated a global translation");
        flush_tlb();
        wait (fetch_ready);
        #1;
        if (fetch_page_fault || fetch_physical_address !== 32'h0040_0200)
            $fatal(1, "all-ASID SFENCE.VMA failed to invalidate a global translation");

        use_two_level = 1'b1;
        pte_root = 32'h0000_0821; // Non-leaf PTE marks all descendants global.
        pte_level0 = 32'h0000_00df;
        flush_tlb();
        wait (fetch_ready);
        #1;
        if (fetch_page_fault || fetch_physical_address !== 32'h0000_0200)
            $fatal(1, "two-level global mapping did not translate");
        pte_level0 = 32'h0000_40df;
        satp = 32'h8040_0001;
        #1;
        if (!fetch_ready || fetch_page_fault ||
            fetch_physical_address !== 32'h0000_0200)
            $fatal(1, "non-leaf global mapping missed after an ASID switch");
        satp = 32'h8000_0001;

        pte_root = 32'h0000_0801;
        pte_level0 = 32'h0000_00df;
        flush_tlb();
        @(posedge clk);
        #1;
        satp = 32'h8040_0001;
        pte_level0 = 32'h0010_00df;
        wait (fetch_ready);
        #1;
        if (fetch_page_fault || fetch_physical_address !== 32'h0040_0200)
            $fatal(1, "in-flight walk used the previous satp context");

        satp = 32'h8000_0001;
        use_two_level = 1'b0;

        pte_leaf = 32'h0000_00df;
        flush_tlb();
        wait (fetch_ready);
        #1;
        data_read = 1'b1;
        pte_leaf = 32'h0000_0059; // Valid user execute-only leaf with A set.
        flush_tlb();
        wait (fetch_ready);
        #1;
        if (fetch_page_fault)
            $fatal(1, "Sv32 execute-only superpage fetch was denied");
        if (!data_page_fault)
            $fatal(1, "MXR=0 failed to deny a read from execute-only page");
        mxr = 1'b1;
        #1;
        if (data_page_fault)
            $fatal(1, "MXR=1 failed to allow a read from execute-only page");

        mxr = 1'b0;
        pte_leaf = 32'h0000_005f; // Writable leaf with A set but D clear.
        flush_tlb();
        wait (fetch_ready);
        data_write = 1'b1;
        #1;
        if (!data_page_fault)
            $fatal(1, "Sv32 write without a dirty bit did not page fault");

        data_write = 1'b0;
        pte_leaf = 32'h0000_001f; // Leaf with the accessed bit clear.
        flush_tlb();
        wait (fetch_ready);
        #1;
        if (!fetch_page_fault)
            $fatal(1, "Sv32 fetch without an accessed bit did not page fault");

        fetch_virtual_address = 32'h0080_0000;
        pte_access_fault = 1'b1;
        flush_tlb();
        wait (fetch_ready);
        #1;
        if (!fetch_access_fault || fetch_page_fault)
            $fatal(1, "Sv32 page-table bus fault was not reported as an access fault");

        $display("Sv32 superpage, SUM, MXR, A/D, and bus-fault checks passed");
        $finish;
    end

    initial begin
        #1000 $fatal(1, "Sv32 MMU test timed out");
    end
endmodule
