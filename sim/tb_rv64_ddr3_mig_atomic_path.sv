`timescale 1ns / 1ps

module tb_rv64_ddr3_mig_atomic_path;
  import riscv_pkg::*;
  logic cpu_clk, cpu_reset, request_valid, request_word_operation;
  logic [63:0] request_address, request_source_data, response_read_data;
  atomic_op_t request_operation;
  logic request_ready, response_error;
  logic ui_clk, ui_reset, init_calib_complete;
  logic [3:0] axi_awid, axi_bid, axi_arid, axi_rid;
  logic [30:0] axi_awaddr, axi_araddr;
  logic [7:0] axi_awlen, axi_arlen;
  logic [2:0] axi_awsize, axi_arsize;
  logic [1:0] axi_awburst, axi_bresp, axi_arburst, axi_rresp;
  logic axi_awvalid, axi_awready, axi_wlast, axi_wvalid, axi_wready, axi_bvalid, axi_bready;
  logic axi_arvalid, axi_arready, axi_rlast, axi_rvalid, axi_rready;
  logic [511:0] axi_wdata, axi_rdata;
  logic [63:0] axi_wstrb;
  integer failures;


  rv64_ddr3_mig_atomic_path dut (.*);
  always #5 cpu_clk = ~cpu_clk;
  always #3.5 ui_clk = ~ui_clk;

  task automatic check(input logic condition, input [511:0] message);
    if (!condition) begin $display("FAIL %0s", message); failures = failures + 1; end
  endtask

  task automatic drive_read(input logic [63:0] value);
    begin
      while (!axi_arvalid) begin @(posedge ui_clk); #1; end
      axi_arready = 1'b1; @(posedge ui_clk); #1; axi_arready = 1'b0;
      while (!axi_rready) begin @(posedge ui_clk); #1; end
      axi_rdata = value << (request_address[5:3] * 64);
      axi_rid = '0; axi_rresp = 2'b00; axi_rlast = 1'b1; axi_rvalid = 1'b1;
      @(posedge ui_clk); #1; axi_rvalid = 1'b0; axi_rlast = 1'b0;
    end
  endtask

  task automatic drive_write(input logic [63:0] expected_write_data);
    begin
      while (!axi_awvalid) begin @(posedge ui_clk); #1; end
      axi_awready = 1'b1; @(posedge ui_clk); #1; axi_awready = 1'b0;
      while (!axi_wvalid) begin @(posedge ui_clk); #1; end
      check(axi_wdata[request_address[5:3] * 64 +: 64] === expected_write_data,
            "atomic write data");
      axi_wready = 1'b1; @(posedge ui_clk); #1; axi_wready = 1'b0;
      while (!axi_bready) begin @(posedge ui_clk); #1; end
      axi_bid = '0; axi_bresp = 2'b00; axi_bvalid = 1'b1;
      @(posedge ui_clk); #1; axi_bvalid = 1'b0;
    end
  endtask

  task automatic finish_request(input logic [63:0] expected, input logic expected_error);
    begin
      while (!request_ready) begin @(posedge cpu_clk); #1; end
      check(response_error === expected_error, "atomic response error");
      check(response_read_data === expected, "atomic response value");
      @(posedge cpu_clk); #1; request_valid = 1'b0;
      @(posedge cpu_clk); #1;
    end
  endtask

  initial begin
    cpu_clk = 1'b0; ui_clk = 1'b0; cpu_reset = 1'b1; ui_reset = 1'b1;
    init_calib_complete = 1'b1; request_valid = 1'b0; request_operation = ATOMIC_LR;
    request_word_operation = 1'b0; request_address = '0; request_source_data = '0;
    axi_awready = 1'b0; axi_wready = 1'b0; axi_bid = '0; axi_bresp = '0; axi_bvalid = 1'b0;
    axi_arready = 1'b0; axi_rid = '0; axi_rdata = '0; axi_rresp = '0; axi_rlast = 1'b0; axi_rvalid = 1'b0;
    failures = 0;
    @(posedge cpu_clk); #1; cpu_reset = 1'b0;
    @(posedge ui_clk); #1; ui_reset = 1'b0;

    request_valid = 1'b1; request_operation = ATOMIC_LR; request_address = 64'h8000_0000;
    fork drive_read(64'd7); join
    finish_request(64'd7, 1'b0);

    request_valid = 1'b1; request_operation = ATOMIC_SC; request_source_data = 64'd9;
    fork drive_read(64'd7); join
    fork drive_write(64'd9); join
    finish_request(64'd0, 1'b0);

    request_valid = 1'b1; request_operation = ATOMIC_ADD; request_source_data = 64'd3;
    fork drive_read(64'd9); join
    fork drive_write(64'd12); join
    finish_request(64'd9, 1'b0);

    request_valid = 1'b1; request_operation = ATOMIC_SC; request_address = 64'h8000_0008;
    finish_request(64'd1, 1'b0);
    check(!axi_arvalid && !axi_awvalid, "failed SC emits no AXI transaction");

    init_calib_complete = 1'b0;
    request_valid = 1'b1; request_operation = ATOMIC_LR; request_address = 64'h8000_0000;
    finish_request('0, 1'b1);
    check(!axi_arvalid && !axi_awvalid, "uncalibrated LR emits no AXI transaction");

    if (failures != 0) $fatal(1, "SIM FAIL: %0d MIG atomic checks failed", failures);
    $display("SIM PASS: rv64_ddr3_mig_atomic_path LR/SC/AMO");
    $finish;
  end
endmodule
