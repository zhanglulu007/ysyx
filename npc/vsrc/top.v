// NPC - RV32E processor (Modular Design)
// 模块化设计：将处理器拆分为IFU、IDU、EXU、LSU、WBU等模块
// SimpleBus 协议: 支持完整握手信号 reqValid/reqReady + respValid/respReady
// 两状态状态机: IDLE / WAIT
// 多周期设计: 非访存指令 2+ 周期, load/store 3+ 周期

module top(
  input clk,
  input rst,
  output ifu_valid_out
);

  // ========== 模块间连接信号 ==========

  // IFU <-> IDU
  wire [31:0] pc;
  wire [31:0] inst;
  wire ifu_valid;
  assign ifu_valid_out = ifu_valid;
  wire ifu_reqValid;
  wire ifu_respValid;
  wire load_wb;
  wire [4:0] load_rd;

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
  wire is_ebreak, is_ecall, is_mret;

  // IDU输出 - CSR指令
  wire is_csrrw, is_csrrs;

  // IDU输出 - 控制信号
  wire reg_wen, mem_valid, mem_wen, csr_wen;

  // RegisterFile输出
  wire [31:0] rs1_data, rs2_data;
  wire [31:0] a0_value;  // a0寄存器的值

  // EXU输出
  wire [31:0] alu_result;
  wire [31:0] jump_target;
  wire [31:0] branch_target;
  wire branch_taken;
  wire [31:0] csr_wdata;

  // CSR输出
  wire [31:0] csr_rdata;
  wire [31:0] mepc_out;
  wire [31:0] mtvec_out;
  wire [63:0] mcycle_out;

  // LSU输出
  wire [31:0] mem_rdata;
  wire lsu_reqValid;
  wire lsu_respValid;

  // SimpleBus 连接信号 (完整握手)
  wire [31:0] ifu_raddr;       // IFU -> MEM
  wire [31:0] ifu_rdata;       // MEM -> IFU
  wire        ifu_reqReady;    // MEM -> IFU: 从设备就绪
  wire        ifu_respReady;   // IFU -> MEM: 主设备就绪
  wire [31:0] lsu_addr;        // LSU -> MEM
  wire        lsu_wen;         // LSU -> MEM
  wire [31:0] lsu_wdata;       // LSU -> MEM
  wire [ 3:0] lsu_wmask;       // LSU -> MEM
  wire [31:0] lsu_rdata;       // MEM -> LSU
  wire        lsu_reqReady;    // MEM -> LSU: 从设备就绪
  wire        lsu_respReady;   // LSU -> MEM: 主设备就绪

  // WBU输出
  wire [31:0] rd_data;
  wire [31:0] pc_next;
  wire exception_en;
  wire [31:0] exception_pc;
  wire [31:0] exception_cause;
  wire mret_en;

  // 访存地址计算 (组合逻辑)
  wire [31:0] mem_addr;
  wire is_store = is_sb || is_sh || is_sw;
  assign mem_addr = is_store ? (rs1_data + imm_s) : (rs1_data + imm_i);

  wire is_load;
  assign is_load = is_lb || is_lh || is_lw || is_lbu || is_lhu;

  // ========== 写回逻辑 ==========
  // 非 load 指令: ifu_valid 周期正常写回
  // load 指令:   load_wb 周期写回 (LSU 数据返回后)
  //   注意: load 在 ifu_valid 周期译码时 reg_wen=1,
  //   但数据尚未返回, 需抑制本次写回, 等 load_wb 再写回
  wire reg_wen_final = (reg_wen && ifu_valid && !is_load) || (load_wb && (load_rd != 5'b0));
  wire [4:0] waddr_final = load_wb ? load_rd : rd;
  wire [31:0] wdata_final = load_wb ? mem_rdata : rd_data;

  // ========== 模块实例化 ==========

  // IFU - 取指单元 (两状态状态机: IDLE/WAIT, 完整握手)
  IFU u_ifu(
    .clk(clk),
    .rst(rst),
    .pc_next(pc_next),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .rd(rd),
    .ifu_reqReady(ifu_reqReady),
    .ifu_respValid(ifu_respValid),
    .ifu_respReady(ifu_respReady),
    .lsu_respValid(lsu_respValid),
    .ifu_rdata(ifu_rdata),
    .pc(pc),
    .ifu_reqValid(ifu_reqValid),
    .ifu_raddr(ifu_raddr),
    .inst(inst),
    .ifu_valid(ifu_valid),
    .load_wb(load_wb),
    .load_rd(load_rd)
  );

  // IDU - 译码单元
  IDU u_idu(
    .inst(inst),
    .ifu_valid(ifu_valid),
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
    // CSR指令
    .is_csrrw(is_csrrw),
    .is_csrrs(is_csrrs),
    // 控制信号
    .reg_wen(reg_wen),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .csr_wen(csr_wen)
  );

  // RegisterFile - 寄存器堆
  RegisterFile u_regfile(
    .clk(clk),
    .waddr(waddr_final),
    .wdata(wdata_final),
    .wen(reg_wen_final),
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
    // CSR指令
    .is_csrrw(is_csrrw),
    .is_csrrs(is_csrrs),
    .csr_rdata(csr_rdata),
    .csr_wdata(csr_wdata),
    // 输出
    .alu_result(alu_result),
    .jump_target(jump_target),
    .branch_target(branch_target),
    .branch_taken(branch_taken)
  );

  // CSR - 控制状态寄存器
  CSR u_csr(
    .clk(clk),
    .rst(rst),
    // CSR读写接口
    .csr_addr(imm_i[11:0]),  // CSR地址来自I型立即数的低12位
    .csr_wdata(csr_wdata),
    .csr_wen(csr_wen),
    .csr_rdata(csr_rdata),
    // 异常处理接口
    .exception_en(exception_en),
    .exception_pc(exception_pc),
    .exception_cause(exception_cause),
    // mret指令接口
    .mret_en(mret_en),
    .mepc_out(mepc_out),
    .mtvec_out(mtvec_out),
    .mcycle_out(mcycle_out)
  );

  // LSU - 访存单元
  LSU u_lsu(
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .funct3(funct3),
    .mem_addr(mem_addr),
    .wdata(rs2_data),
    // SimpleBus (连接 MEM, 完整握手)
    .lsu_reqValid(lsu_reqValid),
    .lsu_reqReady(lsu_reqReady),
    .lsu_addr(lsu_addr),
    .lsu_wen(lsu_wen),
    .lsu_wdata(lsu_wdata),
    .lsu_wmask(lsu_wmask),
    .lsu_respValid(lsu_respValid),
    .lsu_respReady(lsu_respReady),
    .lsu_rdata(lsu_rdata),
    // 输出
    .rdata(mem_rdata)
  );

  // MEM - 存储器模块 (内部通过 DPI-C 实现, 对外呈现 SimpleBus 完整握手接口)
  MEM u_mem(
    .clk(clk),
    .rst(rst),
    // IFU SimpleBus (完整握手)
    .ifu_reqValid(ifu_reqValid),
    .ifu_reqReady(ifu_reqReady),
    .ifu_respValid(ifu_respValid),
    .ifu_respReady(ifu_respReady),
    .ifu_raddr(ifu_raddr),
    .ifu_rdata(ifu_rdata),
    // LSU SimpleBus (完整握手)
    .lsu_reqValid(lsu_reqValid),
    .lsu_reqReady(lsu_reqReady),
    .lsu_respValid(lsu_respValid),
    .lsu_respReady(lsu_respReady),
    .lsu_addr(lsu_addr),
    .lsu_wen(lsu_wen),
    .lsu_wdata(lsu_wdata),
    .lsu_wmask(lsu_wmask),
    .lsu_rdata(lsu_rdata)
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
    .is_ecall(is_ecall),
    .is_mret(is_mret),
    // CSR指令
    .is_csrrw(is_csrrw),
    .is_csrrs(is_csrrs),
    .csr_rdata(csr_rdata),
    // 异常处理
    .mtvec(mtvec_out),
    .mepc(mepc_out),
    .exception_en(exception_en),
    .exception_pc(exception_pc),
    .exception_cause(exception_cause),
    .mret_en(mret_en),
    // 输出
    .rd_data(rd_data),
    .pc_next(pc_next)
  );

  // ========== ebreak处理和trace ==========

  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val, input int target_val);

  always @(posedge clk) begin
    if (!rst && ifu_valid) begin
      // ebreak处理
      if (is_ebreak) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x, mcycle=%0d", pc, a0_value, mcycle_out);
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
          ftrace_ret_handler(pc, jump_target);
        end
      end

      // jal也可能是函数调用
      if (is_jal && rd == 5'd1) begin
        ftrace_call_handler(pc, branch_target);
      end
    end
  end

endmodule
