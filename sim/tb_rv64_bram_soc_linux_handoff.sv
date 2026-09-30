`timescale 1ns / 1ps

module tb_rv64_bram_soc_linux_handoff;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer cycle_count;

  rv64_bram_soc #(
    .USE_DDR3_MODEL(1'b1),
    .DDR3_MODEL_WORD_COUNT(16384),
    .DDR3_MODEL_RESPONSE_DELAY(2),
    .BOOT_ROM_INIT_FILE("boot_rom.hex"),
    .DDR3_MODEL_INIT_FILE("linux_ddr3_image.hex")
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
    @(posedge clk);
    #1;
    if (dut.ddr3_model.memory[0] === 64'b0 ||
        dut.ddr3_model.memory[8192] === 64'b0) begin
      $display("FAIL DDR3 sparse image payload=%h dtb=%h",
               dut.ddr3_model.memory[0], dut.ddr3_model.memory[8192]);
      $fatal(1, "SIM FAIL: sparse DDR3 image load");
    end
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 160 && led !== 3'b001;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end
    if (led !== 3'b001 || dut.core.register_file.registers[5] !== 64'hffff_ffff_edfe_0dd0 ||
        dut.core.register_file.registers[10] !== 64'd0 ||
        dut.core.register_file.registers[11] !== 64'h0000_0000_8001_0000 ||
        dut.core.register_file.registers[4] !== 64'h0000_0000_8001_0000) begin
      $display("FAIL Linux-style DDR3 handoff led=%b a0=%h a1=%h x4=%h x5=%h x6=%h pc=%h cycles=%0d",
               led, dut.core.register_file.registers[10],
               dut.core.register_file.registers[11],
               dut.core.register_file.registers[4], dut.core.register_file.registers[5],
               dut.core.register_file.registers[6],
               dut.instruction_address, cycle_count);
      $fatal(1, "SIM FAIL: Linux-style DDR3 handoff");
    end
    $display("SIM PASS: ROM to DDR3 Linux-style payload handoff");
    $finish;
  end
endmodule
