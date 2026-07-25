// NPC - RV32E processor (Modular Design)
// 模块化设计：将处理器拆分为IFU、IDU、EXU、LSU、WBU等模块
// AXI4-Lite 总线协议: IFU+LSU → AXIArbiter → 外部存储器接口
// 综合范围仅包含 CPU 和 AXIArbiter
// 多周期设计: 非访存指令 2+ 周期, load/store 3+ 周期

module RTLOld_Synth(
  input clk,
  input rst,
  output insdone_out,

  // AXI4-Lite AR
  output mem_arvalid,
  input mem_arready,
  output [31:0] mem_araddr,

  // AXI4-Lite R
  input mem_rvalid,
  output mem_rready,
  input [31:0] mem_rdata,
  input [1:0] mem_rresp,

  // AXI4-Lite AW
  output mem_awvalid,
  input mem_awready,
  output [31:0] mem_awaddr,

  // AXI4-Lite W
  output mem_wvalid,
  input mem_wready,
  output [31:0] mem_wdata,
  output [3:0] mem_wstrb,

  // AXI4-Lite B
  input mem_bvalid,
  output mem_bready,
  input [1:0] mem_bresp
);

  // ========== 模块间连接信号 ==========

  // IFU <-> IDU
  wire [31:0] pc;
  wire [31:0] inst;
  wire ifu_valid;
  wire insdone;
  assign insdone_out = insdone;
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

  // LSU输出 (经字节/半字选择后的读数据, 送往 WBU)
  wire [31:0] lsu_mem_rdata;

  // WBU输出
  wire [31:0] rd_data;
  wire [31:0] pc_next;
  wire exception_en;
  wire [31:0] exception_pc;
  wire [31:0] exception_cause;
  wire mret_en;

  // ===================================================================
  // AXI4-Lite 总线连接信号 (IFU/LSU → Arbiter)
  // ===================================================================

  // --- IFU <-> Arbiter (Master 0, 只读: AR + R) ---
  wire        ifu_arvalid;
  wire        ifu_arready;
  wire [31:0] ifu_araddr;
  wire        ifu_rvalid;
  wire        ifu_rready;
  wire [31:0] ifu_rdata;
  wire [ 1:0] ifu_rresp;

  // --- LSU <-> Arbiter (Master 1, 读写: 全部 5 通道) ---
  // AR
  wire        lsu_arvalid;
  wire        lsu_arready;
  wire [31:0] lsu_araddr;
  // R
  wire        lsu_rvalid;
  wire        lsu_rready;
  wire [31:0] lsu_rdata;
  wire [ 1:0] lsu_rresp;
  // AW
  wire        lsu_awvalid;
  wire        lsu_awready;
  wire [31:0] lsu_awaddr;
  // W
  wire        lsu_wvalid;
  wire        lsu_wready;
  wire [31:0] lsu_wdata;
  wire [ 3:0] lsu_wstrb;
  // B
  wire        lsu_bvalid;
  wire        lsu_bready;
  wire [ 1:0] lsu_bresp;

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
  wire [31:0] wdata_final = load_wb ? lsu_mem_rdata : rd_data;

  // ========== 模块实例化 ==========

  // IFU - 取指单元 (AXI4-Lite: AR + R 通道)
  IFU u_ifu(
    .clk(clk),
    .rst(rst),
    .pc_next(pc_next),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .rd(rd),
    // AXI4-Lite AR 通道 (连接 Arbiter)
    .ifu_arready(ifu_arready),
    .ifu_arvalid(ifu_arvalid),
    .ifu_araddr(ifu_araddr),
    // AXI4-Lite R 通道 (连接 Arbiter)
    .ifu_rvalid(ifu_rvalid),
    .ifu_rready(ifu_rready),
    .ifu_rdata(ifu_rdata),
    .ifu_rresp(ifu_rresp),
    // LSU 完成信号 (来自 Arbiter 的 LSU 侧, 用于 load/store 完成检测)
    .lsu_rvalid(lsu_rvalid),
    .lsu_bvalid(lsu_bvalid),
    // 输出
    .pc(pc),
    .inst(inst),
    .ifu_valid(ifu_valid),
    .load_wb(load_wb),
    .load_rd(load_rd),
    .insdone(insdone)
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

  // LSU - 访存单元 (AXI4-Lite: 全部 5 通道, 连接 Arbiter)
  LSU u_lsu(
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .funct3(funct3),
    .mem_addr(mem_addr),
    .wdata(rs2_data),
    // AXI4-Lite AR 通道 (连接 Arbiter)
    .lsu_arvalid(lsu_arvalid),
    .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr),
    // AXI4-Lite R 通道 (连接 Arbiter)
    .lsu_rvalid(lsu_rvalid),
    .lsu_rready(lsu_rready),
    .lsu_rdata(lsu_rdata),
    .lsu_rresp(lsu_rresp),
    // AXI4-Lite AW 通道 (连接 Arbiter)
    .lsu_awvalid(lsu_awvalid),
    .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr),
    // AXI4-Lite W 通道 (连接 Arbiter)
    .lsu_wvalid(lsu_wvalid),
    .lsu_wready(lsu_wready),
    .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb),
    // AXI4-Lite B 通道 (连接 Arbiter)
    .lsu_bvalid(lsu_bvalid),
    .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp),
    // 输出
    .rdata(lsu_mem_rdata)
  );

  // AXIArbiter - AXI4-Lite 仲裁器 (IFU + LSU → 外部存储器)
  AXIArbiter u_arbiter(
    .clk(clk),
    .rst(rst),
    // Master 0: IFU (只读)
    .ifu_arvalid(ifu_arvalid),
    .ifu_arready(ifu_arready),
    .ifu_araddr(ifu_araddr),
    .ifu_rvalid(ifu_rvalid),
    .ifu_rready(ifu_rready),
    .ifu_rdata(ifu_rdata),
    .ifu_rresp(ifu_rresp),
    // Master 1: LSU (读写)
    .lsu_arvalid(lsu_arvalid),
    .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr),
    .lsu_rvalid(lsu_rvalid),
    .lsu_rready(lsu_rready),
    .lsu_rdata(lsu_rdata),
    .lsu_rresp(lsu_rresp),
    .lsu_awvalid(lsu_awvalid),
    .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr),
    .lsu_wvalid(lsu_wvalid),
    .lsu_wready(lsu_wready),
    .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb),
    .lsu_bvalid(lsu_bvalid),
    .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp),
    // Slave: 外部存储器
    .mem_arvalid(mem_arvalid),
    .mem_arready(mem_arready),
    .mem_araddr(mem_araddr),
    .mem_rvalid(mem_rvalid),
    .mem_rready(mem_rready),
    .mem_rdata(mem_rdata),
    .mem_rresp(mem_rresp),
    .mem_awvalid(mem_awvalid),
    .mem_awready(mem_awready),
    .mem_awaddr(mem_awaddr),
    .mem_wvalid(mem_wvalid),
    .mem_wready(mem_wready),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_bvalid(mem_bvalid),
    .mem_bready(mem_bready),
    .mem_bresp(mem_bresp)
  );

  // WBU - 写回单元
  WBU u_wbu(
    .pc(pc),
    .alu_result(alu_result),
    .mem_rdata(lsu_mem_rdata),
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

endmodule
