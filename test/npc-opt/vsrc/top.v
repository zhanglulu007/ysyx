//------------------------------------------------------------------------------
// top: 三级顺序流水线 NPC
//
//   IF  : PC -> ICache 组合查表 -> IF/ID
//   ID  : 译码 + 寄存器堆读 + 共享 adder（地址/分支目标/ALU 加减） -> ID/EX
//   EX  : ALU 逻辑/移位/比较 + 访存 FSM + 写回
//
//   * 命中时 1 指令/周期；I-Cache 缺失用流式填充，顺序取指可边填边取。
//   * BTB(8 项) + 2-bit BHT 做分支/跳转目标预测。
//   * 只有 EX->ID 一条前递通路；load-use 由 EX 多周期停顿自然覆盖。
//
// 保留原 top 的端口、AXI 接口、DPI-C 调试/性能探针。
//------------------------------------------------------------------------------
module top(
  input clk,
  input rst,
  input [31:0] imem_rdata,
  output reg [31:0] pc,
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

  localparam [31:0] BOOT_PC =
`ifdef SOC_MODE
    32'h3000_0000;
`else
    32'h8000_0000;
`endif

  localparam integer CACHE_SETS  = 8;
  localparam integer CACHE_WORDS = 4;
  localparam integer BTB_N       = 8;
  localparam integer BHT_N       = 8;

  localparam [3:0] ALU_ADD  = 4'd0;
  localparam [3:0] ALU_SUB  = 4'd1;
  localparam [3:0] ALU_AND  = 4'd2;
  localparam [3:0] ALU_OR   = 4'd3;
  localparam [3:0] ALU_XOR  = 4'd4;
  localparam [3:0] ALU_SLL  = 4'd5;
  localparam [3:0] ALU_SRL  = 4'd6;
  localparam [3:0] ALU_SRA  = 4'd7;
  localparam [3:0] ALU_SLT  = 4'd8;
  localparam [3:0] ALU_SLTU = 4'd9;

  localparam [2:0] WB_ALU  = 3'd0;
  localparam [2:0] WB_LOAD = 3'd1;
  localparam [2:0] WB_LINK = 3'd2;
  localparam [2:0] WB_IMMU = 3'd3;
  localparam [2:0] WB_CSR  = 3'd4;

  //==========================================================================
  // AXI wires
  //==========================================================================
  wire        ifu_arvalid, ifu_arready;
  wire [31:0] ifu_araddr;
  wire [ 7:0] ifu_arlen;
  wire        ifu_rvalid, ifu_rready;
  wire [31:0] ifu_rdata;
  wire        ifu_rlast;

  wire        lsu_arvalid, lsu_arready;
  wire [31:0] lsu_araddr;
  wire [ 3:0] lsu_arid;
  wire [ 7:0] lsu_arlen;
  wire [ 2:0] lsu_arsize;
  wire [ 1:0] lsu_arburst;
  wire        lsu_rvalid, lsu_rready;
  wire [ 1:0] lsu_rresp;
  wire [31:0] lsu_axi_rdata;
  wire [31:0] lsu_rdata;       // LSU 选择/扩展后的 load 数据
  wire        lsu_rlast;
  wire [ 3:0] lsu_rid;
  wire        lsu_awvalid, lsu_awready;
  wire [31:0] lsu_awaddr;
  wire [ 3:0] lsu_awid;
  wire [ 7:0] lsu_awlen;
  wire [ 2:0] lsu_awsize;
  wire [ 1:0] lsu_awburst;
  wire        lsu_wvalid, lsu_wready;
  wire [31:0] lsu_wdata;
  wire [ 3:0] lsu_wstrb;
  wire        lsu_wlast;
  wire        lsu_bvalid, lsu_bready;
  wire [ 1:0] lsu_bresp;
  wire [ 3:0] lsu_bid;
  wire        lsu_done;

`ifndef SOC_MODE
  wire        mem_arvalid, mem_arready;
  wire [31:0] mem_araddr;
  wire [ 3:0] mem_arid;
  wire [ 7:0] mem_arlen;
  wire [ 2:0] mem_arsize;
  wire [ 1:0] mem_arburst;
  wire        mem_rvalid, mem_rready;
  wire [ 1:0] mem_rresp;
  wire [31:0] mem_rdata;
  wire        mem_rlast;
  wire [ 3:0] mem_rid;
  wire        mem_awvalid, mem_awready;
  wire [31:0] mem_awaddr;
  wire [ 3:0] mem_awid;
  wire [ 7:0] mem_awlen;
  wire [ 2:0] mem_awsize;
  wire [ 1:0] mem_awburst;
  wire        mem_wvalid, mem_wready;
  wire [31:0] mem_wdata;
  wire [ 3:0] mem_wstrb;
  wire        mem_wlast;
  wire        mem_bvalid, mem_bready;
  wire [ 1:0] mem_bresp;
  wire [ 3:0] mem_bid;
`endif

  //==========================================================================
  // IF signals / BTB
  //==========================================================================
  wire [31:0] if_inst;
  wire        if_valid, if_hit, if_stall_ar, if_stall_mem;
  wire        icache_flush;

  reg [3:0]  btb_tag   [0:BTB_N-1];
  reg [31:0] btb_target[0:BTB_N-1];
  reg [BTB_N-1:0] btb_valid;
  reg [1:0]  bht [0:BHT_N-1];

  wire [2:0] btb_idx      = pc[4:2];
  wire [3:0] btb_tag_look = pc[8:5];
  wire [1:0] bht_cnt      = bht[pc[4:2]];
  wire       btb_hit      = btb_valid[btb_idx] && (btb_tag[btb_idx] == btb_tag_look);

  wire if_is_branch = (if_inst[6:0] == 7'b1100011);
  wire if_is_jal    = (if_inst[6:0] == 7'b1101111);
  wire if_is_jalr   = (if_inst[6:0] == 7'b1100111);
  wire if_is_ctrl   = if_is_branch || if_is_jal || if_is_jalr;

  wire       pred_taken    = if_valid && if_is_ctrl && btb_hit &&
                             (if_is_branch ? (bht_cnt >= 2'd2) : 1'b1);
  wire [31:0] btb_target_q = btb_target[btb_idx];
  wire [31:0] fetch_next_pc = pred_taken ? btb_target_q : (pc + 32'd4);

  //==========================================================================
  // IF/ID
  //==========================================================================
  reg        ifid_valid;
  reg [31:0] ifid_inst, ifid_pc;
  reg        ifid_pred_taken;
  reg [31:0] ifid_pred_target;

  //==========================================================================
  // ID signals
  //==========================================================================
  wire [4:0] id_rs1 = ifid_inst[19:15];
  wire [4:0] id_rs2 = ifid_inst[24:20];
  wire [4:0] id_rd  = ifid_inst[11:7];

  wire [31:0] rf_rs1, rf_rs2, a0_value;

  wire [4:0] dec_rd, dec_rs1, dec_rs2;
  wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  wire is_add, is_sub, is_and, is_or, is_xor;
  wire is_sll, is_srl, is_sra, is_slt, is_sltu;
  wire is_addi, is_slti, is_sltiu, is_xori, is_ori, is_andi;
  wire is_slli, is_srli, is_srai;
  wire is_lb_cls, is_lh_cls, is_lw_cls, is_lbu_cls, is_lhu_cls;
  wire is_sb_cls, is_sh_cls, is_sw_cls;
  wire is_beq, is_bne, is_blt, is_bge, is_bltu, is_bgeu;
  wire is_lui, is_auipc, is_jal, is_jalr;
  wire is_ebreak, is_ecall, is_mret;
  wire is_csrrw, is_csrrs;
  wire is_fence_i;
  wire dec_reg_wen, dec_mem_valid, dec_mem_wen, dec_csr_wen;
  wire op_r_type, op_load, op_store, is_jump;

  reg [3:0] id_alu_op;
  reg [2:0] id_wb_sel;
  reg [2:0] id_branch_op;
  reg       id_is_branch;
  reg [2:0] id_add_b_sel;   // 0=rs2,1=imm_i,2=imm_b,3=imm_j,4=imm_u
  reg       id_use_pc;
  reg       id_sub;
  reg [31:0] id_add_b;

  // EX -> ID bypass
  wire [31:0] ex_wb_data;
  wire        ex_wb_valid;
  wire id_rs1_bypass = ex_wb_valid && (id_rs1 != 5'd0) && (id_rs1 == idex_rd);
  wire id_rs2_bypass = ex_wb_valid && (id_rs2 != 5'd0) && (id_rs2 == idex_rd);
  wire [31:0] id_rs1_data = id_rs1_bypass ? ex_wb_data : rf_rs1;
  wire [31:0] id_rs2_data = id_rs2_bypass ? ex_wb_data : rf_rs2;

  //==========================================================================
  // ID/EX
  //==========================================================================
  reg        idex_valid;
  reg [31:0] idex_inst, idex_pc;
  reg [31:0] idex_rs1, idex_rs2, idex_alu_b;
  reg [31:0] idex_imm_u;
  reg [4:0]  idex_rd;
  reg [3:0]  idex_alu_op;
  reg [2:0]  idex_wb_sel;
  reg [2:0]  idex_branch_op;
  reg [4:0]  idex_shamt;
  reg [11:0] idex_csr_addr;
  reg        idex_reg_wen, idex_mem_read, idex_mem_write, idex_csr_wen;
  reg        idex_use_pc, idex_sub;
  reg        idex_is_branch, idex_is_jal, idex_is_jalr;
  reg        idex_is_ecall, idex_is_mret, idex_is_ebreak, idex_is_fence_i;
  reg        idex_pred_taken;
  reg [31:0] idex_pred_target;

  //==========================================================================
  // EX signals
  //==========================================================================
  wire [31:0] ex_alu_result;
  wire        ex_branch_taken;
  wire [31:0] ex_link_value;

  // EX 级共享 adder：地址 / 分支目标 / jal/jalr 目标 / auipc / ALU 加减
  wire [31:0] ex_add_a = idex_use_pc ? idex_pc : idex_rs1;
  wire [31:0] ex_add_result = ex_add_a + (idex_sub ? ~idex_alu_b : idex_alu_b) + {31'b0, idex_sub};

  wire ex_is_jump     = idex_is_jal || idex_is_jalr;
  wire ex_is_ctrl     = idex_is_branch || ex_is_jump;
  wire ex_mem_op      = idex_mem_read || idex_mem_write;
  wire ex_stall       = idex_valid && ex_mem_op && !lsu_done;
  wire ex_commit      = idex_valid && !ex_stall;

  wire ex_actual_taken = ex_is_jump || (idex_is_branch && ex_branch_taken);
  wire ex_pred_ok      = idex_pred_taken && (idex_pred_target == ex_add_result);
  wire ex_redirect_ctrl = idex_valid && ex_is_ctrl &&
                          (ex_actual_taken != idex_pred_taken ||
                           (ex_actual_taken && !ex_pred_ok));
  wire ex_redirect_sys = idex_valid &&
                         (idex_is_ecall || idex_is_mret ||
                          idex_is_ebreak || idex_is_fence_i);
  wire ex_redirect = ex_redirect_ctrl || ex_redirect_sys;

  //==========================================================================
  // CSR signals
  //==========================================================================
  wire [31:0] csr_rdata;
  wire [31:0] mstatus, mcause, mcycle_lo, mcycle_hi, mepc, mtvec;

  wire [31:0] ex_redirect_target =
      idex_is_ecall  ? mtvec :
      idex_is_mret   ? mepc :
      idex_is_ebreak ? idex_pc :
      idex_is_fence_i? (idex_pc + 32'd4) :
      (ex_actual_taken ? ex_add_result : (idex_pc + 32'd4));

  //==========================================================================
  // LSU control signals
  //==========================================================================
  wire [2:0] ex_funct3 = idex_inst[14:12];
  wire ex_is_load  = idex_mem_read;
  wire ex_is_store = idex_mem_write;
  wire ex_is_lb    = ex_is_load  && (ex_funct3 == 3'b000);
  wire ex_is_lh    = ex_is_load  && (ex_funct3 == 3'b001);
  wire ex_is_lw    = ex_is_load  && (ex_funct3 == 3'b010);
  wire ex_is_lbu   = ex_is_load  && (ex_funct3 == 3'b100);
  wire ex_is_lhu   = ex_is_load  && (ex_funct3 == 3'b101);
  wire ex_is_sb    = ex_is_store && (ex_funct3 == 3'b000);
  wire ex_is_sh    = ex_is_store && (ex_funct3 == 3'b001);
  wire ex_is_sw    = ex_is_store && (ex_funct3 == 3'b010);

  //==========================================================================
  // Core instantiations
  //==========================================================================
  assign imem_addr = pc;

  ICache #(.SETS(CACHE_SETS), .WORDS(CACHE_WORDS)) u_icache(
    .clk(clk),
    .rst(rst),
    .flush(icache_flush),
    .if_pc(pc),
    .if_inst(if_inst),
    .if_valid(if_valid),
    .if_hit(if_hit),
    .if_stall_ar(if_stall_ar),
    .if_stall_mem(if_stall_mem),
    .arvalid(ifu_arvalid),
    .arready(ifu_arready),
    .araddr(ifu_araddr),
    .arlen(ifu_arlen),
    .rvalid(ifu_rvalid),
    .rready(ifu_rready),
    .rdata(ifu_rdata),
    .rlast(ifu_rlast)
  );

  IDU u_idu(
    .inst(ifid_inst),
    .ifu_valid(ifid_valid),
    .rd(dec_rd), .rs1(dec_rs1), .rs2(dec_rs2),
    .imm_i(imm_i), .imm_s(imm_s), .imm_b(imm_b), .imm_u(imm_u), .imm_j(imm_j),
    .is_add(is_add), .is_sub(is_sub), .is_and(is_and), .is_or(is_or), .is_xor(is_xor),
    .is_sll(is_sll), .is_srl(is_srl), .is_sra(is_sra), .is_slt(is_slt), .is_sltu(is_sltu),
    .is_addi(is_addi), .is_slti(is_slti), .is_sltiu(is_sltiu), .is_xori(is_xori),
    .is_ori(is_ori), .is_andi(is_andi),
    .is_slli(is_slli), .is_srli(is_srli), .is_srai(is_srai),
    .is_lb(is_lb_cls), .is_lh(is_lh_cls), .is_lw(is_lw_cls),
    .is_lbu(is_lbu_cls), .is_lhu(is_lhu_cls),
    .is_sb(is_sb_cls), .is_sh(is_sh_cls), .is_sw(is_sw_cls),
    .is_beq(is_beq), .is_bne(is_bne), .is_blt(is_blt),
    .is_bge(is_bge), .is_bltu(is_bltu), .is_bgeu(is_bgeu),
    .is_lui(is_lui), .is_auipc(is_auipc), .is_jal(is_jal), .is_jalr(is_jalr),
    .is_ebreak(is_ebreak), .is_ecall(is_ecall), .is_mret(is_mret),
    .is_csrrw(is_csrrw), .is_csrrs(is_csrrs), .is_fence_i(is_fence_i),
    .reg_wen(dec_reg_wen), .mem_valid(dec_mem_valid), .mem_wen(dec_mem_wen),
    .csr_wen(dec_csr_wen),
    .op_r_type(op_r_type), .op_load(op_load), .op_store(op_store), .is_jump(is_jump)
  );

  always @(*) begin
    id_alu_op = ALU_ADD;
    case (1'b1)
      is_add  || is_addi : id_alu_op = ALU_ADD;
      is_sub             : id_alu_op = ALU_SUB;
      is_and  || is_andi : id_alu_op = ALU_AND;
      is_or   || is_ori  : id_alu_op = ALU_OR;
      is_xor  || is_xori : id_alu_op = ALU_XOR;
      is_sll  || is_slli : id_alu_op = ALU_SLL;
      is_srl  || is_srli : id_alu_op = ALU_SRL;
      is_sra  || is_srai : id_alu_op = ALU_SRA;
      is_slt  || is_slti : id_alu_op = ALU_SLT;
      is_sltu || is_sltiu: id_alu_op = ALU_SLTU;
      default            : id_alu_op = ALU_ADD;
    endcase

    if (is_jump)                    id_wb_sel = WB_LINK;
    else if (is_lui)                id_wb_sel = WB_IMMU;
    else if (op_load)               id_wb_sel = WB_LOAD;
    else if (is_csrrw || is_csrrs)  id_wb_sel = WB_CSR;
    else                            id_wb_sel = WB_ALU;

    id_branch_op = 3'd0;
    if (is_beq)       id_branch_op = 3'd0;
    else if (is_bne)  id_branch_op = 3'd1;
    else if (is_blt)  id_branch_op = 3'd2;
    else if (is_bge)  id_branch_op = 3'd3;
    else if (is_bltu) id_branch_op = 3'd4;
    else if (is_bgeu) id_branch_op = 3'd5;

    id_is_branch = is_beq || is_bne || is_blt || is_bge || is_bltu || is_bgeu;
    id_use_pc    = id_is_branch || is_jal || is_auipc;
    id_sub       = is_sub;

    if (id_is_branch)    id_add_b_sel = 3'd2;
    else if (is_jal)     id_add_b_sel = 3'd3;
    else if (is_auipc)   id_add_b_sel = 3'd4;
    else if (op_store)   id_add_b_sel = 3'd5;
    else if (op_r_type)  id_add_b_sel = 3'd0;
    else                 id_add_b_sel = 3'd1;

    case (id_add_b_sel)
      3'd0: id_add_b = id_rs2_data;
      3'd1: id_add_b = imm_i;
      3'd2: id_add_b = imm_b;
      3'd3: id_add_b = imm_j;
      3'd4: id_add_b = imm_u;
      3'd5: id_add_b = imm_s;
      default: id_add_b = imm_i;
    endcase
  end

  EXU u_exu(
    .rs1_data(idex_rs1),
    .rs2_data(idex_rs2),
    .alu_b(idex_alu_b),
    .add_result(ex_add_result),
    .pc(idex_pc),
    .shamt(idex_shamt),
    .alu_op(idex_alu_op),
    .branch_op(idex_branch_op),
    .is_branch(idex_is_branch),
    .alu_result(ex_alu_result),
    .branch_taken(ex_branch_taken),
    .link_value(ex_link_value)
  );

  RegisterFile u_regfile(
    .clk(clk),
    .rst(rst),
    .waddr(idex_rd),
    .wdata(ex_wb_data),
    .wen(ex_wb_valid),
    .raddr1(id_rs1),
    .rdata1(rf_rs1),
    .raddr2(id_rs2),
    .rdata2(rf_rs2),
    .a0_value(a0_value)
  );

  LSU u_lsu(
    .clk(clk), .rst(rst),
    .mem_valid(idex_valid && ex_mem_op),
    .mem_wen(idex_mem_write),
    .is_lb(ex_is_lb), .is_lh(ex_is_lh), .is_lw(ex_is_lw),
    .is_lbu(ex_is_lbu), .is_lhu(ex_is_lhu),
    .is_sb(ex_is_sb), .is_sh(ex_is_sh), .is_sw(ex_is_sw),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr), .lsu_arid(lsu_arid), .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready), .lsu_rresp(lsu_rresp),
    .lsu_rdata(lsu_axi_rdata), .lsu_rlast(lsu_rlast), .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr), .lsu_awid(lsu_awid), .lsu_awlen(lsu_awlen),
    .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready), .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready), .lsu_bresp(lsu_bresp),
    .lsu_bid(lsu_bid),
    .addr(ex_add_result), .wdata(idex_rs2),
    .rdata(lsu_rdata), .lsu_done(lsu_done)
  );

  wire        csr_is_rw  = (idex_inst[14:12] == 3'b001);
  wire [31:0] csr_wdata  = csr_is_rw ? idex_rs1 : (idex_rs1 | csr_rdata);
  wire        csr_wen_ex = idex_valid && idex_csr_wen && !ex_stall;
  wire        ecall_ex   = idex_valid && idex_is_ecall && !ex_stall;

  CSR u_csr(
    .clk(clk), .rst(rst),
    .csr_addr(idex_csr_addr),
    .csr_wdata(csr_wdata),
    .csr_wen(csr_wen_ex),
    .csr_rdata(csr_rdata),
    .is_ecall(ecall_ex),
    .pc(idex_pc),
    .mepc(mepc), .mtvec(mtvec),
    .mstatus_out(mstatus), .mcause_out(mcause),
    .mcycle_lo_out(mcycle_lo), .mcycle_hi_out(mcycle_hi)
  );

  wire [31:0] ex_wb_data_mux =
      (idex_wb_sel == WB_ALU)  ? ex_alu_result :
      (idex_wb_sel == WB_LOAD) ? lsu_rdata :
      (idex_wb_sel == WB_LINK) ? ex_link_value :
      (idex_wb_sel == WB_IMMU) ? idex_imm_u :
      (idex_wb_sel == WB_CSR)  ? csr_rdata : 32'b0;

  assign ex_wb_data  = ex_wb_data_mux;
  assign ex_wb_valid = idex_valid && idex_reg_wen && !ex_stall;
  assign icache_flush = idex_valid && idex_is_fence_i && !ex_stall;
  assign inst = idex_inst;

  //==========================================================================
  // IF/ID + PC 更新
  //==========================================================================
  always @(posedge clk) begin
    if (rst) begin
      pc <= BOOT_PC;
      ifid_valid <= 1'b0;
      ifid_inst  <= 32'h00000013;
      ifid_pc    <= BOOT_PC;
      ifid_pred_taken  <= 1'b0;
      ifid_pred_target <= 32'b0;
    end else if (ex_redirect) begin
      pc <= ex_redirect_target;
      ifid_valid <= 1'b0;
    end else if (ex_stall) begin
      // 保持
    end else if (if_valid) begin
      ifid_valid       <= 1'b1;
      ifid_inst        <= if_inst;
      ifid_pc          <= pc;
      ifid_pred_taken  <= pred_taken;
      ifid_pred_target <= btb_target_q;
      pc               <= fetch_next_pc;
    end else begin
      ifid_valid <= 1'b0;
    end
  end

  //==========================================================================
  // ID/EX 更新
  //==========================================================================
  always @(posedge clk) begin
    if (rst) begin
      idex_valid <= 1'b0;
      idex_reg_wen <= 1'b0;
      idex_mem_read <= 1'b0;
      idex_mem_write <= 1'b0;
      idex_csr_wen <= 1'b0;
      idex_is_branch <= 1'b0;
      idex_is_jal <= 1'b0;
      idex_is_jalr <= 1'b0;
      idex_is_ecall <= 1'b0;
      idex_is_mret <= 1'b0;
      idex_is_ebreak <= 1'b0;
      idex_is_fence_i <= 1'b0;
      idex_pred_taken <= 1'b0;
    end else if (ex_stall) begin
      // 保持
    end else if (ex_redirect) begin
      idex_valid <= 1'b0;
    end else begin
      idex_valid      <= ifid_valid;
      idex_inst       <= ifid_inst;
      idex_pc         <= ifid_pc;
      idex_rs1        <= id_rs1_data;
      idex_rs2        <= id_rs2_data;
      idex_alu_b      <= id_add_b;
      idex_use_pc     <= id_use_pc;
      idex_sub        <= id_sub;
      idex_imm_u      <= imm_u;
      idex_rd         <= id_rd;
      idex_alu_op     <= id_alu_op;
      idex_wb_sel     <= id_wb_sel;
      idex_branch_op  <= id_branch_op;
      idex_shamt      <= op_r_type ? id_rs2_data[4:0] : imm_i[4:0];
      idex_csr_addr   <= imm_i[11:0];
      idex_reg_wen    <= dec_reg_wen;
      idex_mem_read   <= dec_mem_valid && !dec_mem_wen;
      idex_mem_write  <= dec_mem_valid &&  dec_mem_wen;
      idex_csr_wen    <= dec_csr_wen;
      idex_is_branch  <= id_is_branch;
      idex_is_jal     <= is_jal;
      idex_is_jalr    <= is_jalr;
      idex_is_ecall   <= is_ecall;
      idex_is_mret    <= is_mret;
      idex_is_ebreak  <= is_ebreak;
      idex_is_fence_i <= is_fence_i;
      idex_pred_taken <= ifid_pred_taken;
      idex_pred_target<= ifid_pred_target;
    end
  end

  //==========================================================================
  // BTB / BHT 更新
  //==========================================================================
  wire ex_btb_update = ex_commit && ex_is_ctrl && ex_actual_taken;
  integer bi;
  always @(posedge clk) begin
    if (rst) begin
      btb_valid <= {BTB_N{1'b0}};
      for (bi = 0; bi < BHT_N; bi = bi + 1) bht[bi] <= 2'b10;
    end else begin
      if (ex_btb_update) begin
        btb_valid[idex_pc[4:2]]  <= 1'b1;
        btb_tag[idex_pc[4:2]]    <= idex_pc[8:5];
        btb_target[idex_pc[4:2]] <= ex_add_result;
      end
      if (ex_commit && idex_is_branch) begin
        if (ex_branch_taken)
          bht[idex_pc[4:2]] <= (bht[idex_pc[4:2]] == 2'b11) ? 2'b11 : (bht[idex_pc[4:2]] + 2'b01);
        else
          bht[idex_pc[4:2]] <= (bht[idex_pc[4:2]] == 2'b00) ? 2'b00 : (bht[idex_pc[4:2]] - 2'b01);
      end
    end
  end

  //==========================================================================
  // AXI Arbiter
  //==========================================================================
  Arbiter u_arbiter(
    .clk(clk), .rst(rst),
    .ifu_arvalid(ifu_arvalid), .ifu_arready(ifu_arready),
    .ifu_araddr(ifu_araddr), .ifu_arlen(ifu_arlen),
    .ifu_rvalid(ifu_rvalid), .ifu_rready(ifu_rready),
    .ifu_rdata(ifu_rdata), .ifu_rlast(ifu_rlast),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr), .lsu_arid(lsu_arid), .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready), .lsu_rresp(lsu_rresp),
    .lsu_rdata(lsu_axi_rdata), .lsu_rlast(lsu_rlast), .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr), .lsu_awid(lsu_awid), .lsu_awlen(lsu_awlen),
    .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready), .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready), .lsu_bresp(lsu_bresp),
    .lsu_bid(lsu_bid),
    .mem_arvalid(mem_arvalid), .mem_arready(mem_arready),
    .mem_araddr(mem_araddr), .mem_arid(mem_arid), .mem_arlen(mem_arlen),
    .mem_arsize(mem_arsize), .mem_arburst(mem_arburst),
    .mem_rvalid(mem_rvalid), .mem_rready(mem_rready), .mem_rresp(mem_rresp),
    .mem_rdata(mem_rdata), .mem_rlast(mem_rlast), .mem_rid(mem_rid),
    .mem_awvalid(mem_awvalid), .mem_awready(mem_awready),
    .mem_awaddr(mem_awaddr), .mem_awid(mem_awid), .mem_awlen(mem_awlen),
    .mem_awsize(mem_awsize), .mem_awburst(mem_awburst),
    .mem_wvalid(mem_wvalid), .mem_wready(mem_wready), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_wlast(mem_wlast),
    .mem_bvalid(mem_bvalid), .mem_bready(mem_bready), .mem_bresp(mem_bresp),
    .mem_bid(mem_bid)
  );

  //==========================================================================
  // Standalone memory model
  //==========================================================================
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
`else
  PMEM u_pmem(
    .clk(clk), .rst(rst),
    .mem_arvalid(mem_arvalid), .mem_arready(mem_arready),
    .mem_araddr(mem_araddr), .mem_arid(mem_arid), .mem_arlen(mem_arlen),
    .mem_arsize(mem_arsize), .mem_arburst(mem_arburst),
    .mem_rvalid(mem_rvalid), .mem_rready(mem_rready), .mem_rresp(mem_rresp),
    .mem_rdata(mem_rdata), .mem_rlast(mem_rlast), .mem_rid(mem_rid),
    .mem_awvalid(mem_awvalid), .mem_awready(mem_awready),
    .mem_awaddr(mem_awaddr), .mem_awid(mem_awid), .mem_awlen(mem_awlen),
    .mem_awsize(mem_awsize), .mem_awburst(mem_awburst),
    .mem_wvalid(mem_wvalid), .mem_wready(mem_wready),
    .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_wlast(mem_wlast),
    .mem_bvalid(mem_bvalid), .mem_bready(mem_bready),
    .mem_bresp(mem_bresp), .mem_bid(mem_bid)
  );
`endif
`endif

  //==========================================================================
  // DPI-C trace / difftest / perf
  //==========================================================================
`ifndef SYNTHESIS
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val);
  import "DPI-C" function void mtrace_event(input int pc_val, input int addr, input int data, input int len, input int is_store);
  import "DPI-C" function void commit_instruction(input int pc_val, input int inst_val, input int next_pc_val);
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_csr_values(input int mstatus, input int mtvec, input int mepc, input int mcause, input int mcycle_lo, input int mcycle_hi);
  import "DPI-C" function void difftest_skip_ref();

  wire [6:0] ex_opcode = idex_inst[6:0];
  wire [2:0] ex_f3     = idex_inst[14:12];
  wire [6:0] ex_f7     = idex_inst[31:25];

  wire ex_op_r_type  = (ex_opcode == 7'b0110011);
  wire ex_op_i_arith = (ex_opcode == 7'b0010011);
  wire ex_op_load    = (ex_opcode == 7'b0000011);
  wire ex_op_store   = (ex_opcode == 7'b0100011);
  wire ex_op_branch  = (ex_opcode == 7'b1100011);
  wire ex_op_lui     = (ex_opcode == 7'b0110111);
  wire ex_op_auipc   = (ex_opcode == 7'b0010111);
  wire ex_op_jal     = (ex_opcode == 7'b1101111);
  wire ex_op_jalr    = (ex_opcode == 7'b1100111);
  wire ex_op_system  = (ex_opcode == 7'b1110011);
  wire ex_is_jal_s   = ex_op_jal;
  wire ex_is_jalr_s  = ex_op_jalr && (ex_f3 == 3'b000);
  wire ex_is_branch_s= ex_op_branch;
  wire ex_is_csr     = ex_op_system && (ex_f3 == 3'b001 || ex_f3 == 3'b010 ||
                                        ex_f3 == 3'b011 || ex_f3 == 3'b101 ||
                                        ex_f3 == 3'b110 || ex_f3 == 3'b111);
  wire ex_is_ebreak  = (idex_inst == 32'h00100073);
  wire ex_is_ecall   = (idex_inst == 32'h00000073);
  wire ex_is_mret    = (idex_inst == 32'h30200073);
  wire ex_is_fence_i = (idex_inst == 32'h0000100F);
  wire ex_is_alu     = ex_op_r_type || ex_op_i_arith;
  wire ex_is_upper   = ex_op_lui || ex_op_auipc;
  wire ex_is_jump_s  = ex_is_jal_s || ex_is_jalr_s;
  wire ex_is_mem     = ex_op_load || ex_op_store;
  wire [31:0] ex_mem_addr = ex_add_result;
  wire [31:0] ex_mem_wdata = idex_rs2;
  wire [2:0]  ex_mem_len = (ex_is_lb || ex_is_lbu || ex_is_sb) ? 3'd1 :
                           (ex_is_lh || ex_is_lhu || ex_is_sh) ? 3'd2 : 3'd4;

  wire commit = ex_commit;
  wire [31:0] commit_pc = idex_pc;
  wire [31:0] commit_inst = idex_inst;
  wire [31:0] commit_next_pc =
      idex_is_ecall  ? mtvec :
      idex_is_mret   ? mepc :
      idex_is_ebreak ? idex_pc :
      idex_is_fence_i? (idex_pc + 32'd4) :
      ex_is_ctrl     ? (ex_actual_taken ? ex_add_result : (idex_pc + 32'd4)) :
                       (idex_pc + 32'd4);
  wire [31:0] trace_next_pc = commit_next_pc;

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
  localparam PERF_BRANCH_MISPREDICT = 48;
  localparam PERF_IF_SQUASH     = 49;

  import "DPI-C" function void perf_event(input int event_id);

  wire if_take = if_valid && !ex_stall && !ex_redirect;
  wire ic_access_ev = if_take;
  wire ic_hit_ev    = if_take && if_hit;
  wire ic_miss_ev   = if_take && !if_hit;
  wire perf_ld_done = ex_commit && ex_op_load;
  wire perf_st_done = ex_commit && ex_op_store;
  wire perf_ld_wait = ex_stall && idex_mem_read;
  wire perf_st_wait = ex_stall && idex_mem_write;

  always @(posedge clk) begin
    if (!rst) begin
      if (ex_commit)                    perf_event(PERF_COMMIT);
      if (if_take)                      perf_event(PERF_IF_FETCH);
      if (if_stall_ar)                  perf_event(PERF_IF_STALL_BUS);
      if (if_stall_mem)                 perf_event(PERF_IF_STALL_MEM);
      if (perf_ld_done)                 perf_event(PERF_LD_DONE);
      if (perf_st_done)                 perf_event(PERF_ST_DONE);
      if (perf_ld_wait)                 perf_event(PERF_LD_WAIT);
      if (perf_st_wait)                 perf_event(PERF_ST_WAIT);

      if (ic_access_ev)                 perf_event(PERF_IC_ACCESS);
      if (ic_hit_ev)                    perf_event(PERF_IC_HIT);
      if (ic_miss_ev)                   perf_event(PERF_IC_MISS);
      if (ifu_arvalid && ifu_arready)   perf_event(PERF_IC_REFILL);
      if (if_stall_ar)                  perf_event(PERF_IC_MISS_AR);
      if (if_stall_mem)                 perf_event(PERF_IC_MISS_R);

      if (mem_arvalid && mem_arready)   perf_event(PERF_BUS_AR);
      if (mem_rvalid  && mem_rready)    perf_event(PERF_BUS_R);
      if (mem_awvalid && mem_awready)   perf_event(PERF_BUS_AW);
      if (mem_wvalid  && mem_wready)    perf_event(PERF_BUS_W);
      if (mem_bvalid  && mem_bready)    perf_event(PERF_BUS_B);
      if (mem_arvalid && !mem_arready)  perf_event(PERF_BUS_AR_STALL);

      if (ex_redirect && (idex_is_branch || ex_is_jump))
        perf_event(PERF_BRANCH_MISPREDICT);
      if (ex_redirect && (ifid_valid || ex_is_ctrl))
        perf_event(PERF_IF_SQUASH);

      if (ex_commit) begin
        if (ex_is_alu) begin
          perf_event(PERF_ALU);
          if (ex_op_r_type) perf_event(PERF_ALU_R);
          else              perf_event(PERF_ALU_I);
        end
        if (ex_op_load) begin
          perf_event(PERF_LOAD);
          if (ex_is_lb || ex_is_lbu)      perf_event(PERF_LD_BYTE);
          else if (ex_is_lh || ex_is_lhu) perf_event(PERF_LD_HALF);
          else if (ex_is_lw)              perf_event(PERF_LD_WORD);
        end
        if (ex_op_store) begin
          perf_event(PERF_STORE);
          if (ex_is_sb)      perf_event(PERF_ST_BYTE);
          else if (ex_is_sh) perf_event(PERF_ST_HALF);
          else if (ex_is_sw) perf_event(PERF_ST_WORD);
        end
        if (ex_is_branch_s) begin
          perf_event(PERF_BRANCH);
          if (ex_branch_taken) perf_event(PERF_BRANCH_TAKEN);
          else                 perf_event(PERF_BRANCH_NOT_TAKEN);
        end
        if (ex_is_jump_s) begin
          perf_event(PERF_JUMP);
          if (ex_is_jal_s)  perf_event(PERF_JAL);
          if (ex_is_jalr_s) perf_event(PERF_JALR);
        end
        if (ex_is_upper) perf_event(PERF_UPPER);
        if (ex_is_csr) begin
          perf_event(PERF_CSR);
          if (ex_f3 == 3'b001) perf_event(PERF_CSRRW);
          if (ex_f3 == 3'b010) perf_event(PERF_CSRRS);
        end
        if (ex_is_ecall)  perf_event(PERF_ECALL);
        if (ex_is_mret)   perf_event(PERF_MRET);
        if (ex_is_ebreak) perf_event(PERF_EBREAK);
        if (ex_is_fence_i)perf_event(PERF_FENCE_I);
      end
    end
  end
`endif

  always @(posedge clk) begin
    if (rst) begin
      update_pc_value(BOOT_PC);
      update_csr_values(32'h00001800, 32'b0, 32'b0, 32'b0, 32'b0, 32'b0);
    end else begin
      update_csr_values(mstatus, mtvec, mepc, mcause, mcycle_lo, mcycle_hi);

      if (commit) begin
        commit_instruction(commit_pc, commit_inst, trace_next_pc);
      end

      if (commit && ex_is_mem) begin
        mtrace_event(commit_pc, ex_mem_addr,
                     ex_op_store ? ex_mem_wdata : lsu_rdata,
                     {29'b0, ex_mem_len}, {31'b0, ex_op_store});
      end

`ifdef SOC_MODE
      if (commit && ex_is_mem &&
          ((ex_mem_addr >= 32'h10000000 && ex_mem_addr < 32'h10020000) ||
           (ex_mem_addr >= 32'h21000000 && ex_mem_addr < 32'h22000000))) begin
        difftest_skip_ref();
      end
`endif

      if (ex_is_ebreak && commit) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x", commit_pc, a0_value);
        ebreak_handler(a0_value);
      end

      if (ex_is_jalr_s && commit) begin
        if (idex_rd == 5'd1) begin
          ftrace_call_handler(commit_pc, ex_redirect_target);
        end else if (idex_rd == 5'd0 && idex_inst[19:15] == 5'd1) begin
          ftrace_ret_handler(commit_pc);
        end
      end

      if (ex_is_jal_s && idex_rd == 5'd1 && commit) begin
        ftrace_call_handler(commit_pc, ex_redirect_target);
      end
    end
  end
`endif

endmodule
