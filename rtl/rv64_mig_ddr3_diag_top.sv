module rv64_mig_ddr3_diag_top (
  input  logic        clk_50,
  input  logic        reset_n,
  input  logic        sys_clk_p,
  input  logic        sys_clk_n,
  output logic [2:0]  led,
  inout  logic [71:0] ddr3_dq,
  inout  logic [8:0]  ddr3_dqs_n,
  inout  logic [8:0]  ddr3_dqs_p,
  output logic [14:0] ddr3_addr,
  output logic [2:0]  ddr3_ba,
  output logic        ddr3_ras_n,
  output logic        ddr3_cas_n,
  output logic        ddr3_we_n,
  output logic        ddr3_reset_n,
  output logic [0:0]  ddr3_ck_p,
  output logic [0:0]  ddr3_ck_n,
  output logic [0:0]  ddr3_cke,
  output logic [0:0]  ddr3_cs_n,
  output logic [0:0]  ddr3_odt
);
  logic ui_clk;
  logic ui_clk_sync_rst;
  logic init_calib_complete;
  logic [3:0] axi_awid;
  logic [30:0] axi_awaddr;
  logic [7:0] axi_awlen;
  logic [2:0] axi_awsize;
  logic [1:0] axi_awburst;
  logic axi_awvalid;
  logic axi_awready;
  logic [511:0] axi_wdata;
  logic [63:0] axi_wstrb;
  logic axi_wlast;
  logic axi_wvalid;
  logic axi_wready;
  logic [3:0] axi_bid;
  logic [1:0] axi_bresp;
  logic axi_bvalid;
  logic axi_bready;
  logic [3:0] axi_arid;
  logic [30:0] axi_araddr;
  logic [7:0] axi_arlen;
  logic [2:0] axi_arsize;
  logic [1:0] axi_arburst;
  logic axi_arvalid;
  logic axi_arready;
  logic [3:0] axi_rid;
  logic [511:0] axi_rdata;
  logic [1:0] axi_rresp;
  logic axi_rlast;
  logic axi_rvalid;
  logic axi_rready;
  logic request_valid;
  logic request_write;
  logic [63:0] request_address;
  logic [63:0] request_write_data;
  logic [7:0] request_write_strobe;
  logic request_ready;
  logic [63:0] response_read_data;
  logic response_error;
  logic diag_done;
  logic diag_failed;
  logic [1:0] diag_pattern_phase;
  logic [7:0] diag_word_index;
  logic [63:0] diag_expected_data;
  logic [63:0] diag_observed_data;
  logic reset;

  assign reset = !reset_n;
  assign led = {diag_failed, diag_done, init_calib_complete};

  rv64_ddr3_diag_controller diag (
    .clk(clk_50),
    .reset(reset),
    .init_calib_complete(init_calib_complete),
    .request_valid(request_valid),
    .request_write(request_write),
    .request_address(request_address),
    .request_write_data(request_write_data),
    .request_write_strobe(request_write_strobe),
    .request_ready(request_ready),
    .response_read_data(response_read_data),
    .response_error(response_error),
    .done(diag_done),
    .failed(diag_failed),
    .pattern_phase(diag_pattern_phase),
    .word_index(diag_word_index),
    .expected_data(diag_expected_data),
    .observed_data(diag_observed_data)
  );

  rv64_ddr3_mig_path ddr3_path (
    .cpu_clk(clk_50),
    .cpu_reset(reset),
    .cpu_request_valid(request_valid),
    .cpu_request_write(request_write),
    .cpu_request_address(request_address),
    .cpu_request_write_data(request_write_data),
    .cpu_request_write_strobe(request_write_strobe),
    .cpu_request_ready(request_ready),
    .cpu_response_read_data(response_read_data),
    .cpu_response_error(response_error),
    .ui_clk(ui_clk),
    .ui_reset(ui_clk_sync_rst),
    .init_calib_complete(init_calib_complete),
    .axi_awid(axi_awid), .axi_awaddr(axi_awaddr), .axi_awlen(axi_awlen),
    .axi_awsize(axi_awsize), .axi_awburst(axi_awburst), .axi_awvalid(axi_awvalid),
    .axi_awready(axi_awready), .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb),
    .axi_wlast(axi_wlast), .axi_wvalid(axi_wvalid), .axi_wready(axi_wready),
    .axi_bid(axi_bid), .axi_bresp(axi_bresp), .axi_bvalid(axi_bvalid), .axi_bready(axi_bready),
    .axi_arid(axi_arid), .axi_araddr(axi_araddr), .axi_arlen(axi_arlen),
    .axi_arsize(axi_arsize), .axi_arburst(axi_arburst), .axi_arvalid(axi_arvalid),
    .axi_arready(axi_arready), .axi_rid(axi_rid), .axi_rdata(axi_rdata),
    .axi_rresp(axi_rresp), .axi_rlast(axi_rlast), .axi_rvalid(axi_rvalid), .axi_rready(axi_rready)
  );

  rv64_mig_ch0 mig (
    .ddr3_dq(ddr3_dq), .ddr3_dqs_n(ddr3_dqs_n), .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_addr(ddr3_addr), .ddr3_ba(ddr3_ba), .ddr3_ras_n(ddr3_ras_n),
    .ddr3_cas_n(ddr3_cas_n), .ddr3_we_n(ddr3_we_n), .ddr3_reset_n(ddr3_reset_n),
    .ddr3_ck_p(ddr3_ck_p), .ddr3_ck_n(ddr3_ck_n), .ddr3_cke(ddr3_cke),
    .ddr3_cs_n(ddr3_cs_n), .ddr3_odt(ddr3_odt), .sys_clk_p(sys_clk_p), .sys_clk_n(sys_clk_n),
    .ui_clk(ui_clk), .ui_clk_sync_rst(ui_clk_sync_rst), .mmcm_locked(),
    .app_ecc_multiple_err(), .app_ecc_single_err(), .aresetn(!reset),
    .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
    .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
    .s_axi_awid(axi_awid), .s_axi_awaddr(axi_awaddr), .s_axi_awlen(axi_awlen),
    .s_axi_awsize(axi_awsize), .s_axi_awburst(axi_awburst), .s_axi_awlock(1'b0),
    .s_axi_awcache(4'b0), .s_axi_awprot(3'b0), .s_axi_awqos(4'b0),
    .s_axi_awvalid(axi_awvalid), .s_axi_awready(axi_awready), .s_axi_wdata(axi_wdata),
    .s_axi_wstrb(axi_wstrb), .s_axi_wlast(axi_wlast), .s_axi_wvalid(axi_wvalid), .s_axi_wready(axi_wready),
    .s_axi_bready(axi_bready), .s_axi_bid(axi_bid), .s_axi_bresp(axi_bresp), .s_axi_bvalid(axi_bvalid),
    .s_axi_arid(axi_arid), .s_axi_araddr(axi_araddr), .s_axi_arlen(axi_arlen),
    .s_axi_arsize(axi_arsize), .s_axi_arburst(axi_arburst), .s_axi_arlock(1'b0),
    .s_axi_arcache(4'b0), .s_axi_arprot(3'b0), .s_axi_arqos(4'b0),
    .s_axi_arvalid(axi_arvalid), .s_axi_arready(axi_arready), .s_axi_rready(axi_rready),
    .s_axi_rid(axi_rid), .s_axi_rdata(axi_rdata), .s_axi_rresp(axi_rresp),
    .s_axi_rlast(axi_rlast), .s_axi_rvalid(axi_rvalid),
    .s_axi_ctrl_awvalid(1'b0), .s_axi_ctrl_awready(), .s_axi_ctrl_awaddr(32'b0),
    .s_axi_ctrl_wvalid(1'b0), .s_axi_ctrl_wready(), .s_axi_ctrl_wdata(32'b0),
    .s_axi_ctrl_bvalid(), .s_axi_ctrl_bready(1'b0), .s_axi_ctrl_bresp(),
    .s_axi_ctrl_arvalid(1'b0), .s_axi_ctrl_arready(), .s_axi_ctrl_araddr(32'b0),
    .s_axi_ctrl_rvalid(), .s_axi_ctrl_rready(1'b0), .s_axi_ctrl_rdata(), .s_axi_ctrl_rresp(),
    .interrupt(), .init_calib_complete(init_calib_complete), .device_temp(), .sys_rst(reset_n)
  );
endmodule
