// ============================================================================
//  IFU - 取指 FIFO
//
//  与 npc/vsrc/IFU.v 的 "每条指令发一次 AR/R 握手" 不同, 这里用 8 项指令
//  FIFO 把取指和执行解耦:
//    * ICache 自主顺序预取, 每个周期可以送入一条指令;
//    * 执行单元按 FIFO 顺序退休, 没有额外取指握手开销;
//    * 分支/跳转重定向时清空 FIFO.
//  FIFO 中的指令地址是连续的, 因此只保存 head_pc, 不保存每条指令的 PC.
// ============================================================================
module IFU #(
  parameter [31:0] BOOT_PC = 32'h8000_0000
)(
  input  clk,
  input  rst,

  input         redirect,
  input  [31:0] redirect_addr,

  input  [31:0] fill_data,
  input         fill_valid,
  input         fill_miss,
  output        fill_ready,

  output [31:0] inst,
  output [31:0] pc,
  output        valid,
  output        head_miss,

  input         pop
);

  localparam DEPTH = 8;

  reg [31:0] fifo [0:DEPTH-1];
  reg [DEPTH-1:0] fifo_miss;
  reg [2:0]  rptr;
  reg [2:0]  wptr;
  reg [3:0]  count;
  reg [31:0] head_pc;

  wire full  = (count == DEPTH[3:0]);
  wire empty = (count == 4'd0);
  wire push  = fill_valid && !full && !redirect;

  always @(posedge clk) begin
    if (rst) begin
      rptr    <= 3'b0;
      wptr    <= 3'b0;
      count   <= 4'b0;
      head_pc <= BOOT_PC;
      fifo_miss <= {DEPTH{1'b0}};
    end else if (redirect) begin
      rptr    <= 3'b0;
      wptr    <= 3'b0;
      count   <= 4'b0;
      head_pc <= redirect_addr;
      fifo_miss <= {DEPTH{1'b0}};
    end else begin
      if (push) begin
        fifo[wptr]      <= fill_data;
        fifo_miss[wptr] <= fill_miss;
        wptr            <= wptr + 3'd1;
      end
      if (pop) begin
        rptr    <= rptr + 3'd1;
        head_pc <= head_pc + 32'd4;
      end
      count <= count + (push ? 4'd1 : 4'd0) - (pop ? 4'd1 : 4'd0);
    end
  end

  assign fill_ready = !full && !redirect;
  assign inst       = fifo[rptr];
  assign pc         = head_pc;
  assign valid      = !empty;
  assign head_miss  = fifo_miss[rptr];

endmodule
