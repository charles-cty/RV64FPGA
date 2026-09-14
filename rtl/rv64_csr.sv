module rv64_csr (
  input  logic        clk,
  input  logic        reset,
  input  logic [11:0] read_address,
  output logic [63:0] read_data,
  input  logic        write_enable,
  input  logic [11:0] write_address,
  input  logic [63:0] write_data,
  input  logic        trap_to_machine,
  input  logic [63:0] trap_pc,
  input  logic [63:0] trap_cause,
  input  logic [63:0] trap_value,
  input  logic [1:0]  current_privilege,
  input  logic        return_from_machine
);
  localparam logic [63:0] MISA_VALUE = 64'h8000_0000_0000_1101;
  localparam logic [63:0] SSTATUS_MASK = 64'h8000_0003_000d_e162;

  logic [63:0] mstatus;
  logic [63:0] medeleg;
  logic [63:0] mideleg;
  logic [63:0] mie;
  logic [63:0] mtvec;
  logic [63:0] mscratch;
  logic [63:0] mepc;
  logic [63:0] mcause;
  logic [63:0] mtval;
  logic [63:0] mip;
  logic [63:0] sie;
  logic [63:0] stvec;
  logic [63:0] sscratch;
  logic [63:0] sepc;
  logic [63:0] scause;
  logic [63:0] stval;
  logic [63:0] satp;
  logic [63:0] time_counter;

  always_comb begin
    read_data = '0;
    unique case (read_address)
      12'h100: read_data = mstatus & SSTATUS_MASK;
      12'h104: read_data = sie;
      12'h105: read_data = stvec;
      12'h140: read_data = sscratch;
      12'h141: read_data = sepc;
      12'h142: read_data = scause;
      12'h143: read_data = stval;
      12'h144: read_data = mip;
      12'h180: read_data = satp;
      12'h300: read_data = mstatus;
      12'h301: read_data = MISA_VALUE;
      12'h302: read_data = medeleg;
      12'h303: read_data = mideleg;
      12'h304: read_data = mie;
      12'h305: read_data = mtvec;
      12'h340: read_data = mscratch;
      12'h341: read_data = mepc;
      12'h342: read_data = mcause;
      12'h343: read_data = mtval;
      12'h344: read_data = mip;
      12'hC01: read_data = time_counter;
      12'hC81: read_data = time_counter[63:32];
      default: read_data = '0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      mstatus <= '0;
      medeleg <= '0;
      mideleg <= '0;
      mie <= '0;
      mtvec <= '0;
      mscratch <= '0;
      mepc <= '0;
      mcause <= '0;
      mtval <= '0;
      mip <= '0;
      sie <= '0;
      stvec <= '0;
      sscratch <= '0;
      sepc <= '0;
      scause <= '0;
      stval <= '0;
      satp <= '0;
      time_counter <= '0;
    end else begin
      time_counter <= time_counter + 64'd1;

      if (write_enable) begin
        unique case (write_address)
          12'h100: mstatus <= (mstatus & ~SSTATUS_MASK) | (write_data & SSTATUS_MASK);
          12'h104: sie <= write_data;
          12'h105: stvec <= write_data;
          12'h140: sscratch <= write_data;
          12'h141: sepc <= write_data;
          12'h142: scause <= write_data;
          12'h143: stval <= write_data;
          12'h144: mip <= write_data;
          12'h180: satp <= write_data;
          12'h300: mstatus <= write_data;
          12'h302: medeleg <= write_data;
          12'h303: mideleg <= write_data;
          12'h304: mie <= write_data;
          12'h305: mtvec <= write_data;
          12'h340: mscratch <= write_data;
          12'h341: mepc <= write_data;
          12'h342: mcause <= write_data;
          12'h343: mtval <= write_data;
          12'h344: mip <= write_data;
          default: ;
        endcase
      end

      if (trap_to_machine) begin
        mepc <= trap_pc;
        mcause <= trap_cause;
        mtval <= trap_value;
        mstatus[7] <= mstatus[3];
        mstatus[3] <= 1'b0;
        mstatus[12:11] <= current_privilege;
      end else if (return_from_machine) begin
        mstatus[3] <= mstatus[7];
        mstatus[7] <= 1'b1;
        mstatus[12:11] <= 2'b00;
      end
    end
  end
endmodule
