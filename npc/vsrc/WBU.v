// ============================================================================
// WBU - 写回选择 (E stage)
//
// 关键优化: 不在写回路径上做加法。
//   * AUIPC 的 pc+imm_u 已由 ALU 计算 (alu_result);
//   * JAL/JALR 的 pc+4 由 Top 的 ex_pc_plus4 提供;
//   * 默认 pc_next 也用 pc_plus4。
// 这样 rd_data / pc_next 只经过纯 mux, 不再有 32-bit 加法器。
// ============================================================================
module WBU(
  input [31:0] pc,
  input [31:0] pc_plus4,
  input [31:0] alu_result,
  input [31:0] rdata,
  input [31:0] imm_u,
  input [31:0] pc_imm,
  input [31:0] jump_target,
  input [31:0] branch_target,
  input [31:0] csr_rdata,
  input [31:0] mepc,
  input [31:0] mtvec,
  input        branch_taken,

  input        is_lui,
  input        is_auipc,
  input        is_jal,
  input        is_jalr,
  input        is_ebreak,
  input        is_ecall,
  input        is_mret,
  input        is_csr,
  input        op_load,
  input        is_jump,

  output reg [31:0] rd_data,
  output reg [31:0] pc_next
);

  always @(*) begin
    rd_data = alu_result;
    if (op_load)  rd_data = rdata;
    if (is_lui)   rd_data = imm_u;
    if (is_auipc) rd_data = pc_imm;
    if (is_jump)  rd_data = pc_plus4;
    if (is_csr)   rd_data = csr_rdata;
  end

  always @(*) begin
    pc_next = pc_plus4;
    if (branch_taken) pc_next = branch_target;
    if (is_jal)       pc_next = branch_target;
    if (is_jalr)      pc_next = jump_target;
    if (is_mret)      pc_next = mepc;
    if (is_ecall)     pc_next = mtvec;
    if (is_ebreak)    pc_next = pc;
  end

endmodule
