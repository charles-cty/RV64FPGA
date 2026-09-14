module rv64_bram_soc (
  input  logic        clk,
  input  logic        reset,
  output logic [2:0]  led
);
  localparam logic [63:0] LED_ADDRESS = 64'h0000_0000_1000_1000;

  logic [31:0] instruction_memory [0:16383];
  logic [63:0] data_memory [0:8191];
  logic [63:0] instruction_address;
  logic [31:0] instruction_data;
  logic        data_valid;
  logic        data_write;
  logic [63:0] data_address;
  logic [63:0] data_write_data;
  logic [7:0]  data_write_strobe;
  logic [63:0] data_read_data;
  logic        data_ready;
  logic        commit_valid;
  logic [63:0] commit_pc;
  logic [31:0] commit_instruction;
  logic [63:0] commit_next_pc;
  logic        commit_rd_write;
  logic [4:0]  commit_rd;
  logic [63:0] commit_rd_value;
  logic        commit_csr_write;
  logic [11:0] commit_csr_address;
  logic [63:0] commit_csr_value;
  logic        commit_trap_valid;
  logic [63:0] commit_trap_cause;
  logic        illegal_instruction;
  integer index;
  integer byte_index;

  rv64_core core (.*);

  assign instruction_data = instruction_memory[instruction_address[15:2]];
  assign data_ready = 1'b1;

  always_comb begin
    if (data_address == LED_ADDRESS) begin
      data_read_data = {61'b0, led};
    end else begin
      data_read_data = data_memory[data_address[15:3]];
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      led <= 3'b0;
    end else if (data_valid && data_write) begin
      if (data_address == LED_ADDRESS) begin
        if (data_write_strobe[0]) begin
          led <= data_write_data[2:0];
        end
      end else begin
        for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
          if (data_write_strobe[byte_index]) begin
            data_memory[data_address[15:3]][byte_index*8 +: 8] <= data_write_data[byte_index*8 +: 8];
          end
        end
      end
    end
  end

  initial begin
    for (index = 0; index < 16384; index = index + 1) begin
      instruction_memory[index] = 32'h0000_0013;
    end
    for (index = 0; index < 8192; index = index + 1) begin
      data_memory[index] = 64'b0;
    end
  end
endmodule
