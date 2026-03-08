// WBU - WriteBack Unit
// 写回单元：负责选择写回寄存器的数据，并计算下一个PC

module WBU(
  input [31:0] pc,            // 当前PC
  input [31:0] alu_result,    // ALU结果
  input [31:0] mem_rdata,     // 存储器读数据
  input [31:0] imm_u,         // U型立即数
  input [31:0] jump_target,   // jalr跳转目标地址
  input [31:0] branch_target, // jal/分支目标地址
  input branch_taken,         // 分支是否跳转
  
  // 加载指令
  input is_lb,
  input is_lh,
  input is_lw,
  input is_lbu,
  input is_lhu,
  
  // 分支指令
  input is_beq,
  input is_bne,
  input is_blt,
  input is_bge,
  input is_bltu,
  input is_bgeu,
  
  // U型指令
  input is_lui,
  input is_auipc,
  
  // J型指令
  input is_jal,
  input is_jalr,
  
  // 系统指令
  input is_ebreak,
  
  // 输出
  output [31:0] rd_data,      // 写回寄存器的数据
  output [31:0] pc_next       // 下一个PC
);

  // ========== 写回数据选择 ==========
  wire is_load = is_lb || is_lh || is_lw || is_lbu || is_lhu;
  wire is_jump = is_jal || is_jalr;
  wire is_branch = is_beq || is_bne || is_blt || is_bge || is_bltu || is_bgeu;
  
  assign rd_data = is_jump ? (pc + 4) :           // jal/jalr：保存返回地址
                   is_lui ? imm_u :                // lui：加载立即数
                   is_auipc ? (pc + imm_u) :       // auipc：PC + 立即数
                   is_load ? mem_rdata :           // load：存储器数据
                   alu_result;                     // 其他：ALU结果
  
  // ========== PC更新逻辑 ==========
  assign pc_next = is_ebreak ? pc :                           // ebreak：PC不变
                   is_jalr ? jump_target :                    // jalr：跳转到jump_target
                   is_jal ? branch_target :                   // jal：跳转到branch_target
                   (is_branch && branch_taken) ? branch_target : // 分支跳转
                   pc + 4;                                    // 其他：顺序执行

endmodule
