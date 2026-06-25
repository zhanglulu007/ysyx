// CLINT - Core Local INTerrupt controller (AXI4-Lite Slave)
// 实现 RISC-V CLINT 的时钟功能 (mtime 寄存器)
// 地址: [0x1000_0048, 0x1000_0050) (8 字节)
//   0x10000048: mtime 低 32 位 (只读)
//   0x1000004c: mtime 高 32 位 (只读)
// mtime 为 64 位计数器, 每周期递增 1
//
// AXI 握手规则:
//   1. valid 不依赖 ready
//   2. valid 一旦置位必须保持直到握手完成
//   3. ready 可依赖 valid
//
// 状态机:
//   IDLE:   等待 AR (读) 或 AW+W (写) 请求
//   R_BUSY: 读事务, 等待 rvalid 握手
//   W_BUSY: 写事务, 等待 bvalid 握手 (写被静默忽略)

module CLINT(
  input clk,
  input rst,

  // ===== AXI4-Lite AR 通道 (读地址) =====
  input         clint_arvalid,
  output        clint_arready,
  input  [31:0] clint_araddr,

  // ===== AXI4-Lite R 通道 (读数据) =====
  output        clint_rvalid,
  input         clint_rready,
  output [31:0] clint_rdata,
  output [ 1:0] clint_rresp,

  // ===== AXI4-Lite AW 通道 (写地址) =====
  input         clint_awvalid,
  output        clint_awready,
  input  [31:0] clint_awaddr,

  // ===== AXI4-Lite W 通道 (写数据) =====
  input         clint_wvalid,
  output        clint_wready,
  input  [31:0] clint_wdata,
  input  [ 3:0] clint_wstrb,

  // ===== AXI4-Lite B 通道 (写回复) =====
  output        clint_bvalid,
  input         clint_bready,
  output [ 1:0] clint_bresp
);

  // ========== mtime 寄存器 (64 位, 每周期递增) ==========
  reg [63:0] mtime;

  // ========== 状态机 ==========
  localparam IDLE   = 2'b00;  // 等待请求
  localparam R_BUSY = 2'b01;  // 读事务: 等待 R 握手
  localparam W_BUSY = 2'b10;  // 写事务: 等待 B 握手 (写被静默忽略)

  reg [1:0] state;

  // 读数据锁存 (AR 握手时保存)
  reg [31:0] latched_rdata;

  // 写通道握手追踪 (AW 和 W 可独立完成)
  reg aw_done;
  reg w_done;

  // 读地址锁存 (用于日志)
  reg [31:0] logged_araddr;

  // ========== 组合逻辑: 检测 AW/W 是否在本周期完成 ==========
  wire aw_completing = (state == IDLE) && clint_awvalid && clint_awready && !aw_done;
  wire w_completing  = (state == IDLE) && clint_wvalid  && clint_wready  && !w_done;

  // AW/W 是否已就绪 (包括本周期完成)
  wire aw_ready_c = aw_done || aw_completing;
  wire w_ready_c  = w_done  || w_completing;

  // ========== 通道就绪信号 ==========
  assign clint_arready = (state == IDLE) && !rst;
  assign clint_awready = (state == IDLE) && !aw_done && !rst;
  assign clint_wready  = (state == IDLE) && !w_done && !rst;

  // ========== 响应信号 ==========
  assign clint_rvalid = (state == R_BUSY);
  assign clint_rdata  = latched_rdata;
  assign clint_rresp  = 2'b00;         // OKAY

  assign clint_bvalid = (state == W_BUSY);
  assign clint_bresp  = 2'b00;         // OKAY

  // ========== mtime 计数器 ==========
  always @(posedge clk) begin
    if (rst) begin
      mtime <= 64'b0;
    end else begin
      mtime <= mtime + 64'd1;
    end
  end

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state         <= IDLE;
      aw_done       <= 1'b0;
      w_done        <= 1'b0;
      latched_rdata <= 32'b0;
      logged_araddr <= 32'b0;
    end else begin
      case (state)
        IDLE: begin
          // ----- 读事务: AR 握手 -----
          if (clint_arvalid && clint_arready) begin
            // 根据地址选择 mtime 的低 32 位或高 32 位
            // clint_araddr[2]: 0 = 低 32 位 (0x48), 1 = 高 32 位 (0x4c)
            latched_rdata <= clint_araddr[2] ? mtime[63:32] : mtime[31:0];
            logged_araddr <= clint_araddr;
            state <= R_BUSY;
          end
          // ----- 写事务: AW 和 W 握手追踪 (写被静默忽略) -----
          else begin
            // 当 AW 和 W 均完成 (包括本周期) 时, 进入 W_BUSY
            if (aw_ready_c && w_ready_c) begin
              state   <= W_BUSY;
              aw_done <= 1'b0;
              w_done  <= 1'b0;
            end else begin
              // 各自独立追踪
              if (aw_completing) begin
                aw_done <= 1'b1;
              end

              if (w_completing) begin
                w_done <= 1'b1;
              end
            end
          end
        end

        R_BUSY: begin
          // R 握手: rvalid && rready
          if (clint_rvalid && clint_rready) begin
            state <= IDLE;
          end
        end

        W_BUSY: begin
          // B 握手: bvalid && bready
          if (clint_bvalid && clint_bready) begin
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
