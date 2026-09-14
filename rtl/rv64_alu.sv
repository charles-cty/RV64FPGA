module rv64_alu (
  input  logic [63:0]        lhs,
  input  logic [63:0]        rhs,
  input  riscv_pkg::alu_op_t operation,
  output logic [63:0]        result
);
  import riscv_pkg::*;

  localparam logic [63:0] SIGNED_MIN = 64'h8000_0000_0000_0000;
  localparam logic [31:0] SIGNED_MIN_W = 32'h8000_0000;

  logic signed [127:0] product_signed_signed;
  logic signed [127:0] product_signed_unsigned;
  logic        [127:0] product_unsigned_unsigned;
  logic        [31:0] word_result;

  always_comb begin
    product_signed_signed = $signed(lhs) * $signed(rhs);
    product_signed_unsigned = $signed(lhs) * $signed({1'b0, rhs});
    product_unsigned_unsigned = lhs * rhs;
    word_result = '0;
    result = '0;

    unique case (operation)
      ALU_ADD: result = lhs + rhs;
      ALU_SUB: result = lhs - rhs;
      ALU_SLL: result = lhs << rhs[5:0];
      ALU_SLT: result = $signed(lhs) < $signed(rhs);
      ALU_SLTU: result = lhs < rhs;
      ALU_XOR: result = lhs ^ rhs;
      ALU_SRL: result = lhs >> rhs[5:0];
      ALU_SRA: result = $signed(lhs) >>> rhs[5:0];
      ALU_OR: result = lhs | rhs;
      ALU_AND: result = lhs & rhs;

      ALU_ADDW: word_result = lhs[31:0] + rhs[31:0];
      ALU_SUBW: word_result = lhs[31:0] - rhs[31:0];
      ALU_SLLW: word_result = lhs[31:0] << rhs[4:0];
      ALU_SRLW: word_result = lhs[31:0] >> rhs[4:0];
      ALU_SRAW: word_result = $signed(lhs[31:0]) >>> rhs[4:0];

      ALU_MUL: result = product_signed_signed[63:0];
      ALU_MULH: result = product_signed_signed[127:64];
      ALU_MULHSU: result = product_signed_unsigned[127:64];
      ALU_MULHU: result = product_unsigned_unsigned[127:64];
      ALU_DIV: begin
        if (rhs == '0) begin
          result = '1;
        end else if ((lhs == SIGNED_MIN) && (rhs == '1)) begin
          result = SIGNED_MIN;
        end else begin
          result = $signed(lhs) / $signed(rhs);
        end
      end
      ALU_DIVU: result = (rhs == '0) ? '1 : lhs / rhs;
      ALU_REM: begin
        if (rhs == '0) begin
          result = lhs;
        end else if ((lhs == SIGNED_MIN) && (rhs == '1)) begin
          result = '0;
        end else begin
          result = $signed(lhs) % $signed(rhs);
        end
      end
      ALU_REMU: result = (rhs == '0) ? lhs : lhs % rhs;

      ALU_MULW: word_result = lhs[31:0] * rhs[31:0];
      ALU_DIVW: begin
        if (rhs[31:0] == '0) begin
          word_result = '1;
        end else if ((lhs[31:0] == SIGNED_MIN_W) && (rhs[31:0] == '1)) begin
          word_result = SIGNED_MIN_W;
        end else begin
          word_result = $signed(lhs[31:0]) / $signed(rhs[31:0]);
        end
      end
      ALU_DIVUW: word_result = (rhs[31:0] == '0) ? '1 : lhs[31:0] / rhs[31:0];
      ALU_REMW: begin
        if (rhs[31:0] == '0) begin
          word_result = lhs[31:0];
        end else if ((lhs[31:0] == SIGNED_MIN_W) && (rhs[31:0] == '1)) begin
          word_result = '0;
        end else begin
          word_result = $signed(lhs[31:0]) % $signed(rhs[31:0]);
        end
      end
      ALU_REMUW: word_result = (rhs[31:0] == '0) ? lhs[31:0] : lhs[31:0] % rhs[31:0];

      default: result = '0;
    endcase

    unique case (operation)
      ALU_ADDW, ALU_SUBW, ALU_SLLW, ALU_SRLW, ALU_SRAW,
      ALU_MULW, ALU_DIVW, ALU_DIVUW, ALU_REMW, ALU_REMUW:
        result = {{32{word_result[31]}}, word_result};
      default: ;
    endcase
  end
endmodule
