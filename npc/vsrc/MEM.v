// MEM - Memory Module with LFSR Random Delay
// 模拟存储器，内部通过 DPI-C 实现访存，对外呈现 SimpleBus 接口
// 支持完整握手信号的 SimpleBus 协议: reqValid/reqReady + respValid/respReady
// 通过 LFSR 随机延迟 reqReady 和 respValid, 用于测试总线实现的鲁棒性
//
// 每通道状态机:
//   IDLE: reqReady 受 LFSR 随机延迟, 等待 reqValid && reqReady 握手
//   BUSY: 请求已接受, DPI-C 已完成, respValid 受 LFSR 随机延迟
//         等待 respValid && respReady 握手完成

module MEM(
  input clk,
  input rst,

  // IFU SimpleBus (只读)
  input         ifu_reqValid,
  output        ifu_reqReady,
  output        ifu_respValid,
  input         ifu_respReady,
  input  [31:0] ifu_raddr,
  output [31:0] ifu_rdata,

  // LSU SimpleBus (可读可写)
  input         lsu_reqValid,
  output        lsu_reqReady,
  output        lsu_respValid,
  input         lsu_respReady,
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

  // ================================================================
  // IFU 通道: 完整握手状态机
  // ================================================================
  // 状态编码:
  //   IDLE(1'b0): 等待 reqValid && reqReady 握手
  //   BUSY(1'b1): 请求已处理, 等待 respValid && respReady 握手
  localparam IFU_IDLE = 1'b0;
  localparam IFU_BUSY = 1'b1;

  reg        ifu_state;
  reg [31:0] ifu_rdata_latched;
  reg [ 3:0] ifu_req_ready_cnt;   // reqReady 延迟计数器 (0=就绪)
  reg [ 3:0] ifu_resp_delay_cnt;  // respValid 延迟计数器 (0=响应就绪)

  // reqReady: 空闲且延迟计数器归零时, 可以接收新请求
  assign ifu_reqReady = (ifu_state == IFU_IDLE) && (ifu_req_ready_cnt == 4'd0) && !rst;

  // respValid: BUSY 状态且延迟计数器归零时, 响应有效
  assign ifu_respValid = (ifu_state == IFU_BUSY) && (ifu_resp_delay_cnt == 4'd0);

  // 读数据输出
  assign ifu_rdata = ifu_rdata_latched;

  always @(posedge clk) begin
    if (rst) begin
      ifu_state         <= IFU_IDLE;
      ifu_rdata_latched <= 32'b0;
      ifu_req_ready_cnt <= 4'd0;
      ifu_resp_delay_cnt <= 4'd0;
    end else begin
      // reqReady 延迟计数器: 空闲时递减到 0
      if (ifu_state == IFU_IDLE && ifu_req_ready_cnt > 4'd0)
        ifu_req_ready_cnt <= ifu_req_ready_cnt - 4'd1;

      // respValid 延迟计数器: BUSY 时递减到 0
      if (ifu_state == IFU_BUSY && ifu_resp_delay_cnt > 4'd0)
        ifu_resp_delay_cnt <= ifu_resp_delay_cnt - 4'd1;

      case (ifu_state)
        IFU_IDLE: begin
          // 握手: reqValid && reqReady
          if (ifu_reqValid && ifu_reqReady) begin
            // 接受请求, 立即调用 DPI-C 完成实际读操作
            ifu_rdata_latched <= pmem_read(ifu_raddr);
            // 采样 LFSR 决定响应延迟 (1~8 周期)
            ifu_resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;
            ifu_state <= IFU_BUSY;
          end
        end

        IFU_BUSY: begin
          // 握手: respValid && respReady
          if (ifu_respValid && ifu_respReady) begin
            // 响应被主设备接受, 准备接收下一个请求
            // 加载新的 reqReady 延迟 (0~7 周期)
            ifu_req_ready_cnt <= {1'b0, lfsr_val[5:3]};
            ifu_state <= IFU_IDLE;
          end
        end

        default: ifu_state <= IFU_IDLE;
      endcase
    end
  end


  // ================================================================
  // LSU 通道: 完整握手状态机
  // ================================================================
  localparam LSU_IDLE = 1'b0;
  localparam LSU_BUSY = 1'b1;

  reg        lsu_state;
  reg [31:0] lsu_rdata_latched;
  reg [ 3:0] lsu_req_ready_cnt;
  reg [ 3:0] lsu_resp_delay_cnt;

  assign lsu_reqReady = (lsu_state == LSU_IDLE) && (lsu_req_ready_cnt == 4'd0) && !rst;
  assign lsu_respValid = (lsu_state == LSU_BUSY) && (lsu_resp_delay_cnt == 4'd0);
  assign lsu_rdata = lsu_rdata_latched;

  always @(posedge clk) begin
    if (rst) begin
      lsu_state         <= LSU_IDLE;
      lsu_rdata_latched <= 32'b0;
      lsu_req_ready_cnt <= 4'd0;
      lsu_resp_delay_cnt <= 4'd0;
    end else begin
      // reqReady 延迟计数器
      if (lsu_state == LSU_IDLE && lsu_req_ready_cnt > 4'd0)
        lsu_req_ready_cnt <= lsu_req_ready_cnt - 4'd1;

      // respValid 延迟计数器
      if (lsu_state == LSU_BUSY && lsu_resp_delay_cnt > 4'd0)
        lsu_resp_delay_cnt <= lsu_resp_delay_cnt - 4'd1;

      case (lsu_state)
        LSU_IDLE: begin
          // 握手: reqValid && reqReady
          if (lsu_reqValid && lsu_reqReady) begin
            if (!lsu_wen) begin
              // 读操作: 立即调用 pmem_read, 锁存数据
              lsu_rdata_latched <= pmem_read(lsu_addr);
            end else begin
              // 写操作: 立即调用 pmem_write
              pmem_write(lsu_addr, lsu_wdata, {4'b0, lsu_wmask});
              lsu_rdata_latched <= 32'b0;
            end
            // 采样 LFSR 决定响应延迟 (1~8 周期)
            lsu_resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;
            lsu_state <= LSU_BUSY;
          end
        end

        LSU_BUSY: begin
          // 握手: respValid && respReady
          if (lsu_respValid && lsu_respReady) begin
            // 响应被主设备接受, 加载新的 reqReady 延迟 (0~7 周期)
            lsu_req_ready_cnt <= {1'b0, lfsr_val[5:3]};
            lsu_state <= LSU_IDLE;
          end
        end

        default: lsu_state <= LSU_IDLE;
      endcase
    end
  end

endmodule
