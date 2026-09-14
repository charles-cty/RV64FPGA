module rv64_imm_gen (
  input  logic [31:0]                  instruction,
  input  riscv_pkg::immediate_kind_t  kind,
  output logic [63:0]                  immediate
);
  import riscv_pkg::*;

  always_comb begin
    immediate = '0;
    unique case (kind)
      IMM_I: immediate = {{52{instruction[31]}}, instruction[31:20]};
      IMM_S: immediate = {{52{instruction[31]}}, instruction[31:25], instruction[11:7]};
      IMM_B: immediate = {{51{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
      IMM_U: immediate = {{32{instruction[31]}}, instruction[31:12], 12'b0};
      IMM_J: immediate = {{43{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};
      default: immediate = '0;
    endcase
  end
endmodule
