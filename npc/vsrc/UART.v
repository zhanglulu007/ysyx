// UART - AXI4-Lite UART Slave Module
// 通过 AXI4-Lite 接口实现字符输出 (printf 方式)
// 地址空间: [0x1000_0000, 0x1000_0fff)
// 写操作: 将 wdata[7:0] 作为字符通过 $write 输出
// 读操作: 返回 0 (无状态寄存器)
//
// AXI 握手规则:
//   1. valid 不依赖 ready
//   2. valid 一旦置位必须保持直到握手完成
//   3. ready 可依赖 valid
//
// 状态机:
//   IDLE:   等待 AR (读) 或 AW+W (写) 请求
//   R_BUSY: 读事务, 等待 rvalid 握手 (单周期响应)
//   W_BUSY: 写事务, 等待 bvalid 握手

module UART(
  input clk,
  input rst,

  // ===== AXI4-Lite AR 通道 (读地址) =====
  input         uart_arvalid,
  output        uart_arready,
  input  [31:0] uart_araddr,

  // ===== AXI4-Lite R 通道 (读数据) =====
  output        uart_rvalid,
  input         uart_rready,
  output [31:0] uart_rdata,
  output [ 1:0] uart_rresp,

  // ===== AXI4-Lite AW 通道 (写地址) =====
  input         uart_awvalid,
  output        uart_awready,
  input  [31:0] uart_awaddr,

  // ===== AXI4-Lite W 通道 (写数据) =====
  input         uart_wvalid,
  output        uart_wready,
  input  [31:0] uart_wdata,
  input  [ 3:0] uart_wstrb,

  // ===== AXI4-Lite B 通道 (写回复) =====
  output        uart_bvalid,
  input         uart_bready,
  output [ 1:0] uart_bresp
);

  // ========== 状态机 ==========
  localparam IDLE   = 2'b00;  // 等待请求
  localparam R_BUSY = 2'b01;  // 读事务进行中
  localparam W_BUSY = 2'b10;  // 写事务进行中

  reg [1:0] state;

  // 写通道握手追踪 (AW 和 W 可独立完成)
  reg aw_done;
  reg w_done;
  reg [7:0] latched_char;  // 锁存的待输出字符

  // ========== 组合逻辑: 检测 AW/W 是否在本周期完成 ==========
  wire aw_completing = (state == IDLE) && uart_awvalid && uart_awready && !aw_done;
  wire w_completing  = (state == IDLE) && uart_wvalid  && uart_wready  && !w_done;

  // AW/W 是否已就绪 (包括本周期完成)
  wire aw_ready_c = aw_done || aw_completing;
  wire w_ready_c  = w_done  || w_completing;

  // ========== 通道就绪信号 ==========
  assign uart_arready = (state == IDLE) && !rst;
  assign uart_awready = (state == IDLE) && !aw_done && !rst;
  assign uart_wready  = (state == IDLE) && !w_done && !rst;

  // ========== 响应信号 ==========
  assign uart_rvalid = (state == R_BUSY);
  assign uart_rdata  = 32'h00000000;  // 读串口始终返回 0
  assign uart_rresp  = 2'b00;         // OKAY

  assign uart_bvalid = (state == W_BUSY);
  assign uart_bresp  = 2'b00;         // OKAY

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state        <= IDLE;
      aw_done      <= 1'b0;
      w_done       <= 1'b0;
      latched_char <= 8'b0;
    end else begin
      case (state)
        IDLE: begin
          // ----- 读事务: AR 握手 -----
          if (uart_arvalid && uart_arready) begin
            state <= R_BUSY;
          end
          // ----- 写事务: AW 和 W 握手追踪 -----
          else begin
            // 当 AW 和 W 均完成 (包括本周期) 时, 输出字符并进入 B 响应
            if (aw_ready_c && w_ready_c) begin
              // 使用本周期 W 数据或锁存的上周期数据
              if (w_completing)
                $write("%c", uart_wdata[7:0]);
              else
                $write("%c", latched_char);

              state   <= W_BUSY;
              aw_done <= 1'b0;
              w_done  <= 1'b0;
            end else begin
              // 各自独立追踪
              if (aw_completing)
                aw_done <= 1'b1;

              if (w_completing) begin
                w_done       <= 1'b1;
                latched_char <= uart_wdata[7:0];
              end
            end
          end
        end

        R_BUSY: begin
          // R 握手: rvalid && rready
          if (uart_rvalid && uart_rready) begin
            state <= IDLE;
          end
        end

        W_BUSY: begin
          // B 握手: bvalid && bready
          if (uart_bvalid && uart_bready) begin
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
