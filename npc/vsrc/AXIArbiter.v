// AXIArbiter - AXI4-Lite 仲裁器
// 在多个 AXI4-Lite master 之间仲裁, 选择一个与单一 slave 通信
//
// 功能 (讲义 B1 第 703-718 行):
//   1. 调度: 选择一个正在发送有效请求的 master (固定优先级: IFU > LSU)
//   2. 阻塞: 阻塞其他 master 的访问 (将其 ready 信号置 0)
//   3. 转发: 将获得访问权的 master 的请求转发给 slave,
//            并将 slave 的响应转发回该 master
//
// AXI 握手规则 (防死锁/活锁):
//   1. valid 不依赖 ready (发送方自主决定)
//   2. valid 一旦置位必须保持直到握手完成
//   3. ready 可依赖 valid (接收方可等待)
//
// 状态机:
//   IDLE: 无 master 获得授权, 检测请求
//   BUSY: 已授权某个 master, 转发其事务直到完成
//
// 组合逻辑授权: IDLE 状态下若检测到请求, 组合同步授权,
// 实现零周期延迟转发 (请求到达的同一周期即可转发给 slave)

module AXIArbiter(
  input clk,
  input rst,

  // ===== Master 0: IFU (只读: AR + R 通道) =====
  // AR 通道
  input         ifu_arvalid,
  output        ifu_arready,
  input  [31:0] ifu_araddr,
  // R 通道
  output        ifu_rvalid,
  input         ifu_rready,
  output [31:0] ifu_rdata,
  output [ 1:0] ifu_rresp,

  // ===== Master 1: LSU (读写: 全部 5 通道) =====
  // AR 通道
  input         lsu_arvalid,
  output        lsu_arready,
  input  [31:0] lsu_araddr,
  // R 通道
  output        lsu_rvalid,
  input         lsu_rready,
  output [31:0] lsu_rdata,
  output [ 1:0] lsu_rresp,
  // AW 通道
  input         lsu_awvalid,
  output        lsu_awready,
  input  [31:0] lsu_awaddr,
  // W 通道
  input         lsu_wvalid,
  output        lsu_wready,
  input  [31:0] lsu_wdata,
  input  [ 3:0] lsu_wstrb,
  // B 通道
  output        lsu_bvalid,
  input         lsu_bready,
  output [ 1:0] lsu_bresp,

  // ===== Slave: MEM (单一 AXI4-Lite 接口) =====
  // AR 通道
  output        mem_arvalid,
  input         mem_arready,
  output [31:0] mem_araddr,
  // R 通道
  input         mem_rvalid,
  output        mem_rready,
  input  [31:0] mem_rdata,
  input  [ 1:0] mem_rresp,
  // AW 通道
  output        mem_awvalid,
  input         mem_awready,
  output [31:0] mem_awaddr,
  // W 通道
  output        mem_wvalid,
  input         mem_wready,
  output [31:0] mem_wdata,
  output [ 3:0] mem_wstrb,
  // B 通道
  input         mem_bvalid,
  output        mem_bready,
  input  [ 1:0] mem_bresp
);

  // ========== 状态机 ==========
  localparam IDLE = 1'b0;  // 等待请求
  localparam BUSY = 1'b1;  // 事务进行中

  reg state;
  reg grant;          // 0 = IFU, 1 = LSU
  reg lsu_is_read;    // LSU 事务类型: 1 = 读(AR), 0 = 写(AW+W)

  // ========== 请求检测 ==========
  wire ifu_req = ifu_arvalid;
  wire lsu_req = lsu_arvalid || lsu_awvalid;

  // ========== 组合逻辑授权 (IDLE 时零周期转发) ==========
  // 固定优先级: IFU > LSU
  // IDLE 状态时, 若有请求立即组合授权
  // BUSY 状态时, 根据已注册的 grant 授权
  wire ifu_granted = (state == IDLE && ifu_req && !rst) ||
                     (state == BUSY && grant == 1'b0);
  wire lsu_granted = (state == IDLE && lsu_req && !ifu_req && !rst) ||
                     (state == BUSY && grant == 1'b1);

  // ========== AR 通道转发 ==========
  // Master → Slave
  assign mem_arvalid = ifu_granted ? ifu_arvalid :
                       lsu_granted ? lsu_arvalid : 1'b0;
  assign mem_araddr  = ifu_granted ? ifu_araddr  : lsu_araddr;

  // Slave → Master (阻塞未授权 master: ready = 0)
  assign ifu_arready = ifu_granted ? mem_arready : 1'b0;
  assign lsu_arready = lsu_granted ? mem_arready : 1'b0;

  // ========== R 通道转发 ==========
  // Slave → Master (阻塞未授权 master: valid = 0)
  assign ifu_rvalid = ifu_granted ? mem_rvalid : 1'b0;
  assign lsu_rvalid = lsu_granted ? mem_rvalid : 1'b0;
  assign ifu_rdata  = mem_rdata;
  assign lsu_rdata  = mem_rdata;
  assign ifu_rresp  = mem_rresp;
  assign lsu_rresp  = mem_rresp;

  // Master → Slave
  assign mem_rready = ifu_granted ? ifu_rready :
                      lsu_granted ? lsu_rready : 1'b0;

  // ========== AW 通道转发 (仅 LSU) ==========
  assign mem_awvalid = lsu_granted ? lsu_awvalid : 1'b0;
  assign mem_awaddr  = lsu_awaddr;
  assign lsu_awready = lsu_granted ? mem_awready : 1'b0;

  // ========== W 通道转发 (仅 LSU) ==========
  assign mem_wvalid = lsu_granted ? lsu_wvalid : 1'b0;
  assign mem_wdata  = lsu_wdata;
  assign mem_wstrb  = lsu_wstrb;
  assign lsu_wready = lsu_granted ? mem_wready : 1'b0;

  // ========== B 通道转发 (仅 LSU) ==========
  assign lsu_bvalid = lsu_granted ? mem_bvalid : 1'b0;
  assign lsu_bresp  = mem_bresp;
  assign mem_bready = lsu_granted ? lsu_bready : 1'b0;

  // ========== 事务完成检测 ==========
  // IFU: 读事务完成 = R 通道握手
  // LSU 读: 完成 = R 通道握手
  // LSU 写: 完成 = B 通道握手
  wire ifu_done  = mem_rvalid && mem_rready;
  wire lsu_done  = lsu_is_read ? (mem_rvalid && mem_rready)
                               : (mem_bvalid && mem_bready);

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state       <= IDLE;
      grant       <= 1'b0;
      lsu_is_read <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          if (ifu_req) begin
            // IFU 请求 (固定优先级更高)
            state       <= BUSY;
            grant       <= 1'b0;  // IFU
            // IFU 只读, lsu_is_read 无关
          end else if (lsu_req) begin
            // LSU 请求
            state <= BUSY;
            grant <= 1'b1;  // LSU
            // 记录事务类型: arvalid 有效 = 读, 否则 = 写
            lsu_is_read <= lsu_arvalid && !lsu_awvalid;
          end
        end

        BUSY: begin
          if (grant == 1'b0) begin
            // IFU 授权中
            if (ifu_done) begin
              state <= IDLE;
            end
          end else begin
            // LSU 授权中
            if (lsu_done) begin
              state <= IDLE;
              lsu_is_read <= 1'b0;
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
