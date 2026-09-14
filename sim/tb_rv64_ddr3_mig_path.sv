`timescale 1ns / 1ps

module tb_rv64_ddr3_mig_path;
  logic cpu_clk, cpu_reset, cpu_request_valid, cpu_request_write, cpu_request_ready, cpu_response_error;
  logic [63:0] cpu_request_address, cpu_request_write_data, cpu_response_read_data;
  logic [7:0] cpu_request_write_strobe;
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

  rv64_ddr3_mig_path dut (.*);
  always #5 cpu_clk = ~cpu_clk;
  always #3.5 ui_clk = ~ui_clk;

  task automatic check_condition(input logic condition, input [511:0] message);
    begin
      if (!condition) begin
        $display("FAIL %0s", message);
        failures = failures + 1;
      end
    end
  endtask

  task automatic finish_cpu_request(input logic expected_error, input logic [63:0] expected_data);
    begin
      while (!cpu_request_ready) begin
        @(posedge cpu_clk);
        #1;
      end
      check_condition(cpu_response_error === expected_error, "CPU receives AXI/calibration error");
      if (!expected_error && !cpu_request_write) begin
        check_condition(cpu_response_read_data === expected_data, "CPU receives selected AXI read lane");
      end
      @(posedge cpu_clk);
      #1;
      cpu_request_valid = 1'b0;
      @(posedge cpu_clk);
      #1;
    end
  endtask

  initial begin
    cpu_clk = 1'b0;
    ui_clk = 1'b0;
    cpu_reset = 1'b1;
    ui_reset = 1'b1;
    init_calib_complete = 1'b1;
    cpu_request_valid = 1'b0;
    cpu_request_write = 1'b0;
    cpu_request_address = '0;
    cpu_request_write_data = '0;
    cpu_request_write_strobe = '0;
    axi_awready = 1'b0;
    axi_wready = 1'b0;
    axi_bid = '0;
    axi_bresp = '0;
    axi_bvalid = 1'b0;
    axi_arready = 1'b0;
    axi_rid = '0;
    axi_rdata = '0;
    axi_rresp = '0;
    axi_rlast = 1'b0;
    axi_rvalid = 1'b0;
    failures = 0;

    @(posedge cpu_clk);
    #1;
    cpu_reset = 1'b0;
    @(posedge ui_clk);
    #1;
    ui_reset = 1'b0;

    cpu_request_valid = 1'b1;
    cpu_request_write = 1'b0;
    cpu_request_address = 64'h8000_0020;
    cpu_request_write_data = '0;
    cpu_request_write_strobe = '0;
    @(posedge cpu_clk);
    #1;
    while (!axi_arvalid) begin
      @(posedge ui_clk);
      #1;
    end
    check_condition(axi_araddr == 31'd0 && axi_arsize == 3'd6 && axi_arlen == 0,
                    "combined path creates aligned MIG read");
    axi_arready = 1'b1;
    @(posedge ui_clk);
    #1;
    axi_arready = 1'b0;
    while (!axi_rready) begin
      @(posedge ui_clk);
      #1;
    end
    axi_rdata = {192'b0, 64'h1122_3344_5566_7788, 256'b0};
    axi_rid = '0;
    axi_rresp = 2'b00;
    axi_rlast = 1'b1;
    axi_rvalid = 1'b1;
    @(posedge ui_clk);
    #1;
    axi_rvalid = 1'b0;
    finish_cpu_request(1'b0, 64'h1122_3344_5566_7788);

    cpu_request_valid = 1'b1;
    cpu_request_write = 1'b1;
    cpu_request_address = 64'h8000_0038;
    cpu_request_write_data = 64'hfeed_face_cafe_babe;
    cpu_request_write_strobe = 8'h81;
    @(posedge cpu_clk);
    #1;
    while (!axi_awvalid) begin
      @(posedge ui_clk);
      #1;
    end
    axi_awready = 1'b1;
    @(posedge ui_clk);
    #1;
    axi_awready = 1'b0;
    while (!axi_wvalid) begin
      @(posedge ui_clk);
      #1;
    end
    check_condition(axi_wdata[7*64 +: 64] == 64'hfeed_face_cafe_babe &&
                    axi_wstrb == (64'h81 << 56), "combined path places write in lane seven");
    axi_wready = 1'b1;
    @(posedge ui_clk);
    #1;
    axi_wready = 1'b0;
    while (!axi_bready) begin
      @(posedge ui_clk);
      #1;
    end
    axi_bresp = 2'b10;
    axi_bvalid = 1'b1;
    @(posedge ui_clk);
    #1;
    axi_bvalid = 1'b0;
    finish_cpu_request(1'b1, '0);

    init_calib_complete = 1'b0;
    cpu_request_valid = 1'b1;
    cpu_request_write = 1'b0;
    cpu_request_address = 64'h8000_0000;
    cpu_request_write_data = '0;
    cpu_request_write_strobe = '0;
    @(posedge cpu_clk);
    #1;
    finish_cpu_request(1'b1, '0);
    check_condition(!axi_awvalid && !axi_arvalid, "uncalibrated combined path emits no AXI transaction");

    if (failures != 0) $fatal(1, "SIM FAIL: %0d DDR3 path checks failed", failures);
    $display("SIM PASS: rv64_ddr3_mig_path integration regression");
    $finish;
  end
endmodule
