// EXU - Execution Unit
// 执行单元：负责ALU运算、分支判断和跳转地址计算

module EXU(
  input [31:0] rs1_data,      // 源寄存器1数据
  input [31:0] rs2_data,      // 源寄存器2数据
  input [31:0] imm_i,         // I型立即数
  input [31:0] imm_b,         // B型立即数
  input [31:0] imm_j,         // J型立即数
  input [31:0] pc,            // 当前PC
  
  // R型算术/逻辑指令
  input is_add,
  input is_sub,
  input is_and,
  input is_or,
  input is_xor,
  input is_sll,
  input is_srl,
  input is_sra,
  input is_slt,
  input is_sltu,
  
  // I型算术/逻辑指令
  input is_addi,
  input is_slti,
  input is_sltiu,
  input is_xori,
  input is_ori,
  input is_andi,
  input is_slli,
  input is_srli,
  input is_srai,
  
  // B型分支指令
  input is_beq,
  input is_bne,
  input is_blt,
  input is_bge,
  input is_bltu,
  input is_bgeu,
  
  // J型指令
  input is_jal,
  input is_jalr,
  
  // CSR指令
  input is_csrrw,
  input is_csrrs,
  input [31:0] csr_rdata,     // CSR读数据
  output [31:0] csr_wdata,    // CSR写数据
  
  // 输出
  output [31:0] alu_result,   // ALU计算结果
  output [31:0] jump_target,  // 跳转目标地址
  output [31:0] branch_target,// 分支目标地址
  output branch_taken         // 分支是否跳转
);

  // ========== ALU运算 ==========
  wire [31:0] alu_src1 = rs1_data;
  wire [31:0] alu_src2;
  wire [4:0] shamt;  // 移位量
  
  // 选择ALU第二个操作数：R型用rs2，I型用imm_i
  wire is_r_type = is_add || is_sub || is_and || is_or || is_xor || is_sll || is_srl || is_sra || is_slt || is_sltu;
  assign alu_src2 = is_r_type ? rs2_data : imm_i;
  
  // 移位量：R型用rs2[4:0]，I型用imm_i[4:0]
  assign shamt = is_r_type ? rs2_data[4:0] : imm_i[4:0];
  
  // ALU运算结果
  reg [31:0] alu_out;
  always @(*) begin
    case (1'b1)
      // 加法
      is_add || is_addi: alu_out = alu_src1 + alu_src2;
      
      // 减法
      is_sub: alu_out = alu_src1 - alu_src2;
      
      // 逻辑运算
      is_and || is_andi: alu_out = alu_src1 & alu_src2;
      is_or  || is_ori:  alu_out = alu_src1 | alu_src2;
      is_xor || is_xori: alu_out = alu_src1 ^ alu_src2;
      
      // 移位运算
      is_sll || is_slli: alu_out = alu_src1 << shamt;
      is_srl || is_srli: alu_out = alu_src1 >> shamt;
      is_sra || is_srai: alu_out = $signed(alu_src1) >>> shamt;
      
      // 比较运算（有符号）
      is_slt || is_slti: alu_out = ($signed(alu_src1) < $signed(alu_src2)) ? 32'b1 : 32'b0;
      
      // 比较运算（无符号）
      is_sltu || is_sltiu: alu_out = (alu_src1 < alu_src2) ? 32'b1 : 32'b0;
      
      default: alu_out = 32'b0;
    endcase
  end
  
  assign alu_result = alu_out;
  
  // ========== 分支判断 ==========
  reg branch_cond;
  always @(*) begin
    case (1'b1)
      is_beq:  branch_cond = (rs1_data == rs2_data);
      is_bne:  branch_cond = (rs1_data != rs2_data);
      is_blt:  branch_cond = ($signed(rs1_data) < $signed(rs2_data));
      is_bge:  branch_cond = ($signed(rs1_data) >= $signed(rs2_data));
      is_bltu: branch_cond = (rs1_data < rs2_data);
      is_bgeu: branch_cond = (rs1_data >= rs2_data);
      default: branch_cond = 1'b0;
    endcase
  end
  
  assign branch_taken = branch_cond;
  
  // ========== 跳转和分支目标地址计算 ==========
  // jalr: (rs1 + imm_i) & ~1，最低位清零确保对齐
  assign jump_target = (rs1_data + imm_i) & ~32'h1;
  
  // jal和分支: PC + imm
  assign branch_target = pc + (is_jal ? imm_j : imm_b);
  
  // ========== CSR指令处理 ==========
  // csrrw: CSR = rs1, rd = old_CSR
  // csrrs: CSR = CSR | rs1, rd = old_CSR
  assign csr_wdata = is_csrrw ? rs1_data : (csr_rdata | rs1_data);

endmodule
