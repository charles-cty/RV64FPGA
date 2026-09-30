`timescale 1ns / 1ps

module tb_rv64_bram_soc_random;
  localparam integer PROGRAM_LENGTH = 96;
  localparam integer MAX_CYCLES = 5000;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer trace_file;
  integer commit_count;
  integer cycle_count;

  rv64_bram_soc dut (
    .clk(clk), .reset(reset), .led(led), .uart_tx(uart_tx), .uart_rx(1'b1),
    .external_ddr3_request_ready(1'b0),
    .external_ddr3_response_read_data(64'b0),
    .external_ddr3_response_error(1'b0)
  );
  always #5 clk = ~clk;

  task automatic write_trace;
    begin
      if (dut.core.commit_rd_write) begin
        $fdisplay(trace_file,
                  "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":\"0x%016h\"}",
                  dut.core.commit_pc, dut.core.commit_instruction, dut.core.commit_next_pc,
                  dut.core.commit_rd, dut.core.commit_rd_value);
      end else begin
        $fdisplay(trace_file,
                  "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":null}",
                  dut.core.commit_pc, dut.core.commit_instruction, dut.core.commit_next_pc,
                  dut.core.commit_rd);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    commit_count = 0;
    trace_file = $fopen("rtl_trace.jsonl", "w");
    if (trace_file == 0) begin
      $display("SIM FAIL: could not open rtl_trace.jsonl");
      $fatal(1);
    end
    #1;
    for (index = 0; index < 16384; index = index + 1) begin
      dut.instruction_memory[index] = 32'h0000_0013;
    end
    for (index = 0; index < 8192; index = index + 1) begin
      dut.data_memory[index] = '0;
    end
    $readmemh("sim/random_program.hex", dut.instruction_memory);

    @(posedge clk);
    #1;
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < MAX_CYCLES && commit_count < PROGRAM_LENGTH;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
      if (dut.core.commit_valid) begin
        if (dut.core.illegal_instruction || dut.core.commit_trap_valid) begin
          $display("FAIL random SoC trap: pc=%h illegal=%b trap=%b cause=%h",
                   dut.core.commit_pc, dut.core.illegal_instruction,
                   dut.core.commit_trap_valid, dut.core.commit_trap_cause);
          failures = failures + 1;
        end
        write_trace();
        commit_count = commit_count + 1;
      end
    end

    if (commit_count != PROGRAM_LENGTH) begin
      $display("FAIL random SoC timeout: commits=%0d cycles=%0d", commit_count, cycle_count);
      failures = failures + 1;
    end
    $fclose(trace_file);
    if (failures != 0) begin
      $display("SIM FAIL: %0d random SoC checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_bram_soc structured-random cache regression");
    $finish;
  end
endmodule
