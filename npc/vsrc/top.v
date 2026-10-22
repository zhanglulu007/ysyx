// ============================================================================
// NPC Top - 3 级流水线核 (F / D / E)
//
//   F: PC + ICache + BTB -> IFID
//   D: 译码(IDU) + 寄存器堆读 + 控制包生成 -> IDEX
//   E: ALU / 分支 / CSR / 访存发起 / 写回 (含 EX->EX 旁路)
//
// 关键点:
//   * 译码放在 D 段, IDEX 只寄存操作数和约 23 位控制包; E 段的关键路径
//     不再包含 opcode/funct 译码, 只从寄存器出发做 ALU + 写回。
//   * ICache 命中每拍一条; 缺失同拍发 AR, 填满后服务。
//   * BTB (8 项 taken cache) 预测 taken 分支; E 段用"下一条指令 PC 是否
//     正确"校验预测, BTB 只影响性能不影响正确性。
//   * 访存按序: load 的 R / store 的 B 完成才 commit。
// ============================================================================
module top(
  input clk,
  input rst,
  input [31:0] imem_rdata,
  output [31:0] pc,
  output [31:0] inst,
  output [31:0] imem_addr

`ifdef SOC_MODE
  ,
  output        mem_arvalid,
  input         mem_arready,
  output [31:0] mem_araddr,
  output [ 3:0] mem_arid,
  output [ 7:0] mem_arlen,
  output [ 2:0] mem_arsize,
  output [ 1:0] mem_arburst,
  input         mem_rvalid,
  output        mem_rready,
  input  [ 1:0] mem_rresp,
  input  [31:0] mem_rdata,
  input         mem_rlast,
  input  [ 3:0] mem_rid,
  output        mem_awvalid,
  input         mem_awready,
  output [31:0] mem_awaddr,
  output [ 3:0] mem_awid,
  output [ 7:0] mem_awlen,
  output [ 2:0] mem_awsize,
  output [ 1:0] mem_awburst,
  output        mem_wvalid,
  input         mem_wready,
  output [31:0] mem_wdata,
  output [ 3:0] mem_wstrb,
  output        mem_wlast,
  input         mem_bvalid,
  output        mem_bready,
  input  [ 1:0] mem_bresp,
  input  [ 3:0] mem_bid
`endif
);

`ifdef SOC_MODE
  localparam [31:0] RESET_PC = 32'h3000_0000;
`else
  localparam [31:0] RESET_PC = 32'h8000_0000;
