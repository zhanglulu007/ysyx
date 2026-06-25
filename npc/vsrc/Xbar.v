// Xbar - AXI4-Lite Crossbar (多进多出总线开关)
// 根据地址将请求转发到不同的 slave 设备
//
// 功能说明 (讲义 B1 第 754-773 行):
//   1. 地址译码: 根据请求地址决定转发到哪个 slave
//   2. 请求转发: 将 master 的请求转发到选中的 slave
//   3. 响应转发: 将 slave 的响应转发回对应的 master
//
// 地址映射 (npc.h):
//   - UART:      [0x1000_0000, 0x1000_00FF) → slave 0 (UART)
//   - MEM:       [0x8000_0000, 0x8FFF_FFFF) → slave 1 (MEM)
//   - 其他地址:  返回错误 (DECERR)
//
// 当前架构:
//   +-----+      +------+      +-----+
//   | IFU | ---> |      | ---> | UART|  [0x1000_0000, 0x1000_00FF)
//   +-----+      |      |      +-----+
//                | Xbar |
//   +-----+      |      |      +-----+
//   | LSU | ---> |      | ---> | MEM |  [0x8000_0000, 0x8FFF_FFFF)
//   +-----+      +------+      +-----+
//
// 注意: 当前实现为简化版，支持单个 master (LSU) 访问多个 slave
//       IFU 只能访问 MEM (取指)，不能访问 UART
//       如需支持多 master，需要增加仲裁逻辑

