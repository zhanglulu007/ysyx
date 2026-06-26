// CLINT - Core Local INTerrupt controller
// 核心局部中断控制器：实现 mtime 计时器 (64位计数器)
// AXI4-Lite 接口，只读访问
// 地址空间: 0x0200_0000 ~ 0x0200_ffff
//   - 0x0200_bff8: mtime 低32位
//   - 0x0200_bffc: mtime 高32位

module CLINT(
  input         clk,
  input         rst,

  // AXI4-Lite AR 通道 (读地址)
  input         clint_arvalid,
  output        clint_arready,
  input  [31:0] clint_araddr,

  // AXI4-Lite R 通道 (读数据)
  output        clint_rvalid,
  input         clint_rready,
  output [31:0] clint_rdata,
  output [ 1:0] clint_rresp,

  // AXI4-Lite AW 通道 (写地址 - CLINT不支持写)
  input         clint_awvalid,
  output        clint_awready,
  input  [31:0] clint_awaddr,

  // AXI4-Lite W 通道 (写数据 - CLINT不支持写)
  input         clint_wvalid,
  output        clint_wready,
  input  [31:0] clint_wdata,
  input  [ 3:0] clint_wstrb,

  // AXI4-Lite B 通道 (写回复)
  output        clint_bvalid,
  input         clint_bready,
  output [ 1:0] clint_bresp
);

  // ========== mtime 计时器 (64位，每周期+1) ==========
  reg [63:0] mtime;

  always @(posedge clk) begin
    if (rst)
      mtime <= 64'b0;
    else
      mtime <= mtime + 1;
  end

  // ========== AXI4-Lite 读状态机 ==========
  localparam R_IDLE = 1'b0, R_WAIT = 1'b1;
  reg r_state;
  reg [31:0] rdata_latch;

  // 地址译码
  // 0x0200_bff8 -> mtime[31:0]
  // 0x0200_bffc -> mtime[63:32]
  wire is_mtime_lo = (clint_araddr[15:0] == 16'hbff8);
  wire is_mtime_hi = (clint_araddr[15:0] == 16'hbffc);

  // AR 通道
  assign clint_arready = (r_state == R_IDLE);

  // R 通道
  assign clint_rvalid = (r_state == R_WAIT);
  assign clint_rdata = rdata_latch;
  assign clint_rresp = 2'b00;  // OKAY

  // 读状态机
  always @(posedge clk) begin
    if (rst) begin
      r_state <= R_IDLE;
      rdata_latch <= 32'b0;
    end else begin
      case (r_state)
        R_IDLE: begin
          if (clint_arvalid) begin
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

  // ========== AXI4-Lite 写通道 (不支持，直接返回错误) ==========
  assign clint_awready = 1'b1;  // 总是接收写地址
  assign clint_wready = 1'b1;   // 总是接收写数据

  // 写状态机
  localparam W_IDLE = 2'b00, W_WAIT_W = 2'b01, W_WAIT_B = 2'b10;
  reg [1:0] w_state;

  assign clint_bvalid = (w_state == W_WAIT_B);
  assign clint_bresp = 2'b10;  // SLVERR (不支持写操作)

  always @(posedge clk) begin
    if (rst) begin
      w_state <= W_IDLE;
    end else begin
      case (w_state)
        W_IDLE: begin
          if (clint_awvalid && clint_wvalid) begin
            w_state <= W_WAIT_B;
          end else if (clint_awvalid) begin
            w_state <= W_WAIT_W;
          end else if (clint_wvalid) begin
            w_state <= W_WAIT_B;  // 简化处理
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
