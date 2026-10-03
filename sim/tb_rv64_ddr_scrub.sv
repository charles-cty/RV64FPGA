`timescale 1ns/1ps
module ddr_scrub_case #(parameter bit INJECT_ERROR=0)(output logic done);
  logic clk=0, reset=1;
  always #5 clk=~clk;
  logic valid, wr, ready, error;
  logic [63:0] addr, wdata, rdata;
  logic [7:0] strobe;
  logic [63:0] memory[0:8207];
  logic [63:0] pending_addr, pending_data;
  logic [7:0] pending_strobe;
  logic pending_write;
  integer delay_left=-1, writes=0;
  rv64_bram_soc #(.USE_DDR3_EXTERNAL(1'b1)) dut (
    .clk(clk), .reset(reset), .uart_rx(1'b1), .led(), .uart_tx(),
    .console_rx_valid(1'b0), .console_rx_data(8'b0), .console_rx_ready(),
    .console_tx_valid(), .console_tx_data(), .console_tx_ready(1'b1),
    .external_ddr3_request_valid(valid), .external_ddr3_request_write(wr),
    .external_ddr3_request_address(addr), .external_ddr3_request_write_data(wdata),
    .external_ddr3_request_write_strobe(strobe), .external_ddr3_request_ready(ready),
    .external_ddr3_response_read_data(rdata), .external_ddr3_response_error(error)
  );
  assign ready = delay_left == 0;
  assign error = ready && pending_write && INJECT_ERROR;
  assign rdata = ready && !pending_write ? memory[(pending_addr-64'h80000000)>>3] : 0;
  always @(posedge clk) if (!reset) begin
    if (delay_left > 0) delay_left <= delay_left-1;
    if (valid && delay_left < 0) begin
      pending_addr <= addr; pending_data <= wdata;
      pending_strobe <= strobe; pending_write <= wr;
      delay_left <= 3;
      if (!wr && !(addr >= 64'h80000000 && addr < 64'h80000100)) begin
        $display("SIM FAIL: scrub read outside initialized code %h",addr); $finish;
      end
    end else if (ready) begin
      if (pending_write) begin
        if (pending_addr != 64'h80010000+8*writes || pending_strobe != 8'hff || pending_data != 0 || writes >= 16) begin
          $display("SIM FAIL: scrub sequence/address/data/strobe"); $finish;
        end
        if (!error) memory[(pending_addr-64'h80000000)>>3] <= pending_data;
        writes <= writes+1;
      end
      delay_left <= -1;
    end
  end
  initial begin
    done=0;
    for (integer i=0;i<8192;i=i+1) memory[i]=0;
    for (integer i=8192;i<8208;i=i+1) memory[i]='1;
    $readmemh("ddr-scrub-test.hex",memory,0,16);
    // The regular boot ROM jumps to the loaded program at PA 0x80000000.
    dut.instruction_memory[0]=32'h800002b7;
    dut.instruction_memory[1]=32'h02029293;
    dut.instruction_memory[2]=32'h0202d293;
    dut.instruction_memory[3]=32'h00028067;
    repeat(5) @(posedge clk);
    @(negedge clk) reset=0;
    for (integer cycles=0;cycles<100000;cycles=cycles+1) begin
      @(negedge clk);
      if (dut.commit_valid && dut.commit_pc == (INJECT_ERROR ? 64'h80000084 : 64'h80000080)) begin
        if (writes != (INJECT_ERROR ? 1 : 16)) begin
          $display("SIM FAIL: scrub wrong write count %0d",writes); $finish;
        end
        if (!INJECT_ERROR) for(integer i=8192;i<8208;i=i+1) if(memory[i]!==0) begin
          $display("SIM FAIL: scrub left nonzero memory"); $finish;
        end
        done=1;
        wait(0);
      end
    end
    $display("SIM FAIL: scrub timeout error_case=%b",INJECT_ERROR); $finish;
  end
endmodule
module tb_rv64_ddr_scrub;
  wire good_done, error_done;
  ddr_scrub_case good_case(good_done);
  ddr_scrub_case #(.INJECT_ERROR(1)) error_case(error_done);
  initial begin
    wait(good_done && error_done);
    $display("SIM PASS: DDR scrub writes each full ECC word; bus errors cannot signal completion");
    $finish;
  end
endmodule
