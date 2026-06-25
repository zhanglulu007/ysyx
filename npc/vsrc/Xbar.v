// Xbar - AXI4-Lite Crossbar (地址译码 + 多路开关)
// 1 个 master 端口 (来自 Arbiter) → 2 个 slave 端口 (UART, MEM)
// 根据请求地址将事务路由到对应的 slave:
//   UART: [0x1000_0000, 0x1000_0fff)
//   MEM:  [0x8000_0000, 0x8800_0000)
// 未映射地址返回 DECERR (resp = 2'b11)
//
// AXI 握手规则:
//   1. valid 不依赖 ready
//   2. valid 一旦置位必须保持直到握手完成
//   3. ready 可依赖 valid
//
// 设计要点:
//   - 读/写事务独立追踪 (各自的 slave 选择和激活状态)
//   - 地址译码在 AR/AW 握手时完成, 结果锁存供响应通道使用
//   - 未映射地址由 Xbar 直接生成 DECERR 响应

module Xbar(
  input clk,
  input rst,

  // ===== Master 端口 (连接 Arbiter) =====
  // AR 通道
  input         m_arvalid,
  output        m_arready,
  input  [31:0] m_araddr,
  // R 通道
  output        m_rvalid,
  input         m_rready,
  output [31:0] m_rdata,
  output [ 1:0] m_rresp,
  // AW 通道
  input         m_awvalid,
  output        m_awready,
  input  [31:0] m_awaddr,
  // W 通道
  input         m_wvalid,
  output        m_wready,
  input  [31:0] m_wdata,
  input  [ 3:0] m_wstrb,
  // B 通道
  output        m_bvalid,
  input         m_bready,
  output [ 1:0] m_bresp,

  // ===== Slave 0: UART (地址空间 [0x1000_0000, 0x1000_0fff)) =====
  // AR 通道
  output        uart_arvalid,
  input         uart_arready,
  output [31:0] uart_araddr,
  // R 通道
  input         uart_rvalid,
  output        uart_rready,
  input  [31:0] uart_rdata,
  input  [ 1:0] uart_rresp,
  // AW 通道
  output        uart_awvalid,
  input         uart_awready,
  output [31:0] uart_awaddr,
  // W 通道
  output        uart_wvalid,
  input         uart_wready,
  output [31:0] uart_wdata,
  output [ 3:0] uart_wstrb,
  // B 通道
  input         uart_bvalid,
  output        uart_bready,
  input  [ 1:0] uart_bresp,

  // ===== Slave 1: MEM (地址空间 [0x8000_0000, 0x8800_0000)) =====
  // AR 通道
  output        mem_arvalid,
  input         mem_arready,
  output [31:0] mem_araddr,
  // R 通道
  input         mem_rvalid,
  output        mem_rready,
  input  [31:0] mem_rdata,
  input  [ 1:0] mem_rresp,
  // AW 通道
  output        mem_awvalid,
  input         mem_awready,
  output [31:0] mem_awaddr,
  // W 通道
  output        mem_wvalid,
  input         mem_wready,
  output [31:0] mem_wdata,
  output [ 3:0] mem_wstrb,
  // B 通道
  input         mem_bvalid,
  output        mem_bready,
  input  [ 1:0] mem_bresp
);

  // ========== 地址译码 (组合逻辑) ==========
  // 对 AR 地址译码
  wire ar_is_uart = (m_araddr >= 32'h1000_0000) && (m_araddr < 32'h1000_1000);
  wire ar_is_mem  = (m_araddr >= 32'h8000_0000) && (m_araddr < 32'h8800_0000);

  // 对 AW 地址译码
  wire aw_is_uart = (m_awaddr >= 32'h1000_0000) && (m_awaddr < 32'h1000_1000);
  wire aw_is_mem  = (m_awaddr >= 32'h8000_0000) && (m_awaddr < 32'h8800_0000);

  // ========== 事务追踪寄存器 ==========
  // 读事务
  reg read_active;
  reg read_sel_uart;   // 1 = UART, 0 = MEM
  reg read_is_error;   // 1 = DECERR (地址未映射)

  // 写事务
  reg write_active;
  reg write_sel_uart;  // 1 = UART, 0 = MEM
  reg write_is_error;  // 1 = DECERR
  reg write_w_done;    // 1 = W 通道握手已完成 (用于 error case 的 B 生成)

  // ========== AR 通道转发 (Master → Slave) ==========
  // 读事务未激活时, 就绪接收新的读地址
  assign m_arready = !read_active && !rst;

  // 使用 m_arready 控制流: 当 m_arready=1 时允许新请求, 直接转发
  assign uart_arvalid = m_arvalid && ar_is_uart && !read_active && !rst;
  assign mem_arvalid  = m_arvalid && ar_is_mem  && !read_active && !rst;

  assign uart_araddr = m_araddr;
  assign mem_araddr  = m_araddr;

  // ========== R 通道转发 (Slave → Master) ==========
  // 从选中 slave 或错误生成器获取响应
  assign m_rvalid = read_active ? (read_is_error ? 1'b1 :
                                   read_sel_uart ? uart_rvalid : mem_rvalid) : 1'b0;

  assign m_rdata  = read_sel_uart ? uart_rdata : mem_rdata;
  assign m_rresp  = read_is_error ? 2'b11 :
                    read_sel_uart ? uart_rresp : mem_rresp;

  // rready: 仅转发给选中的 slave
  assign uart_rready = read_active && read_sel_uart && !read_is_error ? m_rready : 1'b0;
  assign mem_rready  = read_active && !read_sel_uart && !read_is_error ? m_rready : 1'b0;

  // ========== AW 通道转发 (Master → Slave) ==========
  // 写事务未激活时, 就绪接收新的写地址
  assign m_awready = !write_active && !rst;

  assign uart_awvalid = m_awvalid && aw_is_uart && !write_active && !rst;
  assign mem_awvalid  = m_awvalid && aw_is_mem  && !write_active && !rst;

  assign uart_awaddr = m_awaddr;
  assign mem_awaddr  = m_awaddr;

  // ========== W 通道转发 (Master → Slave) ==========
  // wready: 转发自选中 slave (写事务激活后) 或直接允许 (AW 阶段)
  // 在 write_active 之前 (AW 握手同时或之前), 根据 aw_is_* 选择
  assign m_wready = write_active ? (write_is_error ? 1'b1 :
                                    write_sel_uart ? uart_wready : mem_wready) :
                     (aw_is_uart ? uart_wready :
                      aw_is_mem  ? mem_wready  : 1'b1);  // error 情况也接受

  assign uart_wvalid = m_wvalid && ((write_active && write_sel_uart && !write_is_error) ||
                                    (!write_active && aw_is_uart)) && !rst;
  assign mem_wvalid  = m_wvalid && ((write_active && !write_sel_uart && !write_is_error) ||
                                    (!write_active && aw_is_mem)) && !rst;

  assign uart_wdata = m_wdata;
  assign mem_wdata  = m_wdata;

  assign uart_wstrb = m_wstrb;
  assign mem_wstrb  = m_wstrb;

  // ========== B 通道转发 (Slave → Master) ==========
  // 对于 DECERR case: 必须等 AW 和 W 均完成后才能 assert bvalid
  // 对于正常 case: slave 的 bvalid 已经隐含 W 完成
  assign m_bvalid = write_active ? (write_is_error ? (write_w_done) :
                                    write_sel_uart ? uart_bvalid : mem_bvalid) : 1'b0;

  assign m_bresp  = write_is_error ? 2'b11 :
                    write_sel_uart ? uart_bresp : mem_bresp;

  // bready: 仅转发给选中的 slave (error 时不转发, Xbar 自己生成 B)
  assign uart_bready = write_active && write_sel_uart && !write_is_error ? m_bready : 1'b0;
  assign mem_bready  = write_active && !write_sel_uart && !write_is_error ? m_bready : 1'b0;

  // ========== 读事务状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      read_active   <= 1'b0;
      read_sel_uart <= 1'b0;
      read_is_error <= 1'b0;
    end else begin
      if (!read_active) begin
        // 等待 AR 握手, 锁存译码结果
        if (m_arvalid && m_arready) begin
          read_active   <= 1'b1;
          read_sel_uart <= ar_is_uart;
          read_is_error <= !ar_is_uart && !ar_is_mem;
        end
      end else begin
        // 等待 R 握手完成
        if (m_rvalid && m_rready) begin
          read_active   <= 1'b0;
          read_sel_uart <= 1'b0;
          read_is_error <= 1'b0;
        end
      end
    end
  end

  // ========== 写事务状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      write_active   <= 1'b0;
      write_sel_uart <= 1'b0;
      write_is_error <= 1'b0;
      write_w_done   <= 1'b0;
    end else begin
      if (!write_active) begin
        // 等待 AW 握手, 锁存译码结果
        if (m_awvalid && m_awready) begin
          write_active   <= 1'b1;
          write_sel_uart <= aw_is_uart;
          write_is_error <= !aw_is_uart && !aw_is_mem;
          // 若 W 在同周期也完成握手, 直接标记完成
          write_w_done   <= (m_wvalid && m_wready);
        end
      end else begin
        // 追踪 W 握手完成 (error 时需要知道 W 是否已完成)
        if (m_wvalid && m_wready && !write_w_done) begin
          write_w_done <= 1'b1;
        end

        // 等待 B 握手完成
        if (m_bvalid && m_bready) begin
          write_active   <= 1'b0;
          write_sel_uart <= 1'b0;
          write_is_error <= 1'b0;
          write_w_done   <= 1'b0;
        end
      end
    end
  end

endmodule
