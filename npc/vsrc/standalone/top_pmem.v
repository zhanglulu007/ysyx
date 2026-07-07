// top - 独立 NPC 仿真顶层 (riscv32e-npc)
// 把 CPU 核心 ysyx_26020070 的完整 AXI4 master 口接到简化的 pmem + uart 后端
// 不依赖任何 ysyxSoC 外设, 用于快速功能测试
//
// 地址译码 (与 AM 的 npc.h 一致):
//   0x80000000 ~ 0xffffffff  → pmem_axi  (主存, DPI-C pmem_read/pmem_write)
//   其他 (0x10000000 段等)    → uart_axi  (设备, DPI-C pmem_read/pmem_write 处理 MMIO)
//
// 注意: ysyx_26020070 内部已含 CLINT (0x0200_BFF8 mtime), 不会被路由到本顶层

module top(
  input         clk,
  input         rst,

  // 调试输出 (供 C++ 仿真层观察, 防止优化)
  output [31:0] pc_out,
  output [31:0] inst_out,
  output        cpu_valid
);

  // ========== CPU 核心 (ysyx_26020070) ==========
  // AXI4 master 信号
  wire        m_arvalid, m_arready;
  wire [31:0] m_araddr;
  wire [ 3:0] m_arid;
  wire [ 7:0] m_arlen;
  wire [ 2:0] m_arsize;
  wire [ 1:0] m_arburst;

  wire        m_rvalid, m_rready;
  wire [31:0] m_rdata;
  wire [ 1:0] m_rresp;
  wire        m_rlast;
  wire [ 3:0] m_rid;

  wire        m_awvalid, m_awready;
  wire [31:0] m_awaddr;
  wire [ 3:0] m_awid;
  wire [ 7:0] m_awlen;
  wire [ 2:0] m_awsize;
  wire [ 1:0] m_awburst;

  wire        m_wvalid, m_wready;
  wire [31:0] m_wdata;
  wire [ 3:0] m_wstrb;
  wire        m_wlast;

  wire        m_bvalid, m_bready;
  wire [ 1:0] m_bresp;
  wire [ 3:0] m_bid;

  // ========== 地址译码 (读写分离, 避免组合环路) ==========
  // 读事务选路: 基于 araddr (只在 AR 通道有效时有意义)
  wire ar_is_pmem  = (m_araddr[31] == 1'b1);
  // 写事务选路: 基于 awaddr (只在 AW 通道有效时有意义)
  wire aw_is_pmem  = (m_awaddr[31] == 1'b1);

  // ========== pmem_axi 信号 ==========
  wire        p_arvalid, p_arready;
  wire [31:0] p_araddr;
  wire [ 3:0] p_arid;
  wire [ 7:0] p_arlen;
  wire [ 2:0] p_arsize;
  wire [ 1:0] p_arburst;
  wire        p_rvalid, p_rready;
  wire [31:0] p_rdata;
  wire [ 1:0] p_rresp;
  wire        p_rlast;
  wire [ 3:0] p_rid;
  wire        p_awvalid, p_awready;
  wire [31:0] p_awaddr;
  wire [ 3:0] p_awid;
  wire [ 7:0] p_awlen;
  wire [ 2:0] p_awsize;
  wire [ 1:0] p_awburst;
  wire        p_wvalid, p_wready;
  wire [31:0] p_wdata;
  wire [ 3:0] p_wstrb;
  wire        p_wlast;
  wire        p_bvalid, p_bready;
  wire [ 1:0] p_bresp;
  wire [ 3:0] p_bid;

  // ========== uart_axi 信号 ==========
  wire        u_arvalid, u_arready;
  wire [31:0] u_araddr;
  wire [ 3:0] u_arid;
  wire [ 7:0] u_arlen;
  wire [ 2:0] u_arsize;
  wire [ 1:0] u_arburst;
  wire        u_rvalid, u_rready;
  wire [31:0] u_rdata;
  wire [ 1:0] u_rresp;
  wire        u_rlast;
  wire [ 3:0] u_rid;
  wire        u_awvalid, u_awready;
  wire [31:0] u_awaddr;
  wire [ 3:0] u_awid;
  wire [ 7:0] u_awlen;
  wire [ 2:0] u_awsize;
  wire [ 1:0] u_awburst;
  wire        u_wvalid, u_wready;
  wire [31:0] u_wdata;
  wire [ 3:0] u_wstrb;
  wire        u_wlast;
  wire        u_bvalid, u_bready;
  wire [ 1:0] u_bresp;
  wire [ 3:0] u_bid;

  // ========== AXI4 Xbar: master → {pmem_axi, uart_axi} ==========
  // 读和写事务的选路完全独立, 基于各自的地址译码
  // 读通道 (AR/R)
  assign p_arvalid = m_arvalid &&  ar_is_pmem;
  assign p_araddr  = m_araddr;
  assign p_arid    = m_arid;
  assign p_arlen   = m_arlen;
  assign p_arsize  = m_arsize;
  assign p_arburst = m_arburst;

  assign u_arvalid = m_arvalid && !ar_is_pmem;
  assign u_araddr  = m_araddr;
  assign u_arid    = m_arid;
  assign u_arlen   = m_arlen;
  assign u_arsize  = m_arsize;
  assign u_arburst = m_arburst;

  // master 的 arready: 仅被选中的 slave 驱动
  assign m_arready = ar_is_pmem ? p_arready : u_arready;

  // R 通道回传
  assign m_rvalid = ar_is_pmem ? p_rvalid : u_rvalid;
  assign m_rdata  = ar_is_pmem ? p_rdata  : u_rdata;
  assign m_rresp  = ar_is_pmem ? p_rresp  : u_rresp;
  assign m_rlast  = ar_is_pmem ? p_rlast  : u_rlast;
  assign m_rid    = ar_is_pmem ? p_rid    : u_rid;

  assign p_rready = m_rready &&  ar_is_pmem;
  assign u_rready = m_rready && !ar_is_pmem;

  // 写通道 (AW/W/B)
  assign p_awvalid = m_awvalid &&  aw_is_pmem;
  assign p_awaddr  = m_awaddr;
  assign p_awid    = m_awid;
  assign p_awlen   = m_awlen;
  assign p_awsize  = m_awsize;
  assign p_awburst = m_awburst;

  assign u_awvalid = m_awvalid && !aw_is_pmem;
  assign u_awaddr  = m_awaddr;
  assign u_awid    = m_awid;
  assign u_awlen   = m_awlen;
  assign u_awsize  = m_awsize;
  assign u_awburst = m_awburst;

  assign m_awready = aw_is_pmem ? p_awready : u_awready;

  assign p_wvalid = m_wvalid &&  aw_is_pmem;
  assign p_wdata  = m_wdata;
  assign p_wstrb  = m_wstrb;
  assign p_wlast  = m_wlast;

  assign u_wvalid = m_wvalid && !aw_is_pmem;
  assign u_wdata  = m_wdata;
  assign u_wstrb  = m_wstrb;
  assign u_wlast  = m_wlast;

  assign m_wready = aw_is_pmem ? p_wready : u_wready;

  assign m_bvalid = aw_is_pmem ? p_bvalid : u_bvalid;
  assign m_bresp  = aw_is_pmem ? p_bresp  : u_bresp;
  assign m_bid    = aw_is_pmem ? p_bid    : u_bid;

  assign p_bready = m_bready &&  aw_is_pmem;
  assign u_bready = m_bready && !aw_is_pmem;

  // ========== 调试输出 ==========
  // C++ 仿真层通过 DPI-C (npc_get_pc 等) 获取 CPU 内部状态, 不依赖这些端口
  // 这里的输出仅用于防止顶层信号被优化掉, 取自非反馈路径
  assign pc_out    = 32'b0;
  assign inst_out  = 32'b0;
  assign cpu_valid = 1'b0;

  // ========== 模块实例化 ==========

  // CPU 核心
  ysyx_26020070 u_cpu(
    .clock(clk),
    .reset(rst),
    .io_interrupt(1'b0),
    // AXI4 master
    .io_master_arvalid(m_arvalid),
    .io_master_arready(m_arready),
    .io_master_araddr(m_araddr),
    .io_master_arid(m_arid),
    .io_master_arlen(m_arlen),
    .io_master_arsize(m_arsize),
    .io_master_arburst(m_arburst),
    .io_master_rvalid(m_rvalid),
    .io_master_rready(m_rready),
    .io_master_rdata(m_rdata),
    .io_master_rresp(m_rresp),
    .io_master_rlast(m_rlast),
    .io_master_rid(m_rid),
    .io_master_awvalid(m_awvalid),
    .io_master_awready(m_awready),
    .io_master_awaddr(m_awaddr),
    .io_master_awid(m_awid),
    .io_master_awlen(m_awlen),
    .io_master_awsize(m_awsize),
    .io_master_awburst(m_awburst),
    .io_master_wvalid(m_wvalid),
    .io_master_wready(m_wready),
    .io_master_wdata(m_wdata),
    .io_master_wstrb(m_wstrb),
    .io_master_wlast(m_wlast),
    .io_master_bvalid(m_bvalid),
    .io_master_bready(m_bready),
    .io_master_bresp(m_bresp),
    .io_master_bid(m_bid),
    // AXI4 slave (未使用, 悬空)
    .io_slave_awready(),
    .io_slave_awvalid(1'b0),
    .io_slave_awid(4'b0),
    .io_slave_awaddr(32'b0),
    .io_slave_awlen(8'b0),
    .io_slave_awsize(3'b0),
    .io_slave_awburst(2'b0),
    .io_slave_wready(),
    .io_slave_wvalid(1'b0),
    .io_slave_wdata(32'b0),
    .io_slave_wstrb(4'b0),
    .io_slave_wlast(1'b0),
    .io_slave_bready(1'b0),
    .io_slave_bvalid(),
    .io_slave_bid(),
    .io_slave_bresp(),
    .io_slave_arready(),
    .io_slave_arvalid(1'b0),
    .io_slave_arid(4'b0),
    .io_slave_araddr(32'b0),
    .io_slave_arlen(8'b0),
    .io_slave_arsize(3'b0),
    .io_slave_arburst(2'b0),
    .io_slave_rready(1'b0),
    .io_slave_rvalid(),
    .io_slave_rid(),
    .io_slave_rdata(),
    .io_slave_rresp(),
    .io_slave_rlast()
  );

  // pmem 后端 (主存)
  pmem_axi u_pmem(
    .clk(clk),
    .rst(rst),
    .arvalid(p_arvalid),
    .arready(p_arready),
    .araddr(p_araddr),
    .arid(p_arid),
    .arlen(p_arlen),
    .arsize(p_arsize),
    .arburst(p_arburst),
    .rvalid(p_rvalid),
    .rready(p_rready),
    .rdata(p_rdata),
    .rresp(p_rresp),
    .rlast(p_rlast),
    .rid(p_rid),
    .awvalid(p_awvalid),
    .awready(p_awready),
    .awaddr(p_awaddr),
    .awid(p_awid),
    .awlen(p_awlen),
    .awsize(p_awsize),
    .awburst(p_awburst),
    .wvalid(p_wvalid),
    .wready(p_wready),
    .wdata(p_wdata),
    .wstrb(p_wstrb),
    .wlast(p_wlast),
    .bvalid(p_bvalid),
    .bready(p_bready),
    .bresp(p_bresp),
    .bid(p_bid)
  );

  // UART 设备后端 (串口/RTC/KBD/VGA 等 MMIO)
  uart_axi u_uart(
    .clk(clk),
    .rst(rst),
    .arvalid(u_arvalid),
    .arready(u_arready),
    .araddr(u_araddr),
    .arid(u_arid),
    .arlen(u_arlen),
    .arsize(u_arsize),
    .arburst(u_arburst),
    .rvalid(u_rvalid),
    .rready(u_rready),
    .rdata(u_rdata),
    .rresp(u_rresp),
    .rlast(u_rlast),
    .rid(u_rid),
    .awvalid(u_awvalid),
    .awready(u_awready),
    .awaddr(u_awaddr),
    .awid(u_awid),
    .awlen(u_awlen),
    .awsize(u_awsize),
    .awburst(u_awburst),
    .wvalid(u_wvalid),
    .wready(u_wready),
    .wdata(u_wdata),
    .wstrb(u_wstrb),
    .wlast(u_wlast),
    .bvalid(u_bvalid),
    .bready(u_bready),
    .bresp(u_bresp),
    .bid(u_bid)
  );

endmodule
