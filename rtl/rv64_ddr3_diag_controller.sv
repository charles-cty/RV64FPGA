module rv64_ddr3_diag_controller #(
  parameter logic [63:0] DDR_BASE_ADDRESS = 64'h0000_0000_8000_0000,
  parameter integer TEST_WORD_COUNT = 256
) (
  input  logic        clk,
  input  logic        reset,
  input  logic        init_calib_complete,
  output logic        request_valid,
  output logic        request_write,
  output logic [63:0] request_address,
  output logic [63:0] request_write_data,
  output logic [7:0]  request_write_strobe,
  input  logic        request_ready,
  input  logic [63:0] response_read_data,
  input  logic        response_error,
  output logic        done,
  output logic        failed,
  output logic [1:0]  pattern_phase,
  output logic [7:0]  word_index,
  output logic [63:0] expected_data,
  output logic [63:0] observed_data
);
  typedef enum logic [2:0] {
    WAIT_CALIBRATION,
    WRITE_REQUEST,
    READ_REQUEST,
    COMPLETE,
    FAILURE
  } state_t;

  state_t state;

  function automatic logic [63:0] pattern_for(
    input logic [1:0] phase,
    input logic [7:0] index
  );
    logic [63:0] index_repeated;
    begin
      index_repeated = {8{index}};
      case (phase)
        2'd0: pattern_for = 64'h0000_0000_0000_0000;
        2'd1: pattern_for = 64'hffff_ffff_ffff_ffff;
        2'd2: pattern_for = 64'haa55_aa55_aa55_aa55 ^ index_repeated;
        default: pattern_for = 64'h55aa_55aa_55aa_55aa ^ index_repeated;
      endcase
    end
  endfunction

  always_comb begin
    request_valid = state == WRITE_REQUEST || state == READ_REQUEST;
    request_write = state == WRITE_REQUEST;
    request_address = DDR_BASE_ADDRESS + ({56'b0, word_index} << 3);
    request_write_data = pattern_for(pattern_phase, word_index);
    request_write_strobe = 8'hff;
    done = state == COMPLETE;
    failed = state == FAILURE;
    expected_data = pattern_for(pattern_phase, word_index);
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= WAIT_CALIBRATION;
      pattern_phase <= '0;
      word_index <= '0;
      observed_data <= '0;
    end else begin
      case (state)
        WAIT_CALIBRATION: begin
          if (init_calib_complete) begin
            state <= WRITE_REQUEST;
          end
        end
        WRITE_REQUEST: begin
          if (request_ready) begin
            if (response_error) begin
              state <= FAILURE;
            end else begin
              state <= READ_REQUEST;
            end
          end
        end
        READ_REQUEST: begin
          if (request_ready) begin
            observed_data <= response_read_data;
            if (response_error || response_read_data != pattern_for(pattern_phase, word_index)) begin
              state <= FAILURE;
            end else if (word_index == TEST_WORD_COUNT - 1) begin
              word_index <= '0;
              if (pattern_phase == 2'd3) begin
                state <= COMPLETE;
              end else begin
                pattern_phase <= pattern_phase + 1'b1;
                state <= WRITE_REQUEST;
              end
            end else begin
              word_index <= word_index + 1'b1;
              state <= WRITE_REQUEST;
            end
          end
        end
        COMPLETE: state <= COMPLETE;
        FAILURE: state <= FAILURE;
        default: state <= FAILURE;
      endcase
    end
  end
endmodule
