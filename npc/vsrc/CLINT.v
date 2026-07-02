// CLINT - Core Local INTerrupt controller
// 核心局部中断控制器：实现 mtime 计时器 (64位计数器)
// 完整 AXI4 接口，只读访问
// 地址空间: 0x0200_0000 ~ 0x0200_ffff
//   - 0x0200_bff8: mtime 低32位
//   - 0x0200_bffc: mtime 高32位

module CLINT(
  input         clk,
  input         rst,

  // ===== AXI4 AR 通道 (读地址) =====
  input         clint_arvalid,
  output        clint_arready,
  input  [31:0] clint_araddr,
  input  [ 3:0] clint_arid,      // AXI4 Transaction ID
  input  [ 7:0] clint_arlen,     // AXI4 Burst length (固定为0 单次传输)
  input  [ 2:0] clint_arsize,    // AXI4 Transfer size
  input  [ 1:0] clint_arburst,   // AXI4 Burst type

  // ===== AXI4 R 通道 (读数据) =====
  output        clint_rvalid,
  input         clint_rready,
  output [31:0] clint_rdata,
  output [ 1:0] clint_rresp,
  output        clint_rlast,     // AXI4 Last beat
  output [ 3:0] clint_rid,      // AXI4 Transaction ID

  // ===== AXI4 AW 通道 (写地址 - CLINT不支持写) =====
  input         clint_awvalid,
  output        clint_awready,
  input  [31:0] clint_awaddr,
  input  [ 3:0] clint_awid,      // AXI4
  input  [ 7:0] clint_awlen,     // AXI4
  input  [ 2:0] clint_awsize,    // AXI4
  input  [ 1:0] clint_awburst,   // AXI4

  // ===== AXI4 W 通道 (写数据 - CLINT不支持写) =====
  input         clint_wvalid,
  output        clint_wready,
  input  [31:0] clint_wdata,
  input  [ 3:0] clint_wstrb,
  input         clint_wlast,     // AXI4

  // ===== AXI4 B 通道 (写回复) =====
  output        clint_bvalid,
  input         clint_bready,
  output [ 1:0] clint_bresp,
  output [ 3:0] clint_bid       // AXI4
);

  // ========== mtime 计时器 (64位，每周期+1) ==========
  reg [63:0] mtime;

  always @(posedge clk) begin
    if (rst)
      mtime <= 64'b0;
    else
      mtime <= mtime + 1;
  end

  // ========== AXI4 读状态机 ==========
  localparam R_IDLE = 1'b0, R_WAIT = 1'b1;
  reg r_state;
  reg [31:0] rdata_latch;
  reg [ 3:0] rid_latch;      // 锁存 ARID 以在 R 通道回传

  // 地址译码
  // 0x0200_bff8 -> mtime[31:0]
  // 0x0200_bffc -> mtime[63:32]
  wire is_mtime_lo = (clint_araddr[15:0] == 16'hbff8);
  wire is_mtime_hi = (clint_araddr[15:0] == 16'hbffc);

  // AR 通道
  assign clint_arready = (r_state == R_IDLE);
  // AXI4 扩展参数: 忽略 arlen/arsize/arburst, 固定单次4字节传输

  // R 通道
  assign clint_rvalid = (r_state == R_WAIT);
  assign clint_rdata  = rdata_latch;
  assign clint_rresp  = 2'b00;  // OKAY
  assign clint_rlast  = clint_rvalid;  // 单次传输，rvalid 即 last
  assign clint_rid    = rid_latch;

  // 读状态机
  always @(posedge clk) begin
    if (rst) begin
      r_state     <= R_IDLE;
      rdata_latch <= 32'b0;
      rid_latch   <= 4'b0;
    end else begin
      case (r_state)
        R_IDLE: begin
          if (clint_arvalid) begin
            // 锁存 ARID
            rid_latch <= clint_arid;
            // 读数据
            if (is_mtime_lo)
              rdata_latch <= mtime[31:0];
            else if (is_mtime_hi)
              rdata_latch <= mtime[63:32];
            else
              rdata_latch <= 32'b0;  // 其他地址返回0
            r_state <= R_WAIT;
          end
        end

        R_WAIT: begin
          if (clint_rready) begin
            r_state <= R_IDLE;
          end
        end

        default: r_state <= R_IDLE;
      endcase
    end
  end

  // ========== AXI4 写通道 (不支持，返回 SLVERR) ==========
  // AW 通道: 总是 ready
  assign clint_awready = 1'b1;
  // W 通道: 总是 ready
  assign clint_wready  = 1'b1;

  // 写状态机: 支持 AXI4 的 AW+W 独立握手
  localparam W_IDLE = 2'b00, W_WAIT_W = 2'b01, W_WAIT_B = 2'b10;
  reg [1:0] w_state;
  reg [3:0] bid_latch;  // 锁存 AWID 以在 B 通道回传

  assign clint_bvalid = (w_state == W_WAIT_B);
  assign clint_bresp  = 2'b10;  // SLVERR (不支持写操作)
  assign clint_bid    = bid_latch;

  always @(posedge clk) begin
    if (rst) begin
      w_state   <= W_IDLE;
      bid_latch <= 4'b0;
    end else begin
      case (w_state)
        W_IDLE: begin
          if (clint_awvalid) begin
            bid_latch <= clint_awid;  // 锁存 AWID
            if (clint_wvalid) begin
              // AW 和 W 同时到达
              w_state <= W_WAIT_B;
            end else begin
              // AW 先到，等待 W
              w_state <= W_WAIT_W;
            end
          end else if (clint_wvalid) begin
            // W 先到 (异常情况，但 AXI 允许)
            w_state <= W_WAIT_W;
          end
        end

        W_WAIT_W: begin
          if (clint_wvalid) begin
            w_state <= W_WAIT_B;
          end
        end

        W_WAIT_B: begin
          if (clint_bready) begin
            w_state <= W_IDLE;
          end
        end

        default: w_state <= W_IDLE;
      endcase
    end
  end

endmodule