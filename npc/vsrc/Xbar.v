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
// 简化版实现:
//   - 无仲裁逻辑，假设同时只有一个 master 请求
//   - AR/R 和 AW/W/B 独立处理
//   - 通过寄存器记录路由状态

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
  function automatic [1:0] decode_addr(input [31:0] addr);
    casez (addr[31:8])
      24'h100000: return 2'b01;  // UART
      24'b1000_????_????_????_????_??: return 2'b10;  // MEM (0x8???????)
      default:    return 2'b00;  // 无效地址
    endcase
  endfunction

  wire [1:0] ar_slave = decode_addr(master_araddr);
  wire [1:0] aw_slave = decode_addr(master_awaddr);

  // ========== 路由状态寄存器 ==========
  reg [1:0] r_slave;  // 当前读事务的 slave
  reg [1:0] b_slave;  // 当前写事务的 slave

  // ========== AR 通道转发 ==========
  // 地址有效才转发，无效地址立即响应
  assign master_arready = (ar_slave == 2'b01) ? uart_arready :
                          (ar_slave == 2'b10) ? mem_arready  :
                          1'b1;  // 无效地址立即接受

  assign uart_arvalid = master_arvalid && (ar_slave == 2'b01);
  assign mem_arvalid  = master_arvalid && (ar_slave == 2'b10);
  assign uart_araddr  = master_araddr;
  assign mem_araddr   = master_araddr;

  // ========== R 通道转发 ==========
  assign master_rvalid = (r_slave == 2'b01) ? uart_rvalid :
                         (r_slave == 2'b10) ? mem_rvalid  :
                         (r_slave == 2'b11) ? 1'b1       :  // 无效地址立即响应
                         1'b0;

  assign master_rdata  = (r_slave == 2'b01) ? uart_rdata :
                         (r_slave == 2'b10) ? mem_rdata  :
                         32'b0;

  assign master_rresp  = (r_slave == 2'b01) ? uart_rresp :
                         (r_slave == 2'b10) ? mem_rresp  :
                         2'b11;  // DECERR

  assign uart_rready = (r_slave == 2'b01) ? master_rready : 1'b0;
  assign mem_rready  = (r_slave == 2'b10) ? master_rready : 1'b0;

  // ========== AW 通道转发 ==========
  assign master_awready = (aw_slave == 2'b01) ? uart_awready :
                          (aw_slave == 2'b10) ? mem_awready  :
                          1'b1;  // 无效地址立即接受

  assign uart_awvalid = master_awvalid && (aw_slave == 2'b01);
  assign mem_awvalid  = master_awvalid && (aw_slave == 2'b10);
  assign uart_awaddr  = master_awaddr;
  assign mem_awaddr   = master_awaddr;

  // ========== W 通道转发 ==========
  // W 通道数据同时发给所有 slave，但只有地址匹配的 slave 会响应
  assign master_wready = uart_wready | mem_wready | (b_slave == 2'b00);
  assign uart_wvalid = master_wvalid;
  assign mem_wvalid  = master_wvalid;
  assign uart_wdata  = master_wdata;
  assign mem_wdata   = master_wdata;
  assign uart_wstrb  = master_wstrb;
  assign mem_wstrb   = master_wstrb;

  // ========== B 通道转发 ==========
  assign master_bvalid = (b_slave == 2'b01) ? uart_bvalid :
                         (b_slave == 2'b10) ? mem_bvalid  :
                         (b_slave == 2'b11) ? 1'b1       :  // 无效地址立即响应
                         1'b0;

  assign master_bresp  = (b_slave == 2'b01) ? uart_bresp :
                         (b_slave == 2'b10) ? mem_bresp  :
                         2'b11;  // DECERR

  assign uart_bready = (b_slave == 2'b01) ? master_bready : 1'b0;
  assign mem_bready  = (b_slave == 2'b10) ? master_bready : 1'b0;

  // ========== 路由状态追踪 ==========
  always @(posedge clk) begin
    if (rst) begin
      r_slave <= 2'b00;
      b_slave <= 2'b00;
    end else begin
      // AR 握手：记录读事务路由
      if (master_arvalid && master_arready) begin
        r_slave <= (ar_slave == 2'b00) ? 2'b11 : ar_slave;  // 2'b11 表示无效地址
      end

      // R 握手：清除读事务路由
      if (master_rvalid && master_rready) begin
        r_slave <= 2'b00;
      end

      // AW 握手：记录写事务路由
      if (master_awvalid && master_awready) begin
        b_slave <= (aw_slave == 2'b00) ? 2'b11 : aw_slave;  // 2'b11 表示无效地址
      end

      // B 握手：清除写事务路由
      if (master_bvalid && master_bready) begin
        b_slave <= 2'b00;
      end
    end
  end

endmodule
