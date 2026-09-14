`timescale 1ns / 1ps

module tb_rv64_mmu;
  import riscv_pkg::*;

  logic clk;
  logic reset;
  logic translate_valid;
  logic [63:0] virtual_address;
  mmu_access_t access;
  logic [1:0] privilege;
  logic sum_enable;
  logic [63:0] satp;
  logic pte_request;
  logic [63:0] pte_address;
  logic [63:0] pte_read_data;
  logic pte_ready;
  logic sfence_valid;
  logic sfence_all;
  logic [63:0] sfence_virtual_address;
  logic translation_done;
  logic translation_fault;
  logic [63:0] physical_address;
  logic busy;
  logic [63:0] page_table [0:65535];
  integer failures;

  localparam logic [63:0] ROOT_4K = 64'h0000_0000_0000_1000;
  localparam logic [63:0] L1_4K = 64'h0000_0000_0000_2000;
  localparam logic [63:0] L0_4K = 64'h0000_0000_0000_3000;
  localparam logic [63:0] ROOT_2M = 64'h0000_0000_0000_4000;
  localparam logic [63:0] L1_2M = 64'h0000_0000_0000_5000;
  localparam logic [63:0] ROOT_1G = 64'h0000_0000_0000_6000;
  localparam logic [63:0] ROOT_BAD = 64'h0000_0000_0000_7000;
  localparam logic [63:0] ROOT_INVALID = 64'h0000_0000_0000_8000;
  localparam logic [63:0] VA_4K = 64'h0000_0000_1234_5678;
  localparam logic [63:0] VA_2M = 64'h0000_0000_0045_6789;
  localparam logic [63:0] VA_1G = 64'h0000_0000_2345_6789;

  rv64_mmu dut (.*);
  always #5 clk = ~clk;

  function automatic logic [63:0] make_pte(
    input logic [43:0] ppn,
    input logic [7:0] flags
  );
    make_pte = {10'b0, ppn, 2'b0, flags};
  endfunction

  function automatic logic [63:0] pte_slot(
    input logic [63:0] base,
    input logic [63:0] address,
    input integer target_level
  );
    begin
      case (target_level)
        2: pte_slot = base + ({55'b0, address[38:30]} << 3);
        1: pte_slot = base + ({55'b0, address[29:21]} << 3);
        default: pte_slot = base + ({55'b0, address[20:12]} << 3);
      endcase
    end
  endfunction

  task automatic set_pte(
    input logic [63:0] base,
    input logic [63:0] address,
    input integer target_level,
    input logic [43:0] ppn,
    input logic [7:0] flags
  );
    logic [63:0] slot;
    begin
      slot = pte_slot(base, address, target_level);
      page_table[slot[18:3]] = make_pte(ppn, flags);
    end
  endtask

  task automatic translate(
    input logic [511:0] name,
    input logic [63:0] address,
    input mmu_access_t target_access,
    input logic [1:0] target_privilege,
    input logic target_sum,
    input logic [63:0] target_satp,
    input logic expected_fault,
    input logic [63:0] expected_physical
  );
    integer cycles;
    begin
      virtual_address = address;
      access = target_access;
      privilege = target_privilege;
      sum_enable = target_sum;
      satp = target_satp;
      translate_valid = 1'b1;
      @(posedge clk);
      #1;
      translate_valid = 1'b0;
      cycles = 0;
      while (!translation_done && cycles < 16) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
      end
      if (!translation_done || translation_fault !== expected_fault ||
          (!expected_fault && physical_address !== expected_physical)) begin
        $display("FAIL %0s: done=%b fault=%b physical=%h expected_fault=%b expected_physical=%h cycles=%0d",
                 name, translation_done, translation_fault, physical_address,
                 expected_fault, expected_physical, cycles);
        failures = failures + 1;
      end
      @(posedge clk);
      #1;
    end
  endtask

  task automatic sfence(input logic invalidate_all, input logic [63:0] address);
    begin
      sfence_all = invalidate_all;
      sfence_virtual_address = address;
      sfence_valid = 1'b1;
      @(posedge clk);
      #1;
      sfence_valid = 1'b0;
    end
  endtask

  always_comb begin
    pte_ready = 1'b0;
    pte_read_data = '0;
    if (pte_request) begin
      pte_ready = 1'b1;
      pte_read_data = page_table[pte_address[18:3]];
    end
  end

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    translate_valid = 1'b0;
    virtual_address = '0;
    access = MMU_LOAD;
    privilege = 2'b01;
    sum_enable = 1'b0;
    satp = '0;
    sfence_valid = 1'b0;
    sfence_all = 1'b0;
    sfence_virtual_address = '0;
    failures = 0;

    for (integer table_index = 0; table_index < 65536; table_index = table_index + 1) begin
      page_table[table_index] = '0;
    end

    set_pte(ROOT_4K, VA_4K, 2, 44'd2, 8'h01);
    set_pte(L1_4K, VA_4K, 1, 44'd3, 8'h01);
    set_pte(L0_4K, VA_4K, 0, 44'h12345, 8'hc7);

    set_pte(ROOT_2M, VA_2M, 2, 44'd5, 8'h01);
    set_pte(L1_2M, VA_2M, 1, 44'h00400, 8'hc7);

    set_pte(ROOT_1G, VA_1G, 2, 44'h80000, 8'h43);
    set_pte(ROOT_BAD, VA_1G, 2, 44'h80001, 8'h43);

    @(posedge clk);
    #1;
    reset = 1'b0;

    translate("bare direct", 64'h0000_0000_4000_1234, MMU_LOAD, 2'b01, 1'b0,
              64'd0, 1'b0, 64'h0000_0000_4000_1234);
    translate("reserved satp mode", 64'h0000_0000_4000_1234, MMU_LOAD, 2'b01, 1'b0,
              64'h1000_0000_0000_0001, 1'b1, '0);
    translate("M-mode satp bypass", 64'h0000_0000_4000_5678, MMU_LOAD, 2'b11, 1'b0,
              64'h8000_0000_0000_0001, 1'b0, 64'h0000_0000_4000_5678);
    translate("4K load", VA_4K, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b0, 64'h0000_0000_1234_5678);
    translate("4K store", VA_4K, MMU_STORE, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b0, 64'h0000_0000_1234_5678);
    page_table[pte_slot(L0_4K, VA_4K, 0)[18:3]] = '0;
    translate("4K cached hit", VA_4K, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b0, 64'h0000_0000_1234_5678);
    sfence(1'b0, VA_4K);
    translate("4K sfence address", VA_4K, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b1, '0);
    set_pte(L0_4K, VA_4K, 0, 44'h12345, 8'hc7);
    translate("2M superpage", VA_2M, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0004, 1'b0, 64'h0000_0000_0045_6789);
    sfence(1'b0, VA_2M);
    set_pte(L1_2M, VA_2M, 1, 44'h00401, 8'hc7);
    translate("misaligned 2M", VA_2M, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0004, 1'b1, '0);
    set_pte(L1_2M, VA_2M, 1, 44'h00400, 8'hc7);
    translate("1G superpage", VA_1G, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0006, 1'b0, 64'h0000_0000_a345_6789);
    translate("noncanonical", 64'h0000_8000_0000_0000, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b1, '0);
    translate("invalid root PTE", VA_4K, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0008, 1'b1, '0);
    translate("misaligned 1G", VA_1G, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0007, 1'b1, '0);

    set_pte(L0_4K, VA_4K, 0, 44'h12345, 8'h49);
    translate("load execute-only fault", VA_4K, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b1, '0);
    set_pte(L0_4K, VA_4K, 0, 44'h12345, 8'h47);
    translate("store dirty fault", VA_4K, MMU_STORE, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b1, '0);
    set_pte(L0_4K, VA_4K, 0, 44'h12345, 8'hd7);
    translate("S load U page SUM off", VA_4K, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b1, '0);
    translate("S load U page SUM on", VA_4K, MMU_LOAD, 2'b01, 1'b1,
              64'h8000_0000_0000_0001, 1'b0, 64'h0000_0000_1234_5678);
    translate("S fetch U page SUM on", VA_4K, MMU_FETCH, 2'b01, 1'b1,
              64'h8000_0000_0000_0001, 1'b1, '0);
    translate("U load U page", VA_4K, MMU_LOAD, 2'b00, 1'b0,
              64'h8000_0000_0000_0001, 1'b0, 64'h0000_0000_1234_5678);
    sfence(1'b0, VA_4K);
    set_pte(L0_4K, VA_4K, 0, 44'h12345, 8'hc7);
    translate("U load supervisor page", VA_4K, MMU_LOAD, 2'b00, 1'b0,
              64'h8000_0000_0000_0001, 1'b1, '0);
    sfence(1'b1, '0);
    page_table[pte_slot(L0_4K, VA_4K, 0)[18:3]] = '0;
    translate("4K sfence all", VA_4K, MMU_LOAD, 2'b01, 1'b0,
              64'h8000_0000_0000_0001, 1'b1, '0);

    if (failures != 0) begin
      $display("SIM FAIL: %0d MMU checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_mmu Sv39 regression");
    $finish;
  end
endmodule
