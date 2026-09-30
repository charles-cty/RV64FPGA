`timescale 1ns / 1ps

module tb_rv64_bram_soc_ddr3_high_half;
  localparam integer DDR_WORDS = 300000;
  localparam logic [63:0] TARGET_VA = 64'hffff_ffff_8000_fff0;
  localparam logic [63:0] TARGET_PA = 64'h0000_0000_8020_fff0;

  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer cycle_count;
  integer failures;

  rv64_bram_soc #(
    .USE_DDR3_MODEL(1'b1),
    .DDR3_MODEL_WORD_COUNT(DDR_WORDS),
    .DDR3_MODEL_RESPONSE_DELAY(3)
  ) dut (
    .clk(clk), .reset(reset), .led(led), .uart_tx(uart_tx), .uart_rx(1'b1),
    .external_ddr3_request_ready(1'b0),
    .external_ddr3_response_read_data(64'b0),
    .external_ddr3_response_error(1'b0)
  );

  always #5 clk = ~clk;

  function automatic logic [31:0] encode_addi(
    input logic [4:0] destination,
    input logic [11:0] immediate
  );
    encode_addi = {immediate, 5'd0, 3'b000, destination, 7'b0010011};
  endfunction

  function automatic logic [63:0] make_pte(
    input logic [43:0] ppn,
    input logic [7:0] flags
  );
    make_pte = {10'b0, ppn, 2'b0, flags};
  endfunction

  always_ff @(posedge clk) begin
    if (!reset && dut.instruction_translation_ready &&
        dut.instruction_address >= TARGET_VA &&
        dut.instruction_address <= TARGET_VA + 64'h18) begin
      if (dut.instruction_physical_address < TARGET_PA ||
          dut.instruction_physical_address > TARGET_PA + 64'h18 ||
          !dut.instruction_cache_request) begin
        $display("FAIL high-half route va=%h pa=%h cache_request=%b",
                 dut.instruction_address, dut.instruction_physical_address,
                 dut.instruction_cache_request);
        $fatal(1, "SIM FAIL: high-half instruction was not routed to DDR3");
      end
    end
  end

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;

    // Enter S-mode at a canonical high-half VA with an Sv39 root in DDR3.
    dut.instruction_memory[0] = 32'h8000_00b7; // lui x1,0x80000
    dut.instruction_memory[1] = 32'h0200_9093; // slli x1,x1,32
    dut.instruction_memory[2] = 32'h0008_0137; // lui x2,0x80
    dut.instruction_memory[3] = 32'h0020_e0b3; // or x1,x1,x2
    dut.instruction_memory[4] = 32'h1800_9073; // csrw satp,x1
    dut.instruction_memory[5] = 32'h0010_0093; // addi x1,x0,1
    dut.instruction_memory[6] = 32'h00b0_9093; // slli x1,x1,11
    dut.instruction_memory[7] = 32'h3000_9073; // csrw mstatus,x1
    dut.instruction_memory[8] = 32'h8001_00b7; // lui x1,0x80010
    dut.instruction_memory[9] = 32'hff00_8093; // addi x1,x1,-16
    dut.instruction_memory[10] = 32'h3410_9073; // csrw mepc,x1
    dut.instruction_memory[11] = 32'h3020_0073; // mret

    // Root[510] -> L1 at 0x80001000. L1[0] maps the 2 MiB kernel
    // virtual window to physical 0x80200000 with supervisor X/R/A.
    dut.ddr3_model.memory[510] = make_pte(44'h80001, 8'h01);
    dut.ddr3_model.memory[512] = make_pte(44'h80200, 8'h4b);

    // Distinct instructions straddle the 64 KiB boundary that failed on board.
    dut.ddr3_model.memory[270334] = {encode_addi(5'd4, 12'd22), encode_addi(5'd3, 12'd11)};
    dut.ddr3_model.memory[270335] = {encode_addi(5'd6, 12'd44), encode_addi(5'd5, 12'd33)};
    dut.ddr3_model.memory[270336] = {encode_addi(5'd8, 12'd66), encode_addi(5'd7, 12'd55)};
    dut.ddr3_model.memory[270337] = {32'h0000_006f, 32'h0000_0013};

    @(posedge clk);
    #1;
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 1200 && dut.core.register_file.registers[8] !== 64'd66;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.register_file.registers[3] !== 64'd11 ||
        dut.core.register_file.registers[4] !== 64'd22 ||
        dut.core.register_file.registers[5] !== 64'd33 ||
        dut.core.register_file.registers[6] !== 64'd44 ||
        dut.core.register_file.registers[7] !== 64'd55 ||
        dut.core.register_file.registers[8] !== 64'd66 ||
        dut.satp_value !== 64'h8000_0000_0008_0000) begin
      $display("FAIL high-half fetch pc=%h satp=%h x3=%h x4=%h x5=%h x6=%h x7=%h x8=%h cycles=%0d",
               dut.instruction_address, dut.satp_value,
               dut.core.register_file.registers[3], dut.core.register_file.registers[4],
               dut.core.register_file.registers[5], dut.core.register_file.registers[6],
               dut.core.register_file.registers[7], dut.core.register_file.registers[8], cycle_count);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d high-half fetch checks failed", failures);
    $display("SIM PASS: Sv39 high-half DDR3 fetch crosses 64 KiB boundary");
    $finish;
  end
endmodule
