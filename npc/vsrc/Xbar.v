// Xbar - AXI4-Lite Crossbar (地址译码 + 多路开关)
// 1 个 master 端口 (来自 Arbiter) → 3 个 slave 端口 (UART, CLINT, MEM)
// 根据请求地址将事务路由到对应的 slave:
//   CLINT: [0x1000_0048, 0x1000_0050)  (mtime 低/high, 8 字节)
//   UART:  [0x1000_0000, 0x1000_0048) + [0x1000_0050, 0x1000_1000)
//   MEM:   其余所有地址
//
// AXI 握手规则:
//   1. valid 不依赖 ready
//   2. valid 一旦置位必须保持直到握手完成
//   3. ready 可依赖 valid
//
// 关键设计: master 端 ready 必须等 slave 端 ready, 否则请求会在 Xbar 丢失
//   - m_arready 依赖选中 slave 的 arready
//   - m_awready 依赖选中 slave 的 awready
//   - m_wready  依赖选中 slave 的 wready (写激活后)

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

  // ===== Slave 0: UART =====
  // 地址空间: [0x1000_0000, 0x1000_0048) + [0x1000_0050, 0x1000_1000)
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

  // ===== Slave 1: CLINT (mtime 只读) =====
  // 地址空间: [0x1000_0048, 0x1000_0050)  (8 字节)
  // AR 通道
  output        clint_arvalid,
  input         clint_arready,
  output [31:0] clint_araddr,
  // R 通道
  input         clint_rvalid,
  output        clint_rready,
  input  [31:0] clint_rdata,
  input  [ 1:0] clint_rresp,
  // AW 通道
  output        clint_awvalid,
  input         clint_awready,
  output [31:0] clint_awaddr,
  // W 通道
  output        clint_wvalid,
  input         clint_wready,
  output [31:0] clint_wdata,
  output [ 3:0] clint_wstrb,
  // B 通道
  input         clint_bvalid,
  output        clint_bready,
  input  [ 1:0] clint_bresp,

  // ===== Slave 2: MEM (其余所有地址) =====
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

  // ========== Slave 选择编码 ==========
  localparam [1:0] SEL_UART  = 2'b00;
  localparam [1:0] SEL_CLINT = 2'b01;
  localparam [1:0] SEL_MEM   = 2'b10;

  // ========== 地址译码 (组合逻辑) ==========
  // CLINT: [0x1000_0048, 0x1000_0050) — mtime lo (0x48) 和 mtime hi (0x4c)
  wire ar_is_clint = (m_araddr >= 32'h1000_0048) && (m_araddr < 32'h1000_0050);
  wire ar_is_uart  = (m_araddr >= 32'h1000_0000) && (m_araddr < 32'h1000_1000) && !ar_is_clint;

  wire aw_is_clint = (m_awaddr >= 32'h1000_0048) && (m_awaddr < 32'h1000_0050);
  wire aw_is_uart  = (m_awaddr >= 32'h1000_0000) && (m_awaddr < 32'h1000_1000) && !aw_is_clint;

  // ========== 当前地址选中的 slave ==========
  wire [1:0] ar_sel = ar_is_clint ? SEL_CLINT :
                       ar_is_uart  ? SEL_UART  :
                                     SEL_MEM;

  wire [1:0] aw_sel = aw_is_clint ? SEL_CLINT :
                       aw_is_uart  ? SEL_UART  :
                                     SEL_MEM;

  // ========== 选中 slave 的 ready (用于反压) ==========
  wire slave_arready_sel = (ar_sel == SEL_CLINT) ? clint_arready :
                           (ar_sel == SEL_UART)  ? uart_arready  :
                                                   mem_arready;
  wire slave_awready_sel = (aw_sel == SEL_CLINT) ? clint_awready :
                           (aw_sel == SEL_UART)  ? uart_awready  :
                                                   mem_awready;

  // ========== 事务追踪寄存器 ==========
  reg read_active;
  reg [1:0] read_sel;     // 使用 SEL_* 编码

  reg write_active;
  reg [1:0] write_sel;    // 使用 SEL_* 编码

  // ========== AR 通道转发 (Master → Slave) ==========
  assign m_arready = !read_active && !rst && slave_arready_sel;

  assign uart_arvalid  = m_arvalid && (ar_sel == SEL_UART)  && !read_active && !rst;
  assign clint_arvalid = m_arvalid && (ar_sel == SEL_CLINT) && !read_active && !rst;
  assign mem_arvalid   = m_arvalid && (ar_sel == SEL_MEM)   && !read_active && !rst;

  assign uart_araddr  = m_araddr;
  assign clint_araddr = m_araddr;
  assign mem_araddr   = m_araddr;

  // ========== R 通道转发 (Slave → Master) ==========
  assign m_rvalid = read_active ? (
                      (read_sel == SEL_UART)  ? uart_rvalid  :
                      (read_sel == SEL_CLINT) ? clint_rvalid :
                                                mem_rvalid
                    ) : 1'b0;

  assign m_rdata = (read_sel == SEL_UART)  ? uart_rdata  :
                   (read_sel == SEL_CLINT) ? clint_rdata :
                                             mem_rdata;

  assign m_rresp = (read_sel == SEL_UART)  ? uart_rresp  :
                   (read_sel == SEL_CLINT) ? clint_rresp :
                                             mem_rresp;

  assign uart_rready  = read_active && (read_sel == SEL_UART)  ? m_rready : 1'b0;
  assign clint_rready = read_active && (read_sel == SEL_CLINT) ? m_rready : 1'b0;
  assign mem_rready   = read_active && (read_sel == SEL_MEM)   ? m_rready : 1'b0;

  // ========== AW 通道转发 (Master → Slave) ==========
  assign m_awready = !write_active && !rst && slave_awready_sel;

  assign uart_awvalid  = m_awvalid && (aw_sel == SEL_UART)  && !write_active && !rst;
  assign clint_awvalid = m_awvalid && (aw_sel == SEL_CLINT) && !write_active && !rst;
  assign mem_awvalid   = m_awvalid && (aw_sel == SEL_MEM)   && !write_active && !rst;

  assign uart_awaddr  = m_awaddr;
  assign clint_awaddr = m_awaddr;
  assign mem_awaddr   = m_awaddr;

  // ========== W 通道转发 (Master → Slave) ==========
  wire [1:0] w_active_sel = write_active ? write_sel : aw_sel;

  assign m_wready = (w_active_sel == SEL_UART)  ? uart_wready  :
                    (w_active_sel == SEL_CLINT) ? clint_wready :
                                                  mem_wready;

  assign uart_wvalid  = m_wvalid && (w_active_sel == SEL_UART)  && !rst;
  assign clint_wvalid = m_wvalid && (w_active_sel == SEL_CLINT) && !rst;
  assign mem_wvalid   = m_wvalid && (w_active_sel == SEL_MEM)   && !rst;

  assign uart_wdata  = m_wdata;
  assign clint_wdata = m_wdata;
  assign mem_wdata   = m_wdata;

  assign uart_wstrb  = m_wstrb;
  assign clint_wstrb = m_wstrb;
  assign mem_wstrb   = m_wstrb;

  // ========== B 通道转发 (Slave → Master) ==========
  assign m_bvalid = write_active ? (
                      (write_sel == SEL_UART)  ? uart_bvalid  :
                      (write_sel == SEL_CLINT) ? clint_bvalid :
                                                 mem_bvalid
                    ) : 1'b0;

  assign m_bresp = (write_sel == SEL_UART)  ? uart_bresp  :
                   (write_sel == SEL_CLINT) ? clint_bresp :
                                              mem_bresp;

  assign uart_bready  = write_active && (write_sel == SEL_UART)  ? m_bready : 1'b0;
  assign clint_bready = write_active && (write_sel == SEL_CLINT) ? m_bready : 1'b0;
  assign mem_bready   = write_active && (write_sel == SEL_MEM)   ? m_bready : 1'b0;

  // ========== 读事务状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      read_active <= 1'b0;
      read_sel    <= SEL_UART;
    end else begin
      if (!read_active) begin
        // AR 握手: master 和 slave 同时完成 (因 m_arready 等了 slave_arready)
        if (m_arvalid && m_arready) begin
          read_active <= 1'b1;
          read_sel    <= ar_sel;
        end
      end else begin
        // R 握手: slave 响应返回给 master
        if (m_rvalid && m_rready) begin
          read_active <= 1'b0;
        end
      end
    end
  end

  // ========== 写事务状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      write_active <= 1'b0;
      write_sel    <= SEL_UART;
    end else begin
      if (!write_active) begin
        // AW 握手: master 和 slave 同时完成
        if (m_awvalid && m_awready) begin
          write_active <= 1'b1;
          write_sel    <= aw_sel;
        end
      end else begin
        // B 握手: slave 写回复返回给 master
        if (m_bvalid && m_bready) begin
          write_active <= 1'b0;
        end
      end
    end
  end

endmodule
