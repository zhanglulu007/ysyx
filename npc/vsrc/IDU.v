// IDU - Instruction Decode Unit
// 译码单元：负责对指令进行译码，提取操作数和控制信号

module IDU(
  input [31:0] inst,          // 输入指令
  
  // 指令字段
  output [6:0] opcode,
  output [4:0] rd,
  output [4:0] rs1,
  output [4:0] rs2,
  output [2:0] funct3,
  output [6:0] funct7,
  
  // 立即数
  output [31:0] imm_i,        // I型立即数
  output [31:0] imm_s,        // S型立即数
  output [31:0] imm_b,        // B型立即数
  output [31:0] imm_u,        // U型立即数
  output [31:0] imm_j,        // J型立即数
  
  // R型算术/逻辑指令
  output is_add,
  output is_sub,
  output is_and,
  output is_or,
  output is_xor,
  output is_sll,
  output is_srl,
  output is_sra,
  output is_slt,
  output is_sltu,
  
  // I型算术/逻辑指令
  output is_addi,
  output is_slti,
  output is_sltiu,
  output is_xori,
  output is_ori,
  output is_andi,
  output is_slli,
  output is_srli,
  output is_srai,
  
  // I型加载指令
  output is_lb,
  output is_lh,
  output is_lw,
  output is_lbu,
  output is_lhu,
  
  // S型存储指令
  output is_sb,
  output is_sh,
  output is_sw,
  
  // B型分支指令
  output is_beq,
  output is_bne,
  output is_blt,
  output is_bge,
  output is_bltu,
  output is_bgeu,
  
  // U型指令
  output is_lui,
  output is_auipc,
  
  // J型指令
  output is_jal,
  output is_jalr,
  
  // 系统指令
  output is_ebreak,
  
  // 控制信号
  output reg_wen,             // 寄存器写使能
  output mem_valid,           // 访存有效
  output mem_wen              // 存储器写使能
);

  // 提取指令字段
  assign opcode = inst[6:0];
  assign rd = inst[11:7];
  assign rs1 = inst[19:15];
  assign rs2 = inst[24:20];
  assign funct3 = inst[14:12];
  assign funct7 = inst[31:25];
  
  // 提取立即数
  assign imm_i = {{20{inst[31]}}, inst[31:20]};                                    // I型：符号扩展
  assign imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};                       // S型：符号扩展
  assign imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}; // B型：符号扩展，左移1位
  assign imm_u = {inst[31:12], 12'b0};                                             // U型：高20位
  assign imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}; // J型：符号扩展，左移1位
  
  // ========== R型算术/逻辑指令 ==========
  assign is_add  = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
  assign is_sub  = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0100000);
  assign is_and  = (opcode == 7'b0110011) && (funct3 == 3'b111) && (funct7 == 7'b0000000);
  assign is_or   = (opcode == 7'b0110011) && (funct3 == 3'b110) && (funct7 == 7'b0000000);
  assign is_xor  = (opcode == 7'b0110011) && (funct3 == 3'b100) && (funct7 == 7'b0000000);
  assign is_sll  = (opcode == 7'b0110011) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
  assign is_srl  = (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
  assign is_sra  = (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 == 7'b0100000);
  assign is_slt  = (opcode == 7'b0110011) && (funct3 == 3'b010) && (funct7 == 7'b0000000);
  assign is_sltu = (opcode == 7'b0110011) && (funct3 == 3'b011) && (funct7 == 7'b0000000);
  
  // ========== I型算术/逻辑指令 ==========
  assign is_addi  = (opcode == 7'b0010011) && (funct3 == 3'b000);
  assign is_slti  = (opcode == 7'b0010011) && (funct3 == 3'b010);
  assign is_sltiu = (opcode == 7'b0010011) && (funct3 == 3'b011);
  assign is_xori  = (opcode == 7'b0010011) && (funct3 == 3'b100);
  assign is_ori   = (opcode == 7'b0010011) && (funct3 == 3'b110);
  assign is_andi  = (opcode == 7'b0010011) && (funct3 == 3'b111);
  assign is_slli  = (opcode == 7'b0010011) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
  assign is_srli  = (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
  assign is_srai  = (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 == 7'b0100000);
  
  // ========== I型加载指令 ==========
  assign is_lb  = (opcode == 7'b0000011) && (funct3 == 3'b000);
  assign is_lh  = (opcode == 7'b0000011) && (funct3 == 3'b001);
  assign is_lw  = (opcode == 7'b0000011) && (funct3 == 3'b010);
  assign is_lbu = (opcode == 7'b0000011) && (funct3 == 3'b100);
  assign is_lhu = (opcode == 7'b0000011) && (funct3 == 3'b101);
  
  // ========== S型存储指令 ==========
  assign is_sb = (opcode == 7'b0100011) && (funct3 == 3'b000);
  assign is_sh = (opcode == 7'b0100011) && (funct3 == 3'b001);
  assign is_sw = (opcode == 7'b0100011) && (funct3 == 3'b010);
  
  // ========== B型分支指令 ==========
  assign is_beq  = (opcode == 7'b1100011) && (funct3 == 3'b000);
  assign is_bne  = (opcode == 7'b1100011) && (funct3 == 3'b001);
  assign is_blt  = (opcode == 7'b1100011) && (funct3 == 3'b100);
  assign is_bge  = (opcode == 7'b1100011) && (funct3 == 3'b101);
  assign is_bltu = (opcode == 7'b1100011) && (funct3 == 3'b110);
  assign is_bgeu = (opcode == 7'b1100011) && (funct3 == 3'b111);
  
  // ========== U型指令 ==========
  assign is_lui   = (opcode == 7'b0110111);
  assign is_auipc = (opcode == 7'b0010111);
  
  // ========== J型指令 ==========
  assign is_jal  = (opcode == 7'b1101111);
  assign is_jalr = (opcode == 7'b1100111) && (funct3 == 3'b000);
  
  // ========== 系统指令 ==========
  assign is_ebreak = (inst == 32'h00100073);
  
  // ========== 控制信号生成 ==========
  // 寄存器写使能：所有需要写回rd的指令（除了分支、存储、ebreak）
  wire is_r_type = is_add || is_sub || is_and || is_or || is_xor || is_sll || is_srl || is_sra || is_slt || is_sltu;
  wire is_i_arith = is_addi || is_slti || is_sltiu || is_xori || is_ori || is_andi || is_slli || is_srli || is_srai;
  wire is_load = is_lb || is_lh || is_lw || is_lbu || is_lhu;
  wire is_jump = is_jal || is_jalr;
  wire is_u_type = is_lui || is_auipc;
  
  assign reg_wen = ((is_r_type || is_i_arith || is_load || is_jump || is_u_type) && (rd != 5'b0));
  
  // 访存有效：所有加载和存储指令
  wire is_store = is_sb || is_sh || is_sw;
  assign mem_valid = is_load || is_store;
  
  // 存储器写使能：所有存储指令
  assign mem_wen = is_store;

endmodule
