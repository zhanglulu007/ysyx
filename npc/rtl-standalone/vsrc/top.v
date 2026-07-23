module top(
  input clk,
  input rst,
  input [31:0] imem_rdata,

  output [31:0] pc,
  output [31:0] inst
);

  // ========== 模块间连接信号 ==========
  

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
  wire is_ecall, is_mret, is_fencei, icache_flush;
  wire is_csrrw, is_csrrs, csr_wen;
  wire is_csr = is_csrrw || is_csrrs;
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
  wire [31:0] mem_addr; // LSU计算的访存地址
  wire [31:0] mem_wdata;
  wire [7:0] mem_wmask;
  wire [31:0] addr = op_store ? (rs1_data + imm_s) : (rs1_data + imm_i);
  wire [31:0] rdata; 

  wire op_r_type;
  wire op_load;
  wire op_branch;
  wire op_store;
  wire is_jump;
  wire [31:0] mepc, mtvec, csr_rdata;
  wire [31:0] csr_wdata = is_csrrw ? rs1_data : (rs1_data | csr_rdata); 

  // ========== 模块实例化 ==========
  
  // IFU - 取指单元
  IFU u_ifu(
    .clk(clk),
    .rst(rst),
    .pc_next(pc_next),
    .imem_rdata(imem_rdata),
    .pc(pc),
    .inst(inst)
  );
  
  // IDU - 译码单元
  IDU u_idu(
    .inst(inst),
    .ifu_valid(!rst),
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
    .is_ecall(is_ecall),
    .is_mret(is_mret),
    .is_fencei(is_fencei),
    .icache_flush(icache_flush),
    .is_csrrw(is_csrrw),
    .is_csrrs(is_csrrs),
    // 控制信号
    .reg_wen(reg_wen),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .csr_wen(csr_wen),

    .op_r_type(op_r_type),
    .op_load(op_load),
    .op_store(op_store),
    .op_branch(op_branch),
    .is_jump(is_jump)
  );
  
  // RegisterFile - 寄存器堆
  RegisterFile u_regfile(
    .clk(clk),
    .rst(rst),
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
    .imm_s(imm_s),
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
    .op_r_type(op_r_type),
    .op_load(op_load),
    .op_store(op_store),
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
    .mem_rdata(mem_rdata),
    .addr(addr), 
    .wdata(rs2_data),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wmask(mem_wmask),
    .rdata(rdata)
  );

`ifndef SYNTHESIS
  PMEM u_pmem(
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wmask(mem_wmask),
    .mem_rdata(mem_rdata)
  );
`endif

  // CSR - 控制状态寄存器
  CSR u_csr(
    .clk(clk),
    .rst(rst),
    .csr_addr(imm_i[11:0]),
    .csr_wdata(csr_wdata),
    .csr_wen(csr_wen),
    .csr_rdata(csr_rdata),
    .is_ecall(is_ecall),
    .pc(pc),
    .mret_en(is_mret),
    .mepc(mepc),
    .mtvec(mtvec)
  );

  // WBU - 写回单元
  WBU u_wbu(
    .pc(pc),
    .alu_result(alu_result),
    .rdata(rdata),
    .imm_u(imm_u),
    .jump_target(jump_target),
    .branch_target(branch_target),
    .branch_taken(branch_taken),
    .csr_rdata(csr_rdata),
    .mepc(mepc),
    .mtvec(mtvec),
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
    .is_ecall(is_ecall),
    .is_mret(is_mret),
    .is_csr(is_csr),
    .op_load(op_load),
    .is_jump(is_jump),
    // 输出
    .rd_data(rd_data),
    .pc_next(pc_next)
  );
  
  // ========== ebreak处理和trace ==========
  
`ifndef SYNTHESIS
  import "DPI-C" function void ebreak_handler(input int a0_value);
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
      
    end
  end
`endif

endmodule
