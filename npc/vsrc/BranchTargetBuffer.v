module BranchTargetBuffer #(
  parameter integer ENTRY_NUM = 8
)(
  input         clk,
  input         rst,

  input  [31:0] lookup_pc,
  output        lookup_hit,
  output [31:0] lookup_target,
  output        lookup_backward,

  input         update_valid,
  input  [31:0] update_pc,
  input  [31:0] update_target,
  input         update_backward
);

 localparam integer INDEX_BITS = (ENTRY_NUM <= 1) ? 1 : $clog2(ENTRY_NUM);

  reg        valid_array    [0:ENTRY_NUM-1];
  reg [31:0] pc_tag_array   [0:ENTRY_NUM-1];
  reg [31:0] target_array   [0:ENTRY_NUM-1];
  reg        backward_array [0:ENTRY_NUM-1];
  integer i;

  wire [INDEX_BITS-1:0] lookup_index;
  wire [INDEX_BITS-1:0] update_index;
  generate
    if (ENTRY_NUM == 1) begin : gen_single_entry_index
      assign lookup_index = {INDEX_BITS{1'b0}};
      assign update_index = {INDEX_BITS{1'b0}};
    end else begin : gen_direct_mapped_index
      assign lookup_index = lookup_pc[INDEX_BITS+1:2];
      assign update_index = update_pc[INDEX_BITS+1:2];
    end
  endgenerate

  assign lookup_hit      = valid_array[lookup_index] &&
                           (pc_tag_array[lookup_index] == lookup_pc);
  assign lookup_target   = target_array[lookup_index];
  assign lookup_backward = backward_array[lookup_index];

`ifndef SYNTHESIS
  initial begin
    if (ENTRY_NUM < 1 || (ENTRY_NUM & (ENTRY_NUM - 1)) != 0) begin
      $error("BranchTargetBuffer ENTRY_NUM must be a positive power of two");
    end
  end
`endif

  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < ENTRY_NUM; i = i + 1) begin
        valid_array[i] <= 1'b0;
      end
    end else if (update_valid) begin
      valid_array[update_index]    <= 1'b1;
      pc_tag_array[update_index]   <= update_pc;
      target_array[update_index]   <= update_target;
      backward_array[update_index] <= update_backward;
    end
  end

endmodule
