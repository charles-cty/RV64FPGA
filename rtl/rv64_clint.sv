module rv64_clint (
  input  logic        clk,
  input  logic        reset,
  input  logic        request,
  input  logic        write,
  input  logic [15:0] address,
  input  logic [63:0] write_data,
  input  logic [7:0]  write_strobe,
  output logic [63:0] read_data,
  output logic        ready,
  output logic        timer_interrupt,
  output logic        software_interrupt
);
  logic [63:0] mtime;
  logic [63:0] mtimecmp;
  logic        msip;
  // Sticky first-write diagnostics. These are intentionally retained until
  // reset so an ILA capture taken much later can prove whether firmware ever
  // programmed the timer comparator.
  logic        mtimecmp_write_seen;
  logic [15:0] mtimecmp_write_address;
  logic [63:0] mtimecmp_write_data;
  logic [7:0]  mtimecmp_write_strobe;
  integer index;

  assign ready = request;
  assign timer_interrupt = mtime >= mtimecmp;
  assign software_interrupt = msip;

  always_comb begin
    read_data = '0;
    unique case (address)
      16'h0000: read_data = {63'b0, msip};
      16'h4000: read_data = mtimecmp;
      16'hBFF8: read_data = mtime;
      default: read_data = '0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      mtime <= '0;
      mtimecmp <= 64'hffff_ffff_ffff_ffff;
      msip <= 1'b0;
      mtimecmp_write_seen <= 1'b0;
      mtimecmp_write_address <= '0;
      mtimecmp_write_data <= '0;
      mtimecmp_write_strobe <= '0;
    end else begin
      mtime <= mtime + 64'd1;
      if (request && write) begin
        if (address == 16'h4000 && !mtimecmp_write_seen) begin
          mtimecmp_write_seen <= 1'b1;
          mtimecmp_write_address <= address;
          mtimecmp_write_data <= write_data;
          mtimecmp_write_strobe <= write_strobe;
        end
        unique case (address)
          16'h0000: if (write_strobe[0]) msip <= write_data[0];
          16'h4000: begin
            for (index = 0; index < 8; index = index + 1) begin
              if (write_strobe[index]) mtimecmp[index*8 +: 8] <= write_data[index*8 +: 8];
            end
          end
          default: ;
        endcase
      end
    end
  end
endmodule
