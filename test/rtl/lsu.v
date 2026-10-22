// ============================================================================
//  LSU - 数据访存单元 (AXI4 单 beat)
//
//  与 npc/vsrc/LSU.v 功能一致, 但:
//   * 尺寸/掩码生成用编码后的 mem_op, 不再用 one-hot is_* 优先级 case;
//   * 读写状态机保持最小 (读: IDLE/WAIT_R, 写: IDLE/WAIT_B + aw/w done 标志).
// ============================================================================
module LSU(
  input  clk,
  input  rst,

  input  mem_valid,
  input  mem_wen,
  input  [3:0] mem_op,        // 与 IDU 的 M_* 编码一致
  input  [31:0] addr,
  input  [31:0] wdata,
  output reg [31:0] rdata,

  // AXI4 AR
  output        lsu_arvalid,
  input         lsu_arready,
  output [31:0] lsu_araddr,
  output [3:0]  lsu_arid,
  output [7:0]  lsu_arlen,
  output [2:0]  lsu_arsize,
  output [1:0]  lsu_arburst,

  // AXI4 R
  input         lsu_rvalid,
  output        lsu_rready,
  input  [1:0]  lsu_rresp,
  input  [31:0] lsu_rdata,
  input         lsu_rlast,
  input  [3:0]  lsu_rid,

  // AXI4 AW
  output        lsu_awvalid,
  input         lsu_awready,
  output [31:0] lsu_awaddr,
  output [3:0]  lsu_awid,
  output [7:0]  lsu_awlen,
  output [2:0]  lsu_awsize,
  output [1:0]  lsu_awburst,

  // AXI4 W
  output        lsu_wvalid,
  input         lsu_wready,
  output reg [31:0] lsu_wdata,
  output reg [3:0]  lsu_wstrb,
  output        lsu_wlast,

  // AXI4 B
  input         lsu_bvalid,
  output        lsu_bready,
  input  [1:0]  lsu_bresp,
  input  [3:0]  lsu_bid,

  output        lsu_done
);

  localparam [3:0] M_NONE = 4'd0,
                   M_LB   = 4'd1,
                   M_LH   = 4'd2,
                   M_LW   = 4'd3,
                   M_LBU  = 4'd4,
                   M_LHU  = 4'd5,
                   M_SB   = 4'd6,
                   M_SH   = 4'd7,
                   M_SW   = 4'd8;

  wire is_load  = (mem_op == M_LB)  || (mem_op == M_LH)  ||
                  (mem_op == M_LW)  || (mem_op == M_LBU) ||
                  (mem_op == M_LHU);
  wire is_store = (mem_op == M_SB)  || (mem_op == M_SH)  ||
                  (mem_op == M_SW);

  wire [2:0] size = (mem_op == M_LB) || (mem_op == M_LBU) || (mem_op == M_SB) ? 3'd0 :
                    (mem_op == M_LH) || (mem_op == M_LHU) || (mem_op == M_SH) ? 3'd1 : 3'd2;

  // ------------------------------------------------------------ 读状态机
  localparam R_IDLE = 1'b0, R_WAIT = 1'b1;
  reg rstate;

  // ------------------------------------------------------------ 写状态机
  localparam W_IDLE = 1'b0, W_WAIT = 1'b1;
  reg wstate;
  reg aw_done, w_done;

  assign lsu_arvalid = mem_valid && is_load  && (rstate == R_IDLE);
  assign lsu_araddr  = addr;
  assign lsu_arid    = 4'b0010;
  assign lsu_arlen   = 8'b0;
  assign lsu_arsize  = size;
  assign lsu_arburst = 2'b01;
  assign lsu_rready  = mem_valid && is_load && (rstate == R_WAIT);

  assign lsu_awvalid = mem_valid && is_store && (wstate == W_IDLE) && !aw_done;
  assign lsu_awaddr  = addr;
  assign lsu_awid    = 4'b0010;
  assign lsu_awlen   = 8'b0;
  assign lsu_awsize  = size;
  assign lsu_awburst = 2'b01;

  assign lsu_wvalid  = mem_valid && is_store && (wstate == W_IDLE) && !w_done;
  assign lsu_wlast   = 1'b1;
  assign lsu_bready  = mem_valid && is_store && (wstate == W_WAIT);

  wire aw_fire = lsu_awvalid && lsu_awready;
  wire w_fire  = lsu_wvalid  && lsu_wready;
  wire aw_ok   = aw_done || aw_fire;
  wire w_ok    = w_done  || w_fire;

  always @(posedge clk) begin
    if (rst) begin
      rstate  <= R_IDLE;
      wstate  <= W_IDLE;
      aw_done <= 1'b0;
      w_done  <= 1'b0;
    end else begin
      // 读
      case (rstate)
        R_IDLE: begin
          if (lsu_arvalid && lsu_arready) rstate <= R_WAIT;
        end
        R_WAIT: begin
          if (lsu_rvalid && lsu_rready && lsu_rlast) rstate <= R_IDLE;
        end
        default: rstate <= R_IDLE;
      endcase

      // 写
      case (wstate)
        W_IDLE: begin
          if (aw_fire) aw_done <= 1'b1;
          if (w_fire)  w_done  <= 1'b1;
          if (aw_ok && w_ok) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
            wstate  <= W_WAIT;
          end
        end
        W_WAIT: begin
          if (lsu_bvalid && lsu_bready) wstate <= W_IDLE;
        end
        default: wstate <= W_IDLE;
      endcase
    end
  end

  assign lsu_done = (rstate == R_WAIT) && lsu_rvalid && lsu_rready && lsu_rlast ||
                    (wstate == W_WAIT) && lsu_bvalid && lsu_bready;

  // ------------------------------------------------------------ 读数据扩展
  wire [7:0]  byte0 = lsu_rdata[7:0];
  wire [7:0]  byte1 = lsu_rdata[15:8];
  wire [7:0]  byte2 = lsu_rdata[23:16];
  wire [7:0]  byte3 = lsu_rdata[31:24];
  wire [15:0] half0 = lsu_rdata[15:0];
  wire [15:0] half1 = lsu_rdata[31:16];

  reg [7:0] sel_byte;
  reg [15:0] sel_half;
  always @(*) begin
    case (addr[1:0])
      2'b00: sel_byte = byte0;
      2'b01: sel_byte = byte1;
      2'b10: sel_byte = byte2;
      default: sel_byte = byte3;
    endcase
    sel_half = addr[1] ? half1 : half0;
  end

  always @(*) begin
    case (mem_op)
      M_LB : rdata = {{24{sel_byte[7]}}, sel_byte};
      M_LBU: rdata = {24'b0, sel_byte};
      M_LH : rdata = {{16{sel_half[15]}}, sel_half};
      M_LHU: rdata = {16'b0, sel_half};
      M_LW : rdata = lsu_rdata;
      default: rdata = 32'b0;
    endcase
  end

  // ------------------------------------------------------------ 写数据/掩码
  always @(*) begin
    case (mem_op)
      M_SW: begin
        lsu_wdata = wdata;
        lsu_wstrb = 4'b1111;
      end
      M_SH: begin
        lsu_wdata = addr[1] ? {wdata[15:0], 16'b0} : wdata;
        lsu_wstrb = addr[1] ? 4'b1100 : 4'b0011;
      end
      M_SB: begin
        case (addr[1:0])
          2'b00: begin lsu_wdata = wdata;         lsu_wstrb = 4'b0001; end
          2'b01: begin lsu_wdata = wdata << 8;    lsu_wstrb = 4'b0010; end
          2'b10: begin lsu_wdata = wdata << 16;   lsu_wstrb = 4'b0100; end
          default: begin lsu_wdata = wdata << 24; lsu_wstrb = 4'b1000; end
        endcase
      end
      default: begin
        lsu_wdata = 32'b0;
        lsu_wstrb = 4'b0;
      end
    endcase
  end

endmodule
