// uart_axi - 完整 AXI4 简化 UART 设备
// 用于独立 NPC 仿真 (riscv32e-npc): 处理串口 (0x10000000)、RTC、键盘、VGA 等 MMIO 地址
// 通过 DPI-C 复用 C++ 仿真层的 pmem_read/pmem_write (内部已处理设备地址分发)
//
// 设计要点 (与 pmem_axi 类似):
//   - 接收完整 AXI4, 固定 rlast=1, 回传 rid/bid, rresp/bresp=OKAY
//   - 单拍响应 (无随机延迟, 设备响应即时)
//   - AW/W 可独立握手

module uart_axi(
  input clk,
  input rst,

  // ===== 完整 AXI4 AR 通道 =====
  input         arvalid,
  output        arready,
  input  [31:0] araddr,
  input  [ 3:0] arid,
  input  [ 7:0] arlen,
  input  [ 2:0] arsize,
  input  [ 1:0] arburst,

  // ===== 完整 AXI4 R 通道 =====
  output        rvalid,
  input         rready,
  output [31:0] rdata,
  output [ 1:0] rresp,
  output        rlast,
  output [ 3:0] rid,

  // ===== 完整 AXI4 AW 通道 =====
  input         awvalid,
  output        awready,
  input  [31:0] awaddr,
  input  [ 3:0] awid,
  input  [ 7:0] awlen,
  input  [ 2:0] awsize,
  input  [ 1:0] awburst,

  // ===== 完整 AXI4 W 通道 =====
  input         wvalid,
  output        wready,
  input  [31:0] wdata,
  input  [ 3:0] wstrb,
  input         wlast,

  // ===== 完整 AXI4 B 通道 =====
  output        bvalid,
  input         bready,
  output [ 1:0] bresp,
  output [ 3:0] bid
);

  // DPI-C 函数: 复用 C++ 仿真层的 pmem_read/pmem_write
  // 这两个函数内部已处理设备地址 (SERIAL_PORT / RTC / KBD / VGA 等) 的读写
  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

  // ========== 状态机 ==========
  localparam IDLE   = 2'b00;
  localparam R_BUSY = 2'b01;
  localparam W_BUSY = 2'b10;

  reg [1:0] state;

  // 写通道握手追踪
  reg        aw_done;
  reg        w_done;
  reg [31:0] latched_awaddr;
  reg [31:0] latched_wdata;
  reg [ 3:0] latched_wstrb;

  // 读数据锁存
  reg [31:0] latched_rdata;
  reg [ 3:0] rid_latched;
  reg [ 3:0] bid_latched;

  // ========== 组合逻辑: 检测 AW/W 是否在本周期完成 ==========
  wire aw_completing = (state == IDLE) && awvalid && awready && !aw_done;
  wire w_completing  = (state == IDLE) && wvalid  && wready  && !w_done;

  wire aw_ready_c = aw_done || aw_completing;
  wire w_ready_c  = w_done  || w_completing;

  // ========== 通道就绪信号 ==========
  assign arready = (state == IDLE) && !rst;
  assign awready = (state == IDLE) && !aw_done && !rst;
  assign wready  = (state == IDLE) && !w_done && !rst;

  // ========== 响应信号 ==========
  assign rvalid = (state == R_BUSY);
  assign rdata  = latched_rdata;
  assign rresp  = 2'b00;          // OKAY
  assign rlast  = rvalid;         // 单拍传输
  assign rid    = rid_latched;

  assign bvalid = (state == W_BUSY);
  assign bresp  = 2'b00;          // OKAY
  assign bid    = bid_latched;

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state          <= IDLE;
      aw_done        <= 1'b0;
      w_done         <= 1'b0;
      latched_awaddr <= 32'b0;
      latched_wdata  <= 32'b0;
      latched_wstrb  <= 4'b0;
      latched_rdata  <= 32'b0;
      rid_latched    <= 4'b0;
      bid_latched    <= 4'b0;
    end else begin
      case (state)
        IDLE: begin
          // ----- 读事务: AR 握手 -----
          if (arvalid && arready) begin
            latched_rdata <= pmem_read(araddr);
            rid_latched   <= arid;
            state <= R_BUSY;
          end
          // ----- 写事务: AW 和 W 握手追踪 -----
          else begin
            if (aw_ready_c && w_ready_c) begin
              // AW 和 W 均完成, 调用 DPI-C 写入
              if (aw_completing && w_completing) begin
                pmem_write(awaddr, wdata, {4'b0, wstrb});
                bid_latched <= awid;
              end else if (aw_completing) begin
                pmem_write(awaddr, latched_wdata, {4'b0, latched_wstrb});
                bid_latched <= awid;
              end else if (w_completing) begin
                pmem_write(latched_awaddr, wdata, {4'b0, wstrb});
              end else begin
                pmem_write(latched_awaddr, latched_wdata, {4'b0, latched_wstrb});
              end
              state   <= W_BUSY;
              aw_done <= 1'b0;
              w_done  <= 1'b0;
            end else begin
              if (aw_completing) begin
                aw_done        <= 1'b1;
                latched_awaddr <= awaddr;
                bid_latched    <= awid;
              end
              if (w_completing) begin
                w_done        <= 1'b1;
                latched_wdata <= wdata;
                latched_wstrb <= wstrb;
              end
            end
          end
        end

        R_BUSY: begin
          if (rvalid && rready) state <= IDLE;
        end

        W_BUSY: begin
          if (bvalid && bready) state <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
