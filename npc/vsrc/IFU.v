// ============================================================================
// IFU - 取指段 (F stage)
//
// 流式取指: 命中时每拍一条。取指目标由 4 项 BTB (taken cache) 预测:
// 若当前 PC 有表项 -> 下一拍直接取目标; 否则顺序 pc+4。
//
// 预测是否正确不再随指令携带元数据, 而是在 E 段用"流水线里下一条指令的 PC
// 是否等于正确的下一 PC"来校验 (见 top.v 的 next_pc_ok):
//   * 正确 -> 不打断流水;
//   * 错误/未预测到 -> 重定向并刷新 IFID。
// 这样 BTB 只影响性能, 不影响正确性, 也省掉 IFID/IDEX 中的预测目标寄存器。
// ============================================================================
module IFU(
  input clk,
  input rst,

  input        redirect,
  input [31:0] redirect_pc,
  input        flush_btb,

  output        fetch_req_valid,
  input         fetch_req_ready,
  output [31:0] fetch_pc,
  input         fetch_resp_valid,
  input  [31:0] fetch_resp_inst,
  output        fetch_resp_ready,

  output reg        ifid_valid,
  output reg [31:0] ifid_inst,
  output reg [31:0] ifid_pc,

  input d_advance,

  // E 段实际跳转结果 -> BTB 更新 (在 taken 时写入)
  input        btb_update,
  input [31:0] btb_update_pc,
  input [31:0] btb_update_target,

  output [31:0] pc_out,
  output        btb_hit_out
);

`ifdef SOC_MODE
  localparam [31:0] RESET_PC = 32'h3000_0000;
`else
  localparam [31:0] RESET_PC = 32'h8000_0000;
`endif

  localparam BTB_ENTRIES = 8;

  reg [BTB_ENTRIES-1:0] btb_valid;
  reg [18:0]            btb_tag [0:BTB_ENTRIES-1];   // pc[23:5]
  reg [14:0]            btb_target [0:BTB_ENTRIES-1]; // target[14:0]

  reg [31:0] pc_f;

  wire [2:0]  btb_idx    = pc_f[4:2];
  wire [18:0] btb_tag_in = pc_f[23:5];
  wire [2:0]  btb_widx   = btb_update_pc[4:2];

  wire btb_match = btb_valid[btb_idx] && (btb_tag[btb_idx] == btb_tag_in);

  // 标签被截断, 必须只在取到的指令确实是 B/J 时才使用预测, 否则一个
  // 标签别名可能让非分支指令跳到错误目标而无法被 E 段纠正。
  wire is_ctrl = (fetch_resp_inst[6:0] == 7'b1100011) ||   // B-type
                 (fetch_resp_inst[6:0] == 7'b1101111) ||   // JAL
                 (fetch_resp_inst[6:0] == 7'b1100111);     // JALR
  wire btb_hit = btb_match && is_ctrl;

  wire [31:0] btb_target_out = {pc_f[31:15], btb_target[btb_idx]};
  wire [31:0] pc_plus4 = pc_f + 32'd4;
  wire [31:0] next_pc = btb_hit ? btb_target_out : pc_plus4;

  wire can_fetch = !ifid_valid || d_advance;

  assign fetch_req_valid   = !rst && can_fetch && !redirect;
  assign fetch_resp_ready  = !rst && can_fetch && !redirect;
  assign fetch_pc          = pc_f;
  assign pc_out            = pc_f;
  assign btb_hit_out       = btb_hit;

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      pc_f      <= RESET_PC;
      ifid_valid<= 1'b0;
      ifid_inst <= 32'h0000_0013;
      ifid_pc   <= RESET_PC;
      btb_valid <= {BTB_ENTRIES{1'b0}};
      for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
        btb_tag[i]    <= 19'b0;
        btb_target[i] <= 15'b0;
      end
    end else begin
      if (btb_update) begin
        btb_valid[btb_widx]  <= 1'b1;
        btb_tag[btb_widx]    <= btb_update_pc[23:5];
        btb_target[btb_widx] <= btb_update_target[14:0];
      end
      if (flush_btb) begin
        btb_valid <= {BTB_ENTRIES{1'b0}};
      end

      if (redirect) begin
        pc_f       <= redirect_pc;
        ifid_valid <= 1'b0;
      end else if (fetch_resp_valid && fetch_resp_ready) begin
        ifid_valid <= 1'b1;
        ifid_inst  <= fetch_resp_inst;
        ifid_pc    <= pc_f;
        pc_f       <= next_pc;
      end else if (ifid_valid && d_advance) begin
        ifid_valid <= 1'b0;
      end
    end
  end

endmodule
