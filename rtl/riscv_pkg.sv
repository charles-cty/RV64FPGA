package riscv_pkg;
  typedef enum logic [2:0] {
    IMM_I,
    IMM_S,
    IMM_B,
    IMM_U,
    IMM_J
  } immediate_kind_t;

  typedef enum logic [5:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_SRL,
    ALU_SRA,
    ALU_OR,
    ALU_AND,
    ALU_ADDW,
    ALU_SUBW,
    ALU_SLLW,
    ALU_SRLW,
    ALU_SRAW,
    ALU_MUL,
    ALU_MULH,
    ALU_MULHSU,
    ALU_MULHU,
    ALU_DIV,
    ALU_DIVU,
    ALU_REM,
    ALU_REMU,
    ALU_MULW,
    ALU_DIVW,
    ALU_DIVUW,
    ALU_REMW,
    ALU_REMUW
  } alu_op_t;
endpackage
