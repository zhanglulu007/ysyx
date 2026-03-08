// NPC - RV32E processor (Modular Design)
// 模块化设计：将处理器拆分为IFU、IDU、EXU、LSU、WBU等模块

module top(
  input clk,
  input rst
);

  // ========== 模块间连接信号 ==========
  
  // IFU <-> IDU
  wire [31:0] pc;
  wire [31:0] inst;
  
  // IDU输出 - 指令字段
  wire [6:0] opcode;
  wire [4:0] rd, rs1, rs2;
  wire [2:0] funct3;
  wire [6:0] funct7;
  
  // IDU输出 - 立即数
  wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  
  // IDU输出 - R型指令
  wire is_add, is_sub, is_and, is_or, is_xor;
  wire is_sll, is_srl, is_sra, is_slt, is_sltu;
  
  // IDU输出 - I型算术/逻辑指令
  wire is_addi, is_slti, is_sltiu, is_xori, is_ori, is_andi;
  wire is_slli, is_srli, is_srai;
  
  // IDU输出 - I型加载指令
  wire is_lb, is_lh, is_lw, is_lbu, is_lhu;
  
  // IDU输出 - S型存储指令
  wire is_sb, is_sh, is_sw;
  
  // IDU输出 - B型分支指令
  wire is_beq, is_bne, is_blt, is_bge, is_bltu, is_bgeu;
  
  // IDU输出 - U型指令
  wire is_lui, is_auipc;
  
  // IDU输出 - J型指令
  wire is_jal, is_jalr;
  
  // IDU输出 - 系统指令
  wire is_ebreak;
  
  // IDU输出 - 控制信号
  wire reg_wen, mem_valid, mem_wen;
  
  // RegisterFile输出
  wire [31:0] rs1_data, rs2_data;
  wire [31:0] a0_value;  // a0寄存器的值
  
  // EXU输出
  wire [31:0] alu_result;
  wire [31:0] jump_target;
  wire [31:0] branch_target;
  wire branch_taken;
  
  // LSU输出
  wire [31:0] mem_rdata;
  
  // WBU输出
  wire [31:0] rd_data;
  wire [31:0] pc_next;
  
  // 访存地址计算
  wire [31:0] mem_addr;
  wire is_store = is_sb || is_sh || is_sw;
  assign mem_addr = is_store ? (rs1_data + imm_s) : (rs1_data + imm_i);
  
  // ========== 模块实例化 ==========
  
  // IFU - 取指单元
  IFU u_ifu(
    .clk(clk),
    .rst(rst),
    .pc_next(pc_next),
    .pc(pc),
    .inst(inst)
  );
  
  // IDU - 译码单元
  IDU u_idu(
    .inst(inst),
    .opcode(opcode),
    .rd(rd),
    .rs1(rs1),
    .rs2(rs2),
    .funct3(funct3),
    .funct7(funct7),
    // 立即数
    .imm_i(imm_i),
    .imm_s(imm_s),
    .imm_b(imm_b),
    .imm_u(imm_u),
    .imm_j(imm_j),
    // R型指令
    .is_add(is_add),
    .is_sub(is_sub),
    .is_and(is_and),
    .is_or(is_or),
    .is_xor(is_xor),
    .is_sll(is_sll),
    .is_srl(is_srl),
    .is_sra(is_sra),
    .is_slt(is_slt),
    .is_sltu(is_sltu),
    // I型算术/逻辑指令
    .is_addi(is_addi),
    .is_slti(is_slti),
    .is_sltiu(is_sltiu),
    .is_xori(is_xori),
    .is_ori(is_ori),
    .is_andi(is_andi),
    .is_slli(is_slli),
    .is_srli(is_srli),
    .is_srai(is_srai),
    // I型加载指令
    .is_lb(is_lb),
    .is_lh(is_lh),
    .is_lw(is_lw),
    .is_lbu(is_lbu),
    .is_lhu(is_lhu),
    // S型存储指令
    .is_sb(is_sb),
    .is_sh(is_sh),
    .is_sw(is_sw),
    // B型分支指令
    .is_beq(is_beq),
    .is_bne(is_bne),
    .is_blt(is_blt),
    .is_bge(is_bge),
    .is_bltu(is_bltu),
    .is_bgeu(is_bgeu),
    // U型指令
    .is_lui(is_lui),
    .is_auipc(is_auipc),
    // J型指令
    .is_jal(is_jal),
    .is_jalr(is_jalr),
    // 系统指令
    .is_ebreak(is_ebreak),
    // 控制信号
    .reg_wen(reg_wen),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen)
  );
  
  // RegisterFile - 寄存器堆
  RegisterFile u_regfile(
    .clk(clk),
    .waddr(rd),
    .wdata(rd_data),
    .wen(reg_wen),
    .raddr1(rs1),
    .rdata1(rs1_data),
    .raddr2(rs2),
    .rdata2(rs2_data),
    .a0_value(a0_value)
  );
  
  // EXU - 执行单元
  EXU u_exu(
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .imm_i(imm_i),
    .imm_b(imm_b),
    .imm_j(imm_j),
    .pc(pc),
    // R型指令
    .is_add(is_add),
    .is_sub(is_sub),
    .is_and(is_and),
    .is_or(is_or),
    .is_xor(is_xor),
    .is_sll(is_sll),
    .is_srl(is_srl),
    .is_sra(is_sra),
    .is_slt(is_slt),
    .is_sltu(is_sltu),
    // I型算术/逻辑指令
    .is_addi(is_addi),
    .is_slti(is_slti),
    .is_sltiu(is_sltiu),
    .is_xori(is_xori),
    .is_ori(is_ori),
    .is_andi(is_andi),
    .is_slli(is_slli),
    .is_srli(is_srli),
    .is_srai(is_srai),
    // B型分支指令
    .is_beq(is_beq),
    .is_bne(is_bne),
    .is_blt(is_blt),
    .is_bge(is_bge),
    .is_bltu(is_bltu),
    .is_bgeu(is_bgeu),
    // J型指令
    .is_jal(is_jal),
    .is_jalr(is_jalr),
    // 输出
    .alu_result(alu_result),
    .jump_target(jump_target),
    .branch_target(branch_target),
    .branch_taken(branch_taken)
  );
  
  // LSU - 访存单元
  LSU u_lsu(
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    // 加载指令
    .is_lb(is_lb),
    .is_lh(is_lh),
    .is_lw(is_lw),
    .is_lbu(is_lbu),
    .is_lhu(is_lhu),
    // 存储指令
    .is_sb(is_sb),
    .is_sh(is_sh),
    .is_sw(is_sw),
    // 地址和数据
    .mem_addr(mem_addr),
    .wdata(rs2_data),
    .rdata(mem_rdata)
  );
  
  // WBU - 写回单元
  WBU u_wbu(
    .pc(pc),
    .alu_result(alu_result),
    .mem_rdata(mem_rdata),
    .imm_u(imm_u),
    .jump_target(jump_target),
    .branch_target(branch_target),
    .branch_taken(branch_taken),
    // 加载指令
    .is_lb(is_lb),
    .is_lh(is_lh),
    .is_lw(is_lw),
    .is_lbu(is_lbu),
    .is_lhu(is_lhu),
    // 分支指令
    .is_beq(is_beq),
    .is_bne(is_bne),
    .is_blt(is_blt),
    .is_bge(is_bge),
    .is_bltu(is_bltu),
    .is_bgeu(is_bgeu),
    // U型指令
    .is_lui(is_lui),
    .is_auipc(is_auipc),
    // J型指令
    .is_jal(is_jal),
    .is_jalr(is_jalr),
    // 系统指令
    .is_ebreak(is_ebreak),
    // 输出
    .rd_data(rd_data),
    .pc_next(pc_next)
  );
  
  // ========== ebreak处理和trace ==========
  
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val);
  
  always @(posedge clk) begin
    if (!rst) begin
      // ebreak处理
      if (is_ebreak) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x", pc, a0_value);
        ebreak_handler(a0_value);
      end
      
      // ftrace检测
      if (is_jalr) begin
        // jalr ra, rs1, offset (rd == 1) 是函数调用
        if (rd == 5'd1) begin
          ftrace_call_handler(pc, jump_target);
        end
        // jalr zero, ra, 0 (rd == 0 && rs1 == 1) 是函数返回
        else if (rd == 5'd0 && rs1 == 5'd1) begin
          ftrace_ret_handler(pc);
        end
      end
      
      // jal也可能是函数调用
      if (is_jal && rd == 5'd1) begin
        ftrace_call_handler(pc, branch_target);
      end
      
      // 每个时钟周期更新指令到C++侧
      update_inst_value(pc, inst);
    end
  end

endmodule


