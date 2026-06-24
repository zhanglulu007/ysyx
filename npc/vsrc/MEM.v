// MEM - Memory Module with LFSR Random Delay
// 模拟存储器，内部通过 DPI-C 实现访存，对外呈现 SimpleBus 接口
// 支持有效信号的 SimpleBus 协议: reqValid/respValid 握手
// 通过 LFSR 随机延迟 respValid, 用于测试总线实现的鲁棒性
//
// 延迟机制: 每个通道独立的延迟计数器
//   - 收到 reqValid 后立即调用 DPI-C 完成实际访存
//   - 采样 LFSR 值决定延迟周期数 (1~8 周期)
//   - 延迟结束后返回 respValid=1 (1 周期脉冲)

module MEM(
  input clk,
  input rst,

  // IFU SimpleBus (只读)
  input         ifu_reqValid,
  output        ifu_respValid,
  input  [31:0] ifu_raddr,
  output [31:0] ifu_rdata,

  // LSU SimpleBus (可读可写)
  input         lsu_reqValid,
  output        lsu_respValid,
  input  [31:0] lsu_addr,
  input         lsu_wen,
  input  [31:0] lsu_wdata,
  input  [ 3:0] lsu_wmask,
  output [31:0] lsu_rdata
);

  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

  // ===== LFSR 实例化 =====
  wire [7:0] lfsr_val;
  LFSR u_lfsr(
    .clk(clk),
    .rst(rst),
    .value(lfsr_val)
  );

  // ===== IFU 通道: 随机延迟计数器 + 锁存读数据 =====
  reg [3:0] ifu_delay_cnt;
  reg [31:0] ifu_rdata_latched;

  always @(posedge clk) begin
    if (rst) begin
      ifu_delay_cnt    <= 4'd0;
      ifu_rdata_latched <= 32'b0;
    end else begin
      // 延迟计数器递减
      if (ifu_delay_cnt > 4'd0)
        ifu_delay_cnt <= ifu_delay_cnt - 4'd1;

      // 空闲时接受新请求: 立即 DPI-C 读, 采样 LFSR 决定延迟
      // LFSR[2:0] 范围 0~7, +1 后延迟范围 1~8 周期
      if (ifu_reqValid && ifu_delay_cnt == 4'd0) begin
        ifu_rdata_latched <= pmem_read(ifu_raddr);
        ifu_delay_cnt    <= {1'b0, lfsr_val[2:0]} + 4'd1;
      end
    end
  end

  // respValid: 延迟计数器 == 1 时产生 1 周期脉冲
  assign ifu_respValid = (ifu_delay_cnt == 4'd1);
  assign ifu_rdata     = ifu_rdata_latched;

  // ===== LSU 通道: 随机延迟计数器 + 锁存读数据 =====
  reg [3:0] lsu_delay_cnt;
  reg [31:0] lsu_rdata_latched;

  always @(posedge clk) begin
    if (rst) begin
      lsu_delay_cnt    <= 4'd0;
      lsu_rdata_latched <= 32'b0;
    end else begin
      // 延迟计数器递减
      if (lsu_delay_cnt > 4'd0)
        lsu_delay_cnt <= lsu_delay_cnt - 4'd1;

      // 空闲时接受新请求: 立即 DPI-C 读/写, 采样 LFSR 决定延迟
      if (lsu_reqValid && lsu_delay_cnt == 4'd0) begin
        if (!lsu_wen) begin
          // 读操作: 立即调用 pmem_read, 锁存数据
          lsu_rdata_latched <= pmem_read(lsu_addr);
        end else begin
          // 写操作: 立即调用 pmem_write, rdata 无关
          pmem_write(lsu_addr, lsu_wdata, {4'b0, lsu_wmask});
          lsu_rdata_latched <= 32'b0;
        end
        lsu_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;
      end
    end
  end

  assign lsu_respValid = (lsu_delay_cnt == 4'd1);
  assign lsu_rdata     = lsu_rdata_latched;

endmodule
