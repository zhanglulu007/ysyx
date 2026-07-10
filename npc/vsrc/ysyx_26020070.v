// ysyx_26020070 - RV32E 五级流水线处理器 for ysyxSoC
// 流水级: IF(取指) → ID(译码/读RF) → EX(执行/算地址) → LS(访存) → WB(写回)
// 冒险: RAW阻塞(ID阶段检测), 控制冒险(预测不跳转+冲刷), fence.i冲刷
// 符合 ysyxSoC 接口规范

module ysyx_26020070(
  input         clock,
  input         reset,
  input         io_interrupt,

  // ===== AXI4 Master 总线 =====
  output        io_master_arvalid,
  input         io_master_arready,
  output [31:0] io_master_araddr,
  output [ 3:0] io_master_arid,
  output [ 7:0] io_master_arlen,
  output [ 2:0] io_master_arsize,
  output [ 1:0] io_master_arburst,

  input         io_master_rvalid,
  output        io_master_rready,
  input  [31:0] io_master_rdata,
  input  [ 1:0] io_master_rresp,
  input         io_master_rlast,
  input  [ 3:0] io_master_rid,

  output        io_master_awvalid,
  input         io_master_awready,
  output [31:0] io_master_awaddr,
  output [ 3:0] io_master_awid,
  output [ 7:0] io_master_awlen,
  output [ 2:0] io_master_awsize,
  output [ 1:0] io_master_awburst,

  output        io_master_wvalid,
  input         io_master_wready,
  output [31:0] io_master_wdata,
  output [ 3:0] io_master_wstrb,
  output        io_master_wlast,

  input         io_master_bvalid,
  output        io_master_bready,
  input  [ 1:0] io_master_bresp,
  input  [ 3:0] io_master_bid,

  // ===== AXI4 Slave 总线 (不使用) =====
  output        io_slave_awready,
  input         io_slave_awvalid,
  input  [ 3:0] io_slave_awid,
  input  [31:0] io_slave_awaddr,
  input  [ 7:0] io_slave_awlen,
  input  [ 2:0] io_slave_awsize,
  input  [ 1:0] io_slave_awburst,

  output        io_slave_wready,
  input         io_slave_wvalid,
  input  [31:0] io_slave_wdata,
  input  [ 3:0] io_slave_wstrb,
  input         io_slave_wlast,

  input         io_slave_bready,
  output        io_slave_bvalid,
  output [ 3:0] io_slave_bid,
  output [ 1:0] io_slave_bresp,

  output        io_slave_arready,
  input         io_slave_arvalid,
  input  [ 3:0] io_slave_arid,
  input  [31:0] io_slave_araddr,
  input  [ 7:0] io_slave_arlen,
  input  [ 2:0] io_slave_arsize,
  input  [ 1:0] io_slave_arburst,

  input         io_slave_rready,
  output        io_slave_rvalid,
  output [ 3:0] io_slave_rid,
  output [31:0] io_slave_rdata,
  output [ 1:0] io_slave_rresp,
  output        io_slave_rlast
);

  // ========== Slave (未使用) ==========
  assign io_slave_awready = 1'b0;
  assign io_slave_wready  = 1'b0;
  assign io_slave_bvalid  = 1'b0;
  assign io_slave_bid     = 4'b0;
  assign io_slave_bresp   = 2'b0;
  assign io_slave_arready = 1'b0;
  assign io_slave_rvalid  = 1'b0;
  assign io_slave_rid     = 4'b0;
  assign io_slave_rdata   = 32'b0;
  assign io_slave_rresp   = 2'b0;
  assign io_slave_rlast   = 1'b0;

  wire rst = reset;

  // ====================================================================
  //  流水线控制信号
  // ====================================================================
  reg  stall_F, stall_D;
  reg  flush_F, flush_D;
  reg  [31:0] redirect_pc;

  // ====================================================================
  //  IF 阶段: 简化取指 (连续取, 遇阻塞则暂停)
  // ====================================================================
  reg  [31:0] if_pc;
  reg         if_state;  // 0=IDLE, 1=WAIT
  localparam F_IDLE = 1'b0, F_WAIT = 1'b1;

  // IFU <-> ICache AXI 信号
  wire        ifu_arvalid = (if_state == F_IDLE) && !rst && !flush_F;
  wire [31:0] ifu_araddr  = if_pc;
  wire [ 3:0] ifu_arid    = 4'd0;
  wire [ 7:0] ifu_arlen   = 8'd0;
  wire [ 2:0] ifu_arsize  = 3'b010;
  wire [ 1:0] ifu_arburst = 2'b01;
  wire        ifu_rready  = (if_state == F_WAIT) && !rst && !stall_F;
  wire        ifu_arready, ifu_rvalid;
  wire [31:0] ifu_rdata;
  wire [ 1:0] ifu_rresp;
  wire        ifu_rlast;
  wire [ 3:0] ifu_rid;

  wire if_valid = (if_state == F_WAIT) && ifu_rvalid && ifu_rready && !rst;
  wire [31:0] if_inst = if_valid ? ifu_rdata : 32'h00000013;

  wire [31:0] if_pc_next_default = if_pc + 32'd4;

  always @(posedge clock) begin
    if (rst) begin
      if_state <= F_IDLE;
