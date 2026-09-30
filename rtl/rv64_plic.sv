module rv64_plic (
  input  logic        clk,
  input  logic        reset,
  input  logic [31:0] interrupt_sources,
  input  logic        request,
  input  logic        write,
  input  logic [21:0] address,
  input  logic [63:0] write_data,
  output logic [63:0] read_data,
  output logic        ready,
  output logic        external_interrupt
);
  logic [2:0] priorities [1:31];
  logic [31:0] pending;
  logic [31:0] enable;
  logic [2:0] threshold;
  logic [5:0] claim_id;
  logic [2:0] highest_priority;
  integer claim_index;
  integer reset_index;

  assign ready = request;
  assign external_interrupt = (claim_id != 0);

  always_comb begin
    claim_id = 6'd0;
    highest_priority = 3'd0;
    for (claim_index = 1; claim_index <= 31; claim_index = claim_index + 1) begin
      if (pending[claim_index] && enable[claim_index] &&
          (priorities[claim_index] > threshold) &&
          (priorities[claim_index] > highest_priority)) begin
        highest_priority = priorities[claim_index];
        claim_id = claim_index[5:0];
      end
    end
  end

  always_comb begin
    read_data = '0;
    if ((address >= 22'h000004) && (address < 22'h000080) && (address[1:0] == 2'b00)) begin
        read_data = {61'b0, priorities[address[6:2]]};
    end else begin
      unique case (address)
        22'h001000: read_data = {32'b0, pending};
        22'h002000: read_data = {32'b0, enable};
        22'h200000, 22'h201000: read_data = {61'b0, threshold};
        22'h200004, 22'h201004: read_data = {58'b0, claim_id};
        default: read_data = '0;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      pending <= '0;
      enable <= '0;
      threshold <= '0;
      for (reset_index = 1; reset_index < 32; reset_index = reset_index + 1) begin
        priorities[reset_index] <= '0;
      end
    end else begin
      pending[31:1] <= pending[31:1] | interrupt_sources[31:1];
      if (request && write) begin
        if ((address >= 22'h000004) && (address < 22'h000080) && (address[1:0] == 2'b00)) begin
          priorities[address[6:2]] <= write_data[2:0];
        end else begin
          unique case (address)
            22'h002000: enable <= write_data[31:0];
            22'h200000, 22'h201000: threshold <= write_data[2:0];
            22'h200004, 22'h201004: if (write_data[5:0] != 0) pending[write_data[5:0]] <= 1'b0;
            default: ;
          endcase
        end
      end else if (request && !write &&
                   ((address == 22'h200004) || (address == 22'h201004)) &&
                   (claim_id != 0)) begin
        pending[claim_id] <= 1'b0;
      end
    end
  end
endmodule
