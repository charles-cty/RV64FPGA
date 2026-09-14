module rv64_regfile (
  input  logic        clk,
  input  logic        reset,
  input  logic        write_enable,
  input  logic [4:0]  write_address,
  input  logic [63:0] write_data,
  input  logic [4:0]  read_address_a,
  input  logic [4:0]  read_address_b,
  output logic [63:0] read_data_a,
  output logic [63:0] read_data_b
);
  logic [63:0] registers [0:31];
  integer index;

  always_ff @(posedge clk) begin
    if (reset) begin
      for (index = 0; index < 32; index = index + 1) begin
        registers[index] <= '0;
      end
    end else if (write_enable && (write_address != 5'd0)) begin
      registers[write_address] <= write_data;
    end
  end

  always_comb begin
    read_data_a = (read_address_a == 5'd0) ? '0 : registers[read_address_a];
    read_data_b = (read_address_b == 5'd0) ? '0 : registers[read_address_b];
  end
endmodule
