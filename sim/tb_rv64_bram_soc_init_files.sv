`timescale 1ns / 1ps

module tb_rv64_bram_soc_init_files;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer cycle_count;

  rv64_bram_soc #(
    .UART_BIT_CYCLES(2),
    .USE_DDR3_MODEL(1'b1),
    .BOOT_ROM_INIT_FILE("sim/boot_rom_init.hex"),
    .DDR3_MODEL_INIT_FILE("sim/ddr3_model_init.hex")
  ) dut (
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

    @(posedge clk);
    #1;
    reset = 1'b0;

    for (cycle_count = 0; cycle_count < 40 &&
         dut.core.register_file.registers[1] !== 64'd7;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.instruction_memory[0] !== 32'h0070_0093 ||
        dut.instruction_memory[1] !== 32'h0000_006f) begin
      $display("FAIL boot ROM init first=%h second=%h",
               dut.instruction_memory[0], dut.instruction_memory[1]);
      failures = failures + 1;
    end
    if (dut.ddr3_model.memory[0] !== 64'h1122_3344_5566_7788) begin
      $display("FAIL DDR3 init word=%h", dut.ddr3_model.memory[0]);
      failures = failures + 1;
    end
    if (dut.core.register_file.registers[1] !== 64'd7) begin
      $display("FAIL boot ROM execution x1=%h cycles=%0d",
               dut.core.register_file.registers[1], cycle_count);
      failures = failures + 1;
    end

    if (failures != 0) $fatal(1, "SIM FAIL: %0d init-file checks failed", failures);
    $display("SIM PASS: rv64_bram_soc init-file loading");
    $finish;
  end
endmodule
