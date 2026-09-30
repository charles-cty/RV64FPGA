`timescale 1ns / 1ps

module tb_rv64_bram_soc_ddr3_external;
  localparam logic [63:0] DDR3_BASE_ADDRESS = 64'h0000_0000_8000_0000;

  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  logic external_request_valid;
  logic external_request_write;
  logic [63:0] external_request_address;
  logic [63:0] external_request_write_data;
  logic [7:0] external_request_write_strobe;
  logic external_request_ready;
  logic [63:0] external_response_read_data;
  logic external_response_error;
  logic [63:0] memory [0:1023];
  logic [63:0] pending_address;
  logic [63:0] pending_write_data;
  logic [7:0] pending_write_strobe;
  logic pending_write;
  integer response_countdown;
  integer request_count;
  integer physical_base_request_count;
  integer non_physical_request_count;
  integer write_count;
  integer read_count;
  integer failures;
  integer index;
  integer memory_index;
  integer cycle_count;

  rv64_bram_soc #(
    .UART_BIT_CYCLES(2),
    .USE_DDR3_EXTERNAL(1'b1)
  ) dut (
    .clk(clk), .reset(reset), .led(led), .uart_tx(uart_tx), .uart_rx(1'b1),
    .external_ddr3_request_valid(external_request_valid),
    .external_ddr3_request_write(external_request_write),
    .external_ddr3_request_address(external_request_address),
    .external_ddr3_request_write_data(external_request_write_data),
    .external_ddr3_request_write_strobe(external_request_write_strobe),
    .external_ddr3_request_ready(external_request_ready),
    .external_ddr3_response_read_data(external_response_read_data),
    .external_ddr3_response_error(external_response_error)
  );

  always #5 clk = ~clk;

  always_comb begin
    external_request_ready = response_countdown == 0 && pending_address !== 'x;
    external_response_read_data = memory[(pending_address - DDR3_BASE_ADDRESS) >> 3];
    external_response_error = 1'b0;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      pending_address <= 'x;
      pending_write_data <= '0;
      pending_write_strobe <= '0;
      pending_write <= 1'b0;
      response_countdown <= -1;
      request_count <= 0;
      physical_base_request_count <= 0;
      non_physical_request_count <= 0;
      write_count <= 0;
      read_count <= 0;
      for (memory_index = 0; memory_index < 1024; memory_index = memory_index + 1) memory[memory_index] <= '0;
    end else begin
      if (response_countdown > 0) response_countdown <= response_countdown - 1;
      if (external_request_valid && response_countdown < 0) begin
        pending_address <= external_request_address;
        pending_write_data <= external_request_write_data;
        pending_write_strobe <= external_request_write_strobe;
        pending_write <= external_request_write;
        response_countdown <= 2;
        request_count <= request_count + 1;
        if (external_request_address == DDR3_BASE_ADDRESS)
          physical_base_request_count <= physical_base_request_count + 1;
        else
          non_physical_request_count <= non_physical_request_count + 1;
        if (external_request_write) write_count <= write_count + 1;
        else read_count <= read_count + 1;
      end else if (external_request_ready) begin
        if (pending_write) begin
          for (memory_index = 0; memory_index < 8; memory_index = memory_index + 1) begin
            if (pending_write_strobe[memory_index])
              memory[(pending_address - DDR3_BASE_ADDRESS) >> 3][memory_index*8 +: 8] <=
                pending_write_data[memory_index*8 +: 8];
          end
        end
        pending_address <= 'x;
        response_countdown <= -1;
      end
    end
  end

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    #1;
    for (index = 0; index < 16384; index = index + 1) dut.instruction_memory[index] = 32'h0000_0013;
    dut.instruction_memory[0] = 32'h8000_0537;
    dut.instruction_memory[1] = 32'h0205_1513;
    dut.instruction_memory[2] = 32'h0205_5513;
    dut.instruction_memory[3] = 32'h0110_0093; // addi x1, x0, 0x11
    dut.instruction_memory[4] = 32'h0015_00a3; // sb x1, 1(x10)
    dut.instruction_memory[5] = 32'h0220_0093; // addi x1, x0, 0x22
    dut.instruction_memory[6] = 32'h0015_03a3; // sb x1, 7(x10)
    dut.instruction_memory[7] = 32'h0005_4103; // lbu x2, 0(x10)
    dut.instruction_memory[8] = 32'h0015_4183; // lbu x3, 1(x10)
    dut.instruction_memory[9] = 32'h0075_4203; // lbu x4, 7(x10)
    dut.instruction_memory[10] = 32'h0005_5283; // lhu x5, 0(x10)
    dut.instruction_memory[11] = 32'h0065_5303; // lhu x6, 6(x10)
    dut.instruction_memory[12] = 32'h0045_6383; // lwu x7, 4(x10)
    dut.instruction_memory[13] = 32'h0000_006f;
    @(posedge clk);
    #1;
    reset = 1'b0;

    for (cycle_count = 0; cycle_count < 240 && dut.core.register_file.registers[7] !== 64'h2200_0000;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.register_file.registers[10] !== 64'h0000_0000_8000_0000 ||
        dut.core.register_file.registers[2] !== 64'h00 ||
        dut.core.register_file.registers[3] !== 64'h11 ||
        dut.core.register_file.registers[4] !== 64'h22 ||
        dut.core.register_file.registers[5] !== 64'h1100 ||
        dut.core.register_file.registers[6] !== 64'h2200 ||
        dut.core.register_file.registers[7] !== 64'h2200_0000 ||
        memory[0] !== 64'h2200_0000_0000_1100 || write_count != 2 || read_count != 1 ||
        request_count != 3 || physical_base_request_count != 3 ||
        non_physical_request_count != 0) begin
      $display("FAIL external DDR3 x2=%h x3=%h x4=%h x5=%h x6=%h x7=%h mem=%h writes=%0d reads=%0d requests=%0d physical_base=%0d non_physical=%0d cycles=%0d",
               dut.core.register_file.registers[2], dut.core.register_file.registers[3],
               dut.core.register_file.registers[4], dut.core.register_file.registers[5],
               dut.core.register_file.registers[6], dut.core.register_file.registers[7],
               memory[0], write_count, read_count, request_count,
               physical_base_request_count, non_physical_request_count, cycle_count);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d external DDR3 SoC checks failed", failures);
    $display("SIM PASS: rv64_bram_soc external DDR3 endpoint integration");
    $finish;
  end
endmodule
