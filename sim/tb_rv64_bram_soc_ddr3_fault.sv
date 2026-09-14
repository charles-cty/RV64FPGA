`timescale 1ns / 1ps

module tb_rv64_bram_soc_ddr3_fault;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;

  rv64_bram_soc #(.USE_DDR3_MODEL(1'b1), .DDR3_MODEL_CALIBRATED(1'b0),
                  .DDR3_MODEL_RESPONSE_DELAY(2)) dut (.*);
  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    #1;
    for (index = 0; index < 16384; index = index + 1) dut.instruction_memory[index] = 32'h0000_0013;
    dut.instruction_memory[0] = 32'h0400_0093; // addi x1, x0, 64
    dut.instruction_memory[1] = 32'h3050_9073; // csrrw x0, mtvec, x1
    dut.instruction_memory[2] = 32'h0000_3103; // ld x2, 0(x0)
    dut.instruction_memory[16] = 32'h0000_006f;
    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (20) @(posedge clk);
    #1;
    if (dut.core.csr_file.mcause !== 64'd13 || dut.core.csr_file.mtval !== 64'd0 ||
        dut.core.csr_file.mepc !== 64'd8 || dut.core.instruction_address !== 64'h40 ||
        dut.core.register_file.registers[2] !== 64'b0) begin
      $display("FAIL DDR3 unavailable fault cause=%h value=%h pc=%h next=%h x2=%h",
               dut.core.csr_file.mcause, dut.core.csr_file.mtval, dut.core.csr_file.mepc,
               dut.core.instruction_address, dut.core.register_file.registers[2]);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d DDR3 unavailable checks failed", failures);
    $display("SIM PASS: rv64_bram_soc DDR3 unavailable access fault");
    $finish;
  end
endmodule
