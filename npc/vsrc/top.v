// NPC - minirv processor (Modular Design)
// 模块化设计：将处理器拆分为IFU、IDU、EXU、LSU、WBU等模块

module top(
  input clk,
  input rst
);

  // ========== 模块间连接信号 ==========
  
  // IFU <-> IDU
  wire [31:0] pc;
  wire [31:0] inst;
  
  // IDU输出
  wire [6:0] opcode;
  wire [4:0] rd, rs1, rs2;
  wire [2:0] funct3;
  wire [6:0] funct7;
  wire [31:0] imm_i, imm_s, imm_u;
  wire is_addi, is_jalr, is_ebreak, is_lui, is_add;
  wire is_lw, is_lbu, is_sw, is_sb;
  wire reg_wen, mem_valid, mem_wen;
  
  // RegisterFile输出
  wire [31:0] rs1_data, rs2_data;
  wire [31:0] a0_value;  // a0寄存器的值
  
  // EXU输出
  wire [31:0] alu_result;
  wire [31:0] jump_target;
  
  // LSU输出
  wire [31:0] mem_rdata;
  
  // WBU输出
  wire [31:0] rd_data;
  wire [31:0] pc_next;
  
  // 访存地址计算
  wire [31:0] mem_addr;
  assign mem_addr = (is_sw || is_sb) ? (rs1_data + imm_s) : (rs1_data + imm_i);
  
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
    .imm_i(imm_i),
    .imm_s(imm_s),
    .imm_u(imm_u),
    .is_addi(is_addi),
    .is_jalr(is_jalr),
    .is_ebreak(is_ebreak),
    .is_lui(is_lui),
    .is_add(is_add),
    .is_lw(is_lw),
    .is_lbu(is_lbu),
    .is_sw(is_sw),
    .is_sb(is_sb),
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
    .pc(pc),
    .is_add(is_add),
    .is_jalr(is_jalr),
    .alu_result(alu_result),
    .jump_target(jump_target)
  );
  
  // LSU - 访存单元
  LSU u_lsu(
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .is_lw(is_lw),
    .is_lbu(is_lbu),
    .is_sw(is_sw),
    .is_sb(is_sb),
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
    .is_jalr(is_jalr),
    .is_lui(is_lui),
    .is_lw(is_lw),
    .is_lbu(is_lbu),
    .is_ebreak(is_ebreak),
    .rd_data(rd_data),
    .pc_next(pc_next)
  );
  
  // ========== ebreak处理 ==========
  
  import "DPI-C" function void ebreak_handler(input int a0_value);
  
  always @(posedge clk) begin
    if (!rst && is_ebreak) begin
      $display("EBREAK detected at PC=0x%08x, a0=0x%08x", pc, a0_value);
      ebreak_handler(a0_value);
    end
  end

endmodule


