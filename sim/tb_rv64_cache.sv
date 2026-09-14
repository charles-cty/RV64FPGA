`timescale 1ns / 1ps

module tb_rv64_cache;
  logic clk;
  logic reset;
  logic request_valid;
  logic request_ready;
  logic request_write;
  logic [63:0] request_address;
  logic [63:0] request_write_data;
  logic [7:0] request_write_strobe;
  logic response_valid;
  logic [63:0] response_read_data;
  logic memory_valid;
  logic memory_ready;
  logic memory_write;
  logic [63:0] memory_address;
  logic [63:0] memory_write_data;
  logic [7:0] memory_write_strobe;
  logic [63:0] memory_read_data;
  logic [63:0] memory [0:63];
  integer failures;
  integer index;
  integer write_index;
  integer backend_reads;
  integer backend_writes;

  rv64_cache #(.LINE_COUNT(4)) dut (.*);
  always #5 clk = ~clk;

  always_comb begin
    memory_ready = memory_valid;
    memory_read_data = memory[memory_address[8:3]];
  end

  always @(posedge clk) begin
    if (memory_valid && memory_ready) begin
      if (memory_write) begin
        backend_writes <= backend_writes + 1;
        for (write_index = 0; write_index < 8; write_index = write_index + 1) begin
          if (memory_write_strobe[write_index]) begin
            memory[memory_address[8:3]][write_index*8 +: 8] <=
              memory_write_data[write_index*8 +: 8];
          end
        end
      end else begin
        backend_reads <= backend_reads + 1;
      end
    end
  end

  task automatic load(input logic [63:0] address, input logic [63:0] expected);
    begin
      while (!request_ready) @(negedge clk);
      request_address = address;
      request_write = 1'b0;
      request_valid = 1'b1;
      @(posedge clk);
      #1;
      request_valid = 1'b0;
      while (!response_valid) begin
        @(posedge clk);
        #1;
      end
      if (response_read_data !== expected) begin
        $display("FAIL load address=%h got=%h expected=%h", address, response_read_data, expected);
        failures = failures + 1;
      end
    end
  endtask

  task automatic store(input logic [63:0] address, input logic [63:0] value,
                       input logic [7:0] strobe);
    begin
      while (!request_ready) @(negedge clk);
      request_address = address;
      request_write = 1'b1;
      request_write_data = value;
      request_write_strobe = strobe;
      request_valid = 1'b1;
      @(posedge clk);
      #1;
      request_valid = 1'b0;
      while (!response_valid) begin
        @(posedge clk);
        #1;
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    request_valid = 1'b0;
    request_write = 1'b0;
    request_address = '0;
    request_write_data = '0;
    request_write_strobe = '0;
    failures = 0;
    backend_reads = 0;
    backend_writes = 0;
    for (index = 0; index < 64; index = index + 1) begin
      memory[index] = 64'h1000_0000_0000_0000 + index;
    end

    @(posedge clk);
    #1;
    reset = 1'b0;
    load(64'h0000_0000_0000_0018, memory[3]);
    if (backend_reads != 1) begin
      $display("FAIL initial read miss count=%0d", backend_reads);
      failures = failures + 1;
    end
    load(64'h0000_0000_0000_0018, memory[3]);
    if (backend_reads != 1) begin
      $display("FAIL read hit accessed backing memory count=%0d", backend_reads);
      failures = failures + 1;
    end
    store(64'h0000_0000_0000_0018, 64'hdead_beef_1122_3344, 8'hff);
    if (memory[3] !== 64'hdead_beef_1122_3344) begin
      $display("FAIL write-through memory got=%h", memory[3]);
      failures = failures + 1;
    end
    load(64'h0000_0000_0000_0018, 64'hdead_beef_1122_3344);
    store(64'h0000_0000_0000_0019, 64'h0000_0000_0000_aa00, 8'h02);
    if (memory[3] !== 64'hdead_beef_1122_aa44) begin
      $display("FAIL byte write memory got=%h", memory[3]);
      failures = failures + 1;
    end
    load(64'h0000_0000_0000_0018, 64'hdead_beef_1122_aa44);
    load(64'h0000_0000_0000_0038, memory[7]);
    load(64'h0000_0000_0000_0018, 64'hdead_beef_1122_aa44);
    store(64'h0000_0000_0000_0020, 64'h0123_4567_89ab_cdef, 8'hff);
    load(64'h0000_0000_0000_0020, 64'h0123_4567_89ab_cdef);
    if (backend_reads != 4) begin
      $display("FAIL conflict eviction read count=%0d", backend_reads);
      failures = failures + 1;
    end
    if (backend_writes != 3) begin
      $display("FAIL write-through count=%0d", backend_writes);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d cache checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_cache direct-mapped write-through regression");
    $finish;
  end
endmodule
