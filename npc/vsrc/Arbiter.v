module Arbiter(
  input clk,
  input rst,

  // IFU AR (from ICache)
  input        ifu_arvalid,
  output       ifu_arready,
  input [31:0] ifu_araddr,
  input [7:0]  ifu_arlen,
  input        ifu_ar_prefetch,

  // IFU R
  output       ifu_rvalid,
  input        ifu_rready,
  output [31:0] ifu_rdata,
  output       ifu_rlast,

  // LSU AR
  input        lsu_arvalid,
  output       lsu_arready,
  input [31:0] lsu_araddr,
  input [3:0]  lsu_arid,
  input [7:0]  lsu_arlen,
  input [2:0]  lsu_arsize,
  input [1:0]  lsu_arburst,

  // LSU R
  output       lsu_rvalid,
  input        lsu_rready,
  output [1:0] lsu_rresp,
  output [31:0] lsu_rdata,
  output       lsu_rlast,
  output [3:0] lsu_rid,

  // LSU AW
  input        lsu_awvalid,
  output       lsu_awready,
  input [31:0] lsu_awaddr,
  input [3:0]  lsu_awid,
  input [7:0]  lsu_awlen,
  input [2:0]  lsu_awsize,
  input [1:0]  lsu_awburst,

  // LSU W
  input        lsu_wvalid,
  output       lsu_wready,
  input [31:0] lsu_wdata,
  input [3:0]  lsu_wstrb,
  input        lsu_wlast,

  // LSU B
  output       lsu_bvalid,
  input        lsu_bready,
  output [1:0] lsu_bresp,
  output [3:0] lsu_bid,

  // MEM AXI4 AR
  output        mem_arvalid,
  input         mem_arready,
  output [31:0] mem_araddr,
  output [3:0]  mem_arid,
  output [7:0]  mem_arlen,
  output [2:0]  mem_arsize,
  output [1:0]  mem_arburst,

  // MEM AXI4 R
  input         mem_rvalid,
  output        mem_rready,
  input  [1:0]  mem_rresp,
  input  [31:0] mem_rdata,
  input         mem_rlast,
  input  [3:0]  mem_rid,

  // MEM AXI4 AW
  output        mem_awvalid,
  input         mem_awready,
  output [31:0] mem_awaddr,
  output [3:0]  mem_awid,
  output [7:0]  mem_awlen,
  output [2:0]  mem_awsize,
  output [1:0]  mem_awburst,

  // MEM AXI4 W
  output        mem_wvalid,
  input         mem_wready,
  output [31:0] mem_wdata,
  output [3:0]  mem_wstrb,
  output        mem_wlast,

  // MEM AXI4 B
  input         mem_bvalid,
  output        mem_bready,
  input  [1:0]  mem_bresp,
  input  [3:0]  mem_bid
);

  localparam IFU_ID = 4'b0001;
  localparam LSU_ID = 4'b0010;
  localparam [2:0] IFU_SIZE  = 3'b010;
  localparam [1:0] IFU_BURST = 2'b01;

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

  reg rd_busy_ifu, rd_busy_lsu;
  wire ifu_free = !rd_busy_ifu;
  wire lsu_free = !rd_busy_lsu;

  wire ifu_grant = ifu_free && ifu_arvalid;
  wire lsu_grant = lsu_free && lsu_arvalid;

  wire lsu_first = lsu_grant && (!ifu_grant || ifu_ar_prefetch);

  reg ar_hold;    
  reg ar_hold_ifu;

  wire ifu_sel = ar_hold ?  ar_hold_ifu : (ifu_grant && !lsu_first);
  wire lsu_sel = ar_hold ? !ar_hold_ifu : (lsu_grant && lsu_first);

  assign mem_arvalid = (ifu_sel && ifu_arvalid) || (lsu_sel && lsu_arvalid);
  assign mem_araddr  = ifu_sel ? ifu_araddr : lsu_araddr;
  assign mem_arid    = ifu_sel ? IFU_ID : lsu_arid;
  assign mem_arlen   = ifu_sel ? ifu_arlen : lsu_arlen;
  assign mem_arsize  = ifu_sel ? IFU_SIZE : lsu_arsize;
  assign mem_arburst = ifu_sel ? IFU_BURST : lsu_arburst;

  assign ifu_arready = ifu_sel && mem_arready;
  assign lsu_arready = lsu_sel && mem_arready;

  assign ifu_rvalid  = mem_rvalid && (mem_rid == IFU_ID);
  assign ifu_rdata   = mem_rdata;
  assign ifu_rlast   = mem_rlast;

  assign lsu_rvalid  = mem_rvalid && (mem_rid == LSU_ID);
  assign lsu_rresp   = mem_rresp;
  assign lsu_rdata   = mem_rdata;
  assign lsu_rlast   = mem_rlast;
  assign lsu_rid     = mem_rid;

  assign mem_rready  = (mem_rid == IFU_ID) ? ifu_rready : lsu_rready;

  wire ar_fire = mem_arvalid && mem_arready;
  wire r_fire  = mem_rvalid && mem_rready;

  wire ar_open_ifu = ar_fire && ifu_sel && (mem_arlen != 8'd0);
  wire ar_open_lsu = ar_fire && lsu_sel && (mem_arlen != 8'd0);

  wire rd_close_ifu = rd_busy_ifu && r_fire && mem_rlast && (mem_rid == IFU_ID);
  wire rd_close_lsu = rd_busy_lsu && r_fire && mem_rlast && (mem_rid == LSU_ID);

  integer dbg_ar = 0, dbg_r = 0, dbg_cyc = 0;
  always @(posedge clk) begin
    if (!rst) begin
      dbg_cyc = dbg_cyc + 1;
      if (ar_fire) dbg_ar = dbg_ar + 1;
      if (r_fire)  dbg_r  = dbg_r + 1;
      if (dbg_cyc % 20000 == 0)
        $display("[ARB] cyc=%0d ar=%0d r=%0d bifu=%b blsu=%b av=%b rv=%b rr=%b rid=%0d ifu_v=%b lsu_v=%b",
                 dbg_cyc, dbg_ar, dbg_r, rd_busy_ifu, rd_busy_lsu,
                 mem_arvalid, mem_rvalid, mem_rready, mem_rid, ifu_arvalid, lsu_arvalid);
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      rd_busy_ifu <= 1'b0;
      rd_busy_lsu <= 1'b0;
      ar_hold     <= 1'b0;
      ar_hold_ifu <= 1'b0;
    end else begin
      if (ar_open_ifu)      rd_busy_ifu <= 1'b1;
      else if (rd_close_ifu) rd_busy_ifu <= 1'b0;

      if (ar_open_lsu)      rd_busy_lsu <= 1'b1;
      else if (rd_close_lsu) rd_busy_lsu <= 1'b0;

      if (ar_fire) begin
        ar_hold     <= 1'b0;
        ar_hold_ifu <= 1'b0;
      end else if (mem_arvalid) begin
        ar_hold     <= 1'b1;
        ar_hold_ifu <= ifu_sel;
      end else begin
        ar_hold     <= 1'b0;  
        ar_hold_ifu <= 1'b0;
      end
    end
  end

endmodule
