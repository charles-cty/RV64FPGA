module rv64_mmu (
  input  logic                   clk,
  input  logic                   reset,
  input  logic                   translate_valid,
  input  logic [63:0]            virtual_address,
  input  riscv_pkg::mmu_access_t access,
  input  logic [1:0]             privilege,
  input  logic                   sum_enable,
  input  logic [63:0]            satp,
  output logic                   pte_request,
  output logic [63:0]            pte_address,
  input  logic [63:0]            pte_read_data,
  input  logic                   pte_ready,
  output logic                   translation_done,
  output logic                   translation_fault,
  output logic [63:0]            physical_address,
  output logic                   busy
);
  import riscv_pkg::*;

  typedef enum logic [1:0] {IDLE, WALK} state_t;
  state_t state;
  logic [63:0] request_virtual_address;
  mmu_access_t request_access;
  logic [1:0] request_privilege;
  logic request_sum;
  logic [1:0] level;
  logic [63:0] table_base;
  function automatic logic canonical_sv39(input logic [63:0] address);
    canonical_sv39 = address[63:39] == {25{address[38]}};
  endfunction

  function automatic logic permission_ok(input logic [63:0] entry);
    logic privilege_ok;
    begin
      if (request_privilege == 2'b00) begin
        privilege_ok = entry[4];
      end else if (request_privilege == 2'b01) begin
        privilege_ok = !entry[4] ||
                       ((request_access != MMU_FETCH) && request_sum);
      end else begin
        privilege_ok = 1'b1;
      end
      permission_ok = entry[0] && !(entry[1] == 1'b0 && entry[2] == 1'b1) &&
                      ((request_access == MMU_FETCH && entry[3]) ||
                       (request_access == MMU_LOAD && entry[1]) ||
                       (request_access == MMU_STORE && entry[2])) &&
                      privilege_ok;
    end
  endfunction

  always_comb begin
    busy = state != IDLE;
    pte_request = state == WALK;
    pte_address = table_base + ({55'b0, request_virtual_address[38:30]} << 3);
    if (level == 1) begin
      pte_address = table_base + ({55'b0, request_virtual_address[29:21]} << 3);
    end else if (level == 0) begin
      pte_address = table_base + ({55'b0, request_virtual_address[20:12]} << 3);
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      state <= IDLE;
      translation_done <= 1'b0;
      translation_fault <= 1'b0;
      physical_address <= '0;
      request_virtual_address <= '0;
      request_access <= MMU_FETCH;
      request_privilege <= 2'b11;
      request_sum <= 1'b0;
      level <= '0;
      table_base <= '0;
    end else begin
      translation_done <= 1'b0;
      translation_fault <= 1'b0;

      if ((state == IDLE) && translate_valid) begin
        request_virtual_address <= virtual_address;
        request_access <= access;
        request_privilege <= privilege;
        request_sum <= sum_enable;
        if ((satp[63:60] != 4'h8) || (privilege == 2'b11)) begin
          physical_address <= virtual_address;
          translation_done <= 1'b1;
        end else if (!canonical_sv39(virtual_address)) begin
          translation_fault <= 1'b1;
          translation_done <= 1'b1;
        end else begin
          level <= 2;
          table_base <= {8'b0, satp[43:0], 12'b0};
          state <= WALK;
        end
      end else if ((state == WALK) && pte_ready) begin
        if (!pte_read_data[0] || (!pte_read_data[1] && pte_read_data[2]) ||
            (pte_read_data[63:54] != 10'b0)) begin
          translation_fault <= 1'b1;
          translation_done <= 1'b1;
          state <= IDLE;
        end else if (pte_read_data[1] || pte_read_data[3]) begin
          if (!permission_ok(pte_read_data) || !pte_read_data[6] ||
              ((level == 2) && (pte_read_data[27:10] != 18'b0)) ||
              ((level == 1) && (pte_read_data[18:10] != 9'b0)) ||
              ((request_access == MMU_STORE) && !pte_read_data[7])) begin
            translation_fault <= 1'b1;
          end else begin
            physical_address <= {8'b0, pte_read_data[53:10], request_virtual_address[11:0]};
            if (level == 2) begin
              physical_address <= {8'b0, pte_read_data[53:28], request_virtual_address[29:0]};
            end else if (level == 1) begin
              physical_address <= {8'b0, pte_read_data[53:19], request_virtual_address[20:0]};
            end
          end
          translation_done <= 1'b1;
          state <= IDLE;
        end else if (level == 0) begin
          translation_fault <= 1'b1;
          translation_done <= 1'b1;
          state <= IDLE;
        end else begin
          level <= level - 1'b1;
          table_base <= {8'b0, pte_read_data[53:10], 12'b0};
        end
      end
    end
  end
endmodule