`endif

  // ======================= F 段 =======================
  wire [31:0] pc_f;
  wire [31:0] ifid_inst, ifid_pc;
  wire        ifid_valid;

  wire        f_req_valid, f_req_ready;
  wire        f_resp_valid, f_resp_ready;
  wire [31:0] f_resp_inst;
  wire        btb_hit;

  // ======================= D 段: 译码 + 读寄存器 =======================
  wire [31:0] d_rs1_data, d_rs2_data;

  wire [4:0] d_rd, d_rs1, d_rs2;
  wire [31:0] d_imm_i, d_imm_s, d_imm_b, d_imm_u, d_imm_j;
  wire d_is_add, d_is_sub, d_is_and, d_is_or, d_is_xor;
  wire d_is_sll, d_is_srl, d_is_sra, d_is_slt, d_is_sltu;
  wire d_is_addi, d_is_slti, d_is_sltiu, d_is_xori, d_is_ori, d_is_andi;
  wire d_is_slli, d_is_srli, d_is_srai;
  wire d_is_lb, d_is_lh, d_is_lw, d_is_lbu, d_is_lhu;
  wire d_is_sb, d_is_sh, d_is_sw;
  wire d_is_beq, d_is_bne, d_is_blt, d_is_bge, d_is_bltu, d_is_bgeu;
  wire d_is_lui, d_is_auipc, d_is_jal, d_is_jalr;
  wire d_is_ebreak, d_is_ecall, d_is_mret;
  wire d_is_csrrw, d_is_csrrs, d_is_fence_i;
  wire d_op_r_type, d_op_load, d_op_store, d_is_jump;
  wire d_reg_wen, d_mem_valid, d_mem_wen, d_csr_wen;

  // 控制包 (D 段组合生成, IDEX 寄存)
  wire [3:0] d_alu_op;
  wire       d_alu_rs2, d_alu_imm_s;
  wire [2:0] d_branch_type;
  wire       d_is_branch, d_is_csr, d_is_alu;

  assign d_is_branch = d_is_beq || d_is_bne || d_is_blt ||
                       d_is_bge || d_is_bltu || d_is_bgeu;

  assign d_is_csr = d_is_csrrw || d_is_csrrs;

  assign d_is_alu = d_op_r_type || d_is_addi || d_is_slti || d_is_sltiu ||
                    d_is_xori || d_is_ori || d_is_andi || d_is_slli ||
                    d_is_srli || d_is_srai;

  // ALU op: 0 ADD, 1 SUB, 2 SLL, 3 SLT, 4 SLTU, 5 XOR, 6 SRL, 7 SRA, 8 OR, 9 AND
  assign d_alu_op = (d_is_add || d_is_addi || d_op_load || d_op_store) ? 4'd0 :
                    d_is_sub                        ? 4'd1 :
                    (d_is_sll  || d_is_slli)        ? 4'd2 :
                    (d_is_slt  || d_is_slti)        ? 4'd3 :
                    (d_is_sltu || d_is_sltiu)       ? 4'd4 :
                    (d_is_xor  || d_is_xori)        ? 4'd5 :
                    (d_is_srl  || d_is_srli)        ? 4'd6 :
                    (d_is_sra  || d_is_srai)        ? 4'd7 :
                    (d_is_or   || d_is_ori)         ? 4'd8 :
                    (d_is_and  || d_is_andi)        ? 4'd9 : 4'd0;

  assign d_alu_rs2    = d_op_r_type;
  assign d_alu_imm_s  = d_op_store;

  assign d_branch_type = d_is_beq  ? 3'd0 :
                         d_is_bne  ? 3'd1 :
                         d_is_blt  ? 3'd2 :
                         d_is_bge  ? 3'd3 :
                         d_is_bltu ? 3'd4 :
                         d_is_bgeu ? 3'd5 : 3'd0;

  IDU u_idu(
    .inst(ifid_inst),
    .ifu_valid(ifid_valid),
    .rd(d_rd),
    .rs1(d_rs1),
    .rs2(d_rs2),
    .imm_i(d_imm_i),
    .imm_s(d_imm_s),
    .imm_b(d_imm_b),
    .imm_u(d_imm_u),
    .imm_j(d_imm_j),
    .is_add(d_is_add),
    .is_sub(d_is_sub),
    .is_and(d_is_and),
    .is_or(d_is_or),
    .is_xor(d_is_xor),
    .is_sll(d_is_sll),
    .is_srl(d_is_srl),
    .is_sra(d_is_sra),
    .is_slt(d_is_slt),
    .is_sltu(d_is_sltu),
    .is_addi(d_is_addi),
    .is_slti(d_is_slti),
    .is_sltiu(d_is_sltiu),
    .is_xori(d_is_xori),
    .is_ori(d_is_ori),
    .is_andi(d_is_andi),
    .is_slli(d_is_slli),
    .is_srli(d_is_srli),
    .is_srai(d_is_srai),
    .is_lb(d_is_lb),
    .is_lh(d_is_lh),
    .is_lw(d_is_lw),
    .is_lbu(d_is_lbu),
    .is_lhu(d_is_lhu),
    .is_sb(d_is_sb),
    .is_sh(d_is_sh),
    .is_sw(d_is_sw),
    .is_beq(d_is_beq),
    .is_bne(d_is_bne),
    .is_blt(d_is_blt),
    .is_bge(d_is_bge),
    .is_bltu(d_is_bltu),
    .is_bgeu(d_is_bgeu),
    .is_lui(d_is_lui),
    .is_auipc(d_is_auipc),
    .is_jal(d_is_jal),
    .is_jalr(d_is_jalr),
    .is_ebreak(d_is_ebreak),
    .is_ecall(d_is_ecall),
    .is_mret(d_is_mret),
    .is_csrrw(d_is_csrrw),
    .is_csrrs(d_is_csrrs),
    .is_fence_i(d_is_fence_i),
    .reg_wen(d_reg_wen),
    .mem_valid(d_mem_valid),
    .mem_wen(d_mem_wen),
    .csr_wen(d_csr_wen),
    .op_r_type(d_op_r_type),
    .op_load(d_op_load),
    .op_store(d_op_store),
    .is_jump(d_is_jump)
  );

  // ======================= IDEX =======================
  reg [31:0] idex_inst, idex_pc, idex_rs1, idex_rs2;
  reg        idex_valid;
  reg [3:0]  idex_alu_op;
  reg        idex_alu_rs2, idex_alu_imm_s;
  reg [2:0]  idex_branch_type;
  reg        idex_is_branch, idex_is_jal, idex_is_jalr;
  reg        idex_is_lui, idex_is_auipc, idex_is_csr;
  reg        idex_is_load, idex_is_store;
  reg        idex_reg_wen, idex_csr_wen;
  reg        idex_is_ecall, idex_is_mret, idex_is_ebreak, idex_is_fence_i;
  reg        idex_is_alu;

  // ======================= E 段 =======================
  wire        ex_valid = idex_valid;
  wire [31:0] ex_inst  = idex_inst;
  wire [31:0] ex_pc    = idex_pc;

  wire [4:0]  ex_rs1 = ex_inst[19:15];
  wire [4:0]  ex_rs2 = ex_inst[24:20];
  wire [4:0]  ex_rd  = ex_inst[11:7];
  wire [2:0]  ex_funct3 = ex_inst[14:12];

  // E 段由 IDEX 指令直接切出的立即数 (纯连线/少量门, 无长译码)
  wire [31:0] ex_imm_i = {{20{ex_inst[31]}}, ex_inst[31:20]};
  wire [31:0] ex_imm_s = {{20{ex_inst[31]}}, ex_inst[31:25], ex_inst[11:7]};
  wire [31:0] ex_imm_b = {{19{ex_inst[31]}}, ex_inst[31], ex_inst[7],
                          ex_inst[30:25], ex_inst[11:8], 1'b0};
  wire [31:0] ex_imm_j = {{11{ex_inst[31]}}, ex_inst[31], ex_inst[19:12],
                          ex_inst[20], ex_inst[30:21], 1'b0};
  wire [31:0] ex_imm_u = {ex_inst[31:12], 12'b0};

  wire [31:0] alu_result, jump_target, branch_target, pc_imm, rd_data, pc_next, rdata;
  wire        branch_taken;

  // 旁路: 上一条已提交指令的结果
  reg         last_wen;
  reg  [4:0]  last_rd;
  reg  [31:0] last_result;

  wire fwd_a = last_wen && (last_rd == ex_rs1) && (ex_rs1 != 5'd0);
  wire fwd_b = last_wen && (last_rd == ex_rs2) && (ex_rs2 != 5'd0);
  wire [31:0] ex_rs1_v = fwd_a ? last_result : idex_rs1;
  wire [31:0] ex_rs2_v = fwd_b ? last_result : idex_rs2;

  // load/store 子类型
  wire ex_is_lb  = idex_is_load  && (ex_funct3 == 3'b000);
  wire ex_is_lh  = idex_is_load  && (ex_funct3 == 3'b001);
  wire ex_is_lw  = idex_is_load  && (ex_funct3 == 3'b010);
  wire ex_is_lbu = idex_is_load  && (ex_funct3 == 3'b100);
  wire ex_is_lhu = idex_is_load  && (ex_funct3 == 3'b101);
  wire ex_is_sb  = idex_is_store && (ex_funct3 == 3'b000);
  wire ex_is_sh  = idex_is_store && (ex_funct3 == 3'b001);
  wire ex_is_sw  = idex_is_store && (ex_funct3 == 3'b010);

  wire ex_is_csrrw = idex_is_csr && (ex_funct3 == 3'b001);
  wire ex_is_csrrs = idex_is_csr && (ex_funct3 == 3'b010);

  wire mem_valid = ex_valid && (idex_is_load || idex_is_store);
  wire mem_wen   = ex_valid && idex_is_store;

  wire [31:0] lsu_addr = alu_result;
  wire        lsu_done;

  wire e_stall = mem_valid && !lsu_done;
  wire commit  = ex_valid && !e_stall;

  wire ex_actual_taken  = idex_is_jal || idex_is_jalr ||
                          (idex_is_branch && branch_taken);
  wire [31:0] ex_actual_target = idex_is_jal ? branch_target :
                                 (idex_is_jalr ? jump_target : branch_target);
  wire [31:0] ex_pc_plus4 = ex_pc + 32'd4;

  // 预测校验: IFID 有效时必须正好是正确下一 PC; IFID 为空时看 F 是否正在取它
  wire [31:0] correct_next_pc = ex_actual_taken ? ex_actual_target : ex_pc_plus4;
  wire next_pc_ok = ifid_valid ? (ifid_pc == correct_next_pc)
                               : (pc_f == correct_next_pc);

  wire ex_cf_redirect  = commit && (ex_actual_taken || idex_is_branch) && !next_pc_ok;
  wire ex_sys_redirect = commit &&
                         (idex_is_ecall || idex_is_mret ||
                          idex_is_ebreak || idex_is_fence_i);
  wire ex_redirect     = ex_cf_redirect || ex_sys_redirect;

  wire [31:0] ex_redirect_pc = ex_sys_redirect ? pc_next :
                                (ex_cf_redirect ? correct_next_pc : ex_pc_plus4);

  wire d_advance = !e_stall && !ex_redirect;

  wire btb_update   = commit && ex_actual_taken && !next_pc_ok;
  wire cache_flush  = commit && idex_is_fence_i;
  wire cache_cancel = ex_redirect;

  // ======================= IDEX 更新 =======================
  always @(posedge clk) begin
    if (rst) begin
      idex_valid       <= 1'b0;
      idex_inst        <= 32'h0000_0013;
      idex_pc          <= RESET_PC;
      idex_rs1         <= 32'b0;
      idex_rs2         <= 32'b0;
      idex_alu_op      <= 4'd0;
      idex_alu_rs2     <= 1'b0;
      idex_alu_imm_s   <= 1'b0;
      idex_branch_type <= 3'd0;
      idex_is_branch   <= 1'b0;
      idex_is_jal      <= 1'b0;
      idex_is_jalr     <= 1'b0;
      idex_is_lui      <= 1'b0;
      idex_is_auipc    <= 1'b0;
      idex_is_csr      <= 1'b0;
      idex_is_load     <= 1'b0;
      idex_is_store    <= 1'b0;
      idex_reg_wen     <= 1'b0;
      idex_csr_wen     <= 1'b0;
      idex_is_ecall    <= 1'b0;
      idex_is_mret     <= 1'b0;
      idex_is_ebreak   <= 1'b0;
      idex_is_fence_i  <= 1'b0;
      idex_is_alu      <= 1'b0;
    end else if (ex_redirect) begin
      idex_valid <= 1'b0;
    end else if (!e_stall) begin
      idex_valid <= ifid_valid;
      if (ifid_valid) begin
        idex_inst        <= ifid_inst;
        idex_pc          <= ifid_pc;
        idex_rs1         <= d_rs1_data;
        idex_rs2         <= d_rs2_data;
        idex_alu_op      <= d_alu_op;
        idex_alu_rs2     <= d_alu_rs2;
        idex_alu_imm_s   <= d_alu_imm_s;
        idex_branch_type <= d_branch_type;
        idex_is_branch   <= d_is_branch;
        idex_is_jal      <= d_is_jal;
        idex_is_jalr     <= d_is_jalr;
        idex_is_lui      <= d_is_lui;
        idex_is_auipc    <= d_is_auipc;
        idex_is_csr      <= d_is_csr;
        idex_is_load     <= d_op_load;
        idex_is_store    <= d_op_store;
        idex_reg_wen     <= d_reg_wen;
        idex_csr_wen     <= d_csr_wen;
        idex_is_ecall    <= d_is_ecall;
        idex_is_mret     <= d_is_mret;
        idex_is_ebreak   <= d_is_ebreak;
        idex_is_fence_i  <= d_is_fence_i;
        idex_is_alu      <= d_is_alu;
      end
    end
  end

  // 上一条已提交指令的结果
  always @(posedge clk) begin
    if (rst) begin
      last_wen    <= 1'b0;
      last_rd     <= 5'd0;
      last_result <= 32'b0;
    end else if (!e_stall) begin
      if (commit && idex_reg_wen && (ex_rd != 5'd0)) begin
        last_wen    <= 1'b1;
        last_rd     <= ex_rd;
        last_result <= rd_data;
      end else begin
        last_wen <= 1'b0;
      end
    end
  end

  // ======================= EXU =======================
  EXU u_exu(
    .rs1_data(ex_rs1_v),
    .rs2_data(ex_rs2_v),
    .imm_i(ex_imm_i),
    .imm_s(ex_imm_s),
    .imm_b(ex_imm_b),
    .imm_j(ex_imm_j),
    .imm_u(ex_imm_u),
    .pc(ex_pc),
    .alu_op(idex_alu_op),
    .alu_rs2(idex_alu_rs2),
    .alu_imm_s(idex_alu_imm_s),
    .branch_type(idex_branch_type),
    .is_branch(idex_is_branch),
    .is_jal(idex_is_jal),
    .is_auipc(idex_is_auipc),
    .alu_result(alu_result),
    .jump_target(jump_target),
    .branch_target(branch_target),
    .pc_imm(pc_imm),
    .branch_taken(branch_taken)
  );

  // ======================= LSU =======================
  wire lsu_arvalid, lsu_arready;
  wire [31:0] lsu_araddr;
  wire [3:0] lsu_arid;
  wire [7:0] lsu_arlen;
  wire [2:0] lsu_arsize;
  wire [1:0] lsu_arburst;
  wire lsu_rvalid, lsu_rready, lsu_rlast;
  wire [1:0] lsu_rresp;
  wire [31:0] lsu_rdata;
  wire [3:0] lsu_rid;
  wire lsu_awvalid, lsu_awready;
  wire [31:0] lsu_awaddr;
  wire [3:0] lsu_awid;
  wire [7:0] lsu_awlen;
  wire [2:0] lsu_awsize;
  wire [1:0] lsu_awburst;
  wire lsu_wvalid, lsu_wready;
  wire [31:0] lsu_wdata;
  wire [3:0] lsu_wstrb;
  wire lsu_wlast;
  wire lsu_bvalid, lsu_bready;
  wire [1:0] lsu_bresp;
  wire [3:0] lsu_bid;

  LSU u_lsu(
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .is_lb(ex_is_lb),
    .is_lh(ex_is_lh),
    .is_lw(ex_is_lw),
    .is_lbu(ex_is_lbu),
    .is_lhu(ex_is_lhu),
    .is_sb(ex_is_sb),
    .is_sh(ex_is_sh),
    .is_sw(ex_is_sw),
    .lsu_arvalid(lsu_arvalid),
    .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr),
    .lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize),
    .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid),
    .lsu_rready(lsu_rready),
    .lsu_rresp(lsu_rresp),
    .lsu_rdata(lsu_rdata),
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
    .addr(lsu_addr),
    .wdata(ex_rs2_v),
    .rdata(rdata),
    .lsu_done(lsu_done)
  );

  // ======================= CSR =======================
  wire [31:0] mstatus, mcause, mcycle_lo, mcycle_hi;
  wire [31:0] mepc, mtvec, csr_rdata;
  wire [31:0] csr_wdata;

  assign csr_wdata = ex_is_csrrw ? ex_rs1_v : (ex_rs1_v | csr_rdata);

  CSR u_csr(
    .clk(clk),
    .rst(rst),
    .csr_addr(ex_inst[31:20]),
    .csr_wdata(csr_wdata),
    .csr_wen(commit && idex_csr_wen),
    .csr_rdata(csr_rdata),
    .is_ecall(idex_is_ecall),
    .pc(ex_pc),
    .mepc(mepc),
    .mtvec(mtvec),
    .mstatus_out(mstatus),
    .mcause_out(mcause),
    .mcycle_lo_out(mcycle_lo),
    .mcycle_hi_out(mcycle_hi)
  );

  // ======================= WBU =======================
  wire is_jump = idex_is_jal || idex_is_jalr;

  WBU u_wbu(
    .pc(ex_pc),
    .pc_plus4(ex_pc_plus4),
    .alu_result(alu_result),
    .rdata(rdata),
    .imm_u(ex_imm_u),
    .pc_imm(pc_imm),
    .jump_target(jump_target),
    .branch_target(branch_target),
    .branch_taken(branch_taken),
    .csr_rdata(csr_rdata),
    .mepc(mepc),
    .mtvec(mtvec),
    .is_lui(idex_is_lui),
    .is_auipc(idex_is_auipc),
    .is_jal(idex_is_jal),
    .is_jalr(idex_is_jalr),
    .is_ebreak(idex_is_ebreak),
    .is_ecall(idex_is_ecall),
    .is_mret(idex_is_mret),
    .is_csr(idex_is_csr),
    .op_load(idex_is_load),
    .is_jump(is_jump),
    .rd_data(rd_data),
    .pc_next(pc_next)
  );

  // ======================= 寄存器堆 (D 读, E 写) =======================
  wire [31:0] a0_value;

  RegisterFile u_regfile(
    .clk(clk),
    .rst(rst),
    .waddr(ex_rd),
    .wdata(rd_data),
    .wen(commit && idex_reg_wen && (ex_rd != 5'd0)),
    .raddr1(ifid_inst[19:15]),
    .rdata1(d_rs1_data),
    .raddr2(ifid_inst[24:20]),
    .rdata2(d_rs2_data),
    .a0_value(a0_value)
  );

  assign pc   = ex_pc;
  assign inst = ex_inst;

  // ======================= 取指通路: ICache / bypass =======================
  assign imem_addr = pc_f;

  wire ifu_cacheable = ((pc_f >= 32'h3000_0000) && (pc_f < 32'h3100_0000)) ||
                       ((pc_f >= 32'h8000_0000) && (pc_f < 32'h8800_0000)) ||
                       ((pc_f >= 32'ha000_0000) && (pc_f < 32'ha200_0000));

  wire icache_arvalid, icache_arready;
  wire [31:0] icache_araddr;
  wire [7:0] icache_arlen;
  wire icache_rvalid, icache_rready, icache_rlast;
  wire [31:0] icache_rdata;
  wire icache_inst_valid, icache_req_ready;
  wire [31:0] icache_inst;
  wire ic_perf_access, ic_perf_hit, ic_perf_miss, ic_perf_refill;
  wire ic_perf_compulsory, ic_perf_replace;

  wire arb_ifu_arvalid, arb_ifu_arready;
  wire [31:0] arb_ifu_araddr;
  wire [7:0] arb_ifu_arlen;
  wire arb_ifu_rvalid, arb_ifu_rready, arb_ifu_rlast;
  wire [31:0] arb_ifu_rdata;

  reg  [1:0] byp_state;
  wire byp_pending = (byp_state == 2'd1);
  wire byp_req = f_req_valid && !ifu_cacheable && !byp_pending;
  wire byp_rready = byp_pending && (f_resp_ready || cache_cancel);

  always @(posedge clk) begin
    if (rst) begin
      byp_state <= 2'd0;
    end else begin
      case (byp_state)
        2'd0: if (byp_req && arb_ifu_arready) byp_state <= 2'd1;
        2'd1: if (arb_ifu_rvalid && byp_rready) byp_state <= 2'd0;
        default: byp_state <= 2'd0;
      endcase
    end
  end

  assign arb_ifu_arvalid = byp_pending ? 1'b0 :
                           (ifu_cacheable ? icache_arvalid : byp_req);
  assign arb_ifu_araddr  = ifu_cacheable ? icache_araddr : pc_f;
  assign arb_ifu_arlen   = ifu_cacheable ? icache_arlen : 8'd0;

  assign f_resp_valid = byp_pending ? arb_ifu_rvalid : icache_inst_valid;
  assign f_resp_inst  = byp_pending ? arb_ifu_rdata  : icache_inst;
  assign f_req_ready  = byp_pending ? 1'b0 :
                        (ifu_cacheable ? icache_req_ready : (byp_state == 2'd0));

  IFU u_ifu(
    .clk(clk),
    .rst(rst),
    .redirect(ex_redirect),
    .redirect_pc(ex_redirect_pc),
    .flush_btb(cache_flush),
    .fetch_req_valid(f_req_valid),
    .fetch_req_ready(f_req_ready),
    .fetch_pc(pc_f),
    .fetch_resp_valid(f_resp_valid),
    .fetch_resp_inst(f_resp_inst),
    .fetch_resp_ready(f_resp_ready),
    .ifid_valid(ifid_valid),
    .ifid_inst(ifid_inst),
    .ifid_pc(ifid_pc),
    .d_advance(d_advance),
    .btb_update(btb_update),
    .btb_update_pc(ex_pc),
    .btb_update_target(ex_actual_target),
    .pc_out(),
    .btb_hit_out(btb_hit)
  );

  ICache u_icache(
    .clk(clk),
    .rst(rst),
    .flush(cache_flush),
    .cancel(cache_cancel),

    .fetch_req_valid(f_req_valid && ifu_cacheable && !byp_pending),
    .fetch_req_ready(icache_req_ready),
    .fetch_pc(pc_f),
    .fetch_inst_valid(icache_inst_valid),
    .fetch_inst(icache_inst),
    .fetch_inst_ready(f_resp_ready && !byp_pending),

    .perf_access(ic_perf_access),
    .perf_hit(ic_perf_hit),
    .perf_miss(ic_perf_miss),
    .perf_refill(ic_perf_refill),
    .perf_compulsory(ic_perf_compulsory),
    .perf_replace(ic_perf_replace),

    .arvalid(icache_arvalid),
    .arready(arb_ifu_arready),
    .araddr(icache_araddr),
    .arlen(icache_arlen),

    .rvalid(arb_ifu_rvalid),
    .rready(icache_rready),
    .rdata(arb_ifu_rdata),
    .rlast(arb_ifu_rlast)
  );

  // ======================= 输出端口 (non-SOC 仿真内存模型) =======================
`ifndef SOC_MODE
  wire mem_arvalid, mem_arready;
  wire [31:0] mem_araddr;
  wire [3:0] mem_arid;
  wire [7:0] mem_arlen;
  wire [2:0] mem_arsize;
  wire [1:0] mem_arburst;
  wire mem_rvalid, mem_rready;
  wire [1:0] mem_rresp;
  wire [31:0] mem_rdata;
  wire mem_rlast;
  wire [3:0] mem_rid;
  wire mem_awvalid, mem_awready;
  wire [31:0] mem_awaddr;
  wire [3:0] mem_awid;
  wire [7:0] mem_awlen;
  wire [2:0] mem_awsize;
  wire [1:0] mem_awburst;
  wire mem_wvalid, mem_wready;
  wire [31:0] mem_wdata;
  wire [3:0] mem_wstrb;
  wire mem_wlast;
  wire mem_bvalid, mem_bready;
  wire [1:0] mem_bresp;
  wire [3:0] mem_bid;
