module WBU(
  input [31:0] pc,            
  input [31:0] alu_result,    
  input [31:0] mem_rdata,     
  input [31:0] imm_u,         
  input [31:0] jump_target,   
  
  input is_jalr,
  input is_lui,
  input is_lw,
  input is_lbu,
  input is_ebreak,
  
  output [31:0] rd_data,      
  output [31:0] pc_next       
);

  // 写回数据选择
  assign rd_data = is_jalr ? (pc + 4) :           // jalr：保存返回地址
                   is_lui ? imm_u :                // lui：加载立即数
                   (is_lw || is_lbu) ? mem_rdata : // load：存储器数据
                   alu_result;                     // 其他：ALU结果
  
  // PC更新逻辑
  assign pc_next = is_ebreak ? pc :               // ebreak：PC不变
                   is_jalr ? jump_target :        // jalr：跳转
                   pc + 4;                        // 其他：顺序执行

endmodule
