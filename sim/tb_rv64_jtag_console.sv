`timescale 1ns / 1ps
module tb_rv64_jtag_console;
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
  logic console_read, console_write, console_error;
  logic [4:0] console_address;
  logic [31:0] console_write_data, console_read_data;
  integer failures;


  logic request = 0, write = 0, ready, tx, rx = 1, interrupt;
  logic [11:0] address = 0;
  logic [63:0] write_data = 0, read_data;
  logic console_rx_valid, console_rx_ready, console_tx_valid, console_tx_ready;
  logic [7:0] console_rx_data, console_tx_data;
  rv64_jtag_axi_loader #(.CONSOLE_ENABLE(1)) dut (.*);
  rv64_jtag_console #(.RX_DEPTH(4), .TX_DEPTH(4), .LEASE_CYCLES(400)) fifo (
    .clk(clk), .reset(reset || cpu_hold_reset),
    .host_read(console_read), .host_write(console_write), .host_address(console_address),
    .host_write_data(console_write_data), .host_read_data(console_read_data), .host_error(console_error),
    .rx_valid(console_rx_valid), .rx_data(console_rx_data), .rx_ready(console_rx_ready),
    .tx_valid(console_tx_valid), .tx_data(console_tx_data), .tx_ready(console_tx_ready)
  );
  rv64_uart #(.BIT_CYCLES(2), .JTAG_CONSOLE(1)) uart (.*);
  always #5 clk = ~clk;
  always @(posedge clk) if (!reset && memory_request_valid) $fatal(1,"console touched DDR");
  initial begin #200000; $fatal(1,"timeout"); end
  task automatic check(input logic ok, input string message);
    if (ok !== 1'b1) $fatal(1,"%s",message);
  endtask
  task automatic wr(input logic [31:0] a, d, input logic [1:0] response = 0,
                    input logic [3:0] strobes = 15, input logic [7:0] len = 0);
    @(negedge clk);
    axi_awaddr=a; axi_awlen=len; axi_awsize=2; axi_awburst=1; axi_awvalid=1;
    do @(posedge clk); while (!axi_awready);
    @(negedge clk); axi_awvalid=0;
    axi_wdata=d; axi_wstrb=strobes; axi_wlast=1; axi_wvalid=1;
    do @(posedge clk); while (!axi_wready);
    @(negedge clk); axi_wvalid=0;
    wait(axi_bvalid); check(axi_bresp==response,"B response");
    repeat(3) @(negedge clk); // Backpressure must not enqueue repeatedly.
    axi_bready=1; @(negedge clk); axi_bready=0;
  endtask
  task automatic rd(input logic [31:0] a, expected, input logic [1:0] response = 0);
    @(negedge clk); axi_araddr=a; axi_arlen=0; axi_arsize=2; axi_arburst=1; axi_arvalid=1;
    do @(posedge clk); while (!axi_arready);
    @(negedge clk); axi_arvalid=0;
    wait(axi_rvalid);
    repeat(4) begin
      @(negedge clk); check((response != 0 || axi_rdata===expected) && axi_rresp==response && axi_rlast,"stable R response");
    end
    axi_rready=1; @(negedge clk); axi_rready=0;
  endtask
  task automatic uw(input logic [11:0] a, input logic [7:0] d);
    @(negedge clk); request=1; write=1; address=a; write_data=d;
    do @(posedge clk); while (!ready);
    @(negedge clk); request=0; write=0;
  endtask
  task automatic ur(input logic [7:0] expected);
    @(negedge clk); request=1; write=0; address=0;
    #1; check(read_data[7:0]===expected,"UART RBR order");
    @(negedge clk); request=0;
  endtask
  initial begin
    clk=0; reset=1; axi_awvalid=0; axi_wvalid=0; axi_arvalid=0;
    axi_bready=0; axi_rready=0; axi_awaddr=0; axi_awlen=0; axi_awsize=2; axi_awburst=1;
    axi_wdata=0; axi_wstrb=15; axi_wlast=1; axi_araddr=0; axi_arlen=0; axi_arsize=2; axi_arburst=1;
    memory_available=1; memory_request_ready=0; memory_response_error=0; memory_response_read_data=0;
    repeat(3) @(negedge clk); reset=0;
    rd('h7ffffe00,'h4a544331);
    wr('h7ffffe0c,65,2); // held CPU cannot accept queued input
    wr('h7fffff00,0); check(!cpu_hold_reset,"release");
    wr('h80000000,0,2); // running CPU still owns DDR
    rd('h80000000,0,2);
    wr('h7ffffe00,1,2); // read-only ID
    wr('h7ffffe0c,65,2,1); // invalid strobes, no enqueue
    wr('h7ffffe0c,65,2,15,1); // no FIFO bursts
    rd('h7ffffe04,4);
    wr('h7ffffe0c,0); wr('h7ffffe0c,255); wr('h7ffffe0c,65); wr('h7ffffe0c,66);
    rd('h7ffffe04,0); wr('h7ffffe0c,99,2);
    uw(3,128); uw(0,7); ur(7); // DLAB read/write must not touch queues
    rd('h7ffffe04,0); uw(3,3);
    ur(0); ur(255); ur(65); ur(66); rd('h7ffffe04,4);
    // Concurrent host push and CPU pop preserve the new byte and occupancy.
    wr('h7ffffe0c,70);
    fork
      begin wr('h7ffffe0c,71); end
      begin
        wait(console_write); request=1; write=0; address=0;
        #1; check(read_data[7:0]==70,"concurrent RX pop");
        @(negedge clk); request=0;
      end
    join
    rd('h7ffffe04,3); ur(71); rd('h7ffffe04,4);
    wr('h7ffffe14,1);
    uw(0,65); uw(0,66); uw(0,67); uw(0,68);
    rd('h7ffffe08,4);
    // Full attached TX blocks a fifth byte, then a host pop releases it.
    fork
      begin uw(0,69); end
      begin
        repeat(30) @(negedge clk); check(!ready,"TX backpressure");
        rd('h7ffffe0c,'h80000041);
      end
    join
    rd('h7ffffe08,4); rd('h7ffffe0c,'h80000042); rd('h7ffffe0c,'h80000043);
    rd('h7ffffe0c,'h80000044); rd('h7ffffe0c,'h80000045); rd('h7ffffe0c,0);
    wr('h7ffffe14,0);
    uw(0,1); uw(0,2); uw(0,3); uw(0,4); uw(0,5); rd('h7ffffe10,1);
    wr('h7ffffe14,1);
    repeat(420) @(negedge clk); rd('h7ffffe14,0); // lost-host lease
    uw(0,6); rd('h7ffffe10,2);
    check(!cpu_hold_reset,"console did not reset CPU");
    wr('h7fffff00,1); rd('h7ffffe08,0); rd('h7ffffe10,0);
    $display("SIM PASS: live JTAG console UART FIFO and loader isolation"); $finish;
  end
endmodule
