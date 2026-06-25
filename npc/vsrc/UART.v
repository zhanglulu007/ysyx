// UART - AXI4-Lite UART 设备模块
// 实现一个简单的 UART 输出功能：写入地址 0x10000000 时通过 $write() 输出字符
//
// 功能说明 (讲义 B1 第 785-788 行):
//   - 设备寄存器地址: 0x10000000 (SERIAL_PORT)
//   - 写操作: 将写入数据的低 8 位作为字符输出
//   - 读操作: 返回 0 (串口只写，但总线协议要求响应)
//
// AXI4-Lite 接口:
//   - AR 通道 (读地址): 支持
//   - R  通道 (读数据): 支持，返回 0
//   - AW 通道 (写地址): 支持
//   - W  通道 (写数据): 支持，输出字符
//   - B  通道 (写回复): 支持
//
// AXI 握手规则 (防死锁/活锁):
//   1. valid 不依赖 ready (发送方自主决定)
//   2. valid 一旦置位必须保持直到握手完成
//   3. ready 可依赖 valid (接收方可等待)
//
// 状态机:
//   IDLE:   等待 AR (读) 或 AW+W (写) 握手
//   R_BUSY: 读事务进行中，立即响应
//   W_BUSY: 写事务进行中，立即响应

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

  // ========== 状态机定义 ==========
  localparam IDLE   = 2'b00;  // 等待读/写请求
  localparam R_BUSY = 2'b01;  // 读事务进行中
  localparam W_BUSY = 2'b10;  // 写事务进行中

  reg [1:0] state;

  // 写路径追踪: AW 和 W 可独立握手
  reg        aw_done;
  reg        w_done;
  reg [31:0] w_data_latched;

  // ========== 通道就绪信号 ==========
  // UART 响应很快，ready 始终为 1（无延迟）
  assign uart_arready = (state == IDLE) && !rst;
  assign uart_awready = (state == IDLE) && !aw_done && !rst;
  assign uart_wready  = (state == IDLE) && !w_done && !rst;

  // ========== 响应信号 ==========
  assign uart_rvalid = (state == R_BUSY);
  assign uart_bvalid = (state == W_BUSY);

  // 串口只写，读返回 0
  assign uart_rdata = 32'b0;
  assign uart_rresp = 2'b00;  // OKAY
  assign uart_bresp = 2'b00;  // OKAY

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state          <= IDLE;
      aw_done        <= 1'b0;
      w_done         <= 1'b0;
      w_data_latched <= 32'b0;
    end else begin
      case (state)
        IDLE: begin
          // ----- 读事务: AR 握手 -----
          if (uart_arvalid && uart_arready) begin
            // 读操作立即完成（串口只写，返回 0）
            state <= R_BUSY;
          end
          // ----- 写事务: AW 和 W 握手追踪 -----
          else begin
            // AW 握手
            if (uart_awvalid && uart_awready && !aw_done) begin
              aw_done <= 1'b1;
            end

            // W 握手
            if (uart_wvalid && uart_wready && !w_done) begin
              w_data_latched <= uart_wdata;
              w_done <= 1'b1;
            end

            // AW 和 W 均完成时输出字符
            if (aw_done && w_done) begin
              // 输出字符（低 8 位）
              $write("%c", w_data_latched[7:0]);

              state    <= W_BUSY;
              aw_done  <= 1'b0;
              w_done   <= 1'b0;
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