`endif

  Arbiter u_arbiter(
    .clk(clk),
    .rst(rst),
    .ifu_arvalid(arb_ifu_arvalid),
    .ifu_arready(arb_ifu_arready),
    .ifu_araddr(arb_ifu_araddr),
    .ifu_arlen(arb_ifu_arlen),
    .ifu_rvalid(arb_ifu_rvalid),
    .ifu_rready(arb_ifu_rready),
    .ifu_rdata(arb_ifu_rdata),
    .ifu_rlast(arb_ifu_rlast),
    .lsu_arvalid(lsu_arvalid),
    .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr),
    .lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize),
    .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid),
    .lsu_rready(lsu_rready),
    .lsu_rresp(lsu_rresp),
    .lsu_rdata(lsu_rdata),
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
    .mem_arvalid(mem_arvalid),
    .mem_arready(mem_arready),
    .mem_araddr(mem_araddr),
    .mem_arid(mem_arid),
    .mem_arlen(mem_arlen),
    .mem_arsize(mem_arsize),
    .mem_arburst(mem_arburst),
    .mem_rvalid(mem_rvalid),
    .mem_rready(mem_rready),
    .mem_rresp(mem_rresp),
    .mem_rdata(mem_rdata),
    .mem_rlast(mem_rlast),
    .mem_rid(mem_rid),
    .mem_awvalid(mem_awvalid),
    .mem_awready(mem_awready),
    .mem_awaddr(mem_awaddr),
    .mem_awid(mem_awid),
    .mem_awlen(mem_awlen),
    .mem_awsize(mem_awsize),
    .mem_awburst(mem_awburst),
    .mem_wvalid(mem_wvalid),
    .mem_wready(mem_wready),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_wlast(mem_wlast),
    .mem_bvalid(mem_bvalid),
    .mem_bready(mem_bready),
    .mem_bresp(mem_bresp),
    .mem_bid(mem_bid)
  );

  assign arb_ifu_rready = byp_pending ? byp_rready : icache_rready;

`ifndef SOC_MODE
`ifndef SYNTHESIS
  PMEM u_pmem(
    .clk(clk),
    .rst(rst),
    .mem_arvalid(mem_arvalid),
    .mem_arready(mem_arready),
    .mem_araddr(mem_araddr),
    .mem_arid(mem_arid),
    .mem_arlen(mem_arlen),
    .mem_arsize(mem_arsize),
    .mem_arburst(mem_arburst),
    .mem_rvalid(mem_rvalid),
    .mem_rready(mem_rready),
    .mem_rresp(mem_rresp),
    .mem_rdata(mem_rdata),
    .mem_rlast(mem_rlast),
    .mem_rid(mem_rid),
    .mem_awvalid(mem_awvalid),
    .mem_awready(mem_awready),
    .mem_awaddr(mem_awaddr),
    .mem_awid(mem_awid),
    .mem_awlen(mem_awlen),
    .mem_awsize(mem_awsize),
    .mem_awburst(mem_awburst),
    .mem_wvalid(mem_wvalid),
    .mem_wready(mem_wready),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_wlast(mem_wlast),
    .mem_bvalid(mem_bvalid),
    .mem_bready(mem_bready),
    .mem_bresp(mem_bresp),
    .mem_bid(mem_bid)
  );
`endif
`endif

`ifndef SOC_MODE
`ifdef SYNTHESIS
  reg synth_rvalid;
  reg [3:0] synth_rid;
  reg [31:0] synth_rdata;

  assign mem_arready = !synth_rvalid || mem_rready;
  assign mem_rvalid  = synth_rvalid;
  assign mem_rresp   = 2'b00;
  assign mem_rdata   = synth_rdata;
  assign mem_rlast   = 1'b1;
  assign mem_rid     = synth_rid;
  assign mem_awready = 1'b1;
  assign mem_wready  = 1'b1;
  assign mem_bvalid  = 1'b1;
  assign mem_bresp   = 2'b00;
  assign mem_bid     = 4'b0010;

  always @(posedge clk) begin
    if (rst) begin
      synth_rvalid <= 1'b0;
      synth_rid    <= 4'b0;
      synth_rdata  <= 32'b0;
    end else begin
      if (mem_rvalid && mem_rready) synth_rvalid <= 1'b0;
      if (mem_arvalid && mem_arready) begin
        synth_rvalid <= 1'b1;
        synth_rid    <= mem_arid;
        synth_rdata  <= (mem_arid == 4'b0001) ? imem_rdata : 32'b0;
      end
    end
  end
`endif
`endif

  // ======================= ebreak / trace / perf =======================
`ifndef SYNTHESIS
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val);
  import "DPI-C" function void mtrace_event(input int pc_val, input int addr, input int data, input int len, input int is_store);
  import "DPI-C" function void commit_instruction(input int pc_val, input int inst_val, input int next_pc_val);
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_csr_values(input int mstatus, input int mtvec, input int mepc, input int mcause, input int mcycle_lo, input int mcycle_hi);
  import "DPI-C" function void difftest_skip_ref();

