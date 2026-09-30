`timescale 1ns / 1ps

module tb_rv64_bram_soc_jtag_smoke;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  logic uart_low_seen;
  integer cycle_count;

  rv64_bram_soc #(
    .USE_DDR3_MODEL(1'b1),
    .DDR3_MODEL_WORD_COUNT(16384),
    .DDR3_MODEL_RESPONSE_DELAY(2),
    .BOOT_ROM_INIT_FILE("boot_rom.hex"),
    .DDR3_MODEL_INIT_FILE("jtag_smoke_ddr3_image.hex")
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
    uart_low_seen = 1'b0;
    @(posedge clk);
    #1;
    if (dut.ddr3_model.memory[0] !== 64'h04a0_0313_1000_02b7) begin
      $display("FAIL JTAG smoke DDR3 image word=%h", dut.ddr3_model.memory[0]);
      $fatal(1, "SIM FAIL: JTAG smoke DDR3 image load");
    end
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 320 && (led !== 3'b101 || !uart_low_seen);
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
      if (!uart_tx) uart_low_seen = 1'b1;
    end
    if (led !== 3'b101 || !uart_low_seen ||
        dut.core.register_file.registers[5] !== 64'h0000_0000_1000_1000 ||
        dut.core.register_file.registers[6] !== 64'd5) begin
      $display("FAIL JTAG smoke led=%b uart_tx=%b x5=%h x6=%h cycles=%0d",
               led, uart_tx, dut.core.register_file.registers[5],
               dut.core.register_file.registers[6], cycle_count);
      $fatal(1, "SIM FAIL: JTAG smoke payload");
    end
    $display("SIM PASS: ROM to DDR3 JTAG smoke payload");
    $finish;
  end
endmodule
