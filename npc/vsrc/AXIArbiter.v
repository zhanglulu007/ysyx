// AXIArbiter - AXI4 仲裁器
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

  // ===== Slave 0: CLINT (本地, AXI4, 只读) =====
  output        clint_arvalid,
  input         clint_arready,
  output [31:0] clint_araddr,
  output [ 3:0] clint_arid,
  output [ 7:0] clint_arlen,
  output [ 2:0] clint_arsize,
  output [ 1:0] clint_arburst,
  input         clint_rvalid,
  output        clint_rready,
  input  [31:0] clint_rdata,
  input  [ 1:0] clint_rresp,
  input         clint_rlast,
  input  [ 3:0] clint_rid,
  // AW 通道 (CLINT 不支持写)
  output        clint_awvalid,
  input         clint_awready,
  output [31:0] clint_awaddr,
  output [ 3:0] clint_awid,
  output [ 7:0] clint_awlen,
  output [ 2:0] clint_awsize,
  output [ 1:0] clint_awburst,
  // W 通道
  output        clint_wvalid,
  input         clint_wready,
  output [31:0] clint_wdata,
  output [ 3:0] clint_wstrb,
  output        clint_wlast,
  // B 通道
  input         clint_bvalid,
  output        clint_bready,
  input  [ 1:0] clint_bresp,
  input  [ 3:0] clint_bid,

  // ===== Slave 1: 外部 MEM (ysyxSoC Xbar, AXI4) =====
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

  localparam IDLE = 1'b0, BUSY = 1'b1;
  localparam IFU = 1'b0, LSU = 1'b1;
  localparam ROUTE_NONE      = 2'b00;
  localparam ROUTE_IFU_MEM   = 2'b01;
  localparam ROUTE_LSU_MEM   = 2'b10;
  localparam ROUTE_LSU_CLINT = 2'b11;

  reg state;
  reg grant;          // 0 = IFU, 1 = LSU
  reg lsu_is_read;    // LSU 事务类型: 1 = 读(AR), 0 = 写(AW+W)

  // ========== CLINT 地址空间检测 (LSU 访问) ==========
  wire lsu_is_clint = (lsu_araddr[31:20] == 12'h020) || (lsu_awaddr[31:20] == 12'h020);
  // CLINT 地址空间: 0x0200_0000 ~ 0x0200_ffff

  // ========== 请求检测 ==========
  wire ifu_req = ifu_arvalid;
  wire lsu_req = lsu_arvalid || lsu_awvalid;
  // ========== 组合逻辑授权 (IDLE 时零周期转发) ==========
  wire drain = (state == IDLE) && (mem_rvalid || mem_bvalid);
  wire ifu_granted = ((state == IDLE && ifu_req && !drain) || (state == BUSY && grant == IFU)) && !rst;
  wire lsu_granted = ((state == IDLE && lsu_req && !ifu_req && !drain) || (state == BUSY && grant == LSU)) && !rst;

  reg [1:0] active_route;
  always @(*) begin
    case ({ifu_granted, lsu_granted, lsu_is_clint})
      3'b100,
      3'b101: active_route = ROUTE_IFU_MEM;
      3'b010: active_route = ROUTE_LSU_MEM;
      3'b011: active_route = ROUTE_LSU_CLINT;
      default: active_route = ROUTE_NONE;
    endcase
  end

  reg [49:0] mem_ar_route;
  reg ifu_arready_route, lsu_arready_route;
  reg ifu_rvalid_route;
  reg [39:0] lsu_r_route;
  reg mem_rready_route, clint_rready_route;
  reg mem_awvalid_route, lsu_awready_route;
  reg mem_wvalid_route, lsu_wready_route;
  reg [6:0] lsu_b_route;
  reg mem_bready_route, clint_bready_route;
  reg clint_arvalid_route, clint_awvalid_route, clint_wvalid_route;

  always @(*) begin
    mem_ar_route = 50'b0;
    ifu_arready_route = 1'b0;
    lsu_arready_route = 1'b0;
    ifu_rvalid_route = 1'b0;
    lsu_r_route = 40'b0;
    mem_rready_route = 1'b0;
    clint_rready_route = 1'b0;
    mem_awvalid_route = 1'b0;
    lsu_awready_route = 1'b0;
    mem_wvalid_route = 1'b0;
    lsu_wready_route = 1'b0;
    lsu_b_route = 7'b0;
    mem_bready_route = 1'b0;
    clint_bready_route = 1'b0;
    clint_arvalid_route = 1'b0;
    clint_awvalid_route = 1'b0;
    clint_wvalid_route = 1'b0;

    case (active_route)
      ROUTE_IFU_MEM: begin
        mem_ar_route = {ifu_arvalid, ifu_araddr, ifu_arid,
                        ifu_arlen, ifu_arsize, ifu_arburst};
        ifu_arready_route = mem_arready;
        ifu_rvalid_route = mem_rvalid;
        mem_rready_route = ifu_rready;
      end
      ROUTE_LSU_MEM: begin
        mem_ar_route = {lsu_arvalid, lsu_araddr, lsu_arid,
                        lsu_arlen, lsu_arsize, lsu_arburst};
        lsu_arready_route = mem_arready;
        lsu_r_route = {mem_rvalid, mem_rdata, mem_rresp, mem_rlast, mem_rid};
        mem_rready_route = lsu_rready;
        mem_awvalid_route = lsu_awvalid;
        lsu_awready_route = mem_awready;
        mem_wvalid_route = lsu_wvalid;
        lsu_wready_route = mem_wready;
        lsu_b_route = {mem_bvalid, mem_bresp, mem_bid};
        mem_bready_route = lsu_bready;
      end
      ROUTE_LSU_CLINT: begin
        lsu_arready_route = clint_arready;
        lsu_r_route = {clint_rvalid, clint_rdata, clint_rresp,
                       clint_rlast, clint_rid};
        clint_rready_route = lsu_rready;
        lsu_awready_route = clint_awready;
        lsu_wready_route = clint_wready;
        lsu_b_route = {clint_bvalid, clint_bresp, clint_bid};
        clint_bready_route = lsu_bready;
        clint_arvalid_route = lsu_arvalid;
        clint_awvalid_route = lsu_awvalid;
        clint_wvalid_route = lsu_wvalid;
      end
      default: begin
        if (drain) begin
          mem_rready_route = 1'b1;
          mem_bready_route = 1'b1;
        end
      end
    endcase
  end

  // ========== AR 通道转发 (IFU/LSU → 目标 Slave) ==========
  // IFU 请求永远走外部 MEM (IFU 不会取指到 CLINT 空间)
  assign {mem_arvalid, mem_araddr, mem_arid, mem_arlen,
          mem_arsize, mem_arburst} = mem_ar_route;

  // CLINT AR: 只有 LSU 的 CLINT 读请求
  assign clint_arvalid = clint_arvalid_route;
  assign clint_araddr  = lsu_araddr;
  assign clint_arid    = lsu_arid;
  assign clint_arlen   = lsu_arlen;
  assign clint_arsize  = lsu_arsize;
  assign clint_arburst = lsu_arburst;

  // Slave → Master (阻塞未授权 master)
  assign ifu_arready = ifu_arready_route;
  assign lsu_arready = lsu_arready_route;

  // ========== R 通道转发 (Slave → Master) ==========
  // MEM → Master
  assign ifu_rvalid = ifu_rvalid_route;
  assign {lsu_rvalid, lsu_rdata, lsu_rresp, lsu_rlast, lsu_rid} = lsu_r_route;
  assign ifu_rdata  = mem_rdata;
  assign ifu_rresp  = mem_rresp;
  assign ifu_rlast  = mem_rlast;
  assign ifu_rid    = mem_rid;

  // Master → Slave (R ready)
  // drain 期间排空残留响应
  assign mem_rready = mem_rready_route;
  assign clint_rready = clint_rready_route;

  // ========== AW, W, B 通道转发 (仅 LSU, 且非 CLINT 空间) ==========
  // 外部 MEM 的写通道
  assign mem_awvalid = mem_awvalid_route;
  assign mem_awaddr  = lsu_awaddr;
  assign mem_awid    = lsu_awid;
  assign mem_awlen   = lsu_awlen;
  assign mem_awsize  = lsu_awsize;
  assign mem_awburst = lsu_awburst;
  assign lsu_awready = lsu_awready_route;

  assign mem_wvalid = mem_wvalid_route;
  assign mem_wdata  = lsu_wdata;
  assign mem_wstrb  = lsu_wstrb;
  assign mem_wlast  = lsu_wlast;
  assign lsu_wready = lsu_wready_route;

  assign {lsu_bvalid, lsu_bresp, lsu_bid} = lsu_b_route;
  assign mem_bready = mem_bready_route;
  assign clint_bready = clint_bready_route;

  // CLINT 写通道 (不支持写，CLINT 内部会返回 SLVERR)
  // 只要 LSU 选中 CLINT 且是写操作，就转发 AW/W 到 CLINT
  assign clint_awvalid = clint_awvalid_route;
  assign clint_awaddr  = lsu_awaddr;
  assign clint_awid    = lsu_awid;
  assign clint_awlen   = lsu_awlen;
  assign clint_awsize  = lsu_awsize;
  assign clint_awburst = lsu_awburst;

  assign clint_wvalid = clint_wvalid_route;
  assign clint_wdata  = lsu_wdata;
  assign clint_wstrb  = lsu_wstrb;
  assign clint_wlast  = lsu_wlast;

  // ========== 事务完成检测 ==========
  // IFU 读: 取指用外部 MEM
  wire ifu_done  = mem_rvalid && mem_rready && mem_rlast;
  // LSU 读: 可能走 CLINT 或外部 MEM
  reg lsu_rdone;
  always @(*) begin
    lsu_rdone = 1'b0;
    case ({lsu_is_read, active_route})
      {1'b1, ROUTE_LSU_MEM}:   lsu_rdone = mem_rvalid && mem_rready && mem_rlast;
      {1'b1, ROUTE_LSU_CLINT}: lsu_rdone = clint_rvalid && clint_rready && clint_rlast;
      {1'b0, ROUTE_LSU_MEM}:   lsu_rdone = mem_bvalid && mem_bready;
      {1'b0, ROUTE_LSU_CLINT}: lsu_rdone = clint_bvalid && clint_bready;
      default: ;
    endcase
  end

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state       <= IDLE;
      grant       <= IFU;
      lsu_is_read <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          if (!mem_rvalid && !mem_bvalid) begin
            if (ifu_req) begin
              state       <= BUSY;
              grant       <= IFU;
            end else if (lsu_req) begin
              state <= BUSY;
              grant <= LSU;
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
            if (lsu_rdone) begin
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
