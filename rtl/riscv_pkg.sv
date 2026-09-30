package riscv_pkg;
  // Keep this set aligned with rv64_csr's implemented registers. Returning zero
  // for a missing CSR is not sufficient: firmware probes optional extensions
  // (notably Sstc and AIA) by checking for an illegal-instruction exception.
  function automatic logic csr_implemented(input logic [11:0] address);
    case (address)
      12'hF11, 12'hF12, 12'hF13, 12'hF14,
      12'h100, 12'h104, 12'h105, 12'h140, 12'h141, 12'h142, 12'h143,
      12'h144, 12'h180,
      12'h300, 12'h301, 12'h302, 12'h303, 12'h304, 12'h305,
      12'h340, 12'h341, 12'h342, 12'h343, 12'h344,
      12'hC00, 12'hC01, 12'hC80, 12'hC81: csr_implemented = 1'b1;
      default: csr_implemented = 1'b0;
    endcase
  endfunction

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

  typedef enum logic [3:0] {
    ATOMIC_LR,
    ATOMIC_SC,
    ATOMIC_SWAP,
    ATOMIC_ADD,
    ATOMIC_XOR,
    ATOMIC_AND,
    ATOMIC_OR,
    ATOMIC_MIN,
    ATOMIC_MAX,
    ATOMIC_MINU,
    ATOMIC_MAXU
  } atomic_op_t;

  typedef enum logic [1:0] {
    MMU_FETCH,
    MMU_LOAD,
    MMU_STORE
  } mmu_access_t;
endpackage
