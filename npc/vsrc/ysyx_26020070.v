// ysyx_26020070 - RV32E processor for ysyxSoC
// 符合 ysyxSoC 接口规范的顶层模块
// AXI4 Master 总线连接 ysyxSoC 的 AXI4 Xbar
// 内部包含: IFU, IDU, EXU, LSU, WBU, CSR, RegisterFile, CLINT, AXIArbiter

module ysyx_26020070(
  // ===== ysyxSoC 接口规范 =====
  input         clock,          // 时钟
  input         reset,          // 复位 (高电平有效)
  input         io_interrupt,   // 外部中断 (目前不使用)

  // ===== AXI4 Master 总线 - 连接 ysyxSoC 的 AXI4 Xbar =====
  // AR 通道 (读地址)
  output        io_master_arvalid,
  input         io_master_arready,
  output [31:0] io_master_araddr,
  output [ 3:0] io_master_arid,
  output [ 7:0] io_master_arlen,
  output [ 2:0] io_master_arsize,
  output [ 1:0] io_master_arburst,

  // R 通道 (读数据)
  input         io_master_rvalid,
  output        io_master_rready,
  input  [31:0] io_master_rdata,
  input  [ 1:0] io_master_rresp,
  input         io_master_rlast,
  input  [ 3:0] io_master_rid,

  // AW 通道 (写地址)
  output        io_master_awvalid,
  input         io_master_awready,
  output [31:0] io_master_awaddr,
  output [ 3:0] io_master_awid,
  output [ 7:0] io_master_awlen,
  output [ 2:0] io_master_awsize,
  output [ 1:0] io_master_awburst,

  // W 通道 (写数据)
  output        io_master_wvalid,
  input         io_master_wready,
  output [31:0] io_master_wdata,
  output [ 3:0] io_master_wstrb,
  output        io_master_wlast,

  // B 通道 (写回复)
  input         io_master_bvalid,
  output        io_master_bready,
  input  [ 1:0] io_master_bresp,
  input  [ 3:0] io_master_bid,

  // ===== AXI4 Slave 总线 - 用于调试 (目前不使用，按规范定义端口) =====
  // 注意：Slave接口方向与Master接口镜像相反
  // AW 通道 (写地址)
  output        io_slave_awready,   // slave ready to accept write address
  input         io_slave_awvalid,   // master driving write address
  input  [ 3:0] io_slave_awid,
  input  [31:0] io_slave_awaddr,
  input  [ 7:0] io_slave_awlen,
  input  [ 2:0] io_slave_awsize,
  input  [ 1:0] io_slave_awburst,

  // W 通道 (写数据)
  output        io_slave_wready,    // slave ready to accept write data
  input         io_slave_wvalid,    // master driving write data
  input  [31:0] io_slave_wdata,
  input  [ 3:0] io_slave_wstrb,
  input         io_slave_wlast,

  // B 通道 (写回复)
  input         io_slave_bready,    // master ready to accept response
  output        io_slave_bvalid,    // slave driving response
  output [ 3:0] io_slave_bid,
  output [ 1:0] io_slave_bresp,

  // AR 通道 (读地址)
  output        io_slave_arready,   // slave ready to accept read address
  input         io_slave_arvalid,   // master driving read address
  input  [ 3:0] io_slave_arid,
  input  [31:0] io_slave_araddr,
  input  [ 7:0] io_slave_arlen,
  input  [ 2:0] io_slave_arsize,
  input  [ 1:0] io_slave_arburst,

  // R 通道 (读数据)
  input         io_slave_rready,    // master ready to accept read data
  output        io_slave_rvalid,    // slave driving read data
  output [ 3:0] io_slave_rid,
  output [31:0] io_slave_rdata,
  output [ 1:0] io_slave_rresp,
  output        io_slave_rlast
);

  // ========== 内部信号定义 ==========

  // 复位信号转换 (ysyxSoC高电平复位 -> NPC低电平复位)
  wire rst = reset;

  // ===== AXI4 Slave接口 (不使用，输出赋值为0表示slave未就绪) =====
  // Slave outputs: 表示slave状态
  assign io_slave_awready = 1'b0;   // slave not ready to accept write address
  assign io_slave_wready  = 1'b0;   // slave not ready to accept write data
  assign io_slave_bvalid  = 1'b0;   // slave not driving write response
  assign io_slave_bid     = 4'b0;
  assign io_slave_bresp   = 2'b0;
  assign io_slave_arready = 1'b0;   // slave not ready to accept read address
  assign io_slave_rvalid  = 1'b0;   // slave not driving read data
  assign io_slave_rid     = 4'b0;
  assign io_slave_rdata   = 32'b0;
  assign io_slave_rresp   = 2'b0;
  assign io_slave_rlast   = 1'b0;
  // Slave inputs: 悬空即可（外部master不会访问我们）

  // IFU <-> IDU
  wire [31:0] pc;
  wire [31:0] inst;
  wire ifu_valid;
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
  wire [31:0] a0_value;

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
  wire [31:0] lsu_mem_rdata;

  // WBU输出
  wire [31:0] rd_data;
  wire [31:0] pc_next;
  wire exception_en;
  wire [31:0] exception_pc;
  wire [31:0] exception_cause;
  wire mret_en;

  // ========== Access Fault 异常信号 (跳转地址0) ==========
  wire ifu_access_fault;   // 取指访问异常
  wire lsu_access_fault;   // load/store 访问异常

  // ========== AXI4 总线连接信号 ==========

  // IFU <-> Arbiter (Master 0, 只读)
  wire        ifu_arvalid;
  wire        ifu_arready;
  wire [31:0] ifu_araddr;
  wire [ 3:0] ifu_arid;
  wire [ 7:0] ifu_arlen;
  wire [ 2:0] ifu_arsize;
  wire [ 1:0] ifu_arburst;
  wire        ifu_rvalid;
  wire        ifu_rready;
  wire [31:0] ifu_rdata;
  wire [ 1:0] ifu_rresp;
  wire        ifu_rlast;
  wire [ 3:0] ifu_rid;

  // LSU <-> Arbiter (Master 1, 读写)
  wire        lsu_arvalid;
  wire        lsu_arready;
  wire [31:0] lsu_araddr;
  wire [ 3:0] lsu_arid;
  wire [ 7:0] lsu_arlen;
  wire [ 2:0] lsu_arsize;
  wire [ 1:0] lsu_arburst;
  wire        lsu_rvalid;
  wire        lsu_rready;
  wire [31:0] lsu_rdata;
  wire [ 1:0] lsu_rresp;
  wire        lsu_rlast;
  wire [ 3:0] lsu_rid;
  wire        lsu_awvalid;
  wire        lsu_awready;
  wire [31:0] lsu_awaddr;
  wire [ 3:0] lsu_awid;
  wire [ 7:0] lsu_awlen;
  wire [ 2:0] lsu_awsize;
  wire [ 1:0] lsu_awburst;
  wire        lsu_wvalid;
  wire        lsu_wready;
  wire [31:0] lsu_wdata;
  wire [ 3:0] lsu_wstrb;
  wire        lsu_wlast;
  wire        lsu_bvalid;
  wire        lsu_bready;
  wire [ 1:0] lsu_bresp;
  wire [ 3:0] lsu_bid;

  // Arbiter <-> CLINT (CLINT slave 端口)
  wire        clint_arvalid;
  wire        clint_arready;
  wire [31:0] clint_araddr;
  wire        clint_rvalid;
  wire        clint_rready;
  wire [31:0] clint_rdata;
  wire [ 1:0] clint_rresp;
  wire        clint_awvalid;
  wire        clint_awready;
  wire [31:0] clint_awaddr;
  wire        clint_wvalid;
  wire        clint_wready;
  wire [31:0] clint_wdata;
  wire [ 3:0] clint_wstrb;
  wire        clint_bvalid;
  wire        clint_bready;
  wire [ 1:0] clint_bresp;

  // 访存地址计算
  wire [31:0] mem_addr;
  wire is_store = is_sb || is_sh || is_sw;
  assign mem_addr = is_store ? (rs1_data + imm_s) : (rs1_data + imm_i);
  wire is_load = is_lb || is_lh || is_lw || is_lbu || is_lhu;

  // 写回逻辑
  wire reg_wen_final = (reg_wen && ifu_valid && !is_load) || (load_wb && (load_rd != 5'b0));
  wire [4:0] waddr_final = load_wb ? load_rd : rd;
  wire [31:0] wdata_final = load_wb ? lsu_mem_rdata : rd_data;

  // ========== 模块实例化 ==========

  // IFU - 取指单元
  IFU u_ifu(
    .clk(clock),
    .rst(rst),
    .pc_next(pc_next),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .rd(rd),
    // AXI4 AR 通道
    .ifu_arready(ifu_arready),
    .ifu_arvalid(ifu_arvalid),
    .ifu_araddr(ifu_araddr),
    .ifu_arid(ifu_arid),
    .ifu_arlen(ifu_arlen),
    .ifu_arsize(ifu_arsize),
    .ifu_arburst(ifu_arburst),
    // AXI4 R 通道
    .ifu_rvalid(ifu_rvalid),
    .ifu_rready(ifu_rready),
    .ifu_rdata(ifu_rdata),
    .ifu_rresp(ifu_rresp),
    .ifu_rlast(ifu_rlast),
    .ifu_rid(ifu_rid),
    // LSU 完成信号
    .lsu_rvalid(lsu_rvalid),
    .lsu_bvalid(lsu_bvalid),
    .lsu_access_fault(lsu_access_fault),
    // 输出
    .pc(pc),
    .inst(inst),
    .ifu_valid(ifu_valid),
    .load_wb(load_wb),
    .load_rd(load_rd),
    .ifu_access_fault(ifu_access_fault)
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
    .imm_i(imm_i),
    .imm_s(imm_s),
    .imm_b(imm_b),
    .imm_u(imm_u),
    .imm_j(imm_j),
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
    .is_addi(is_addi),
    .is_slti(is_slti),
    .is_sltiu(is_sltiu),
    .is_xori(is_xori),
    .is_ori(is_ori),
    .is_andi(is_andi),
    .is_slli(is_slli),
    .is_srli(is_srli),
    .is_srai(is_srai),
    .is_lb(is_lb),
    .is_lh(is_lh),
    .is_lw(is_lw),
    .is_lbu(is_lbu),
    .is_lhu(is_lhu),
    .is_sb(is_sb),
    .is_sh(is_sh),
    .is_sw(is_sw),
    .is_beq(is_beq),
    .is_bne(is_bne),
    .is_blt(is_blt),
    .is_bge(is_bge),
    .is_bltu(is_bltu),
    .is_bgeu(is_bgeu),
    .is_lui(is_lui),
    .is_auipc(is_auipc),
    .is_jal(is_jal),
    .is_jalr(is_jalr),
    .is_ebreak(is_ebreak),
    .is_ecall(is_ecall),
    .is_mret(is_mret),
    .is_csrrw(is_csrrw),
    .is_csrrs(is_csrrs),
    .reg_wen(reg_wen),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .csr_wen(csr_wen)
  );

  // RegisterFile - 寄存器堆
  RegisterFile u_regfile(
    .clk(clock),
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
    .is_addi(is_addi),
    .is_slti(is_slti),
    .is_sltiu(is_sltiu),
    .is_xori(is_xori),
    .is_ori(is_ori),
    .is_andi(is_andi),
    .is_slli(is_slli),
    .is_srli(is_srli),
    .is_srai(is_srai),
    .is_beq(is_beq),
    .is_bne(is_bne),
    .is_blt(is_blt),
    .is_bge(is_bge),
    .is_bltu(is_bltu),
    .is_bgeu(is_bgeu),
    .is_jal(is_jal),
    .is_jalr(is_jalr),
    .is_csrrw(is_csrrw),
    .is_csrrs(is_csrrs),
    .csr_rdata(csr_rdata),
    .csr_wdata(csr_wdata),
    .alu_result(alu_result),
    .jump_target(jump_target),
    .branch_target(branch_target),
    .branch_taken(branch_taken)
  );

  // CSR - 控制状态寄存器
  CSR u_csr(
    .clk(clock),
    .rst(rst),
    .csr_addr(imm_i[11:0]),
    .csr_wdata(csr_wdata),
    .csr_wen(csr_wen),
    .csr_rdata(csr_rdata),
    .exception_en(exception_en),
    .exception_pc(exception_pc),
    .exception_cause(exception_cause),
    .mret_en(mret_en),
    .mepc_out(mepc_out),
    .mtvec_out(mtvec_out),
    .mcycle_out(mcycle_out)
  );

  // LSU - 访存单元
  LSU u_lsu(
    .clk(clock),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .funct3(funct3),
    .mem_addr(mem_addr),
    .wdata(rs2_data),
    // AXI4 AR 通道
    .lsu_arvalid(lsu_arvalid),
    .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr),
    .lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize),
    .lsu_arburst(lsu_arburst),
    // AXI4 R 通道
    .lsu_rvalid(lsu_rvalid),
    .lsu_rready(lsu_rready),
    .lsu_rdata(lsu_rdata),
    .lsu_rresp(lsu_rresp),
    .lsu_rlast(lsu_rlast),
    .lsu_rid(lsu_rid),
    // AXI4 AW 通道
    .lsu_awvalid(lsu_awvalid),
    .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr),
    .lsu_awid(lsu_awid),
    .lsu_awlen(lsu_awlen),
    .lsu_awsize(lsu_awsize),
    .lsu_awburst(lsu_awburst),
    // AXI4 W 通道
    .lsu_wvalid(lsu_wvalid),
    .lsu_wready(lsu_wready),
    .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb),
    .lsu_wlast(lsu_wlast),
    // AXI4 B 通道
    .lsu_bvalid(lsu_bvalid),
    .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp),
    .lsu_bid(lsu_bid),
    // 输出
    .rdata(lsu_mem_rdata),
    .lsu_access_fault(lsu_access_fault)
  );

  // AXIArbiter - AXI4 仲裁器 (IFU + LSU → 外部 Xbar)
  AXIArbiter u_arbiter(
    .clk(clock),
    .rst(rst),
    // Master 0: IFU
    .ifu_arvalid(ifu_arvalid),
    .ifu_arready(ifu_arready),
    .ifu_araddr(ifu_araddr),
    .ifu_arid(ifu_arid),
    .ifu_arlen(ifu_arlen),
    .ifu_arsize(ifu_arsize),
    .ifu_arburst(ifu_arburst),
    .ifu_rvalid(ifu_rvalid),
    .ifu_rready(ifu_rready),
    .ifu_rdata(ifu_rdata),
    .ifu_rresp(ifu_rresp),
    .ifu_rlast(ifu_rlast),
    .ifu_rid(ifu_rid),
    // Master 1: LSU
    .lsu_arvalid(lsu_arvalid),
    .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr),
    .lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize),
    .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid),
    .lsu_rready(lsu_rready),
    .lsu_rdata(lsu_rdata),
    .lsu_rresp(lsu_rresp),
    .lsu_rlast(lsu_rlast),
    .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid),
    .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr),
    .lsu_awid(lsu_awid),
    .lsu_awlen(lsu_awlen),
    .lsu_awsize(lsu_awsize),
    .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid),
    .lsu_wready(lsu_wready),
    .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb),
    .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid),
    .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp),
    .lsu_bid(lsu_bid),
    // Slave: 外部 ysyxSoC Xbar
    .mem_arvalid(io_master_arvalid),
    .mem_arready(io_master_arready),
    .mem_araddr(io_master_araddr),
    .mem_arid(io_master_arid),
    .mem_arlen(io_master_arlen),
    .mem_arsize(io_master_arsize),
    .mem_arburst(io_master_arburst),
    .mem_rvalid(io_master_rvalid),
    .mem_rready(io_master_rready),
    .mem_rdata(io_master_rdata),
    .mem_rresp(io_master_rresp),
    .mem_rlast(io_master_rlast),
    .mem_rid(io_master_rid),
    .mem_awvalid(io_master_awvalid),
    .mem_awready(io_master_awready),
    .mem_awaddr(io_master_awaddr),
    .mem_awid(io_master_awid),
    .mem_awlen(io_master_awlen),
    .mem_awsize(io_master_awsize),
    .mem_awburst(io_master_awburst),
    .mem_wvalid(io_master_wvalid),
    .mem_wready(io_master_wready),
    .mem_wdata(io_master_wdata),
    .mem_wstrb(io_master_wstrb),
    .mem_wlast(io_master_wlast),
    .mem_bvalid(io_master_bvalid),
    .mem_bready(io_master_bready),
    .mem_bresp(io_master_bresp),
    .mem_bid(io_master_bid)
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
    .is_lb(is_lb),
    .is_lh(is_lh),
    .is_lw(is_lw),
    .is_lbu(is_lbu),
    .is_lhu(is_lhu),
    .is_beq(is_beq),
    .is_bne(is_bne),
    .is_blt(is_blt),
    .is_bge(is_bge),
    .is_bltu(is_bltu),
    .is_bgeu(is_bgeu),
    .is_lui(is_lui),
    .is_auipc(is_auipc),
    .is_jal(is_jal),
    .is_jalr(is_jalr),
    .is_ebreak(is_ebreak),
    .is_ecall(is_ecall),
    .is_mret(is_mret),
    .is_csrrw(is_csrrw),
    .is_csrrs(is_csrrs),
    .csr_rdata(csr_rdata),
    .mtvec(mtvec_out),
    .mepc(mepc_out),
    .exception_en(exception_en),
    .exception_pc(exception_pc),
    .exception_cause(exception_cause),
    .mret_en(mret_en),
    .rd_data(rd_data),
    .pc_next(pc_next)
  );

  // ========== ebreak处理和trace ==========

  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void access_fault_handler(input int pc_val, input int is_store);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val, input int target_val);
  import "DPI-C" function void difftest_skip_ref();

  // Access Fault: 取指或访存返回 AXI resp 错误时, 跳转地址0
  // 通过 DPI 通知 C++ 仿真环境 (打印告警/可选停止), 避免错过错误事件
  reg prev_access_fault;
  wire access_fault = ifu_access_fault | lsu_access_fault;
  always @(posedge clock) begin
    if (rst) prev_access_fault <= 1'b0;
    else     prev_access_fault <= access_fault;
  end
  always @(posedge clock) begin
    if (!rst && access_fault && !prev_access_fault) begin
      $display("ACCESS FAULT detected at PC=0x%08x, is_store=%0d, mcycle=%0d", pc, mem_wen, mcycle_out);
      access_fault_handler(pc, {31'b0, mem_wen});
    end
  end

  // ========== DiffTest skip 检测 ==========
  wire is_uart_access = mem_valid && (mem_addr[31:12] == 20'h10000);
  always @(posedge clock) begin
    if (!rst && ifu_valid && is_uart_access) begin
      difftest_skip_ref();
    end
  end

  always @(posedge clock) begin
    if (!rst && ifu_valid) begin
      // ebreak处理
      if (is_ebreak) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x, mcycle=%0d", pc, a0_value, mcycle_out);
        ebreak_handler(a0_value);
      end

      // ftrace检测
      if (is_jalr) begin
        if (rd == 5'd1) begin
          ftrace_call_handler(pc, jump_target);
        end
        else if (rd == 5'd0 && rs1 == 5'd1) begin
          ftrace_ret_handler(pc, jump_target);
        end
      end

      if (is_jal && rd == 5'd1) begin
        ftrace_call_handler(pc, branch_target);
      end
    end
  end

endmodule