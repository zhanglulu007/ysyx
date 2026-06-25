// MEM - Memory Module with LFSR Random Delay
// 模拟存储器，内部通过 DPI-C 实现访存，对外呈现 AXI4-Lite 接口
// 支持完整 AXI4-Lite 握手协议
// 通过 LFSR 随机延迟 arready/awready/wready 和 rvalid/bvalid, 用于测试总线实现的鲁棒性
//
// AXI 握手规则 (防死锁/活锁):
//   1. valid 不依赖 ready (发送方自主决定)
//   2. valid 一旦置位必须保持直到握手完成
//   3. ready 可依赖 valid (接收方可等待)
//
// IFU 端口: AR + R 通道 (只读)
//   IDLE: 等待 arvalid && arready 握手, DPI-C 读
//   BUSY: LFSR 延迟后 rvalid 握手
//
// LSU 端口: AR + R + AW + W + B 通道 (读写)
//   IDLE:   等待 AR (读) 或 AW+W (写) 握手
//   R_BUSY: LFSR 延迟后 rvalid 握手
//   W_BUSY: LFSR 延迟后 bvalid 握手
//   写路径: AW 和 W 可独立握手, 均完成后触发 DPI-C 写

module MEM(
  input clk,
  input rst,

  // ===== IFU AXI4-Lite (只读: AR + R 通道) =====
  input         ifu_arvalid,
  output        ifu_arready,
  input  [31:0] ifu_araddr,
  output        ifu_rvalid,
  input         ifu_rready,
  output [31:0] ifu_rdata,
  output [ 1:0] ifu_rresp,

  // ===== LSU AXI4-Lite AR 通道 (读地址) =====
  input         lsu_arvalid,
  output        lsu_arready,
  input  [31:0] lsu_araddr,

  // ===== LSU AXI4-Lite R 通道 (读数据) =====
  output        lsu_rvalid,
  input         lsu_rready,
  output [31:0] lsu_rdata,
  output [ 1:0] lsu_rresp,

  // ===== LSU AXI4-Lite AW 通道 (写地址) =====
  input         lsu_awvalid,
  output        lsu_awready,
  input  [31:0] lsu_awaddr,

  // ===== LSU AXI4-Lite W 通道 (写数据) =====
  input         lsu_wvalid,
  output        lsu_wready,
  input  [31:0] lsu_wdata,
  input  [ 3:0] lsu_wstrb,

  // ===== LSU AXI4-Lite B 通道 (写回复) =====
  output        lsu_bvalid,
  input         lsu_bready,
  output [ 1:0] lsu_bresp
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
  // IFU 通道: AXI4-Lite AR → R (只读)
  // ================================================================
  // 状态编码:
  //   IDLE(1'b0): arready 可用 (受 LFSR 延迟), 等待 arvalid && arready
  //   BUSY(1'b1): DPI-C 读完成, LFSR 延迟后 rvalid 有效, 等待 rvalid && rready
  localparam IFU_IDLE = 1'b0;
  localparam IFU_BUSY = 1'b1;

  reg        ifu_state;
  reg [31:0] ifu_rdata_latched;
  reg [ 3:0] ifu_req_ready_cnt;   // arready 延迟计数器 (0=就绪)
  reg [ 3:0] ifu_resp_delay_cnt;  // rvalid 延迟计数器 (0=响应就绪)

  // arready: 空闲且延迟计数器归零时, 可以接收读地址
  //   AXI 规则: ready 可依赖 valid (允许), 但这里独立于 valid
  assign ifu_arready = (ifu_state == IFU_IDLE) && (ifu_req_ready_cnt == 4'd0) && !rst;

  // rvalid: BUSY 状态且延迟计数器归零时, 读数据有效
  //   AXI 规则: valid 不依赖 ready
  assign ifu_rvalid = (ifu_state == IFU_BUSY) && (ifu_resp_delay_cnt == 4'd0);

  // 读数据和响应 (简单存储器始终返回 OKAY)
  assign ifu_rdata = ifu_rdata_latched;
  assign ifu_rresp = 2'b00;  // OKAY

  always @(posedge clk) begin
    if (rst) begin
      ifu_state          <= IFU_IDLE;
      ifu_rdata_latched  <= 32'b0;
      ifu_req_ready_cnt  <= 4'd0;
      ifu_resp_delay_cnt <= 4'd0;
    end else begin
      // arready 延迟计数器: 空闲时递减到 0
      if (ifu_state == IFU_IDLE && ifu_req_ready_cnt > 4'd0)
        ifu_req_ready_cnt <= ifu_req_ready_cnt - 4'd1;

      // rvalid 延迟计数器: BUSY 时递减到 0
      if (ifu_state == IFU_BUSY && ifu_resp_delay_cnt > 4'd0)
        ifu_resp_delay_cnt <= ifu_resp_delay_cnt - 4'd1;

      case (ifu_state)
        IFU_IDLE: begin
          // AR 握手: arvalid && arready
          if (ifu_arvalid && ifu_arready) begin
            // 接受读地址, 立即调用 DPI-C 完成实际读操作
            ifu_rdata_latched <= pmem_read(ifu_araddr);
            // 采样 LFSR 决定响应延迟 (1~8 周期)
            ifu_resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;
            ifu_state <= IFU_BUSY;
          end
        end

        IFU_BUSY: begin
          // R 握手: rvalid && rready
          if (ifu_rvalid && ifu_rready) begin
            // 响应被主设备接受, 准备接收下一个请求
            // 加载新的 arready 延迟 (0~7 周期)
            ifu_req_ready_cnt <= {1'b0, lfsr_val[5:3]};
            ifu_state <= IFU_IDLE;
          end
        end

        default: ifu_state <= IFU_IDLE;
      endcase
    end
  end


  // ================================================================
  // LSU 通道: AXI4-Lite 全部 5 通道
  // ================================================================
  // 状态编码:
  //   LSU_IDLE    (2'b00): 等待读/写请求
  //   LSU_R_BUSY  (2'b01): 读事务进行中, LFSR 延迟后 rvalid
  //   LSU_W_BUSY  (2'b10): 写事务进行中, LFSR 延迟后 bvalid
  localparam LSU_IDLE    = 2'b00;
  localparam LSU_R_BUSY  = 2'b01;
  localparam LSU_W_BUSY  = 2'b10;

  reg [ 1:0] lsu_state;
  reg [31:0] lsu_rdata_latched;
  reg [ 3:0] lsu_req_ready_cnt;   // arready/awready/wready 延迟计数器 (0=就绪)
  reg [ 3:0] lsu_resp_delay_cnt;  // rvalid/bvalid 延迟计数器 (0=响应就绪)

  // 写路径追踪: AW 和 W 可独立握手
  reg        lsu_aw_done;          // AW 握手已完成
  reg        lsu_w_done;           // W  握手已完成
  reg [31:0] lsu_aw_addr_latched;  // 锁存的写地址
  reg [31:0] lsu_w_data_latched;   // 锁存的写数据
  reg [ 3:0] lsu_w_strb_latched;   // 锁存的写字节使能

  // ----- arready: IDLE 状态, 计数器归零, 且无写事务进行中 -----
  assign lsu_arready = (lsu_state == LSU_IDLE) && (lsu_req_ready_cnt == 4'd0)
                       && !lsu_aw_done && !lsu_w_done && !rst;

  // ----- awready: IDLE 状态, 计数器归零 (或 W 已先完成, 需要地址) -----
  assign lsu_awready = (lsu_state == LSU_IDLE) && !lsu_aw_done && !rst
                       && ((lsu_req_ready_cnt == 4'd0) || lsu_w_done);

  // ----- wready: IDLE 状态, 计数器归零 (或 AW 已先完成, 需要数据) -----
  assign lsu_wready = (lsu_state == LSU_IDLE) && !lsu_w_done && !rst
                      && ((lsu_req_ready_cnt == 4'd0) || lsu_aw_done);

  // ----- rvalid: R_BUSY 状态且延迟计数器归零 -----
  assign lsu_rvalid = (lsu_state == LSU_R_BUSY) && (lsu_resp_delay_cnt == 4'd0);

  // ----- bvalid: W_BUSY 状态且延迟计数器归零 -----
  assign lsu_bvalid = (lsu_state == LSU_W_BUSY) && (lsu_resp_delay_cnt == 4'd0);

  // 读数据和响应
  assign lsu_rdata = lsu_rdata_latched;
  assign lsu_rresp = 2'b00;  // OKAY
  assign lsu_bresp = 2'b00;  // OKAY

  always @(posedge clk) begin
    if (rst) begin
      lsu_state           <= LSU_IDLE;
      lsu_rdata_latched   <= 32'b0;
      lsu_req_ready_cnt   <= 4'd0;
      lsu_resp_delay_cnt  <= 4'd0;
      lsu_aw_done         <= 1'b0;
      lsu_w_done          <= 1'b0;
      lsu_aw_addr_latched <= 32'b0;
      lsu_w_data_latched  <= 32'b0;
      lsu_w_strb_latched  <= 4'b0;
    end else begin
      // reqReady 延迟计数器: IDLE 时递减到 0
      if (lsu_state == LSU_IDLE && lsu_req_ready_cnt > 4'd0)
        lsu_req_ready_cnt <= lsu_req_ready_cnt - 4'd1;

      // 响应延迟计数器: BUSY 时递减到 0
      if ((lsu_state == LSU_R_BUSY || lsu_state == LSU_W_BUSY) && lsu_resp_delay_cnt > 4'd0)
        lsu_resp_delay_cnt <= lsu_resp_delay_cnt - 4'd1;

      case (lsu_state)
        LSU_IDLE: begin
          // ----- 读事务: AR 握手 -----
          if (lsu_arvalid && lsu_arready) begin
            // 接受读地址, 立即调用 DPI-C 完成实际读操作
            lsu_rdata_latched <= pmem_read(lsu_araddr);
            // 采样 LFSR 决定响应延迟 (1~8 周期)
            lsu_resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;
            lsu_state <= LSU_R_BUSY;
          end
          // ----- 写事务: AW 和 W 握手追踪 -----
          else begin
            // AW 握手
            if (lsu_awvalid && lsu_awready && !lsu_aw_done) begin
              lsu_aw_addr_latched <= lsu_awaddr;
              lsu_aw_done <= 1'b1;
            end

            // W 握手
            if (lsu_wvalid && lsu_wready && !lsu_w_done) begin
              lsu_w_data_latched <= lsu_wdata;
              lsu_w_strb_latched <= lsu_wstrb;
              lsu_w_done <= 1'b1;
            end

            // 当 AW 和 W 均完成时, 触发 DPI-C 写
            // (使用寄存器值判断, 确保在握手完成后的下一周期触发)
            if (lsu_aw_done && lsu_w_done) begin
              pmem_write(lsu_aw_addr_latched, lsu_w_data_latched, {4'b0, lsu_w_strb_latched});
              // 采样 LFSR 决定 B 响应延迟 (1~8 周期)
              lsu_resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;
              lsu_state    <= LSU_W_BUSY;
              lsu_aw_done  <= 1'b0;
              lsu_w_done   <= 1'b0;
            end
          end
        end

        LSU_R_BUSY: begin
          // R 握手: rvalid && rready
          if (lsu_rvalid && lsu_rready) begin
            // 响应被主设备接受, 加载新的 reqReady 延迟 (0~7 周期)
            lsu_req_ready_cnt <= {1'b0, lfsr_val[5:3]};
            lsu_state <= LSU_IDLE;
          end
        end

        LSU_W_BUSY: begin
          // B 握手: bvalid && bready
          if (lsu_bvalid && lsu_bready) begin
            // 写回复被主设备接受, 加载新的 reqReady 延迟 (0~7 周期)
            lsu_req_ready_cnt <= {1'b0, lfsr_val[5:3]};
            lsu_state <= LSU_IDLE;
          end
        end

        default: lsu_state <= LSU_IDLE;
      endcase
    end
  end

endmodule
