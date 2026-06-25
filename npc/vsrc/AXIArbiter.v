// AXIArbiter - AXI4-Lite 仲裁器
//
// 状态机:
//   IDLE: 无 master 获得授权, 检测请求
//   BUSY: 已授权某个 master, 转发其事务直到完成
//

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
  wire ifu_granted = (state == IDLE && ifu_req && !rst) || (state == BUSY && grant == IFU);
  wire lsu_granted = (state == IDLE && lsu_req && !ifu_req && !rst) || (state == BUSY && grant == LSU);

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

  // ========== AW , W , B 通道转发 (仅 LSU) ==========
  assign mem_awvalid = lsu_granted ? lsu_awvalid : 1'b0;
  assign mem_awaddr  = lsu_awaddr;
  assign lsu_awready = lsu_granted ? mem_awready : 1'b0;

  assign mem_wvalid = lsu_granted ? lsu_wvalid : 1'b0;
  assign mem_wdata  = lsu_wdata;
  assign mem_wstrb  = lsu_wstrb;
  assign lsu_wready = lsu_granted ? mem_wready : 1'b0;

  assign lsu_bvalid = lsu_granted ? mem_bvalid : 1'b0;
  assign lsu_bresp  = mem_bresp;
  assign mem_bready = lsu_granted ? lsu_bready : 1'b0;

  // ========== 事务完成检测 ==========
  wire ifu_done  = mem_rvalid && mem_rready;
  wire lsu_done  = lsu_is_read ? (mem_rvalid && mem_rready)
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