module Xbar(
  input clk,
  input rst,

  // ===== Master (来自 AXIArbiter) =====
  // AR 通道
  input         master_arvalid,
  output        master_arready,
  input  [31:0] master_araddr,
  // R 通道
  output        master_rvalid,
  input         master_rready,
  output [31:0] master_rdata,
  output [ 1:0] master_rresp,
  // AW 通道
  input         master_awvalid,
  output        master_awready,
  input  [31:0] master_awaddr,
  // W 通道
  input         master_wvalid,
  output        master_wready,
  input  [31:0] master_wdata,
  input  [ 3:0] master_wstrb,
  // B 通道
  output        master_bvalid,
  input         master_bready,
  output [ 1:0] master_bresp,

  // ===== Slave 0: UART =====
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

  // ===== Slave 1: MEM =====
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

  // ========== 地址译码 ==========
  // UART: [0x1000_0000, 0x1000_00FF)
  // MEM:  [0x8000_0000, 0x8FFF_FFFF)
  wire is_uart_addr = (master_araddr[31:8] == 24'h100000) ||
                       (master_awaddr[31:8] == 24'h100000);
  wire is_mem_addr  = (master_araddr[31:28] == 4'h8) ||
                       (master_awaddr[31:28] == 4'h8);

  // ========== 状态机 ==========
  // 记录当前事务路由到哪个 slave
  localparam SLAVE_NONE = 2'b00;
  localparam SLAVE_UART = 2'b01;
  localparam SLAVE_MEM  = 2'b10;

  reg [1:0] current_slave;    // 当前事务的 slave
  reg [1:0] next_slave;       // 下一个事务的 slave (用于写路径)
  reg       is_write;         // 当前事务类型: 1=写, 0=读

  // 写路径握手追踪 (AW 和 W 可独立完成)
  reg aw_done;
  reg w_done;

  // ========== AR 通道转发 ==========
  // Master → Slave
  assign uart_arvalid = master_arvalid && is_uart_addr && (current_slave == SLAVE_NONE);
  assign mem_arvalid  = master_arvalid && is_mem_addr  && (current_slave == SLAVE_NONE);

  assign uart_araddr  = master_araddr;
  assign mem_araddr   = master_araddr;

  // Slave → Master
  // 未匹配任何地址时，返回 DECERR (2'b11)
  wire ar_match = is_uart_addr || is_mem_addr;
  assign master_arready = ar_match ?
                           (is_uart_addr ? uart_arready : mem_arready) :
                           1'b1;  // 不匹配地址立即响应

  // ========== R 通道转发 ==========
  // Slave → Master
  assign master_rvalid = (current_slave == SLAVE_UART) ? uart_rvalid :
                         (current_slave == SLAVE_MEM)  ? mem_rvalid  :
                         1'b0;

  assign master_rdata  = (current_slave == SLAVE_UART) ? uart_rdata :
                         (current_slave == SLAVE_MEM)  ? mem_rdata  :
                         32'b0;

  assign master_rresp  = (current_slave == SLAVE_UART) ? uart_rresp :
                         (current_slave == SLAVE_MEM)  ? mem_rresp  :
                         2'b11;  // DECERR

  // Master → Slave
  assign uart_rready = (current_slave == SLAVE_UART) ? master_rready : 1'b0;
  assign mem_rready  = (current_slave == SLAVE_MEM)  ? master_rready : 1'b0;

  // ========== AW 通道转发 ==========
  // Master → Slave
  assign uart_awvalid = master_awvalid && is_uart_addr && !aw_done;
  assign mem_awvalid  = master_awvalid && is_mem_addr  && !aw_done;

  assign uart_awaddr  = master_awaddr;
  assign mem_awaddr   = master_awaddr;

  // Slave → Master
  wire aw_match = is_uart_addr || is_mem_addr;
  assign master_awready = aw_match ?
                          (is_uart_addr ? uart_awready : mem_awready) :
                          1'b1;  // 不匹配地址立即响应

  // ========== W 通道转发 ==========
  // Master → Slave
  assign uart_wvalid = master_wvalid && !w_done;
  assign mem_wvalid  = master_wvalid && !w_done;

  assign uart_wdata  = master_wdata;
  assign mem_wdata   = master_wdata;
  assign uart_wstrb  = master_wstrb;
  assign mem_wstrb   = master_wstrb;

  // Slave → Master
  assign master_wready = (next_slave == SLAVE_UART) ? uart_wready :
                         (next_slave == SLAVE_MEM)  ? mem_wready  :
                         1'b1;  // 未匹配地址时立即响应

  // ========== B 通道转发 ==========
  // Slave → Master
  assign master_bvalid = (current_slave == SLAVE_UART) ? uart_bvalid :
                         (current_slave == SLAVE_MEM)  ? mem_bvalid  :
                         1'b0;

  assign master_bresp  = (current_slave == SLAVE_UART) ? uart_bresp :
                         (current_slave == SLAVE_MEM)  ? mem_bresp  :
                         2'b11;  // DECERR

  // Master → Slave
  assign uart_bready = (current_slave == SLAVE_UART) ? master_bready : 1'b0;
  assign mem_bready  = (current_slave == SLAVE_MEM)  ? master_bready : 1'b0;

  // ========== 状态机 ==========
  // 追踪当前事务状态
  always @(posedge clk) begin
    if (rst) begin
      current_slave <= SLAVE_NONE;
      next_slave    <= SLAVE_NONE;
      is_write      <= 1'b0;
      aw_done       <= 1'b0;
      w_done        <= 1'b0;
    end else begin
      // 读事务
      if (master_arvalid && master_arready) begin
        current_slave <= is_uart_addr ? SLAVE_UART : SLAVE_MEM;
        is_write      <= 1'b0;
      end

      // 读事务完成
      if (master_rvalid && master_rready) begin
        current_slave <= SLAVE_NONE;
      end

      // 写事务: AW 握手
      if (master_awvalid && master_awready && !aw_done) begin
        next_slave <= is_uart_addr ? SLAVE_UART : SLAVE_MEM;
        aw_done    <= 1'b1;
      end

      // 写事务: W 握手
      if (master_wvalid && master_wready && !w_done) begin
        w_done <= 1'b1;
      end

      // 写事务开始 (AW 和 W 都完成)
      if (aw_done && w_done) begin
        current_slave <= next_slave;
        is_write      <= 1'b1;
      end

      // 写事务完成
      if (master_bvalid && master_bready) begin
        current_slave <= SLAVE_NONE;
        next_slave    <= SLAVE_NONE;
        aw_done       <= 1'b0;
        w_done        <= 1'b0;
      end
    end
  end

endmodule
