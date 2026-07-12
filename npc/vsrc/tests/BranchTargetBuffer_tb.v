`timescale 1ns/1ps

module BranchTargetBuffer_tb;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [31:0] lookup_pc;
  wire lookup_hit;
  wire [31:0] lookup_target;
  wire lookup_backward;
  reg update_valid;
  reg [31:0] update_pc;
  reg [31:0] update_target;
  reg update_backward;

  BranchTargetBuffer #(.ENTRY_NUM(4)) dut(
    .clk(clk), .rst(rst), .lookup_pc(lookup_pc),
    .lookup_hit(lookup_hit), .lookup_target(lookup_target),
    .lookup_backward(lookup_backward), .update_valid(update_valid),
    .update_pc(update_pc), .update_target(update_target),
    .update_backward(update_backward)
  );

  always #5 clk = ~clk;

  task expect_lookup;
    input [31:0] pc;
    input expected_hit;
    input [31:0] expected_target;
    input expected_backward;
    begin
      lookup_pc = pc;
      #1;
      if (lookup_hit !== expected_hit ||
          (expected_hit && (lookup_target !== expected_target ||
                            lookup_backward !== expected_backward))) begin
        $display("BTB lookup failed: pc=%h hit=%b target=%h backward=%b",
                 pc, lookup_hit, lookup_target, lookup_backward);
        $fatal(1);
      end
    end
  endtask

  initial begin
    lookup_pc = 32'h0;
    update_valid = 1'b0;
    update_pc = 32'h0;
    update_target = 32'h0;
    update_backward = 1'b0;

    // Reset invalidates every entry.
    #12 rst = 1'b0;
    expect_lookup(32'h00000100, 1'b0, 32'h0, 1'b0);

    // Fill a backward branch, then read its target and BTFN direction bit.
    update_valid = 1'b1;
    update_pc = 32'h00000100;
    update_target = 32'h000000fc;
    update_backward = 1'b1;
    @(posedge clk);
    #1 update_valid = 1'b0;
    expect_lookup(32'h00000100, 1'b1, 32'h000000fc, 1'b1);

    // 0x100 and 0x110 both map to index zero in a four-entry BTB.
    update_valid = 1'b1;
    update_pc = 32'h00000110;
    update_target = 32'h00000118;
    update_backward = 1'b0;
    @(posedge clk);
    #1 update_valid = 1'b0;
    expect_lookup(32'h00000100, 1'b0, 32'h0, 1'b0);
    expect_lookup(32'h00000110, 1'b1, 32'h00000118, 1'b0);

    $display("BranchTargetBuffer_tb: PASS");
    $finish;
  end
endmodule
