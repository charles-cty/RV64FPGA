`timescale 1ns / 1ps

module tb_rv64_mmu_random;
  import riscv_pkg::*;

  logic clk;
  logic reset;
  logic translate_valid;
  logic [63:0] virtual_address;
  mmu_access_t access;
  logic [1:0] privilege;
  logic sum_enable;
  logic mxr_enable;
  logic [63:0] satp;
  logic pte_request;
  logic [63:0] pte_address;
  logic [63:0] pte_read_data;
  logic pte_ready;
  logic pte_update_valid;
  logic [63:0] pte_update_address;
  logic [63:0] pte_update_data;
  logic sfence_valid;
  logic sfence_all;
  logic [63:0] sfence_virtual_address;
  logic translation_done;
  logic translation_fault;
  logic [63:0] physical_address;
  logic busy;
  logic [63:0] page_table [0:65535];
  integer failures;
  integer translate_count;
  integer tlb_hit_count;
  integer tlb_walk_count;
  integer sfence_address_count;
  integer sfence_all_count;
  integer satp_switch_count;
  integer superpage_count;
  integer fault_count;
  integer random_state;
  logic [63:0] satp_a;
  logic [63:0] satp_b;
  logic [63:0] last_virtual_address;
  logic have_last_address;

  localparam logic [63:0] ROOT_A = 64'h0000_0000_0000_1000;
  localparam logic [63:0] L1_A = 64'h0000_0000_0000_2000;
  localparam logic [63:0] L0_A = 64'h0000_0000_0000_3000;
  localparam logic [63:0] ROOT_B = 64'h0000_0000_0000_4000;
  localparam logic [63:0] L1_B = 64'h0000_0000_0000_5000;
  localparam logic [63:0] L0_B = 64'h0000_0000_0000_6000;
  localparam logic [63:0] VA_SUPER = 64'h0000_0000_4000_0000;

  rv64_mmu dut (.*);
  always #5 clk = ~clk;

  always_comb begin
    pte_ready = 1'b0;
    pte_read_data = '0;
    if (pte_request) begin
      pte_ready = 1'b1;
      pte_read_data = page_table[pte_address[18:3]];
    end
  end

  always_ff @(posedge clk) begin
    if (!reset && pte_update_valid) begin
      page_table[pte_update_address[18:3]] <= pte_update_data;
    end
  end

  function automatic logic [63:0] make_pte(
    input logic [43:0] ppn,
    input logic [7:0] flags
  );
    make_pte = {10'b0, ppn, 2'b0, flags};
  endfunction

  function automatic logic [63:0] pte_address_for(
    input logic [63:0] base,
    input logic [63:0] address,
    input integer level
  );
    begin
      case (level)
        2: pte_address_for = base + ({55'b0, address[38:30]} << 3);
        1: pte_address_for = base + ({55'b0, address[29:21]} << 3);
        default: pte_address_for = base + ({55'b0, address[20:12]} << 3);
      endcase
    end
  endfunction

  function automatic logic canonical_sv39(input logic [63:0] address);
    canonical_sv39 = address[63:39] == {25{address[38]}};
  endfunction

  task automatic reference_translate(
    input logic [63:0] address,
    input mmu_access_t target_access,
    input logic [1:0] target_privilege,
    input logic target_sum,
    input logic target_mxr,
    input logic [63:0] target_satp,
    output logic expected_fault,
    output logic [63:0] expected_physical,
    output integer expected_level
  );
    logic [63:0] entry;
    logic [63:0] base;
    logic privilege_ok;
    integer level;
    begin
      expected_fault = 1'b0;
      expected_physical = address;
      expected_level = -1;
      if (target_privilege == 2'b11 || target_satp[63:60] == 4'h0) begin
        return;
      end
      if (target_satp[63:60] != 4'h8 || !canonical_sv39(address)) begin
        expected_fault = 1'b1;
        expected_physical = '0;
        return;
      end
      base = {8'b0, target_satp[43:0], 12'b0};
      for (level = 2; level >= 0; level = level - 1) begin
        entry = page_table[pte_address_for(base, address, level)[18:3]];
        if (!entry[0] || (!entry[1] && entry[2]) || entry[63:54] != 10'b0) begin
          expected_fault = 1'b1;
          expected_physical = '0;
          return;
        end
        if (entry[1] || entry[3]) begin
          if (target_privilege == 2'b00) begin
            privilege_ok = entry[4];
          end else if (target_privilege == 2'b01) begin
            privilege_ok = !entry[4] || ((target_access != MMU_FETCH) && target_sum);
          end else begin
            privilege_ok = 1'b1;
          end
          if (!privilege_ok ||
              (target_access == MMU_FETCH && !entry[3]) ||
              (target_access == MMU_LOAD && !(entry[1] || (target_mxr && entry[3]))) ||
              (target_access == MMU_STORE && !entry[2]) ||
              (level == 2 && entry[27:10] != 18'b0) ||
              (level == 1 && entry[18:10] != 9'b0)) begin
            expected_fault = 1'b1;
            expected_physical = '0;
            return;
          end
          expected_level = level;
          if (level == 2) begin
            expected_physical = {8'b0, entry[53:28], address[29:0]};
          end else if (level == 1) begin
            expected_physical = {8'b0, entry[53:19], address[20:0]};
          end else begin
            expected_physical = {8'b0, entry[53:10], address[11:0]};
          end
          return;
        end
        base = {8'b0, entry[53:10], 12'b0};
      end
      expected_fault = 1'b1;
      expected_physical = '0;
    end
  endtask

  task automatic do_translate(
    input logic [63:0] address,
    input mmu_access_t target_access,
    input logic [1:0] target_privilege,
    input logic target_sum,
    input logic target_mxr,
    input logic [63:0] target_satp
  );
    logic expected_fault;
    logic [63:0] expected_physical;
    integer expected_level;
    integer cycles;
    begin
      reference_translate(address, target_access, target_privilege, target_sum,
                          target_mxr, target_satp, expected_fault,
                          expected_physical, expected_level);
      virtual_address = address;
      access = target_access;
      privilege = target_privilege;
      sum_enable = target_sum;
      mxr_enable = target_mxr;
      satp = target_satp;
      translate_valid = 1'b1;
      #1;
      if (dut.tlb_match_valid) begin
        tlb_hit_count = tlb_hit_count + 1;
      end else begin
        tlb_walk_count = tlb_walk_count + 1;
      end
      @(posedge clk);
      #1;
      translate_valid = 1'b0;
      cycles = 0;
      while (!translation_done && cycles < 24) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
      end
      translate_count = translate_count + 1;
      if (expected_level >= 1) begin
        superpage_count = superpage_count + 1;
      end
      if (expected_fault) begin
        fault_count = fault_count + 1;
      end
      if (!translation_done || translation_fault !== expected_fault ||
          (!expected_fault && physical_address !== expected_physical)) begin
        $display("FAIL random TLB translation va=%h access=%0d priv=%b done=%b fault=%b pa=%h expected_fault=%b expected_pa=%h cycles=%0d",
                 address, target_access, target_privilege, translation_done,
                 translation_fault, physical_address, expected_fault,
                 expected_physical, cycles);
        failures = failures + 1;
      end
      @(posedge clk);
      #1;
      last_virtual_address = address;
      have_last_address = 1'b1;
    end
  endtask

  task automatic do_sfence(input logic invalidate_all, input logic [63:0] address);
    begin
      sfence_all = invalidate_all;
      sfence_virtual_address = address;
      sfence_valid = 1'b1;
      @(posedge clk);
      #1;
      sfence_valid = 1'b0;
      if (invalidate_all) begin
        sfence_all_count = sfence_all_count + 1;
      end else begin
        sfence_address_count = sfence_address_count + 1;
      end
    end
  endtask

  task automatic initialize_tables;
    integer table_index;
    integer page_index;
    begin
      for (table_index = 0; table_index < 65536; table_index = table_index + 1) begin
        page_table[table_index] = '0;
      end
      page_table[ROOT_A[18:3]] = make_pte(44'd2, 8'h01);
      page_table[L1_A[18:3]] = make_pte(44'd3, 8'h01);
      page_table[ROOT_B[18:3]] = make_pte(44'd5, 8'h01);
      page_table[L1_B[18:3]] = make_pte(44'd6, 8'h01);
      page_table[pte_address_for(ROOT_A, VA_SUPER, 2)[18:3]] = make_pte(44'h40000, 8'hc7);
      page_table[pte_address_for(ROOT_B, VA_SUPER, 2)[18:3]] = make_pte(44'h80000, 8'hc7);
      for (page_index = 1; page_index <= 8; page_index = page_index + 1) begin
        page_table[pte_address_for(L0_A, page_index * 64'h1000, 0)[18:3]] =
          make_pte(44'h00100 + page_index, (page_index % 3 == 0) ? 8'h07 : 8'hc7);
        page_table[pte_address_for(L0_B, page_index * 64'h1000, 0)[18:3]] =
          make_pte(44'h00200 + page_index, 8'hc7);
      end
    end
  endtask

  initial begin
    integer iteration;
    integer operation;
    integer page_index;
    logic [63:0] address;
    logic [63:0] active_satp;
    mmu_access_t target_access;
    logic [1:0] target_privilege;
    logic target_sum;
    logic target_mxr;

    clk = 1'b0;
    reset = 1'b1;
    translate_valid = 1'b0;
    virtual_address = '0;
    access = MMU_LOAD;
    privilege = 2'b01;
    sum_enable = 1'b0;
    mxr_enable = 1'b0;
    satp = '0;
    sfence_valid = 1'b0;
    sfence_all = 1'b0;
    sfence_virtual_address = '0;
    failures = 0;
    translate_count = 0;
    tlb_hit_count = 0;
    tlb_walk_count = 0;
    sfence_address_count = 0;
    sfence_all_count = 0;
    satp_switch_count = 0;
    superpage_count = 0;
    fault_count = 0;
    random_state = 32'h5a39_2026;
    have_last_address = 1'b0;
    satp_a = 64'h8000_0000_0000_0001;
    satp_b = 64'h8000_0000_0000_0004;
    active_satp = satp_a;
    initialize_tables();

    @(posedge clk);
    #1;
    reset = 1'b0;

    for (iteration = 0; iteration < 160; iteration = iteration + 1) begin
      random_state = random_state * 32'h0019_660d + 32'h3c6e_f35f;
      operation = (random_state & 32'h7fff_ffff) % 10;
      if (operation < 7) begin
        if (operation == 6 && have_last_address) begin
          address = last_virtual_address;
        end else if ((iteration % 11) == 0) begin
          address = VA_SUPER;
        end else begin
          random_state = random_state * 32'h0019_660d + 32'h3c6e_f35f;
          page_index = (random_state & 32'h7fff_ffff) % 8 + 1;
          address = page_index * 64'h1000;
        end
        random_state = random_state * 32'h0019_660d + 32'h3c6e_f35f;
        case ((random_state & 32'h7fff_ffff) % 3)
          0: target_access = MMU_FETCH;
          1: target_access = MMU_LOAD;
          default: target_access = MMU_STORE;
        endcase
        random_state = random_state * 32'h0019_660d + 32'h3c6e_f35f;
        target_privilege = ((random_state & 32'h7fff_ffff) % 3 == 0) ? 2'b00 : 2'b01;
        random_state = random_state * 32'h0019_660d + 32'h3c6e_f35f;
        target_sum = (random_state & 1) != 0;
        random_state = random_state * 32'h0019_660d + 32'h3c6e_f35f;
        target_mxr = (random_state & 1) != 0;
        do_translate(address, target_access, target_privilege, target_sum,
                     target_mxr, active_satp);
      end else if (operation == 7) begin
        random_state = random_state * 32'h0019_660d + 32'h3c6e_f35f;
        page_index = (random_state & 32'h7fff_ffff) % 8 + 1;
        address = page_index * 64'h1000;
        do_sfence(1'b0, address);
      end else if (operation == 8) begin
        do_sfence(1'b1, '0);
      end else begin
        active_satp = (active_satp == satp_a) ? satp_b : satp_a;
        satp_switch_count = satp_switch_count + 1;
      end
    end

    if (tlb_hit_count == 0 || tlb_walk_count == 0 || sfence_address_count == 0 ||
        sfence_all_count == 0 || satp_switch_count == 0 || superpage_count == 0 ||
        fault_count == 0) begin
      $display("FAIL TLB coverage hit=%0d walk=%0d sfence_addr=%0d sfence_all=%0d satp_switch=%0d superpage=%0d faults=%0d",
               tlb_hit_count, tlb_walk_count, sfence_address_count,
               sfence_all_count, satp_switch_count, superpage_count, fault_count);
      failures = failures + 1;
    end
    $display("TLB COVERAGE translates=%0d hits=%0d walks=%0d sfence_addr=%0d sfence_all=%0d satp_switch=%0d superpages=%0d faults=%0d",
             translate_count, tlb_hit_count, tlb_walk_count,
             sfence_address_count, sfence_all_count, satp_switch_count,
             superpage_count, fault_count);
    if (failures != 0) begin
      $display("SIM FAIL: %0d random TLB checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_mmu deterministic TLB interaction regression");
    $finish;
  end
endmodule
