// ============================================================================
//  Arbiter - ICache / LSU 的 AXI AR 仲裁 + 读写通道直通
//
//  相比 npc/vsrc/Arbiter.v 去掉了 ar_grant 锁存状态: 采用 IFU 优先的组合
//  仲裁, 既避免 master 撤销 arvalid 后仍被锁存导致的"幽灵 AR", 也省掉
//  几拍状态. IFU 只在 cache miss 时发 AR, 不会饿死 LSU.
//  rd_busy 仍用于防止突发填充期间插入新的 AR.
// ============================================================================
module Arbiter(
  input  clk,
  input  rst,

  // IFU (ICache) AXI4 AR
  input         ifu_arvalid,
  output        ifu_arready,
  input  [31:0] ifu_araddr,
  input  [7:0]  ifu_arlen,

  // IFU AXI4 R
  output        ifu_rvalid,
  input         ifu_rready,
  output [31:0] ifu_rdata,
  output        ifu_rlast,

  // LSU AXI4 AR
  input         lsu_arvalid,
  output        lsu_arready,
  input  [31:0] lsu_araddr,
  input  [3:0]  lsu_arid,
  input  [7:0]  lsu_arlen,
  input  [2:0]  lsu_arsize,
  input  [1:0]  lsu_arburst,

  // LSU AXI4 R
  output        lsu_rvalid,
  input         lsu_rready,
  output [1:0]  lsu_rresp,
  output [31:0] lsu_rdata,
  output        lsu_rlast,
  output [3:0]  lsu_rid,

  // LSU AXI4 AW
  input         lsu_awvalid,
  output        lsu_awready,
  input  [31:0] lsu_awaddr,
  input  [3:0]  lsu_awid,
  input  [7:0]  lsu_awlen,
  input  [2:0]  lsu_awsize,
  input  [1:0]  lsu_awburst,

  // LSU AXI4 W
  input         lsu_wvalid,
  output        lsu_wready,
  input  [31:0] lsu_wdata,
  input  [3:0]  lsu_wstrb,
  input         lsu_wlast,

  // LSU AXI4 B
  output        lsu_bvalid,
  input         lsu_bready,
  output [1:0]  lsu_bresp,
  output [3:0]  lsu_bid,

  // 外部存储 AXI4 AR
  output        mem_arvalid,
  input         mem_arready,
  output [31:0] mem_araddr,
  output [3:0]  mem_arid,
  output [7:0]  mem_arlen,
  output [2:0]  mem_arsize,
  output [1:0]  mem_arburst,

  // 外部存储 AXI4 R
  input         mem_rvalid,
  output        mem_rready,
  input  [1:0]  mem_rresp,
  input  [31:0] mem_rdata,
  input         mem_rlast,
  input  [3:0]  mem_rid,

  // 外部存储 AXI4 AW
  output        mem_awvalid,
  input         mem_awready,
  output [31:0] mem_awaddr,
  output [3:0]  mem_awid,
  output [7:0]  mem_awlen,
  output [2:0]  mem_awsize,
  output [1:0]  mem_awburst,

  // 外部存储 AXI4 W
  output        mem_wvalid,
  input         mem_wready,
  output [31:0] mem_wdata,
  output [3:0]  mem_wstrb,
  output        mem_wlast,

  // 外部存储 AXI4 B
  input         mem_bvalid,
  output        mem_bready,
  input  [1:0]  mem_bresp,
  input  [3:0]  mem_bid
);

  localparam [3:0] IFU_ID = 4'b0001, LSU_ID = 4'b0010;
  localparam [2:0] IFU_SIZE = 3'b010;
  localparam [1:0] IFU_BURST = 2'b01;

  reg rd_busy;

  wire ar_free = !rd_busy;
  wire ifu_ar_select = ar_free && ifu_arvalid;
  wire lsu_ar_select = ar_free && !ifu_arvalid && lsu_arvalid;

  assign mem_arvalid = ifu_ar_select || lsu_ar_select;
  assign mem_araddr  = ifu_ar_select ? ifu_araddr : lsu_araddr;
  assign mem_arid    = ifu_ar_select ? IFU_ID    : lsu_arid;
  assign mem_arlen   = ifu_ar_select ? ifu_arlen : lsu_arlen;
  assign mem_arsize  = ifu_ar_select ? IFU_SIZE  : lsu_arsize;
  assign mem_arburst = ifu_ar_select ? IFU_BURST : lsu_arburst;

  assign ifu_arready = ifu_ar_select && mem_arready;
  assign lsu_arready = lsu_ar_select && mem_arready;

  assign ifu_rvalid = mem_rvalid && (mem_rid == IFU_ID);
  assign ifu_rdata  = mem_rdata;
  assign ifu_rlast  = mem_rlast;

  assign lsu_rvalid = mem_rvalid && (mem_rid == LSU_ID);
  assign lsu_rresp  = mem_rresp;
  assign lsu_rdata  = mem_rdata;
  assign lsu_rlast  = mem_rlast;
  assign lsu_rid    = mem_rid;

  assign mem_rready = (mem_rid == IFU_ID) ? ifu_rready : lsu_rready;

  // 写通道直通
  assign mem_awvalid = lsu_awvalid;
  assign mem_awaddr  = lsu_awaddr;
  assign mem_awid    = lsu_awid;
  assign mem_awlen   = lsu_awlen;
  assign mem_awsize  = lsu_awsize;
  assign mem_awburst = lsu_awburst;
  assign lsu_awready = mem_awready;

  assign mem_wvalid  = lsu_wvalid;
  assign mem_wdata   = lsu_wdata;
  assign mem_wstrb   = lsu_wstrb;
  assign mem_wlast   = lsu_wlast;
  assign lsu_wready  = mem_wready;

  assign lsu_bvalid  = mem_bvalid;
  assign lsu_bresp   = mem_bresp;
  assign lsu_bid     = mem_bid;
  assign mem_bready  = lsu_bready;

  wire ar_fire = mem_arvalid && mem_arready;
  wire r_fire  = mem_rvalid && mem_rready;

  wire ar_open  = ar_fire && (mem_arlen != 8'd0);
  wire rd_close = rd_busy && r_fire && mem_rlast;

  always @(posedge clk) begin
    if (rst) begin
      rd_busy <= 1'b0;
    end else begin
      if (ar_open) begin
        rd_busy <= 1'b1;
      end else if (rd_close) begin
        rd_busy <= 1'b0;
      end
    end
  end

endmodule
