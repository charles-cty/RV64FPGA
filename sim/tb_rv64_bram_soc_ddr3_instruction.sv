`timescale 1ns / 1ps

module tb_rv64_bram_soc_ddr3_instruction;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer cycle_count;

  rv64_bram_soc #(.USE_DDR3_MODEL(1'b1), .DDR3_MODEL_RESPONSE_DELAY(3)) dut (
    .clk(clk), .reset(reset), .led(led), .uart_tx(uart_tx), .uart_rx(1'b1),
    .external_ddr3_request_ready(1'b0),
    .external_ddr3_response_read_data(64'b0),
    .external_ddr3_response_error(1'b0)
  );
  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    #1;
    for (index = 0; index < 16384; index = index + 1) begin
      dut.instruction_memory[index] = 32'h0000_0013;
    end
    for (index = 0; index < 1024; index = index + 1) begin
      dut.ddr3_model.memory[index] = 64'b0;
    end

    dut.instruction_memory[0] = 32'h8000_0537; // lui x10, 0x80000
    dut.instruction_memory[1] = 32'h0205_1513; // slli x10, x10, 32
    dut.instruction_memory[2] = 32'h0205_5513; // srli x10, x10, 32
    dut.instruction_memory[3] = 32'h0005_0067; // jalr x0, 0(x10)
    dut.ddr3_model.memory[0] = 64'h0070_0113_02a0_0093; // addi x1, x0, 42; addi x2, x0, 7
    dut.ddr3_model.memory[1] = 64'h0000_006f_0000_0013; // nop; jal x0, 0

    @(posedge clk);
    #1;
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 180 && dut.core.register_file.registers[2] !== 64'd7;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.instruction_address < 64'h0000_0000_8000_0000 ||
        dut.core.register_file.registers[1] !== 64'd42 ||
        dut.core.register_file.registers[2] !== 64'd7 ||
        !dut.instruction_cache.line_valid[0]) begin
      $display("FAIL DDR3 instruction fetch pc=%h x1=%h x2=%h valid=%b cycles=%0d",
               dut.core.instruction_address, dut.core.register_file.registers[1],
               dut.core.register_file.registers[2], dut.instruction_cache.line_valid, cycle_count);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d DDR3 instruction checks failed", failures);
    $display("SIM PASS: rv64_bram_soc DDR3 instruction fetch integration");
    $finish;
  end
endmodule
