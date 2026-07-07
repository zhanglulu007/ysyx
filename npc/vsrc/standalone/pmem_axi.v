// pmem_axi - 完整 AXI4 转 DPI-C pmem 后端
// 用于独立 NPC 仿真 (riscv32e-npc): 把 ysyx_26020070 的完整 AXI4 master 口
// 接到 DPI-C 实现的 pmem (基址 0x80000000) 后端
//
// 设计要点:
//   - NPC 发出的都是 len=0 的单拍传输, 故固定 rlast=1, 忽略 arlen/awlen
//   - 回传 rid=arid, bid=awid, rresp/bresp=OKAY, 保证 AXI4 协议合规
//   - 通过 LFSR 随机延迟 arready/awready/wready 和 rvalid/bvalid, 测试总线鲁棒性
//   - 不做地址译码 (由上层 top_pmem.v 的 Xbar 完成), 本模块纯做 AXI4↔DPI-C 转换

module pmem_axi(
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

  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

  // ===== LFSR 实例化 (随机延迟源) =====
  wire [7:0] lfsr_val;
  LFSR u_lfsr(
    .clk(clk),
    .rst(rst),
    .value(lfsr_val)
  );

  // ========== 状态机 ==========
  localparam IDLE    = 2'b00;  // 等待读/写请求
  localparam R_BUSY  = 2'b01;  // 读事务进行中
  localparam W_BUSY  = 2'b10;  // 写事务进行中

  reg [ 1:0] state;
  reg [31:0] rdata_latched;
  reg [ 3:0] rid_latched;
  reg [ 3:0] bid_latched;
  reg [ 3:0] req_ready_cnt;    // arready/awready/wready 延迟计数器 (0=就绪)
  reg [ 3:0] resp_delay_cnt;   // rvalid/bvalid 延迟计数器 (0=响应就绪)

  // 写路径追踪: AW 和 W 可独立握手
  reg        aw_done;
  reg        w_done;
  reg [31:0] aw_addr_latched;
  reg [31:0] w_data_latched;
  reg [ 3:0] w_strb_latched;

  // ========== 通道就绪信号 ==========
  assign arready = (state == IDLE) && (req_ready_cnt == 4'd0)
                   && !aw_done && !w_done && !rst;

  assign awready = (state == IDLE) && !aw_done && !rst
                   && ((req_ready_cnt == 4'd0) || w_done);

  assign wready = (state == IDLE) && !w_done && !rst
                  && ((req_ready_cnt == 4'd0) || aw_done);

  // ========== 响应信号 ==========
  assign rvalid = (state == R_BUSY) && (resp_delay_cnt == 4'd0);
  assign bvalid = (state == W_BUSY) && (resp_delay_cnt == 4'd0);

  assign rdata = rdata_latched;
  assign rresp = 2'b00;  // OKAY
  assign rlast = rvalid; // 单拍传输, rvalid 即 last
  assign rid   = rid_latched;

  assign bresp = 2'b00;  // OKAY
  assign bid   = bid_latched;

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state           <= IDLE;
      rdata_latched   <= 32'b0;
      rid_latched     <= 4'b0;
      bid_latched     <= 4'b0;
      req_ready_cnt   <= 4'd0;
      resp_delay_cnt  <= 4'd0;
      aw_done         <= 1'b0;
      w_done          <= 1'b0;
      aw_addr_latched <= 32'b0;
      w_data_latched  <= 32'b0;
      w_strb_latched  <= 4'b0;
    end else begin
      // reqReady 延迟计数器: IDLE 时递减到 0
      if (state == IDLE && req_ready_cnt > 4'd0)
        req_ready_cnt <= req_ready_cnt - 4'd1;

      // 响应延迟计数器: BUSY 时递减到 0
      if ((state == R_BUSY || state == W_BUSY) && resp_delay_cnt > 4'd0)
        resp_delay_cnt <= resp_delay_cnt - 4'd1;

      case (state)
        IDLE: begin
          // ----- 读事务: AR 握手 -----
          if (arvalid && arready) begin
            rdata_latched  <= pmem_read(araddr);
            rid_latched    <= arid;        // 回传 transaction ID
            resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;  // 1~8 周期
            state <= R_BUSY;
          end
          // ----- 写事务: AW 和 W 握手追踪 -----
          else begin
            // AW 握手
            if (awvalid && awready && !aw_done) begin
              aw_addr_latched <= awaddr;
              bid_latched     <= awid;     // 锁存写事务 ID
              aw_done <= 1'b1;
            end

            // W 握手
            if (wvalid && wready && !w_done) begin
              w_data_latched <= wdata;
              w_strb_latched <= wstrb;
              w_done <= 1'b1;
            end

            // AW 和 W 均完成时触发 DPI-C 写
            if (aw_done && w_done) begin
              pmem_write(aw_addr_latched, w_data_latched, {4'b0, w_strb_latched});
              resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;  // 1~8 周期
              state    <= W_BUSY;
              aw_done  <= 1'b0;
              w_done   <= 1'b0;
            end
          end
        end

        R_BUSY: begin
          // R 握手: rvalid && rready
          if (rvalid && rready) begin
            req_ready_cnt <= {1'b0, lfsr_val[5:3]};  // 0~7 周期
            state <= IDLE;
          end
        end

        W_BUSY: begin
          // B 握手: bvalid && bready
          if (bvalid && bready) begin
            req_ready_cnt <= {1'b0, lfsr_val[5:3]};  // 0~7 周期
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