`ifdef ENABLE_PERF
  localparam PERF_COMMIT       = 0;
  localparam PERF_IF_FETCH     = 1;
  localparam PERF_IF_STALL_BUS = 2;
  localparam PERF_IF_STALL_MEM = 3;
  localparam PERF_LD_DONE      = 4;
  localparam PERF_ST_DONE      = 5;
  localparam PERF_LD_WAIT      = 6;
  localparam PERF_ALU          = 7;
  localparam PERF_LOAD         = 8;
  localparam PERF_STORE        = 9;
  localparam PERF_BRANCH       = 10;
  localparam PERF_JUMP         = 11;
  localparam PERF_UPPER        = 12;
  localparam PERF_CSR          = 13;
  localparam PERF_ECALL        = 14;
  localparam PERF_MRET         = 15;
  localparam PERF_EBREAK       = 16;
  localparam PERF_IC_ACCESS    = 17;
  localparam PERF_IC_HIT       = 18;
  localparam PERF_IC_MISS      = 19;
  localparam PERF_IC_REFILL    = 20;
  localparam PERF_IC_MISS_AR   = 21;
  localparam PERF_IC_MISS_R    = 22;
  localparam PERF_IF_BYPASS    = 23;
  localparam PERF_BRANCH_TAKEN = 24;
  localparam PERF_BRANCH_NOT_TAKEN = 25;
  localparam PERF_JAL          = 26;
  localparam PERF_JALR         = 27;
  localparam PERF_LD_BYTE      = 28;
  localparam PERF_LD_HALF      = 29;
  localparam PERF_LD_WORD      = 30;
  localparam PERF_ST_BYTE      = 31;
  localparam PERF_ST_HALF      = 32;
  localparam PERF_ST_WORD      = 33;
  localparam PERF_BUS_AR       = 34;
  localparam PERF_BUS_R        = 35;
  localparam PERF_BUS_AW       = 36;
  localparam PERF_BUS_W        = 37;
  localparam PERF_BUS_B        = 38;
  localparam PERF_BUS_AR_STALL = 39;
  localparam PERF_IC_COMPULSORY = 40;
  localparam PERF_IC_REPLACE   = 41;
  localparam PERF_ALU_R        = 42;
  localparam PERF_ALU_I        = 43;
  localparam PERF_CSRRW        = 44;
  localparam PERF_CSRRS        = 45;
  localparam PERF_ST_WAIT      = 46;
  localparam PERF_FENCE_I      = 47;
  localparam PERF_BTB_PRED     = 48;
  localparam PERF_BTB_MISP     = 49;
  localparam PERF_BTB_ALLOC    = 50;
  localparam PERF_REDIRECT     = 51;
  localparam PERF_SQUASH       = 52;

  import "DPI-C" function void perf_event(input int event_id);

  wire perf_is_alu    = idex_is_alu;
  wire perf_is_branch = idex_is_branch;
  wire perf_is_upper  = idex_is_lui || idex_is_auipc;

  wire perf_if_fetch     = f_resp_valid && f_resp_ready;
  wire perf_if_bypass    = perf_if_fetch && byp_pending;
  wire perf_if_stall_bus = f_req_valid && !f_resp_valid && !byp_pending;
  wire perf_if_stall_mem = f_req_valid && !f_resp_valid && byp_pending;

  wire perf_ld_done = lsu_done && !mem_wen;
  wire perf_st_done = lsu_done && mem_wen;
  wire perf_ld_wait = mem_valid && !mem_wen && !lsu_done;
  wire perf_st_wait = mem_valid && mem_wen && !lsu_done;

  wire perf_btb_pred  = perf_if_fetch && btb_hit;
  wire perf_btb_misp  = ex_cf_redirect;
  wire perf_btb_alloc = btb_update;

  always @(posedge clk) begin
    if (!rst) begin
      if (commit)             perf_event(PERF_COMMIT);
      if (perf_if_fetch)      perf_event(PERF_IF_FETCH);
      if (perf_if_stall_bus)  perf_event(PERF_IF_STALL_BUS);
      if (perf_if_stall_mem)  perf_event(PERF_IF_STALL_MEM);
      if (perf_if_bypass)     perf_event(PERF_IF_BYPASS);
      if (perf_ld_done)       perf_event(PERF_LD_DONE);
      if (perf_st_done)       perf_event(PERF_ST_DONE);
      if (perf_ld_wait)       perf_event(PERF_LD_WAIT);
      if (perf_st_wait)       perf_event(PERF_ST_WAIT);

      if (ic_perf_access)     perf_event(PERF_IC_ACCESS);
      if (ic_perf_hit)        perf_event(PERF_IC_HIT);
      if (ic_perf_miss)       perf_event(PERF_IC_MISS);
      if (ic_perf_refill)     perf_event(PERF_IC_REFILL);
      if (ic_perf_compulsory) perf_event(PERF_IC_COMPULSORY);
      if (ic_perf_replace)    perf_event(PERF_IC_REPLACE);

      if (mem_arvalid && mem_arready) perf_event(PERF_BUS_AR);
      if (mem_rvalid && mem_rready)   perf_event(PERF_BUS_R);
      if (mem_awvalid && mem_awready) perf_event(PERF_BUS_AW);
      if (mem_wvalid && mem_wready)   perf_event(PERF_BUS_W);
      if (mem_bvalid && mem_bready)   perf_event(PERF_BUS_B);
      if (mem_arvalid && !mem_arready) perf_event(PERF_BUS_AR_STALL);

      if (commit) begin
        if (perf_is_alu) begin
          perf_event(PERF_ALU);
          if (idex_alu_rs2) perf_event(PERF_ALU_R);
          else              perf_event(PERF_ALU_I);
        end
        if (idex_is_load) begin
          perf_event(PERF_LOAD);
          if (ex_funct3 == 3'b000 || ex_funct3 == 3'b100) perf_event(PERF_LD_BYTE);
          else if (ex_funct3 == 3'b001 || ex_funct3 == 3'b101) perf_event(PERF_LD_HALF);
          else if (ex_funct3 == 3'b010) perf_event(PERF_LD_WORD);
        end
        if (idex_is_store) begin
          perf_event(PERF_STORE);
          if (ex_funct3 == 3'b000)      perf_event(PERF_ST_BYTE);
          else if (ex_funct3 == 3'b001) perf_event(PERF_ST_HALF);
          else if (ex_funct3 == 3'b010) perf_event(PERF_ST_WORD);
        end
        if (perf_is_branch) begin
          perf_event(PERF_BRANCH);
          if (branch_taken) perf_event(PERF_BRANCH_TAKEN);
          else              perf_event(PERF_BRANCH_NOT_TAKEN);
        end
        if (is_jump) begin
          perf_event(PERF_JUMP);
          if (idex_is_jal)  perf_event(PERF_JAL);
          if (idex_is_jalr) perf_event(PERF_JALR);
        end
        if (perf_is_upper)  perf_event(PERF_UPPER);
        if (idex_is_csr) begin
          perf_event(PERF_CSR);
          if (ex_funct3 == 3'b001) perf_event(PERF_CSRRW);
          if (ex_funct3 == 3'b010) perf_event(PERF_CSRRS);
        end
        if (idex_is_ecall)   perf_event(PERF_ECALL);
        if (idex_is_mret)    perf_event(PERF_MRET);
        if (idex_is_ebreak)  perf_event(PERF_EBREAK);
        if (idex_is_fence_i) perf_event(PERF_FENCE_I);
      end

      if (perf_btb_pred)   perf_event(PERF_BTB_PRED);
      if (perf_btb_misp)   perf_event(PERF_BTB_MISP);
      if (perf_btb_alloc)  perf_event(PERF_BTB_ALLOC);
      if (ex_redirect)     perf_event(PERF_REDIRECT);
      if (ex_redirect)     perf_event(PERF_SQUASH);
    end
  end
`endif

  always @(posedge clk) begin
    if (rst) begin
      update_pc_value(RESET_PC);
      update_csr_values(32'h00001800, 32'b0, 32'b0, 32'b0, 32'b0, 32'b0);
    end else begin
      update_csr_values(mstatus, mtvec, mepc, mcause, mcycle_lo, mcycle_hi);

      if (commit) begin
        commit_instruction(ex_pc, ex_inst, pc_next);
      end

      if (commit && mem_valid) begin
        mtrace_event(ex_pc, lsu_addr, idex_is_store ? ex_rs2_v : rdata,
                     (ex_funct3 == 3'b000 || ex_funct3 == 3'b100) ? 32'd1 :
                     (ex_funct3 == 3'b001 || ex_funct3 == 3'b101) ? 32'd2 : 32'd4,
                     {31'b0, idex_is_store});
      end

`ifdef SOC_MODE
      if (commit && mem_valid &&
          ((lsu_addr >= 32'h10000000 && lsu_addr < 32'h10020000) ||
           (lsu_addr >= 32'h21000000 && lsu_addr < 32'h22000000))) begin
        difftest_skip_ref();
      end
`endif

      if (idex_is_ebreak && commit) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x", ex_pc, a0_value);
        ebreak_handler(a0_value);
      end

      if (idex_is_jalr && commit) begin
        if (ex_rd == 5'd1) begin
          ftrace_call_handler(ex_pc, jump_target);
        end else if (ex_rd == 5'd0 && ex_rs1 == 5'd1) begin
          ftrace_ret_handler(ex_pc);
        end
      end

      if (idex_is_jal && ex_rd == 5'd1 && commit) begin
        ftrace_call_handler(ex_pc, branch_target);
      end
    end
  end
`endif

endmodule
