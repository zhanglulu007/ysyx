`timescale 1ns/1ns

module clint_tb;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [63:0] mtime = 64'h12345678_9abcdef0;
  reg arvalid = 1'b0;
  reg [31:0] araddr = 32'b0;
  reg [3:0] arid = 4'b0;
  reg rready = 1'b0;
  reg awvalid = 1'b0;
  reg [3:0] awid = 4'b0;
  reg wvalid = 1'b0;
  reg bready = 1'b0;

  wire arready;
  wire rvalid;
  wire [1:0] rresp;
  wire [31:0] rdata;
  wire rlast;
  wire [3:0] rid;
  wire awready;
  wire wready;
  wire bvalid;
  wire [1:0] bresp;
  wire [3:0] bid;

  always #1 clk = !clk;

  CLINT dut(
    .clk(clk), .rst(rst), .mtime(mtime),
    .clint_arvalid(arvalid), .clint_arready(arready),
    .clint_araddr(araddr), .clint_arid(arid), .clint_arlen(8'b0),
    .clint_arsize(3'b010), .clint_arburst(2'b01),
    .clint_rvalid(rvalid), .clint_rready(rready), .clint_rresp(rresp),
    .clint_rdata(rdata), .clint_rlast(rlast), .clint_rid(rid),
    .clint_awvalid(awvalid), .clint_awready(awready),
    .clint_awaddr(32'h0200bff8), .clint_awid(awid), .clint_awlen(8'b0),
    .clint_awsize(3'b010), .clint_awburst(2'b01),
    .clint_wvalid(wvalid), .clint_wready(wready), .clint_wdata(32'b0),
    .clint_wstrb(4'b1111), .clint_wlast(1'b1),
    .clint_bvalid(bvalid), .clint_bready(bready),
    .clint_bresp(bresp), .clint_bid(bid)
  );

  task check_read;
    input [31:0] addr;
    input [3:0] id;
    input [31:0] expected;
    begin
      @(negedge clk);
      araddr = addr;
      arid = id;
      arvalid = 1'b1;
      rready = 1'b0;
      @(posedge clk);
      #1;
      arvalid = 1'b0;
      if (!rvalid || !rlast || rresp != 2'b00 || rid != id || rdata != expected)
        $fatal(1, "CLINT read failed: addr=%h data=%h rid=%h", addr, rdata, rid);
      rready = 1'b1;
      @(posedge clk);
      #1;
      rready = 1'b0;
    end
  endtask

  initial begin
    repeat (2) @(posedge clk);
    rst = 1'b0;

    check_read(32'h0200bff8, 4'h3, 32'h9abcdef0);
    check_read(32'h0200bffc, 4'ha, 32'h12345678);
    check_read(32'h02000000, 4'h5, 32'h00000000);

    @(negedge clk);
    awid = 4'h7;
    awvalid = 1'b1;
    wvalid = 1'b1;
    @(posedge clk);
    #1;
    awvalid = 1'b0;
    wvalid = 1'b0;
    if (!bvalid || bresp != 2'b10 || bid != 4'h7)
      $fatal(1, "CLINT write response failed: bresp=%h bid=%h", bresp, bid);
    bready = 1'b1;
    @(posedge clk);
    #1;

    $display("CLINT test passed");
    $finish;
  end
endmodule
