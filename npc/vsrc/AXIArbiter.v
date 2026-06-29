// AXIArbiter - AXI4 仲裁器
//
// 状态机:
//   IDLE: 无 master 获得授权, 检测请求
//   BUSY: 已授权某个 master, 转发其事务直到完成
//
// AXI4 扩展: 转发 id, len, size, burst, last 等信号

module AXIArbiter(
  input clk,
  input rst,

  // ===== Master 0: IFU (只读: AR + R 通道) =====
  // AR 通道
  input         ifu_arvalid,
  output        ifu_arready,
  input  [31:0] ifu_araddr,
  input  [ 3:0] ifu_arid,
  input  [ 7:0] ifu_arlen,
  input  [ 2:0] ifu_arsize,
  input  [ 1:0] ifu_arburst,
  // R 通道
  output        ifu_rvalid,
  input         ifu_rready,
  output [31:0] ifu_rdata,
  output [ 1:0] ifu_rresp,
  output        ifu_rlast,
  output [ 3:0] ifu_rid,

  // ===== Master 1: LSU (读写: 全部 5 通道) =====
  // AR 通道
  input         lsu_arvalid,
  output        lsu_arready,
  input  [31:0] lsu_araddr,
  input  [ 3:0] lsu_arid,
  input  [ 7:0] lsu_arlen,
  input  [ 2:0] lsu_arsize,
  input  [ 1:0] lsu_arburst,
  // R 通道
  output        lsu_rvalid,
  input         lsu_rready,
  output [31:0] lsu_rdata,
  output [ 1:0] lsu_rresp,
  output        lsu_rlast,
  output [ 3:0] lsu_rid,
  // AW 通道
  input         lsu_awvalid,
  output        lsu_awready,
  input  [31:0] lsu_awaddr,
  input  [ 3:0] lsu_awid,
  input  [ 7:0] lsu_awlen,
  input  [ 2:0] lsu_awsize,
  input  [ 1:0] lsu_awburst,
  // W 通道
  input         lsu_wvalid,
  output        lsu_wready,
  input  [31:0] lsu_wdata,
  input  [ 3:0] lsu_wstrb,
  input         lsu_wlast,
  // B 通道
  output        lsu_bvalid,
  input         lsu_bready,
  output [ 1:0] lsu_bresp,
  output [ 3:0] lsu_bid,

  // ===== Slave: MEM (单一 AXI4 接口) =====
  // AR 通道
  output        mem_arvalid,
  input         mem_arready,
  output [31:0] mem_araddr,
  output [ 3:0] mem_arid,
  output [ 7:0] mem_arlen,
  output [ 2:0] mem_arsize,
  output [ 1:0] mem_arburst,
  // R 通道
  input         mem_rvalid,
  output        mem_rready,
  input  [31:0] mem_rdata,
  input  [ 1:0] mem_rresp,
  input         mem_rlast,
  input  [ 3:0] mem_rid,
  // AW 通道
  output        mem_awvalid,
  input         mem_awready,
  output [31:0] mem_awaddr,
  output [ 3:0] mem_awid,
  output [ 7:0] mem_awlen,
  output [ 2:0] mem_awsize,
  output [ 1:0] mem_awburst,
  // W 通道
  output        mem_wvalid,
  input         mem_wready,
  output [31:0] mem_wdata,
  output [ 3:0] mem_wstrb,
  output        mem_wlast,
  // B 通道
  input         mem_bvalid,
  output        mem_bready,
  input  [ 1:0] mem_bresp,
  input  [ 3:0] mem_bid
);

  localparam IDLE = 1'b0 , BUSY = 1'b1;
  localparam IFU = 1'b0 , LSU = 1'b1;

  reg state;
  reg grant;          // 0 = IFU, 1 = LSU
  reg lsu_is_read;    // LSU 事务类型: 1 = 读(AR), 0 = 写(AW+W)

  // ========== 请求检测 ==========
  wire ifu_req = ifu_arvalid;
  wire lsu_req = lsu_arvalid || lsu_awvalid;

  // ========== 组合逻辑授权 (IDLE 时零周期转发) ==========
  // 固定优先级: IFU > LSU
  // 注意: IDLE 状态下若总线仍有残留响应 (mem_rvalid/mem_bvalid), 必须禁止授权,
  // 让残留响应通过下面的 mem_rready/mem_bready 排空逻辑被消费, 而不路由给 master.
  wire drain = (state == IDLE) && (mem_rvalid || mem_bvalid);
  wire ifu_granted = ((state == IDLE && ifu_req && !drain) || (state == BUSY && grant == IFU)) && !rst;
  wire lsu_granted = ((state == IDLE && lsu_req && !ifu_req && !drain) || (state == BUSY && grant == LSU)) && !rst;

  // ========== AR 通道转发 ==========
  // Master → Slave
  assign mem_arvalid = ifu_granted ? ifu_arvalid :
                       lsu_granted ? lsu_arvalid : 1'b0;
  assign mem_araddr  = ifu_granted ? ifu_araddr  : lsu_araddr;
  assign mem_arid    = ifu_granted ? ifu_arid    : lsu_arid;
  assign mem_arlen   = ifu_granted ? ifu_arlen   : lsu_arlen;
  assign mem_arsize  = ifu_granted ? ifu_arsize  : lsu_arsize;
  assign mem_arburst = ifu_granted ? ifu_arburst : lsu_arburst;

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
  assign ifu_rlast  = mem_rlast;
  assign lsu_rlast  = mem_rlast;
  assign ifu_rid    = mem_rid;
  assign lsu_rid    = mem_rid;

  // Master → Slave
  // drain 期间 (IDLE 且总线有残留响应) 主动拉高 mem_rready, 把上一事务被复位打断后
  // 残留在 R 通道的响应消费掉, 释放 MROM 等总线设备. 由于 drain 时无 master 被授权,
  // 该响应不会路由给 IFU/LSU, 不会被误当作指令/数据.
  assign mem_rready = ifu_granted ? ifu_rready :
                      lsu_granted ? lsu_rready :
                      drain ? 1'b1 : 1'b0;

  // ========== AW, W, B 通道转发 (仅 LSU) ==========
  assign mem_awvalid = lsu_granted ? lsu_awvalid : 1'b0;
  assign mem_awaddr  = lsu_awaddr;
  assign mem_awid    = lsu_awid;
  assign mem_awlen   = lsu_awlen;
  assign mem_awsize  = lsu_awsize;
  assign mem_awburst = lsu_awburst;
  assign lsu_awready = lsu_granted ? mem_awready : 1'b0;

  assign mem_wvalid = lsu_granted ? lsu_wvalid : 1'b0;
  assign mem_wdata  = lsu_wdata;
  assign mem_wstrb  = lsu_wstrb;
  assign mem_wlast  = lsu_wlast;
  assign lsu_wready = lsu_granted ? mem_wready : 1'b0;

  assign lsu_bvalid = lsu_granted ? mem_bvalid : 1'b0;
  assign lsu_bresp  = mem_bresp;
  assign lsu_bid    = mem_bid;
  // drain 期间排空残留写响应 (与 R 通道同理)
  assign mem_bready = lsu_granted ? lsu_bready :
                      drain ? 1'b1 : 1'b0;

  // ========== 事务完成检测 ==========
  wire ifu_done  = mem_rvalid && mem_rready && mem_rlast;  // AXI4: 需要rlast
  wire lsu_done  = lsu_is_read ? (mem_rvalid && mem_rready && mem_rlast)
                               : (mem_bvalid && mem_bready);

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state       <= IDLE;
      grant       <= IFU;
      lsu_is_read <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          // 优先排空总线残留响应: 若 R/B 通道仍有上一事务(被复位打断)的响应,
          // 必须先消费掉, 否则新请求会被 grant 并把残留 rdata 当作有效数据取走.
          // 此时 ifu_granted/lsu_granted 均为 0 (见 grant 逻辑加的 !drain 条件),
          // 残留响应不会路由给任何 master.
          if (!mem_rvalid && !mem_bvalid) begin
            if (ifu_req) begin
              state       <= BUSY;
              grant       <= IFU;
              // IFU 只读, lsu_is_read 无关
            end else if (lsu_req) begin
              state <= BUSY;
              grant <= LSU;
              // 记录事务类型: arvalid 有效 = 读, 否则 = 写
              lsu_is_read <= lsu_arvalid && !lsu_awvalid;
            end
          end
        end

        BUSY: begin
          if (grant == IFU) begin
            if (ifu_done) begin
              state <= IDLE;
            end
          end else begin
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