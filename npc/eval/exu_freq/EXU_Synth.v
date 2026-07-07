module EXU_Synth(
  input clk,
  input rst,

  // ===== 输入寄存器 (隔离I/O) =====
  input [31:0] in_rs1_data,
  input [31:0] in_rs2_data,
  input [31:0] in_imm_i,
  input [31:0] in_imm_b,
  input [31:0] in_imm_j,
  input [31:0] in_pc,

  // 指令控制信号 (用输入寄存器打一拍)
  input in_is_add,
  input in_is_sub,
  input in_is_addi,
  input in_is_jal,
  input in_is_jalr,
  input in_is_beq,
  input in_is_bne,

  // ===== 输出寄存器 (输出加法器/ALU结果, 评估关键路径) =====
  output reg [31:0] out_alu_result,
  output reg        out_branch_taken
);

  // ===== 输入端触发器 =====
  reg [31:0] r_rs1, r_rs2, r_imm_i, r_imm_b, r_imm_j, r_pc;
  reg        r_is_add, r_is_sub, r_is_addi;
  reg        r_is_jal, r_is_jalr, r_is_beq, r_is_bne;

  always @(posedge clk) begin
    if (rst) begin
      r_rs1 <= 32'b0; r_rs2 <= 32'b0;
      r_imm_i <= 32'b0; r_imm_b <= 32'b0; r_imm_j <= 32'b0;
      r_pc <= 32'b0;
      r_is_add <= 1'b0; r_is_sub <= 1'b0; r_is_addi <= 1'b0;
      r_is_jal <= 1'b0; r_is_jalr <= 1'b0; r_is_beq <= 1'b0; r_is_bne <= 1'b0;
    end else begin
      r_rs1 <= in_rs1_data;
      r_rs2 <= in_rs2_data;
      r_imm_i <= in_imm_i;
      r_imm_b <= in_imm_b;
      r_imm_j <= in_imm_j;
      r_pc <= in_pc;
      r_is_add <= in_is_add;
      r_is_sub <= in_is_sub;
      r_is_addi <= in_is_addi;
      r_is_jal <= in_is_jal;
      r_is_jalr <= in_is_jalr;
      r_is_beq <= in_is_beq;
      r_is_bne <= in_is_bne;
    end
  end

  // ===== ALU关键路径 (评估加法器延迟) =====
  wire is_r_type = r_is_add || r_is_sub;
  wire [31:0] alu_src2 = is_r_type ? r_rs2 : r_imm_i;

  reg [31:0] alu_out;
  always @(*) begin
    case (1'b1)
      r_is_add || r_is_addi: alu_out = r_rs1 + alu_src2;   // 加法关键路径
      r_is_sub:              alu_out = r_rs1 - alu_src2;
      default:                alu_out = r_rs1 + alu_src2;    // 默认走加法路径
    endcase
  end

  // 分支判断 (也是处理器关键路径之一, 内部含比较器/加法器)
  wire branch_cond =
       r_is_beq  ? (r_rs1 == r_rs2) :
       r_is_bne  ? (r_rs1 != r_rs2) : 1'b0;

  // jalr/jal 目标地址计算 (含加法器)
  wire [31:0] jump_target = (r_is_jalr) ? ((r_rs1 + r_imm_i) & ~32'h1) : 32'b0;
  wire [31:0] branch_target = r_pc + (r_is_jal ? r_imm_j : r_imm_b);

  // ===== 输出端触发器: 把组合结果打进时钟, 把组合延迟纳入关键路径 =====
  always @(posedge clk) begin
    if (rst) begin
      out_alu_result   <= 32'b0;
      out_branch_taken <= 1'b0;
    end else begin
      // 选最大延迟的路径写入输出寄存器, 避免被综合优化掉
      out_alu_result   <= alu_out | jump_target | branch_target;
      out_branch_taken <= branch_cond;
    end
  end

endmodule
