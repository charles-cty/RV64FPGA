`timescale 1ns / 1ps

module tb_rv64_jtag_axi_loader;
  logic clk, reset, axi_awvalid, axi_awready, axi_wvalid, axi_wready, axi_wlast;
  logic axi_bvalid, axi_bready, axi_arvalid, axi_arready, axi_rvalid, axi_rready, axi_rlast;
  logic [31:0] axi_awaddr, axi_wdata, axi_araddr, axi_rdata;
  logic [7:0] axi_awlen, axi_arlen;
  logic [3:0] axi_wstrb;
  logic [2:0] axi_awsize, axi_arsize;
  logic [1:0] axi_awburst, axi_arburst, axi_bresp, axi_rresp;
  logic cpu_hold_reset, memory_available, memory_request_valid, memory_request_write, memory_request_ready, memory_response_error;
  logic [63:0] memory_request_address, memory_request_write_data, memory_response_read_data;
  logic [7:0] memory_request_write_strobe;
  logic [63:0] last_address, last_write_data;
  logic [7:0] last_write_strobe;
  integer failures;

  rv64_jtag_axi_loader dut (.*);
  always #5 clk = ~clk;

  always_ff @(posedge clk) begin
    if (reset) begin
      memory_request_ready <= 1'b0;
      last_address <= '0;
      last_write_data <= '0;
      last_write_strobe <= '0;
    end else begin
      memory_request_ready <= memory_request_valid;
      if (memory_request_valid) begin
        last_address <= memory_request_address;
        last_write_data <= memory_request_write_data;
        last_write_strobe <= memory_request_write_strobe;
      end
    end
  end

  task automatic check(input logic condition, input [511:0] message);
    if (!condition) begin
      $display("FAIL %0s", message);
      failures = failures + 1;
    end
  endtask

  task automatic write32(input logic [31:0] address, input logic [31:0] data, input logic [7:0] length, input logic [1:0] expected_response);
    begin
      axi_awaddr = address; axi_awlen = length; axi_awsize = 3'd2; axi_awburst = 2'b01; axi_awvalid = 1'b1;
      while (!axi_awready) @(posedge clk);
      @(posedge clk); axi_awvalid = 1'b0;
      axi_wdata = data; axi_wstrb = 4'hf; axi_wlast = 1'b1; axi_wvalid = 1'b1;
      while (!axi_wready) @(posedge clk);
      @(posedge clk); axi_wvalid = 1'b0;
      while (!axi_bvalid) @(posedge clk);
      check(axi_bresp == expected_response, "write response");
      axi_bready = 1'b1; @(posedge clk); axi_bready = 1'b0;
    end
  endtask

  task automatic read32(input logic [31:0] address, input logic [31:0] expected_data, input logic [1:0] expected_response);
    begin
      axi_araddr = address; axi_arlen = 0; axi_arsize = 3'd2; axi_arburst = 2'b01; axi_arvalid = 1'b1;
      while (!axi_arready) @(posedge clk);
      @(posedge clk); axi_arvalid = 1'b0;
      while (!axi_rvalid) @(posedge clk);
      check(axi_rdata == expected_data && axi_rresp == expected_response && axi_rlast, "read response");
      axi_rready = 1'b1; @(posedge clk); axi_rready = 1'b0;
    end
  endtask

  task automatic write_burst2(input logic [31:0] address, input logic [31:0] first_data, input logic [31:0] second_data);
    begin
      axi_awaddr = address; axi_awlen = 1; axi_awsize = 3'd2; axi_awburst = 2'b01; axi_awvalid = 1'b1;
      while (!axi_awready) @(posedge clk);
      @(posedge clk); axi_awvalid = 1'b0;
      axi_wdata = first_data; axi_wstrb = 4'hf; axi_wlast = 1'b0; axi_wvalid = 1'b1;
      while (!axi_wready) @(posedge clk);
      @(posedge clk);
      axi_wdata = second_data; axi_wlast = 1'b1;
      while (!axi_wready) @(posedge clk);
      @(posedge clk); axi_wvalid = 1'b0;
      while (!axi_bvalid) @(posedge clk);
      check(axi_bresp == 2'b00, "burst write response");
      axi_bready = 1'b1; @(posedge clk); axi_bready = 1'b0;
    end
  endtask

  task automatic read_burst2(input logic [31:0] address, input logic [31:0] first_data, input logic [31:0] second_data);
    begin
      axi_araddr = address; axi_arlen = 1; axi_arsize = 3'd2; axi_arburst = 2'b01; axi_arvalid = 1'b1;
      while (!axi_arready) @(posedge clk);
      @(posedge clk); axi_arvalid = 1'b0;
      while (!axi_rvalid) @(posedge clk);
      check(axi_rdata == first_data && axi_rresp == 2'b00 && !axi_rlast, "first burst read response");
      axi_rready = 1'b1; @(posedge clk); axi_rready = 1'b0;
      while (!axi_rvalid) @(posedge clk);
      check(axi_rdata == second_data && axi_rresp == 2'b00 && axi_rlast, "second burst read response");
      axi_rready = 1'b1; @(posedge clk); axi_rready = 1'b0;
    end
  endtask

  task automatic write_burst256(input logic [31:0] address);
    integer word_index;
    begin
      axi_awaddr = address; axi_awlen = 8'hff; axi_awsize = 3'd2; axi_awburst = 2'b01; axi_awvalid = 1'b1;
      while (!axi_awready) @(posedge clk);
      @(posedge clk); axi_awvalid = 1'b0;
      axi_wvalid = 1'b1;
      for (word_index = 0; word_index < 256; word_index = word_index + 1) begin
        axi_wdata = 32'h4000_0000 + word_index;
        axi_wstrb = 4'hf;
        axi_wlast = word_index == 255;
        while (!axi_wready) @(posedge clk);
        @(posedge clk);
      end
      axi_wvalid = 1'b0;
      while (!axi_bvalid) @(posedge clk);
      check(axi_bresp == 2'b00, "256-word burst write response");
      axi_bready = 1'b1; @(posedge clk); axi_bready = 1'b0;
    end
  endtask

  initial begin
    clk = 0; reset = 1; axi_awvalid = 0; axi_wvalid = 0; axi_bready = 0; axi_arvalid = 0; axi_rready = 0;
    axi_awaddr = 0; axi_awlen = 0; axi_awsize = 0; axi_awburst = 0; axi_wdata = 0; axi_wstrb = 0; axi_wlast = 0;
    axi_araddr = 0; axi_arlen = 0; axi_arsize = 0; axi_arburst = 0;
    memory_available = 0; memory_response_read_data = 64'h1122_3344_aabb_ccdd; memory_response_error = 0; failures = 0;
    repeat (2) @(posedge clk);
    reset = 0;
    read32(32'h7fff_ff00, 32'h0000_0001, 2'b00);
    write32(32'h8000_0000, 32'hffff_ffff, 0, 2'b10);
    memory_available = 1'b1;
    read32(32'h7fff_ff00, 32'h0000_0003, 2'b00);
    memory_response_error = 1'b1;
    write32(32'h8000_0000, 32'h0000_0000, 0, 2'b10);
    memory_response_error = 1'b0;
    write32(32'h8000_0000, 32'hdead_beef, 0, 2'b00);
    check(last_address == 64'h8000_0000 && last_write_data == 64'h0000_0000_dead_beef && last_write_strobe == 8'h0f, "low DDR3 lane mapping");
    write32(32'h8000_0004, 32'hcafe_babe, 0, 2'b00);
    check(last_write_data == 64'hcafe_babe_0000_0000 && last_write_strobe == 8'hf0, "high DDR3 lane mapping");
    read32(32'h8000_0004, 32'h1122_3344, 2'b00);
    write_burst2(32'h8000_0008, 32'h1020_3040, 32'h5566_7788);
    check(last_address == 64'h8000_0008 && last_write_data == 64'h5566_7788_0000_0000 && last_write_strobe == 8'hf0, "burst DDR3 lane mapping");
    read_burst2(32'h8000_0008, 32'haabb_ccdd, 32'h1122_3344);
    write_burst256(32'h8000_0100);
    check(last_address == 64'h8000_04f8 && last_write_data == 64'h4000_00ff_0000_0000 && last_write_strobe == 8'hf0, "256-word burst final lane mapping");
    write32(32'h8000_0008, 32'h1234_5678, 1, 2'b10);
    write32(32'h7fff_ff00, 0, 0, 2'b00);
    check(!cpu_hold_reset, "control release clears CPU hold");
    write32(32'h8000_0000, 0, 0, 2'b10);
    write32(32'h7fff_ff00, 1, 0, 2'b00);
    read32(32'h7fff_ff00, 32'h0000_0003, 2'b00);
    if (failures != 0) $fatal(1, "SIM FAIL: %0d JTAG loader checks failed", failures);
    $display("SIM PASS: rv64_jtag_axi_loader regression");
    $finish;
  end
endmodule
