module rv64_decoder (
  input  logic [31:0]        instruction,
  output riscv_pkg::alu_op_t operation,
  output logic              uses_immediate,
  output logic              writes_register,
  output logic              illegal
);
  import riscv_pkg::*;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  always_comb begin
    opcode = instruction[6:0];
    funct3 = instruction[14:12];
    funct7 = instruction[31:25];
    operation = ALU_ADD;
    uses_immediate = 1'b0;
    writes_register = 1'b0;
    illegal = 1'b0;

    unique case (opcode)
      7'b0010011: begin
        uses_immediate = 1'b1;
        writes_register = 1'b1;
        unique case (funct3)
          3'b000: operation = ALU_ADD;
          3'b010: operation = ALU_SLT;
          3'b011: operation = ALU_SLTU;
          3'b100: operation = ALU_XOR;
          3'b110: operation = ALU_OR;
          3'b111: operation = ALU_AND;
          3'b001: begin
            operation = ALU_SLL;
            illegal = instruction[31:26] != 6'b000000;
          end
          3'b101: begin
            operation = (instruction[31:26] == 6'b010000) ? ALU_SRA : ALU_SRL;
            illegal = (instruction[31:26] != 6'b000000) &&
                      (instruction[31:26] != 6'b010000);
          end
          default: illegal = 1'b1;
        endcase
      end
      7'b0011011: begin
        uses_immediate = 1'b1;
        writes_register = 1'b1;
        unique case (funct3)
          3'b000: operation = ALU_ADDW;
          3'b001: begin
            operation = ALU_SLLW;
            illegal = funct7 != 7'b0000000;
          end
          3'b101: begin
            operation = (funct7 == 7'b0100000) ? ALU_SRAW : ALU_SRLW;
            illegal = (funct7 != 7'b0000000) && (funct7 != 7'b0100000);
          end
          default: illegal = 1'b1;
        endcase
      end
      7'b0110011, 7'b0111011: begin
        writes_register = 1'b1;
        unique case (funct7)
          7'b0000000: begin
            unique case (funct3)
              3'b000: operation = (opcode == 7'b0110011) ? ALU_ADD : ALU_ADDW;
              3'b001: operation = (opcode == 7'b0110011) ? ALU_SLL : ALU_SLLW;
              3'b010: operation = ALU_SLT;
              3'b011: operation = ALU_SLTU;
              3'b100: operation = ALU_XOR;
              3'b101: operation = (opcode == 7'b0110011) ? ALU_SRL : ALU_SRLW;
              3'b110: operation = ALU_OR;
              3'b111: operation = ALU_AND;
              default: illegal = 1'b1;
            endcase
            if ((opcode == 7'b0111011) && (funct3 inside {3'b010, 3'b011, 3'b100, 3'b110, 3'b111})) begin
              illegal = 1'b1;
            end
          end
          7'b0100000: begin
            if (funct3 == 3'b000) begin
              operation = (opcode == 7'b0110011) ? ALU_SUB : ALU_SUBW;
            end else if (funct3 == 3'b101) begin
              operation = (opcode == 7'b0110011) ? ALU_SRA : ALU_SRAW;
            end else begin
              illegal = 1'b1;
            end
          end
          7'b0000001: begin
            unique case (funct3)
              3'b000: operation = (opcode == 7'b0110011) ? ALU_MUL : ALU_MULW;
              3'b001: operation = ALU_MULH;
              3'b010: operation = ALU_MULHSU;
              3'b011: operation = ALU_MULHU;
              3'b100: operation = (opcode == 7'b0110011) ? ALU_DIV : ALU_DIVW;
              3'b101: operation = (opcode == 7'b0110011) ? ALU_DIVU : ALU_DIVUW;
              3'b110: operation = (opcode == 7'b0110011) ? ALU_REM : ALU_REMW;
              3'b111: operation = (opcode == 7'b0110011) ? ALU_REMU : ALU_REMUW;
              default: illegal = 1'b1;
            endcase
            if ((opcode == 7'b0111011) && (funct3 inside {3'b001, 3'b010, 3'b011})) begin
              illegal = 1'b1;
            end
          end
          default: illegal = 1'b1;
        endcase
      end
      default: illegal = 1'b1;
    endcase

    if (illegal) begin
      writes_register = 1'b0;
    end
  end
endmodule
