module top(
  input         clk,
  input         rst,

  // 调试输出 (C++ 侧通过 DPI-C 获取 CPU 状态, 不依赖这些端口)
  output [31:0] pc_out,
  output [31:0] inst_out,
  output        cpu_valid
);

  // ========== CPU 核心的 AXI4 master 信号 ==========
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

  // ========== 调试输出 (占位, 防止端口悬空警告) ==========
  assign pc_out    = 32'b0;
  assign inst_out  = 32'b0;
  assign cpu_valid = 1'b0;

  // ========== 模块实例化 ==========

  // CPU 核心
  ysyx_26020070 u_cpu(
    .clock(clk),
    .reset(rst),
    .io_interrupt(1'b0),
    // AXI4 master → 直接连到 pmem_axi
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

  // 统一 pmem 后端 (主存 + 设备, 由 C++ DPI-C pmem_read/pmem_write 处理)
  pmem_axi u_pmem(
    .clk(clk),
    .rst(rst),
    .arvalid(m_arvalid),
    .arready(m_arready),
    .araddr(m_araddr),
    .arid(m_arid),
    .arlen(m_arlen),
    .arsize(m_arsize),
    .arburst(m_arburst),
    .rvalid(m_rvalid),
    .rready(m_rready),
    .rdata(m_rdata),
    .rresp(m_rresp),
    .rlast(m_rlast),
    .rid(m_rid),
    .awvalid(m_awvalid),
    .awready(m_awready),
    .awaddr(m_awaddr),
    .awid(m_awid),
    .awlen(m_awlen),
    .awsize(m_awsize),
    .awburst(m_awburst),
    .wvalid(m_wvalid),
    .wready(m_wready),
    .wdata(m_wdata),
    .wstrb(m_wstrb),
    .wlast(m_wlast),
    .bvalid(m_bvalid),
    .bready(m_bready),
    .bresp(m_bresp),
    .bid(m_bid)
  );

endmodule
