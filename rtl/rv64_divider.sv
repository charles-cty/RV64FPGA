module rv64_divider (
  input  logic        clk,
  input  logic        reset,
  input  logic        start,
  input  logic        result_consumed,
  input  logic        signed_operation,
  input  logic        remainder_operation,
  input  logic        word_operation,
  input  logic [63:0] dividend,
  input  logic [63:0] divisor,
  output logic        busy,
  output logic        result_valid,
  output logic [63:0] result
);
  logic [64:0] remainder_register;
  logic [63:0] quotient_register;
  logic [63:0] divisor_register;
  logic        quotient_negative;
  logic        remainder_negative;
  logic [6:0]  iteration_count;
  logic [6:0]  iteration_limit;
  logic [64:0] shifted_remainder;
  logic        subtract_divisor;
  logic [64:0] stepped_remainder;
  logic [63:0] stepped_quotient;
  logic [63:0] completed_unsigned_result;
  logic [63:0] completed_signed_result;

  function automatic logic [63:0] negate_value(
    input logic [63:0] value,
    input logic        is_word
  );
    if (is_word) begin
      negate_value = {32'b0, (~value[31:0]) + 32'd1};
    end else begin
      negate_value = ~value + 64'd1;
    end
  endfunction

  function automatic logic [63:0] format_result(
    input logic [63:0] value,
    input logic        is_word
  );
    if (is_word) begin
      format_result = {{32{value[31]}}, value[31:0]};
    end else begin
      format_result = value;
    end
  endfunction

  always_comb begin
    iteration_limit = word_operation ? 7'd32 : 7'd64;
    shifted_remainder = {remainder_register[63:0],
                         word_operation ? quotient_register[31] : quotient_register[63]};
    subtract_divisor = shifted_remainder >= {1'b0, divisor_register};
    stepped_remainder = subtract_divisor ?
                        (shifted_remainder - {1'b0, divisor_register}) : shifted_remainder;
    if (word_operation) begin
      stepped_quotient = {32'b0, quotient_register[30:0], subtract_divisor};
    end else begin
      stepped_quotient = {quotient_register[62:0], subtract_divisor};
    end
    completed_unsigned_result = remainder_operation ? stepped_remainder[63:0] : stepped_quotient;
    completed_signed_result = completed_unsigned_result;
    if ((remainder_operation && remainder_negative) ||
        (!remainder_operation && quotient_negative)) begin
      completed_signed_result = negate_value(completed_unsigned_result, word_operation);
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      busy <= 1'b0;
      result_valid <= 1'b0;
      result <= '0;
      remainder_register <= '0;
      quotient_register <= '0;
      divisor_register <= '0;
      quotient_negative <= 1'b0;
      remainder_negative <= 1'b0;
      iteration_count <= '0;
    end else if (result_valid) begin
      if (result_consumed) begin
        result_valid <= 1'b0;
      end
    end else if (!busy) begin
      if (start) begin
        if ((word_operation && divisor[31:0] == 32'b0) ||
            (!word_operation && divisor == 64'b0)) begin
          result <= format_result(remainder_operation ? dividend : 64'hffff_ffff_ffff_ffff,
                                  word_operation);
          result_valid <= 1'b1;
        end else begin
          busy <= 1'b1;
          iteration_count <= '0;
          remainder_register <= '0;
          quotient_negative <= signed_operation &&
                               ((word_operation ? dividend[31] : dividend[63]) ^
                                (word_operation ? divisor[31] : divisor[63]));
          remainder_negative <= signed_operation &&
                                (word_operation ? dividend[31] : dividend[63]);
          if (signed_operation && (word_operation ? dividend[31] : dividend[63])) begin
            quotient_register <= negate_value(dividend, word_operation);
          end else if (word_operation) begin
            quotient_register <= {32'b0, dividend[31:0]};
          end else begin
            quotient_register <= dividend;
          end
          if (signed_operation && (word_operation ? divisor[31] : divisor[63])) begin
            divisor_register <= negate_value(divisor, word_operation);
          end else if (word_operation) begin
            divisor_register <= {32'b0, divisor[31:0]};
          end else begin
            divisor_register <= divisor;
          end
        end
      end
    end else begin
      remainder_register <= stepped_remainder;
      quotient_register <= stepped_quotient;
      if (iteration_count == iteration_limit - 1'b1) begin
        busy <= 1'b0;
        result_valid <= 1'b1;
        result <= format_result(signed_operation ? completed_signed_result : completed_unsigned_result,
                                word_operation);
      end else begin
        iteration_count <= iteration_count + 1'b1;
      end
    end
  end
endmodule
