module EXU(
  input [31:0] rs1_data,      
  input [31:0] rs2_data,      
  input [31:0] imm_i,         
  input [31:0] pc,            

  input is_add,
  input is_jalr,
  
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
