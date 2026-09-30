`timescale 1ns / 1ps

module tb_rv64_bram_soc_boot_image;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer cycle_count;

  rv64_bram_soc #(
    .BOOT_ROM_INIT_FILE("boot_rom.hex")
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
    if (dut.instruction_memory[0] !== 32'h8000_02b7 ||
        dut.instruction_memory[1] !== 32'h0202_9293 ||
        dut.instruction_memory[2] !== 32'h0202_d293 ||
        dut.instruction_memory[3] !== 32'h0000_0513 ||
        dut.instruction_memory[4] !== 32'h8001_05b7 ||
        dut.instruction_memory[5] !== 32'h0205_9593 ||
        dut.instruction_memory[6] !== 32'h0205_d593 ||
        dut.instruction_memory[7] !== 32'h0002_8067 ||
        dut.instruction_memory[16] !== 32'h0000_006f) begin
      $display("FAIL generated boot image words=%h,%h,%h,%h,%h,%h,%h,%h,%h",
               dut.instruction_memory[0], dut.instruction_memory[1],
               dut.instruction_memory[2], dut.instruction_memory[3],
               dut.instruction_memory[4], dut.instruction_memory[5],
               dut.instruction_memory[6], dut.instruction_memory[7],
               dut.instruction_memory[16]);
      failures = failures + 1;
    end
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 40; cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end
    if (dut.core.register_file.registers[10] !== 64'd0 ||
        dut.core.register_file.registers[11] !== 64'h0000_0000_8001_0000) begin
      $display("FAIL Linux handoff registers a0=%h a1=%h",
               dut.core.register_file.registers[10], dut.core.register_file.registers[11]);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d boot image checks failed", failures);
    $display("SIM PASS: generated boot image loading");
    $finish;
  end
endmodule
