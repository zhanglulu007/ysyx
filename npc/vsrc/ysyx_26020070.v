// ysyx_26020070 - RV32E processor for ysyxSoC
// 符合 ysyxSoC 接口规范的顶层模块
// AXI4 Master 总线连接 ysyxSoC 的 AXI4 Xbar
// 内部包含: IFU, IDU, EXU, LSU, WBU, CSR, RegisterFile, CLINT, AXIArbiter

module ysyx_26020070(
  // ===== ysyxSoC 接口规范 =====
  input         clock,          // 时钟
  input         reset,          // 复位 (高电平有效)
  input         io_interrupt,   // 外部中断 (目前不使用)

  // ===== AXI4 Master 总线 - 连接 ysyxSoC 的 AXI4 Xbar =====
  // AR 通道 (读地址)
  output        io_master_arvalid,
  input         io_master_arready,
  output [31:0] io_master_araddr,
  output [ 3:0] io_master_arid,
  output [ 7:0] io_master_arlen,
  output [ 2:0] io_master_arsize,
  output [ 1:0] io_master_arburst,

  // R 通道 (读数据)
  input         io_master_rvalid,
  output        io_master_rready,
  input  [31:0] io_master_rdata,
  input  [ 1:0] io_master_rresp,
  input         io_master_rlast,
  input  [ 3:0] io_master_rid,

  // AW 通道 (写地址)
  output        io_master_awvalid,
  input         io_master_awready,
  output [31:0] io_master_awaddr,
  output [ 3:0] io_master_awid,
  output [ 7:0] io_master_awlen,
  output [ 2:0] io_master_awsize,
  output [ 1:0] io_master_awburst,

  // W 通道 (写数据)
  output        io_master_wvalid,
  input         io_master_wready,
  output [31:0] io_master_wdata,
  output [ 3:0] io_master_wstrb,
  output        io_master_wlast,

  // B 通道 (写回复)
  input         io_master_bvalid,
  output        io_master_bready,
  input  [ 1:0] io_master_bresp,
  input  [ 3:0] io_master_bid,

  // ===== AXI4 Slave 总线 - 用于调试 (目前不使用，按规范定义端口) =====
  // 注意：Slave接口方向与Master接口镜像相反
  // AW 通道 (写地址)
  output        io_slave_awready,   // slave ready to accept write address
  input         io_slave_awvalid,   // master driving write address
  input  [ 3:0] io_slave_awid,
  input  [31:0] io_slave_awaddr,
  input  [ 7:0] io_slave_awlen,
  input  [ 2:0] io_slave_awsize,
  input  [ 1:0] io_slave_awburst,

  // W 通道 (写数据)
  output        io_slave_wready,    // slave ready to accept write data
  input         io_slave_wvalid,    // master driving write data
  input  [31:0] io_slave_wdata,
  input  [ 3:0] io_slave_wstrb,
  input         io_slave_wlast,

  // B 通道 (写回复)
  input         io_slave_bready,    // master ready to accept response
  output        io_slave_bvalid,    // slave driving response
  output [ 3:0] io_slave_bid,
  output [ 1:0] io_slave_bresp,

  // AR 通道 (读地址)
  output        io_slave_arready,   // slave ready to accept read address
  input         io_slave_arvalid,   // master driving read address
  input  [ 3:0] io_slave_arid,
  input  [31:0] io_slave_araddr,
  input  [ 7:0] io_slave_arlen,
  input  [ 2:0] io_slave_arsize,
  input  [ 1:0] io_slave_arburst,

  // R 通道 (读数据)
  input         io_slave_rready,    // master ready to accept read data
  output        io_slave_rvalid,    // slave driving read data
  output [ 3:0] io_slave_rid,
  output [31:0] io_slave_rdata,
  output [ 1:0] io_slave_rresp,
  output        io_slave_rlast
);

  // ===== AXI4 Slave接口 (未使用) =====
  assign io_slave_awready = 1'b0;
  assign io_slave_wready  = 1'b0;
  assign io_slave_bvalid  = 1'b0;
  assign io_slave_bid     = 4'b0;
  assign io_slave_bresp   = 2'b0;
  assign io_slave_arready = 1'b0;
  assign io_slave_rvalid  = 1'b0;
  assign io_slave_rid     = 4'b0;
  assign io_slave_rdata   = 32'b0;
  assign io_slave_rresp   = 2'b0;
  assign io_slave_rlast   = 1'b0;

  // ===== 流水线处理器核心 (5-stage in-order pipeline) =====
  PipelineCore u_pipeline_core(
    .clk(clock), .rst(reset),
    .mem_arvalid(io_master_arvalid), .mem_arready(io_master_arready),
    .mem_araddr(io_master_araddr), .mem_arid(io_master_arid),
    .mem_arlen(io_master_arlen), .mem_arsize(io_master_arsize),
    .mem_arburst(io_master_arburst),
    .mem_rvalid(io_master_rvalid), .mem_rready(io_master_rready),
    .mem_rdata(io_master_rdata), .mem_rresp(io_master_rresp),
    .mem_rlast(io_master_rlast), .mem_rid(io_master_rid),
    .mem_awvalid(io_master_awvalid), .mem_awready(io_master_awready),
    .mem_awaddr(io_master_awaddr), .mem_awid(io_master_awid),
    .mem_awlen(io_master_awlen), .mem_awsize(io_master_awsize),
    .mem_awburst(io_master_awburst),
    .mem_wvalid(io_master_wvalid), .mem_wready(io_master_wready),
    .mem_wdata(io_master_wdata), .mem_wstrb(io_master_wstrb),
    .mem_wlast(io_master_wlast),
    .mem_bvalid(io_master_bvalid), .mem_bready(io_master_bready),
    .mem_bresp(io_master_bresp), .mem_bid(io_master_bid)
  );

endmodule