`ifdef SOC_MODE
      if_pc <= 32'h30000000;
`else
      if_pc <= 32'h80000000;
`endif
    end else if (flush_F) begin
      if_state <= F_IDLE;
      if_pc    <= redirect_pc;
    end else if (!stall_F) begin
      case (if_state)
        F_IDLE: if (ifu_arready) if_state <= F_WAIT;
        F_WAIT: if (ifu_rvalid && ifu_rready) begin
          if_pc    <= if_pc_next_default;
          if_state <= F_IDLE;
        end
      endcase
    end
  end

  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);
  always @(posedge clock) begin
    if (!rst && if_valid && !stall_F) begin
      update_inst_value(if_pc, ifu_rdata);
      update_pc_value(if_pc_next_default);
    end
    if (rst) begin
`ifdef SOC_MODE
      update_pc_value(32'h30000000);
`else
      update_pc_value(32'h80000000);
`endif
    end else if (flush_F) begin
      update_pc_value(redirect_pc);
    end
  end
`endif

  // ====================================================================
  //  IF/ID 流水线寄存器
  // ====================================================================
  reg         id_valid;
  reg  [31:0] id_pc, id_inst;

  always @(posedge clock) begin
    if (rst || flush_D) begin
      id_valid <= 1'b0;
    end else if (!stall_D) begin
      id_valid <= if_valid;
      if (if_valid) begin
        id_pc   <= if_pc;
        id_inst <= if_inst;
      end
    end
  end

  // ====================================================================
  //  ID 阶段: 译码 + 读寄存器 + RAW检测
  // ====================================================================

  // ---------- IDU ----------
  wire [6:0] id_opcode;   wire [4:0] id_rd, id_rs1, id_rs2;
  wire [2:0] id_funct3;   wire [6:0] id_funct7;
  wire [31:0] id_imm_i, id_imm_s, id_imm_b, id_imm_u, id_imm_j;
  wire id_is_add,id_is_sub,id_is_and,id_is_or,id_is_xor,id_is_sll,id_is_srl,id_is_sra,id_is_slt,id_is_sltu;
  wire id_is_addi,id_is_slti,id_is_sltiu,id_is_xori,id_is_ori,id_is_andi,id_is_slli,id_is_srli,id_is_srai;
  wire id_is_lb,id_is_lh,id_is_lw,id_is_lbu,id_is_lhu;
  wire id_is_sb,id_is_sh,id_is_sw;
  wire id_is_beq,id_is_bne,id_is_blt,id_is_bge,id_is_bltu,id_is_bgeu;
  wire id_is_lui,id_is_auipc,id_is_jal,id_is_jalr;
  wire id_is_ebreak,id_is_ecall,id_is_mret,id_is_fencei;
  wire id_is_csrrw,id_is_csrrs;
  wire id_reg_wen, id_mem_valid, id_mem_wen, id_csr_wen, id_icache_flush;

  IDU u_idu(
    .inst(id_inst), .ifu_valid(id_valid),
    .opcode(id_opcode), .rd(id_rd), .rs1(id_rs1), .rs2(id_rs2),
    .funct3(id_funct3), .funct7(id_funct7),
    .imm_i(id_imm_i), .imm_s(id_imm_s), .imm_b(id_imm_b), .imm_u(id_imm_u), .imm_j(id_imm_j),
    .is_add(id_is_add), .is_sub(id_is_sub), .is_and(id_is_and), .is_or(id_is_or),
    .is_xor(id_is_xor), .is_sll(id_is_sll), .is_srl(id_is_srl), .is_sra(id_is_sra),
    .is_slt(id_is_slt), .is_sltu(id_is_sltu),
    .is_addi(id_is_addi), .is_slti(id_is_slti), .is_sltiu(id_is_sltiu),
    .is_xori(id_is_xori), .is_ori(id_is_ori), .is_andi(id_is_andi),
    .is_slli(id_is_slli), .is_srli(id_is_srli), .is_srai(id_is_srai),
    .is_lb(id_is_lb), .is_lh(id_is_lh), .is_lw(id_is_lw), .is_lbu(id_is_lbu), .is_lhu(id_is_lhu),
    .is_sb(id_is_sb), .is_sh(id_is_sh), .is_sw(id_is_sw),
    .is_beq(id_is_beq), .is_bne(id_is_bne), .is_blt(id_is_blt), .is_bge(id_is_bge),
    .is_bltu(id_is_bltu), .is_bgeu(id_is_bgeu),
    .is_lui(id_is_lui), .is_auipc(id_is_auipc), .is_jal(id_is_jal), .is_jalr(id_is_jalr),
    .is_ebreak(id_is_ebreak), .is_ecall(id_is_ecall), .is_mret(id_is_mret), .is_fencei(id_is_fencei),
    .icache_flush(id_icache_flush),
    .is_csrrw(id_is_csrrw), .is_csrrs(id_is_csrrs),
    .reg_wen(id_reg_wen), .mem_valid(id_mem_valid), .mem_wen(id_mem_wen), .csr_wen(id_csr_wen)
  );

  // ---------- RegisterFile (读口ID, 写口WB) ----------
  wire [31:0] rf_rs1_data, rf_rs2_data, rf_a0_value;

  RegisterFile u_regfile(
    .clk(clock),
    .waddr(wb_waddr), .wdata(wb_wdata), .wen(wb_wen),
    .raddr1(id_rs1), .rdata1(rf_rs1_data),
    .raddr2(id_rs2), .rdata2(rf_rs2_data),
    .a0_value(rf_a0_value)
  );

  // ---------- RAW 冒险检测 ----------
  // 核对ID阶段的rs1/rs2与后面各阶段的rd
  wire raw_rs1_ex = ex_valid && ex_reg_wen_f && (ex_rd_f != 5'd0) && (ex_rd_f == id_rs1);
  wire raw_rs2_ex = ex_valid && ex_reg_wen_f && (ex_rd_f != 5'd0) && (ex_rd_f == id_rs2);
  wire raw_rs1_ls = ls_valid && ls_reg_wen_f && (ls_rd_f != 5'd0) && (ls_rd_f == id_rs1);
  wire raw_rs2_ls = ls_valid && ls_reg_wen_f && (ls_rd_f != 5'd0) && (ls_rd_f == id_rs2);
  // WB阶段不需要阻塞: 寄存器堆写优先于读 (同周期写入, 读口看到新值)

  wire raw_hazard = id_valid && (
    raw_rs1_ex || raw_rs2_ex || raw_rs1_ls || raw_rs2_ls
  );

  // ====================================================================
  //  ID/EX 流水线寄存器
  // ====================================================================
  reg         ex_valid;
  reg  [31:0] ex_pc;
  reg  [31:0] ex_rs1_data, ex_rs2_data;
  reg  [31:0] ex_imm_i, ex_imm_s, ex_imm_b, ex_imm_u, ex_imm_j;
  reg  [4:0]  ex_rd;
  reg  [2:0]  ex_funct3;   reg  [6:0] ex_funct7;
  reg  ex_is_add,ex_is_sub,ex_is_and,ex_is_or,ex_is_xor,ex_is_sll,ex_is_srl,ex_is_sra,ex_is_slt,ex_is_sltu;
  reg  ex_is_addi,ex_is_slti,ex_is_sltiu,ex_is_xori,ex_is_ori,ex_is_andi,ex_is_slli,ex_is_srli,ex_is_srai;
  reg  ex_is_lb,ex_is_lh,ex_is_lw,ex_is_lbu,ex_is_lhu;
  reg  ex_is_sb,ex_is_sh,ex_is_sw;
  reg  ex_is_beq,ex_is_bne,ex_is_blt,ex_is_bge,ex_is_bltu,ex_is_bgeu;
  reg  ex_is_lui,ex_is_auipc,ex_is_jal,ex_is_jalr;
  reg  ex_is_ebreak,ex_is_ecall,ex_is_mret,ex_is_fencei;
  reg  ex_is_csrrw,ex_is_csrrs;
  reg  ex_reg_wen, ex_mem_valid, ex_mem_wen, ex_csr_wen;

  always @(posedge clock) begin
    if (rst) begin
      ex_valid <= 1'b0;
    end else begin
      ex_valid <= id_valid && !raw_hazard;
      if (id_valid && !raw_hazard) begin
        ex_pc       <= id_pc;
        ex_rs1_data <= rf_rs1_data;
        ex_rs2_data <= rf_rs2_data;
        ex_imm_i <= id_imm_i; ex_imm_s <= id_imm_s; ex_imm_b <= id_imm_b;
        ex_imm_u <= id_imm_u; ex_imm_j <= id_imm_j;
        ex_rd <= id_rd; ex_funct3 <= id_funct3; ex_funct7 <= id_funct7;
        ex_is_add<=id_is_add; ex_is_sub<=id_is_sub; ex_is_and<=id_is_and; ex_is_or<=id_is_or;
        ex_is_xor<=id_is_xor; ex_is_sll<=id_is_sll; ex_is_srl<=id_is_srl; ex_is_sra<=id_is_sra;
        ex_is_slt<=id_is_slt; ex_is_sltu<=id_is_sltu;
        ex_is_addi<=id_is_addi; ex_is_slti<=id_is_slti; ex_is_sltiu<=id_is_sltiu;
        ex_is_xori<=id_is_xori; ex_is_ori<=id_is_ori; ex_is_andi<=id_is_andi;
        ex_is_slli<=id_is_slli; ex_is_srli<=id_is_srli; ex_is_srai<=id_is_srai;
        ex_is_lb<=id_is_lb; ex_is_lh<=id_is_lh; ex_is_lw<=id_is_lw; ex_is_lbu<=id_is_lbu; ex_is_lhu<=id_is_lhu;
        ex_is_sb<=id_is_sb; ex_is_sh<=id_is_sh; ex_is_sw<=id_is_sw;
        ex_is_beq<=id_is_beq; ex_is_bne<=id_is_bne; ex_is_blt<=id_is_blt; ex_is_bge<=id_is_bge;
        ex_is_bltu<=id_is_bltu; ex_is_bgeu<=id_is_bgeu;
        ex_is_lui<=id_is_lui; ex_is_auipc<=id_is_auipc; ex_is_jal<=id_is_jal; ex_is_jalr<=id_is_jalr;
        ex_is_ebreak<=id_is_ebreak; ex_is_ecall<=id_is_ecall; ex_is_mret<=id_is_mret;
        ex_is_fencei<=id_is_fencei;
        ex_is_csrrw<=id_is_csrrw; ex_is_csrrs<=id_is_csrrs;
        ex_reg_wen<=id_reg_wen; ex_mem_valid<=id_mem_valid;
        ex_mem_wen<=id_mem_wen; ex_csr_wen<=id_csr_wen;
      end
    end
  end

  // 暴露给RAW检测
  wire [4:0] ex_rd_f = ex_valid ? ex_rd : 5'd0;
  wire ex_reg_wen_f = ex_valid && ex_reg_wen;
  wire ex_is_load = ex_is_lb||ex_is_lh||ex_is_lw||ex_is_lbu||ex_is_lhu;
  wire ex_is_store= ex_is_sb||ex_is_sh||ex_is_sw;

  // ====================================================================
  //  EX 阶段: ALU + 地址计算 + 分支判断
  // ====================================================================

  // ---------- CSR ----------
  wire [31:0] csr_rdata, csr_wdata;
  wire [31:0] mepc_out, mtvec_out;
  wire [63:0] mcycle_out;

  CSR u_csr(
    .clk(clock), .rst(rst),
    .csr_addr(ex_imm_i[11:0]),
    .csr_wdata(csr_wdata), .csr_wen(ex_valid && ex_csr_wen),
    .csr_rdata(csr_rdata),
    .exception_en(1'b0), .exception_pc(32'd0), .exception_cause(32'd0),
    .mret_en(1'b0),
    .mepc_out(mepc_out), .mtvec_out(mtvec_out), .mcycle_out(mcycle_out)
  );

  // ---------- EXU ----------
  wire [31:0] ex_alu_result;
  wire [31:0] ex_jump_target, ex_branch_target;
  wire        ex_branch_taken;

  EXU u_exu(
    .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
    .imm_i(ex_imm_i), .imm_b(ex_imm_b), .imm_j(ex_imm_j),
    .pc(ex_pc),
    .is_add(ex_is_add), .is_sub(ex_is_sub), .is_and(ex_is_and), .is_or(ex_is_or),
    .is_xor(ex_is_xor), .is_sll(ex_is_sll), .is_srl(ex_is_srl), .is_sra(ex_is_sra),
    .is_slt(ex_is_slt), .is_sltu(ex_is_sltu),
    .is_addi(ex_is_addi), .is_slti(ex_is_slti), .is_sltiu(ex_is_sltiu),
    .is_xori(ex_is_xori), .is_ori(ex_is_ori), .is_andi(ex_is_andi),
    .is_slli(ex_is_slli), .is_srli(ex_is_srli), .is_srai(ex_is_srai),
    .is_beq(ex_is_beq), .is_bne(ex_is_bne), .is_blt(ex_is_blt), .is_bge(ex_is_bge),
    .is_bltu(ex_is_bltu), .is_bgeu(ex_is_bgeu),
    .is_jal(ex_is_jal), .is_jalr(ex_is_jalr),
    .is_csrrw(ex_is_csrrw), .is_csrrs(ex_is_csrrs),
    .csr_rdata(csr_rdata), .csr_wdata(csr_wdata),
    .alu_result(ex_alu_result),
    .jump_target(ex_jump_target),
    .branch_target(ex_branch_target),
    .branch_taken(ex_branch_taken)
  );

  // ---------- 控制冒险 ----------
  wire ex_is_branch_taken = ex_valid && (
    (ex_is_beq||ex_is_bne||ex_is_blt||ex_is_bge||ex_is_bltu||ex_is_bgeu) && ex_branch_taken
  );
  wire ex_is_uncond_jump = ex_valid && (ex_is_jal || ex_is_jalr);
  wire ex_is_taken_jump  = ex_is_branch_taken || ex_is_uncond_jump;
  wire ex_is_fencei_taken= ex_valid && ex_is_fencei;

  wire [31:0] ex_next_pc = ex_is_jalr ? ex_jump_target :
                            (ex_is_jal||ex_is_branch_taken) ? ex_branch_target :
                            ex_pc + 32'd4;

  // fence.i 冲刷ICache
  wire icache_flush_F = ex_is_fencei_taken;

  // ---------- 访存地址 (EX阶段计算) ----------
  wire [31:0] ex_mem_addr = ex_is_store ? (ex_rs1_data + ex_imm_s) : (ex_rs1_data + ex_imm_i);

  // ====================================================================
  //  EX/LS 流水线寄存器
  // ====================================================================
  reg         ls_valid;
  reg  [31:0] ls_pc;
  reg  [31:0] ls_alu_result, ls_rs2_data, ls_mem_addr_r, ls_imm_u;
  reg  [4:0]  ls_rd;
  reg  [2:0]  ls_funct3;
  reg  ls_is_lb,ls_is_lh,ls_is_lw,ls_is_lbu,ls_is_lhu;
  reg  ls_is_sb,ls_is_sh,ls_is_sw;
  reg  ls_is_lui,ls_is_auipc,ls_is_jal,ls_is_jalr;
  reg  ls_is_csrrw,ls_is_csrrs;
  reg  ls_is_ebreak,ls_is_ecall,ls_is_mret;
  reg  ls_reg_wen, ls_mem_valid, ls_mem_wen;
  reg  ls_is_load, ls_is_store;

  always @(posedge clock) begin
    if (rst) begin
      ls_valid <= 1'b0;
    end else begin
      ls_valid <= ex_valid;
      if (ex_valid) begin
        ls_pc         <= ex_pc;
        ls_alu_result <= ex_alu_result;
        ls_rs2_data   <= ex_rs2_data;
        ls_mem_addr_r <= ex_mem_addr;
        ls_imm_u      <= ex_imm_u;
        ls_rd <= ex_rd; ls_funct3 <= ex_funct3;
        ls_is_lb<=ex_is_lb; ls_is_lh<=ex_is_lh; ls_is_lw<=ex_is_lw;
        ls_is_lbu<=ex_is_lbu; ls_is_lhu<=ex_is_lhu;
        ls_is_sb<=ex_is_sb; ls_is_sh<=ex_is_sh; ls_is_sw<=ex_is_sw;
        ls_is_lui<=ex_is_lui; ls_is_auipc<=ex_is_auipc;
        ls_is_jal<=ex_is_jal; ls_is_jalr<=ex_is_jalr;
        ls_is_csrrw<=ex_is_csrrw; ls_is_csrrs<=ex_is_csrrs;
        ls_is_ebreak<=ex_is_ebreak; ls_is_ecall<=ex_is_ecall; ls_is_mret<=ex_is_mret;
        ls_reg_wen<=ex_reg_wen; ls_mem_valid<=ex_mem_valid; ls_mem_wen<=ex_mem_wen;
        ls_is_load <= ex_is_load; ls_is_store<= ex_is_store;
      end
    end
  end

  wire [4:0] ls_rd_f = ls_valid ? ls_rd : 5'd0;
  wire ls_reg_wen_f = ls_valid && ls_reg_wen;

  // ====================================================================
  //  LS 阶段: 访存
  // ====================================================================

  wire        lsu_arvalid, lsu_arready, lsu_rvalid, lsu_rready;
  wire [31:0] lsu_araddr, lsu_rdata;
  wire [ 3:0] lsu_arid, lsu_rid;
  wire [ 7:0] lsu_arlen;
  wire [ 2:0] lsu_arsize;
  wire [ 1:0] lsu_arburst, lsu_rresp;
  wire        lsu_rlast;
  wire        lsu_awvalid, lsu_awready, lsu_wvalid, lsu_wready;
  wire [31:0] lsu_awaddr, lsu_wdata;
  wire [ 3:0] lsu_awid, lsu_wstrb;
  wire [ 7:0] lsu_awlen;
  wire [ 2:0] lsu_awsize;
  wire [ 1:0] lsu_awburst;
  wire        lsu_wlast, lsu_bvalid, lsu_bready;
  wire [ 1:0] lsu_bresp;
  wire [ 3:0] lsu_bid;
  wire [31:0] lsu_mem_rdata;
  wire        lsu_access_fault;

  LSU u_lsu(
    .clk(clock), .rst(rst),
    .mem_valid(ls_valid && ls_mem_valid),
    .mem_wen(ls_valid && ls_mem_wen),
    .funct3(ls_funct3),
    .mem_addr(ls_mem_addr_r),
    .wdata(ls_rs2_data),
    .cpu_pc(ls_pc),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr), .lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen), .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready),
    .lsu_rdata(lsu_rdata), .lsu_rresp(lsu_rresp), .lsu_rlast(lsu_rlast), .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr), .lsu_awid(lsu_awid),
    .lsu_awlen(lsu_awlen), .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready),
    .lsu_wdata(lsu_wdata), .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp), .lsu_bid(lsu_bid),
    .rdata(lsu_mem_rdata),
    .lsu_access_fault(lsu_access_fault),
    .lsu_state_o(), .lsu_load_req(), .lsu_store_req(),
    .lsu_r_handshake(), .lsu_b_handshake(),
    .lsu_wait_ar(), .lsu_wait_r(), .lsu_wait_aw_w(), .lsu_wait_b()
  );

  // ====================================================================
  //  LS/WB 流水线寄存器
  // ====================================================================
  reg         wb_valid;
  reg  [31:0] wb_pc, wb_alu_result, wb_mem_rdata, wb_imm_u;
  reg  [4:0]  wb_rd;
  reg  wb_is_lb,wb_is_lh,wb_is_lw,wb_is_lbu,wb_is_lhu;
  reg  wb_is_lui,wb_is_auipc,wb_is_jal,wb_is_jalr;
  reg  wb_is_csrrw,wb_is_csrrs;
  reg  wb_is_ebreak,wb_is_ecall,wb_is_mret;
  reg  wb_reg_wen;

  always @(posedge clock) begin
    if (rst) begin
      wb_valid <= 1'b0;
    end else begin
      wb_valid <= ls_valid;
      if (ls_valid) begin
        wb_pc <= ls_pc; wb_alu_result <= ls_alu_result;
        wb_mem_rdata <= lsu_mem_rdata; wb_imm_u <= ls_imm_u;
        wb_rd <= ls_rd;
        wb_is_lb<=ls_is_lb; wb_is_lh<=ls_is_lh; wb_is_lw<=ls_is_lw;
        wb_is_lbu<=ls_is_lbu; wb_is_lhu<=ls_is_lhu;
        wb_is_lui<=ls_is_lui; wb_is_auipc<=ls_is_auipc;
        wb_is_jal<=ls_is_jal; wb_is_jalr<=ls_is_jalr;
        wb_is_csrrw<=ls_is_csrrw; wb_is_csrrs<=ls_is_csrrs;
        wb_is_ebreak<=ls_is_ebreak; wb_is_ecall<=ls_is_ecall; wb_is_mret<=ls_is_mret;
        wb_reg_wen<=ls_reg_wen;
      end
    end
  end

  // ====================================================================
  //  WB 阶段: 写回寄存器
  // ====================================================================
  wire wb_is_load_wb = wb_is_lb||wb_is_lh||wb_is_lw||wb_is_lbu||wb_is_lhu;
  wire wb_is_jump    = wb_is_jal||wb_is_jalr;
  wire wb_is_csr     = wb_is_csrrw||wb_is_csrrs;

  wire [31:0] wb_wdata = wb_is_csr    ? csr_rdata :
                          wb_is_jump   ? (wb_pc + 32'd4) :
                          wb_is_lui    ? wb_imm_u :
                          wb_is_auipc  ? (wb_pc + wb_imm_u) :
                          wb_is_load_wb? wb_mem_rdata :
                          wb_alu_result;
  wire [4:0]  wb_waddr = wb_rd;
  wire        wb_wen   = wb_valid && wb_reg_wen && !wb_is_ebreak && !wb_is_ecall && !wb_is_mret;

  // ====================================================================
  //  流水线控制
  // ====================================================================
  always @(*) begin
    stall_F = raw_hazard;
    stall_D = raw_hazard;
  end

  always @(*) begin
    flush_F = ex_is_taken_jump || ex_is_fencei_taken;
    flush_D = ex_is_taken_jump || ex_is_fencei_taken;
    if (ex_is_fencei_taken)
      redirect_pc = ex_pc + 32'd4;
    else if (ex_is_taken_jump)
      redirect_pc = ex_next_pc;
    else
      redirect_pc = 32'd0;
  end

  // ====================================================================
  //  ICache
  // ====================================================================
  wire icache_arvalid, icache_arready, icache_rvalid, icache_rready;
  wire [31:0] icache_araddr, icache_rdata;
  wire [ 3:0] icache_arid, icache_rid;
  wire [ 7:0] icache_arlen;
  wire [ 2:0] icache_arsize;
  wire [ 1:0] icache_arburst, icache_rresp;
  wire        icache_rlast;

  ICache u_icache(
    .clk(clock), .rst(rst),
    .cpu_arvalid(ifu_arvalid), .cpu_arready(ifu_arready),
    .cpu_araddr(ifu_araddr), .cpu_arid(ifu_arid),
    .cpu_arlen(ifu_arlen), .cpu_arsize(ifu_arsize), .cpu_arburst(ifu_arburst),
    .cpu_rvalid(ifu_rvalid), .cpu_rready(ifu_rready),
    .cpu_rdata(ifu_rdata), .cpu_rresp(ifu_rresp),
    .cpu_rlast(ifu_rlast), .cpu_rid(ifu_rid),
    .bus_arvalid(icache_arvalid), .bus_arready(icache_arready),
    .bus_araddr(icache_araddr), .bus_arid(icache_arid),
    .bus_arlen(icache_arlen), .bus_arsize(icache_arsize), .bus_arburst(icache_arburst),
    .bus_rvalid(icache_rvalid), .bus_rready(icache_rready),
    .bus_rdata(icache_rdata), .bus_rresp(icache_rresp),
    .bus_rlast(icache_rlast), .bus_rid(icache_rid),
    .icache_access(), .icache_hit(), .icache_miss(), .icache_uncache(),
    .icache_refill_req(), .icache_refill_req_pulse(),
    .icache_wait_ar(), .icache_wait_r(),
    .flush(icache_flush_F)
  );

  // ====================================================================
  //  CLINT
  // ====================================================================
  wire clint_arvalid, clint_arready, clint_rvalid, clint_rready;
  wire [31:0] clint_araddr, clint_rdata;
  wire [ 3:0] clint_arid, clint_rid;
  wire [ 7:0] clint_arlen;
  wire [ 2:0] clint_arsize;
  wire [ 1:0] clint_arburst, clint_rresp;
  wire clint_rlast;
  wire clint_awvalid, clint_awready, clint_wvalid, clint_wready;
  wire [31:0] clint_awaddr, clint_wdata;
  wire [ 3:0] clint_awid, clint_wstrb;
  wire [ 7:0] clint_awlen;
  wire [ 2:0] clint_awsize;
  wire [ 1:0] clint_awburst;
  wire clint_wlast, clint_bvalid, clint_bready;
  wire [ 1:0] clint_bresp;
  wire [ 3:0] clint_bid;

  CLINT u_clint(
    .clk(clock), .rst(rst),
    .clint_arvalid(clint_arvalid), .clint_arready(clint_arready),
    .clint_araddr(clint_araddr), .clint_arid(clint_arid),
    .clint_arlen(clint_arlen), .clint_arsize(clint_arsize), .clint_arburst(clint_arburst),
    .clint_rvalid(clint_rvalid), .clint_rready(clint_rready),
    .clint_rdata(clint_rdata), .clint_rresp(clint_rresp),
    .clint_rlast(clint_rlast), .clint_rid(clint_rid),
    .clint_awvalid(clint_awvalid), .clint_awready(clint_awready),
    .clint_awaddr(clint_awaddr), .clint_awid(clint_awid),
    .clint_awlen(clint_awlen), .clint_awsize(clint_awsize), .clint_awburst(clint_awburst),
    .clint_wvalid(clint_wvalid), .clint_wready(clint_wready),
    .clint_wdata(clint_wdata), .clint_wstrb(clint_wstrb), .clint_wlast(clint_wlast),
    .clint_bvalid(clint_bvalid), .clint_bready(clint_bready),
    .clint_bresp(clint_bresp), .clint_bid(clint_bid)
  );

  // ====================================================================
  //  AXIArbiter
  // ====================================================================
  AXIArbiter u_arbiter(
    .clk(clock), .rst(rst),
    .ifu_arvalid(icache_arvalid), .ifu_arready(icache_arready),
    .ifu_araddr(icache_araddr), .ifu_arid(icache_arid),
    .ifu_arlen(icache_arlen), .ifu_arsize(icache_arsize), .ifu_arburst(icache_arburst),
    .ifu_rvalid(icache_rvalid), .ifu_rready(icache_rready),
    .ifu_rdata(icache_rdata), .ifu_rresp(icache_rresp),
    .ifu_rlast(icache_rlast), .ifu_rid(icache_rid),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr), .lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen), .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready),
    .lsu_rdata(lsu_rdata), .lsu_rresp(lsu_rresp),
    .lsu_rlast(lsu_rlast), .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr), .lsu_awid(lsu_awid),
    .lsu_awlen(lsu_awlen), .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready),
    .lsu_wdata(lsu_wdata), .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp), .lsu_bid(lsu_bid),
    .clint_arvalid(clint_arvalid), .clint_arready(clint_arready),
    .clint_araddr(clint_araddr), .clint_arid(clint_arid),
    .clint_arlen(clint_arlen), .clint_arsize(clint_arsize), .clint_arburst(clint_arburst),
    .clint_rvalid(clint_rvalid), .clint_rready(clint_rready),
    .clint_rdata(clint_rdata), .clint_rresp(clint_rresp),
    .clint_rlast(clint_rlast), .clint_rid(clint_rid),
    .clint_awvalid(clint_awvalid), .clint_awready(clint_awready),
    .clint_awaddr(clint_awaddr), .clint_awid(clint_awid),
    .clint_awlen(clint_awlen), .clint_awsize(clint_awsize), .clint_awburst(clint_awburst),
    .clint_wvalid(clint_wvalid), .clint_wready(clint_wready),
    .clint_wdata(clint_wdata), .clint_wstrb(clint_wstrb), .clint_wlast(clint_wlast),
    .clint_bvalid(clint_bvalid), .clint_bready(clint_bready),
    .clint_bresp(clint_bresp), .clint_bid(clint_bid),
    .mem_arvalid(io_master_arvalid), .mem_arready(io_master_arready),
    .mem_araddr(io_master_araddr), .mem_arid(io_master_arid),
    .mem_arlen(io_master_arlen), .mem_arsize(io_master_arsize), .mem_arburst(io_master_arburst),
    .mem_rvalid(io_master_rvalid), .mem_rready(io_master_rready),
    .mem_rdata(io_master_rdata), .mem_rresp(io_master_rresp),
    .mem_rlast(io_master_rlast), .mem_rid(io_master_rid),
    .mem_awvalid(io_master_awvalid), .mem_awready(io_master_awready),
    .mem_awaddr(io_master_awaddr), .mem_awid(io_master_awid),
    .mem_awlen(io_master_awlen), .mem_awsize(io_master_awsize), .mem_awburst(io_master_awburst),
    .mem_wvalid(io_master_wvalid), .mem_wready(io_master_wready),
    .mem_wdata(io_master_wdata), .mem_wstrb(io_master_wstrb), .mem_wlast(io_master_wlast),
    .mem_bvalid(io_master_bvalid), .mem_bready(io_master_bready),
    .mem_bresp(io_master_bresp), .mem_bid(io_master_bid)
  );

  // ====================================================================
  //  DPI: ebreak / difftest_skip
  // ====================================================================
`ifndef SYNTHESIS
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void access_fault_handler(input int pc_val, input int is_store);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val, input int target_val);
  import "DPI-C" function void difftest_skip_ref();

  // 外设访问跳过 difftest (EX阶段检测)
  wire ex_is_mem_op = ex_valid && (ex_is_load || ex_is_store);
  wire ex_mem_is_peripheral = ex_is_mem_op && !(
    (ex_mem_addr >= 32'h0f000000 && ex_mem_addr < 32'h0f002000) ||
    (ex_mem_addr >= 32'h20000000 && ex_mem_addr < 32'h20001000) ||
    (ex_mem_addr >= 32'h30000000 && ex_mem_addr < 32'h31000000) ||
    (ex_mem_addr >= 32'h80000000 && ex_mem_addr < 32'h80400000) ||
    (ex_mem_addr >= 32'ha0000000 && ex_mem_addr < 32'ha2000000)
  );

  always @(posedge clock) begin
    if (!rst && ex_mem_is_peripheral) begin
      difftest_skip_ref();
    end
  end

  // ebreak (WB阶段检测, 精确异常)
  always @(posedge clock) begin
    if (!rst && wb_valid) begin
      if (wb_is_ebreak) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x, mcycle=%0d", wb_pc, rf_a0_value, mcycle_out);
        ebreak_handler(rf_a0_value);
      end
    end
  end

  // ftrace (WB阶段)
  always @(posedge clock) begin
    if (!rst && wb_valid) begin
      if (wb_is_jalr) begin
        if (wb_rd == 5'd1)
          ftrace_call_handler(wb_pc, /*target*/32'd0);  // 简化
        else if (wb_rd == 5'd0)
          ftrace_ret_handler(wb_pc, /*target*/32'd0);    // 简化
      end
      if (wb_is_jal && wb_rd == 5'd1) begin
        ftrace_call_handler(wb_pc, /*target*/32'd0);     // 简化
      end
    end
  end
`endif

endmodule
