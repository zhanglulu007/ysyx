module Arbiter(
  input clk,
  input rst,

  // IFU AXI4 AR：arid/arsize/arburst 为恒定值，只有 arlen 随 cache 块大小变化
  input ifu_arvalid,
  output ifu_arready,
  input [31:0] ifu_araddr,
  input [7:0] ifu_arlen,

  // IFU AXI4 R：IFU 只收 4B 单拍，rresp/rid 由仲裁口按 id 分流后即恒定
  output ifu_rvalid,
  input ifu_rready,
  output [31:0] ifu_rdata,
  output ifu_rlast,

  // LSU AXI4 AR
  input lsu_arvalid,
  output lsu_arready,
  input [31:0] lsu_araddr,
  input [3:0] lsu_arid,
  input [7:0] lsu_arlen,
  input [2:0] lsu_arsize,
  input [1:0] lsu_arburst,

  // LSU AXI4 R
  output lsu_rvalid,
  input lsu_rready,
  output [1:0] lsu_rresp,
  output [31:0] lsu_rdata,
  output lsu_rlast,
  output [3:0] lsu_rid,

  // LSU AXI4 AW
  input lsu_awvalid,
  output lsu_awready,
  input [31:0] lsu_awaddr,
  input [3:0] lsu_awid,
  input [7:0] lsu_awlen,
  input [2:0] lsu_awsize,
  input [1:0] lsu_awburst,

  // LSU AXI4 W
  input lsu_wvalid,
  output lsu_wready,
  input [31:0] lsu_wdata,
  input [3:0] lsu_wstrb,
  input lsu_wlast,

  // LSU AXI4 B
  output lsu_bvalid,
  input lsu_bready,
  output [1:0] lsu_bresp,
  output [3:0] lsu_bid,

  // PMEM AXI4 AR
  output mem_arvalid,
  input mem_arready,
  output [31:0] mem_araddr,
  output [3:0] mem_arid,
  output [7:0] mem_arlen,
  output [2:0] mem_arsize,
  output [1:0] mem_arburst,

  // PMEM AXI4 R
  input mem_rvalid,
  output mem_rready,
  input [1:0] mem_rresp,
  input [31:0] mem_rdata,
  input mem_rlast,
  input [3:0] mem_rid,

  // PMEM AXI4 AW
  output mem_awvalid,
  input mem_awready,
  output [31:0] mem_awaddr,
  output [3:0] mem_awid,
  output [7:0] mem_awlen,
  output [2:0] mem_awsize,
  output [1:0] mem_awburst,

  // PMEM AXI4 W
  output mem_wvalid,
  input mem_wready,
  output [31:0] mem_wdata,
  output [3:0] mem_wstrb,
  output mem_wlast,

  // PMEM AXI4 B
  input mem_bvalid,
  output mem_bready,
  input [1:0] mem_bresp,
  input [3:0] mem_bid
);

  assign mem_awvalid = lsu_awvalid;
  assign mem_awaddr = lsu_awaddr;
  assign mem_awid = lsu_awid;
  assign mem_awlen = lsu_awlen;
  assign mem_awsize = lsu_awsize;
  assign mem_awburst = lsu_awburst;
  assign lsu_awready = mem_awready;
  assign mem_wvalid = lsu_wvalid;
  assign mem_wdata = lsu_wdata;
  assign mem_wstrb = lsu_wstrb;
  assign mem_wlast = lsu_wlast;
  assign lsu_wready = mem_wready;
  assign lsu_bvalid = mem_bvalid;
  assign lsu_bresp = mem_bresp;
  assign lsu_bid = mem_bid;
  assign mem_bready = lsu_bready;

  localparam AR_NONE = 2'b00, AR_IFU = 2'b01, AR_LSU = 2'b10;
  localparam IFU_ID = 4'b0001, LSU_ID = 4'b0010;
  // IFU 侧恒定语义：32 位机、单拍 AR size、INCR 突发
  localparam [2:0] IFU_SIZE   = 3'b010;
  localparam [1:0] IFU_BURST  = 2'b01;

  reg [1:0] ar_grant;      // AR 归属（NONE/IFU/LSU）；握手后归还
  reg       rd_busy;       // 总线上存在未完成的多 beat 读事务（突发）

  // 只有多 beat 突发（arlen != 0）才需要在途保护：
  //   突发进行到第 k 个 beat 时若接受新 AR，R 通道会按 rid 交织，数据错位。
  // 单拍事务（arlen == 0，即 LSU 与 ICache 现有行为）保持原有的流水能力，
  // 因此本改动对 ICache 版本与 LSU 的性能零影响。
  wire ar_free = !rd_busy;

  wire ifu_ar_select = ar_free && ((ar_grant == AR_NONE) ? ifu_arvalid : (ar_grant == AR_IFU));
  wire lsu_ar_select = ar_free && ((ar_grant == AR_NONE) ? (!ifu_arvalid && lsu_arvalid) : (ar_grant == AR_LSU));

  assign mem_arvalid = ifu_ar_select || lsu_ar_select;
  assign mem_araddr = ifu_ar_select ? ifu_araddr : lsu_araddr;
  assign mem_arid = ifu_ar_select ? IFU_ID : lsu_arid;
  assign mem_arlen = ifu_ar_select ? ifu_arlen : lsu_arlen;
  assign mem_arsize = ifu_ar_select ? IFU_SIZE : lsu_arsize;
  assign mem_arburst = ifu_ar_select ? IFU_BURST : lsu_arburst;

  assign ifu_arready = ifu_ar_select && mem_arready;
  assign ifu_rvalid = mem_rvalid && (mem_rid == IFU_ID);
  assign ifu_rdata = mem_rdata;
  assign ifu_rlast = mem_rlast;

  assign lsu_arready = lsu_ar_select && mem_arready;
  assign lsu_rvalid = mem_rvalid && (mem_rid == LSU_ID);
  assign lsu_rresp = mem_rresp;
  assign lsu_rdata = mem_rdata;
  assign lsu_rlast = mem_rlast;
  assign lsu_rid = mem_rid;

  assign mem_rready = (mem_rid == IFU_ID) ? ifu_rready : lsu_rready;

  wire ar_fire = mem_arvalid && mem_arready;
  wire r_fire  = mem_rvalid && mem_rready;

  // 多 beat 突发的在途标记：授予一个 arlen != 0 的 AR 时置位，
  // 等到该事务的最后一拍（mem_rlast）握手后才释放。
  wire ar_open  = ar_fire && (mem_arlen != 8'd0);
  wire rd_close = rd_busy && r_fire && mem_rlast;

  always @(posedge clk) begin
    if (rst) begin
      ar_grant <= AR_NONE;
      rd_busy  <= 1'b0;
    end else begin
      if (ar_grant == AR_NONE && !ar_fire) begin
        if (ifu_arvalid) begin
          ar_grant <= AR_IFU;
        end else if (lsu_arvalid) begin
          ar_grant <= AR_LSU;
        end
      end else if (ar_fire) begin
        ar_grant <= AR_NONE;
      end

      if (ar_open) begin
        rd_busy <= 1'b1;
      end else if (rd_close) begin
        rd_busy <= 1'b0;
      end
    end
  end

endmodule
