// EXU - Execution Unit
// 执行单元：负责ALU运算和跳转地址计算

module EXU(
  input [31:0] rs1_data,      // 源寄存器1数据
  input [31:0] rs2_data,      // 源寄存器2数据
  input [31:0] imm_i,         // I型立即数
  input [31:0] pc,            // 当前PC
  
  // 指令类型
  input is_add,
  input is_jalr,
  
  // 输出
  output [31:0] alu_result,   // ALU计算结果
  output [31:0] jump_target   // 跳转目标地址
);

  // ALU：加法运算
  // add指令：rs1 + rs2
  // 其他指令：rs1 + imm_i
  assign alu_result = is_add ? (rs1_data + rs2_data) : (rs1_data + imm_i);
  
  // 跳转目标地址计算（jalr指令）
  // 目标地址 = (rs1 + imm_i) & ~1，最低位清零确保对齐
  assign jump_target = (rs1_data + imm_i) & ~32'h1;

endmodule
