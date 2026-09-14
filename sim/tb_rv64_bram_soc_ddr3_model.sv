`timescale 1ns / 1ps

module tb_rv64_bram_soc_ddr3_model;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer cycle_count;

  rv64_bram_soc #(.UART_BIT_CYCLES(2), .USE_DDR3_MODEL(1'b1),
                  .DDR3_MODEL_RESPONSE_DELAY(3)) dut (.*);
  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    #1;
    for (index = 0; index < 16384; index = index + 1) dut.instruction_memory[index] = 32'h0000_0013;
    dut.instruction_memory[0] = 32'h0050_0093; // addi x1, x0, 5
    dut.instruction_memory[1] = 32'h0010_3023; // sd x1, 0(x0)
    dut.instruction_memory[2] = 32'h0000_3103; // ld x2, 0(x0), delayed miss
    dut.instruction_memory[3] = 32'h0000_3183; // ld x3, 0(x0), cache hit
    dut.instruction_memory[4] = 32'h0000_006f;
    @(posedge clk);
    #1;
    reset = 1'b0;

    for (cycle_count = 0; cycle_count < 120 && dut.core.register_file.registers[3] !== 64'd5;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.register_file.registers[2] !== 64'd5 ||
        dut.core.register_file.registers[3] !== 64'd5 ||
        !dut.data_cache.line_valid[0] ||
        dut.ddr3_model.memory[0] !== 64'd5) begin
      $display("FAIL DDR3 SoC x2=%h x3=%h valid=%b memory=%h cycles=%0d",
               dut.core.register_file.registers[2], dut.core.register_file.registers[3],
               dut.data_cache.line_valid, dut.ddr3_model.memory[0], cycle_count);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d DDR3 model SoC checks failed", failures);
    $display("SIM PASS: rv64_bram_soc delayed DDR3 model integration");
    $finish;
  end
endmodule
