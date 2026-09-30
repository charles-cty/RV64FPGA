module rv64_mig_soc_top #(
  parameter string BOOT_ROM_INIT_FILE = ""
) (
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
  (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic init_calib_complete;
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
  logic cpu_request_valid;
  logic cpu_request_write;
  logic [63:0] cpu_request_address;
  logic [63:0] cpu_request_write_data;
  logic [7:0] cpu_request_write_strobe;
  logic cpu_request_ready;
  logic [63:0] cpu_response_read_data;
  logic cpu_response_error;
  logic memory_request_valid;
  logic memory_request_write;
  logic [63:0] memory_request_address;
  logic [63:0] memory_request_write_data;
  logic [7:0] memory_request_write_strobe;
  logic memory_request_ready;
  logic [63:0] memory_response_read_data;
  logic memory_response_error;
  logic jtag_cpu_hold_reset;
  logic jtag_memory_request_valid;
  logic jtag_memory_request_write;
  logic [63:0] jtag_memory_request_address;
  logic [63:0] jtag_memory_request_write_data;
  logic [7:0] jtag_memory_request_write_strobe;
  logic jtag_memory_request_ready;
  logic [63:0] jtag_memory_response_read_data;
  logic jtag_memory_response_error;
  logic jtag_axi_awvalid, jtag_axi_awready, jtag_axi_wvalid, jtag_axi_wready;
  logic jtag_axi_bvalid, jtag_axi_bready, jtag_axi_arvalid, jtag_axi_arready;
  logic jtag_axi_rvalid, jtag_axi_rready, jtag_axi_wlast, jtag_axi_rlast;
  logic [31:0] jtag_axi_awaddr, jtag_axi_wdata, jtag_axi_araddr, jtag_axi_rdata;
  logic [7:0] jtag_axi_awlen, jtag_axi_arlen;
  logic [3:0] jtag_axi_wstrb;
  logic [2:0] jtag_axi_awsize, jtag_axi_arsize;
  logic [1:0] jtag_axi_awburst, jtag_axi_arburst, jtag_axi_bresp, jtag_axi_rresp;
  logic reset;
  logic jtag_loader_reset;
  logic cpu_reset_async;
  (* ASYNC_REG = "TRUE" *) logic [1:0] cpu_reset_synchronizer = 2'b11;
  (* ASYNC_REG = "TRUE" *) logic [1:0] calibration_synchronizer = 2'b00;
  (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic cpu_reset = 1'b1;
  (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic uart_tx;
  logic debug_commit_valid;
  logic [63:0] debug_commit_pc;
  logic [31:0] debug_commit_instruction;
  logic debug_commit_trap_valid;
  logic [63:0] debug_commit_trap_cause;
  logic debug_illegal_instruction;
  logic [1:0] debug_privilege_mode;
  logic [63:0] debug_satp_value;
  logic [63:0] debug_instruction_address;
  logic debug_instruction_ready;
  logic debug_data_valid;
  logic [63:0] debug_data_address;
  (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [5:0] debug_status;
  (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [225:0] debug_commit_trace;
  (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [129:0] debug_memory_trace;

  assign reset = !reset_n;
  // Keep the ILA at five probes for the Vivado BASIC debug license.
  assign debug_status = {
    debug_illegal_instruction,
    debug_commit_trap_valid,
    debug_commit_valid,
    reset_n,
    jtag_cpu_hold_reset,
    init_calib_complete
  };
  assign debug_commit_trace = {
    debug_satp_value,
    debug_privilege_mode,
    debug_commit_trap_cause,
    debug_commit_instruction,
    debug_commit_pc
  };
  // Temporary MMU trace; layout archived beside this staged source.
  assign debug_memory_trace[129] = soc.data_valid;
  assign debug_memory_trace[128] = soc.data_fault;
  assign debug_memory_trace[127] = soc.data_translation_fault;
  assign debug_memory_trace[126] = soc.data_translation_fault_latched;
  assign debug_memory_trace[125] = soc.data_pte_ready;
  assign debug_memory_trace[124] = soc.data_pte_request;
  assign debug_memory_trace[123] = soc.data_pte_update_valid;
  assign debug_memory_trace[122] = soc.data_pte_write_pending;
  assign debug_memory_trace[121] = soc.pte_master_write_latched;
  assign debug_memory_trace[120] = soc.pte_master_active;
  assign debug_memory_trace[119] = soc.pte_master_owner;
  assign debug_memory_trace[118] = soc.pte_master_ready;
  assign debug_memory_trace[117] = soc.pte_master_response_error;
  assign debug_memory_trace[116] = soc.ddr3_model_error;
  assign debug_memory_trace[115] = soc.data_mmu.tlb_match_valid;
  assign debug_memory_trace[114] = soc.data_mmu.tlb_match_permission;
  assign debug_memory_trace[113] = soc.data_mmu_enabled;
  assign debug_memory_trace[112] = soc.instruction_ready;
  assign debug_memory_trace[111] = soc.data_translation_complete;
  assign debug_memory_trace[110] = soc.data_write;
  assign debug_memory_trace[109] = soc.data_ready;
  assign debug_memory_trace[108] = soc.data_translation_done;
  assign debug_memory_trace[107] = soc.sum_enable;
  assign debug_memory_trace[106] = soc.mxr_enable;
  assign debug_memory_trace[105:104] = soc.data_privilege;
  assign debug_memory_trace[103:102] = soc.data_mmu.request_privilege;
  assign debug_memory_trace[101:100] = soc.data_mmu.request_access;
  assign debug_memory_trace[99:98] = soc.data_mmu.level;
  assign debug_memory_trace[97] = soc.data_translation_ready;
  assign debug_memory_trace[96] = soc.atomic_access;
  assign debug_memory_trace[95:64] = soc.data_pte_address[31:0];
  assign debug_memory_trace[63:0] = soc.data_pte_read_data;
  rv64_startup_reset jtag_loader_startup_reset (
    .clk(clk_50),
    .external_reset(reset),
    .reset(jtag_loader_reset)
  );
  assign cpu_reset_async = reset || !init_calib_complete || jtag_cpu_hold_reset;
  always_ff @(posedge clk_50 or posedge cpu_reset_async) begin
    if (cpu_reset_async) begin
      cpu_reset_synchronizer <= 2'b11;
    end else begin
      cpu_reset_synchronizer <= {cpu_reset_synchronizer[0], 1'b0};
    end
  end

  always_ff @(posedge clk_50) begin
    cpu_reset <= cpu_reset_synchronizer[1];
  end

  always_ff @(posedge clk_50 or posedge reset) begin
    if (reset) begin
      calibration_synchronizer <= 2'b00;
    end else begin
      calibration_synchronizer <= {calibration_synchronizer[0], init_calib_complete};
    end
  end

  assign memory_request_valid = jtag_cpu_hold_reset ? jtag_memory_request_valid : cpu_request_valid;
  assign memory_request_write = jtag_cpu_hold_reset ? jtag_memory_request_write : cpu_request_write;
  assign memory_request_address = jtag_cpu_hold_reset ? jtag_memory_request_address : cpu_request_address;
  assign memory_request_write_data = jtag_cpu_hold_reset ? jtag_memory_request_write_data : cpu_request_write_data;
  assign memory_request_write_strobe = jtag_cpu_hold_reset ? jtag_memory_request_write_strobe : cpu_request_write_strobe;
  assign cpu_request_ready = !jtag_cpu_hold_reset && memory_request_ready;
  assign cpu_response_read_data = memory_response_read_data;
  assign cpu_response_error = !jtag_cpu_hold_reset && memory_request_ready && memory_response_error;
  assign jtag_memory_request_ready = jtag_cpu_hold_reset && memory_request_ready;
  assign jtag_memory_response_read_data = memory_response_read_data;
  assign jtag_memory_response_error = jtag_cpu_hold_reset && memory_request_ready && memory_response_error;

  rv64_bram_soc #(
    .USE_DDR3_EXTERNAL(1'b1),
    .BOOT_ROM_INIT_FILE(BOOT_ROM_INIT_FILE)
  ) soc (
    .clk(clk_50),
    .reset(cpu_reset),
    .led(led),
    .uart_tx(uart_tx),
    .uart_rx(1'b1),
    .debug_commit_valid(debug_commit_valid),
    .debug_commit_pc(debug_commit_pc),
    .debug_commit_instruction(debug_commit_instruction),
    .debug_commit_trap_valid(debug_commit_trap_valid),
    .debug_commit_trap_cause(debug_commit_trap_cause),
    .debug_illegal_instruction(debug_illegal_instruction),
    .debug_privilege_mode(debug_privilege_mode),
    .debug_satp_value(debug_satp_value),
    .debug_instruction_address(debug_instruction_address),
    .debug_instruction_ready(debug_instruction_ready),
    .debug_data_valid(debug_data_valid),
    .debug_data_address(debug_data_address),
    .external_ddr3_request_valid(cpu_request_valid),
    .external_ddr3_request_write(cpu_request_write),
    .external_ddr3_request_address(cpu_request_address),
    .external_ddr3_request_write_data(cpu_request_write_data),
    .external_ddr3_request_write_strobe(cpu_request_write_strobe),
    .external_ddr3_request_ready(cpu_request_ready),
    .external_ddr3_response_read_data(cpu_response_read_data),
    .external_ddr3_response_error(cpu_response_error)
  );

  rv64_ddr3_mig_path ddr3_path (
    .cpu_clk(clk_50),
    .cpu_reset(reset || !init_calib_complete),
    .cpu_request_valid(memory_request_valid),
    .cpu_request_write(memory_request_write),
    .cpu_request_address(memory_request_address),
    .cpu_request_write_data(memory_request_write_data),
    .cpu_request_write_strobe(memory_request_write_strobe),
    .cpu_request_ready(memory_request_ready),
    .cpu_response_read_data(memory_response_read_data),
    .cpu_response_error(memory_response_error),
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

  rv64_jtag_axi jtag_axi (
    .aclk(clk_50), .aresetn(!reset),
    .m_axi_awid(), .m_axi_awaddr(jtag_axi_awaddr), .m_axi_awlen(jtag_axi_awlen),
    .m_axi_awsize(jtag_axi_awsize), .m_axi_awburst(jtag_axi_awburst), .m_axi_awlock(),
    .m_axi_awcache(), .m_axi_awprot(), .m_axi_awqos(), .m_axi_awvalid(jtag_axi_awvalid),
    .m_axi_awready(jtag_axi_awready), .m_axi_wdata(jtag_axi_wdata), .m_axi_wstrb(jtag_axi_wstrb),
    .m_axi_wlast(jtag_axi_wlast), .m_axi_wvalid(jtag_axi_wvalid), .m_axi_wready(jtag_axi_wready),
    .m_axi_bid(1'b0), .m_axi_bresp(jtag_axi_bresp), .m_axi_bvalid(jtag_axi_bvalid),
    .m_axi_bready(jtag_axi_bready), .m_axi_arid(), .m_axi_araddr(jtag_axi_araddr),
    .m_axi_arlen(jtag_axi_arlen), .m_axi_arsize(jtag_axi_arsize), .m_axi_arburst(jtag_axi_arburst),
    .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arqos(), .m_axi_arvalid(jtag_axi_arvalid),
    .m_axi_arready(jtag_axi_arready), .m_axi_rid(1'b0), .m_axi_rdata(jtag_axi_rdata),
    .m_axi_rresp(jtag_axi_rresp), .m_axi_rlast(jtag_axi_rlast), .m_axi_rvalid(jtag_axi_rvalid),
    .m_axi_rready(jtag_axi_rready)
  );

  rv64_jtag_axi_loader jtag_loader (
    .clk(clk_50), .reset(jtag_loader_reset), .axi_awvalid(jtag_axi_awvalid), .axi_awready(jtag_axi_awready),
    .axi_awaddr(jtag_axi_awaddr), .axi_awlen(jtag_axi_awlen), .axi_awsize(jtag_axi_awsize),
    .axi_awburst(jtag_axi_awburst), .axi_wvalid(jtag_axi_wvalid), .axi_wready(jtag_axi_wready),
    .axi_wdata(jtag_axi_wdata), .axi_wstrb(jtag_axi_wstrb), .axi_wlast(jtag_axi_wlast),
    .axi_bvalid(jtag_axi_bvalid), .axi_bready(jtag_axi_bready), .axi_bresp(jtag_axi_bresp),
    .axi_arvalid(jtag_axi_arvalid), .axi_arready(jtag_axi_arready), .axi_araddr(jtag_axi_araddr),
    .axi_arlen(jtag_axi_arlen), .axi_arsize(jtag_axi_arsize), .axi_arburst(jtag_axi_arburst),
    .axi_rvalid(jtag_axi_rvalid), .axi_rready(jtag_axi_rready), .axi_rdata(jtag_axi_rdata),
    .axi_rresp(jtag_axi_rresp), .axi_rlast(jtag_axi_rlast), .cpu_hold_reset(jtag_cpu_hold_reset),
    .memory_available(calibration_synchronizer[1]),
    .memory_request_valid(jtag_memory_request_valid), .memory_request_write(jtag_memory_request_write),
    .memory_request_address(jtag_memory_request_address), .memory_request_write_data(jtag_memory_request_write_data),
    .memory_request_write_strobe(jtag_memory_request_write_strobe), .memory_request_ready(jtag_memory_request_ready),
    .memory_response_read_data(jtag_memory_response_read_data), .memory_response_error(jtag_memory_response_error)
  );

  rv64_debug_ila debug_ila (
    .clk(clk_50),
    .probe0(uart_tx),
    .probe1(cpu_reset),
    .probe2(debug_status),
    .probe3(debug_commit_trace),
    .probe4(debug_memory_trace)
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
