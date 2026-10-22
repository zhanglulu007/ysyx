// ============================================================================
//  top - 三阶段流水线 NPC
//
//  ID  : FIFO/ICache -> 译码 + 寄存器堆读 + 前递 + 操作数/控制寄存
//  EX  : ALU / 分支解析 / LSU 发起 / CSR 读 / 重定向 / 提交(commit)
//  WB  : 寄存器堆写回 + CSR 写回
//
//  取指仍由 8 项 FIFO + 128B 流式 ICache 支撑; FIFO 空时 ICache 输出
//  直接旁路进 ID, 避免多耗一拍.
// ============================================================================
module top(
  input  clk,
  input  rst,
  input  [31:0] imem_rdata,
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
  localparam [31:0] BOOT_PC = 32'h3000_0000;
`else
  localparam [31:0] BOOT_PC = 32'h8000_0000;
`endif

  // =====================================================================
  //  IFU / ICache
  // =====================================================================
  wire [31:0] ifu_pc, ifu_inst;
  wire        ifu_valid, ifu_head_miss;

  wire [31:0] ic_out_data;
  wire        ic_out_valid, ic_out_ready, ic_line_miss;
  wire [31:0] ic_fetch_addr;

  wire [31:0] ifu_araddr;
  wire [7:0]  ifu_arlen;
  wire        ifu_arvalid, ifu_arready;
  wire        ifu_rvalid, ifu_rready, ifu_rlast;
  wire [31:0] ifu_rdata;

  // =====================================================================
  //  ID 级寄存器
  // =====================================================================
  reg [31:0] id_inst, id_pc;
  reg        id_valid, id_miss;

  // ID 译码
  wire [4:0] rd, rs1, rs2;
  wire [3:0] alu_op;
  wire [1:0] alu_a_sel, alu_b_sel, wb_sel;
  wire [3:0] mem_op;
  wire [1:0] csr_op;
  wire       dec_reg_wen, dec_is_branch, dec_is_jal, dec_is_jalr;
  wire       dec_is_ecall, dec_is_mret, dec_is_ebreak, dec_is_fence_i;
  wire       dec_is_load, dec_is_store;
  wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  // 寄存器堆读
  wire [31:0] rf_rs1, rf_rs2;
  wire [31:0] a0_rf;

  // =====================================================================
  //  EX 级寄存器
  // =====================================================================
  reg        ex_valid;
  reg [31:0] ex_pc, ex_inst;
  reg [31:0] ex_op_a, ex_op_b, ex_rs2;
  reg [31:0] ex_pc_plus4, ex_pc_target;
  reg [3:0]  ex_alu_op, ex_mem_op;
  reg [2:0]  ex_funct3;
  reg [1:0]  ex_wb_sel, ex_csr_op;
  reg [11:0] ex_csr_addr;
  reg [4:0]  ex_rd;
  reg        ex_reg_wen, ex_is_branch, ex_is_jal, ex_is_jalr;
  reg        ex_is_ecall, ex_is_mret, ex_is_ebreak, ex_is_fence_i;
  reg        ex_miss;

  // CSR 输出
  wire [31:0] mepc, mtvec, mstatus, mcause, mcycle_lo, mcycle_hi;
  wire [31:0] csr_rdata_raw;

  // =====================================================================
  //  WB 级寄存器
  // =====================================================================
  reg [31:0] wb_data, wb_csr_wdata;
  reg [11:0] wb_csr_addr;
  reg [4:0]  wb_rd;
  reg        wb_wen, wb_csr_wen;

  // =====================================================================
  //  ID 级: 前递 + 操作数选择
  // =====================================================================
  wire [31:0] ex_alu_result;
  wire        ex_branch_taken;
  wire [31:0] ex_csr_rdata = (wb_csr_wen && (wb_csr_addr == ex_csr_addr)) ? wb_csr_wdata : csr_rdata_raw;
  wire [31:0] ex_wb_data;

  wire ex_fwd_wen = ex_valid && ex_reg_wen && (ex_rd != 5'b0);
  wire wb_fwd_wen = wb_wen && (wb_rd != 5'b0);

  wire [31:0] rs1_fwd = (ex_fwd_wen && (ex_rd == rs1)) ? ex_wb_data :
                        (wb_fwd_wen && (wb_rd == rs1)) ? wb_data : rf_rs1;
  wire [31:0] rs2_fwd = (ex_fwd_wen && (ex_rd == rs2)) ? ex_wb_data :
                        (wb_fwd_wen && (wb_rd == rs2)) ? wb_data : rf_rs2;

  wire [31:0] id_src_a = (alu_a_sel == 2'd1) ? id_pc :
                         (alu_a_sel == 2'd2) ? 32'b0 : rs1_fwd;
  wire [31:0] id_src_b = (alu_b_sel == 2'd1) ? imm_i :
                         (alu_b_sel == 2'd2) ? imm_s :
                         (alu_b_sel == 2'd3) ? imm_u : rs2_fwd;

  wire [31:0] id_pc_plus4  = id_pc + 32'd4;
  wire [31:0] id_pc_target = id_pc + (dec_is_jal ? imm_j : imm_b);

  // =====================================================================
  //  ID 装载 / FIFO 弹出
  // =====================================================================
  wire ic_fill_fire   = ic_out_valid && ic_out_ready;
  wire [31:0] id_load_inst  = ifu_valid ? ifu_inst      : ic_out_data;
  wire [31:0] id_load_pc    = ifu_valid ? ifu_pc        : ic_fetch_addr;
  wire        id_load_miss  = ifu_valid ? ifu_head_miss : ic_line_miss;
  wire        id_load_valid = ifu_valid || ic_fill_fire;

  // =====================================================================
  //  EX 级: 访存 / CSR / 重定向 / 提交
  // =====================================================================
  wire ex_is_load  = (ex_mem_op >= 4'd1) && (ex_mem_op <= 4'd5);
  wire ex_is_store = (ex_mem_op >= 4'd6) && (ex_mem_op <= 4'd8);
  wire ex_mem_valid = ex_valid && (ex_is_load || ex_is_store);

  wire [31:0] lsu_rdata_ext;
  wire        lsu_done;

  wire ex_stall  = ex_mem_valid && !lsu_done;
  wire ex_commit = ex_valid && !ex_stall;

  wire ex_redirect = ex_commit && (ex_is_jal || ex_is_jalr || ex_branch_taken ||
                                   ex_is_ecall || ex_is_mret || ex_is_fence_i ||
                                   ex_is_ebreak);

  // CSR 写 (WB) 与 EX 读同拍时前递, 避免 CSR 指令停顿
  wire [31:0] mepc_fwd  = (wb_csr_wen && (wb_csr_addr == 12'h341)) ? wb_csr_wdata : mepc;
  wire [31:0] mtvec_fwd = (wb_csr_wen && (wb_csr_addr == 12'h305)) ? wb_csr_wdata : mtvec;

  wire [31:0] ex_pc_next = ex_is_ecall ? mtvec_fwd :
                           ex_is_mret  ? mepc_fwd :
                           ex_is_jalr  ? {ex_alu_result[31:1], 1'b0} :
                           (ex_is_jal || ex_branch_taken) ? ex_pc_target :
                           ex_is_ebreak ? ex_pc : ex_pc_plus4;

  wire ex_flush_i = ex_commit && ex_is_fence_i;

  wire [31:0] ex_csr_wdata = (ex_csr_op == 2'd1) ? ex_op_a : (ex_op_a | ex_csr_rdata);

  assign ex_wb_data = (ex_wb_sel == 2'd1) ? ex_pc_plus4 :
                      (ex_wb_sel == 2'd2) ? lsu_rdata_ext :
                      (ex_wb_sel == 2'd3) ? ex_csr_rdata : ex_alu_result;

  wire load_next = !ex_redirect && !ex_stall && id_load_valid;

  // =====================================================================
  //  流水线寄存器
  // =====================================================================
  always @(posedge clk) begin
    if (rst) begin
      id_inst  <= 32'b0;
      id_pc    <= BOOT_PC;
      id_valid <= 1'b0;
      id_miss  <= 1'b0;

      ex_valid <= 1'b0;
      ex_pc <= 32'b0; ex_inst <= 32'b0;
      ex_op_a <= 32'b0; ex_op_b <= 32'b0; ex_rs2 <= 32'b0;
      ex_pc_plus4 <= 32'b0; ex_pc_target <= 32'b0;
      ex_alu_op <= 4'b0; ex_mem_op <= 4'b0; ex_funct3 <= 3'b0;
      ex_wb_sel <= 2'b0; ex_csr_op <= 2'b0; ex_csr_addr <= 12'b0;
      ex_rd <= 5'b0; ex_reg_wen <= 1'b0;
      ex_is_branch <= 1'b0; ex_is_jal <= 1'b0; ex_is_jalr <= 1'b0;
      ex_is_ecall <= 1'b0; ex_is_mret <= 1'b0;
      ex_is_ebreak <= 1'b0; ex_is_fence_i <= 1'b0;
      ex_miss <= 1'b0;

      wb_data <= 32'b0; wb_rd <= 5'b0; wb_wen <= 1'b0;
      wb_csr_wdata <= 32'b0; wb_csr_addr <= 12'b0; wb_csr_wen <= 1'b0;
    end else if (!ex_stall) begin
      // ---------------- WB 接收 EX 结果 ----------------
      wb_data      <= ex_wb_data;
      wb_rd        <= ex_rd;
      wb_wen       <= ex_valid && ex_reg_wen && (ex_rd != 5'b0);
      wb_csr_wdata <= ex_csr_wdata;
      wb_csr_addr  <= ex_csr_addr;
      wb_csr_wen   <= ex_valid && (ex_csr_op != 2'b0);

      // ---------------- EX 接收 ID / 重定向清空 ----------------
      if (ex_redirect) begin
        ex_valid <= 1'b0;
        id_valid <= 1'b0;
      end else begin
        ex_valid     <= id_valid;
        ex_pc        <= id_pc;
        ex_inst      <= id_inst;
        ex_op_a      <= id_src_a;
        ex_op_b      <= id_src_b;
        ex_rs2       <= rs2_fwd;
        ex_pc_plus4  <= id_pc_plus4;
        ex_pc_target <= id_pc_target;
        ex_alu_op    <= alu_op;
        ex_mem_op    <= mem_op;
        ex_funct3    <= id_inst[14:12];
        ex_wb_sel    <= wb_sel;
        ex_csr_op    <= csr_op;
        ex_csr_addr  <= id_inst[31:20];
        ex_rd        <= rd;
        ex_reg_wen   <= dec_reg_wen;
        ex_is_branch <= dec_is_branch;
        ex_is_jal    <= dec_is_jal;
        ex_is_jalr   <= dec_is_jalr;
        ex_is_ecall  <= dec_is_ecall;
        ex_is_mret   <= dec_is_mret;
        ex_is_ebreak <= dec_is_ebreak;
        ex_is_fence_i<= dec_is_fence_i;
        ex_miss      <= id_miss;

        // ---------------- ID 装载下一条 ----------------
        id_inst  <= id_load_inst;
        id_pc    <= id_load_pc;
        id_valid <= id_load_valid;
        id_miss  <= id_load_miss;
      end
    end
  end

  assign pc        = ex_pc;
  assign inst      = ex_inst;
  assign imem_addr = ic_fetch_addr;

  // =====================================================================
  //  IFU / ICache
  // =====================================================================
  IFU #(.BOOT_PC(BOOT_PC)) u_ifu(
    .clk(clk), .rst(rst),
    .redirect(ex_redirect),
    .redirect_addr(ex_pc_next),
    .fill_data(ic_out_data),
    .fill_valid(ic_out_valid),
    .fill_miss(ic_line_miss),
    .fill_ready(ic_out_ready),
    .inst(ifu_inst),
    .pc(ifu_pc),
    .valid(ifu_valid),
    .head_miss(ifu_head_miss),
    .pop(load_next)
  );

  ICache #(.BOOT_PC(BOOT_PC)) u_icache(
    .clk(clk), .rst(rst),
    .flush(ex_flush_i),
    .redirect(ex_redirect),
    .redirect_addr(ex_pc_next),
    .fetch_addr(ic_fetch_addr),
    .out_valid(ic_out_valid),
    .out_data(ic_out_data),
    .out_ready(ic_out_ready),
    .line_miss(ic_line_miss),
    .arvalid(ifu_arvalid),
    .arready(ifu_arready),
    .araddr(ifu_araddr),
    .arlen(ifu_arlen),
    .rvalid(ifu_rvalid),
    .rready(ifu_rready),
    .rdata(ifu_rdata),
    .rlast(ifu_rlast)
  );

  // =====================================================================
  //  ID 级译码 + 寄存器堆
  // =====================================================================
  IDU u_idu(
    .inst(id_inst),
    .rd(rd), .rs1(rs1), .rs2(rs2),
    .alu_op(alu_op),
    .alu_a_sel(alu_a_sel),
    .alu_b_sel(alu_b_sel),
    .wb_sel(wb_sel),
    .mem_op(mem_op),
    .csr_op(csr_op),
    .reg_wen(dec_reg_wen),
    .is_branch(dec_is_branch),
    .is_jal(dec_is_jal),
    .is_jalr(dec_is_jalr),
    .is_ecall(dec_is_ecall),
    .is_mret(dec_is_mret),
    .is_ebreak(dec_is_ebreak),
    .is_fence_i(dec_is_fence_i),
    .is_load(dec_is_load),
    .is_store(dec_is_store),
    .imm_i(imm_i), .imm_s(imm_s), .imm_b(imm_b),
    .imm_u(imm_u), .imm_j(imm_j)
  );

  RegisterFile u_regfile(
    .clk(clk), .rst(rst),
    .wdata(wb_data),
    .waddr(wb_rd),
    .wen(wb_wen),
    .raddr1(rs1),
    .rdata1(rf_rs1),
    .raddr2(rs2),
    .rdata2(rf_rs2),
    .a0_value(a0_rf)
  );

  // =====================================================================
  //  EX 级 ALU + LSU + CSR
  // =====================================================================
  ALU u_alu(
    .a(ex_op_a),
    .b(ex_op_b),
    .alu_op(ex_alu_op),
    .is_branch(ex_is_branch),
    .funct3(ex_funct3),
    .result(ex_alu_result),
    .branch_taken(ex_branch_taken)
  );

  // LSU AXI 线
  wire        lsu_arvalid, lsu_arready;
  wire [31:0] lsu_araddr;
  wire [3:0]  lsu_arid;
  wire [7:0]  lsu_arlen;
  wire [2:0]  lsu_arsize;
  wire [1:0]  lsu_arburst;
  wire        lsu_rvalid, lsu_rready;
  wire [1:0]  lsu_rresp;
  wire [31:0] lsu_rdata;
  wire        lsu_rlast;
  wire [3:0]  lsu_rid;
  wire        lsu_awvalid, lsu_awready;
  wire [31:0] lsu_awaddr;
  wire [3:0]  lsu_awid;
  wire [7:0]  lsu_awlen;
  wire [2:0]  lsu_awsize;
  wire [1:0]  lsu_awburst;
  wire        lsu_wvalid, lsu_wready;
  wire [31:0] lsu_wdata;
  wire [3:0]  lsu_wstrb;
  wire        lsu_wlast;
  wire        lsu_bvalid, lsu_bready;
  wire [1:0]  lsu_bresp;
  wire [3:0]  lsu_bid;

  LSU u_lsu(
    .clk(clk), .rst(rst),
    .mem_valid(ex_mem_valid),
    .mem_wen(ex_valid && ex_is_store),
    .mem_op(ex_mem_op),
    .addr(ex_alu_result),
    .wdata(ex_rs2),
    .rdata(lsu_rdata_ext),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr), .lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen), .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready),
    .lsu_rresp(lsu_rresp), .lsu_rdata(lsu_rdata), .lsu_rlast(lsu_rlast),
    .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr), .lsu_awid(lsu_awid),
    .lsu_awlen(lsu_awlen), .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready),
    .lsu_wdata(lsu_wdata), .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp), .lsu_bid(lsu_bid),
    .lsu_done(lsu_done)
  );

  CSR u_csr(
    .clk(clk), .rst(rst),
    .csr_raddr(ex_csr_addr),
    .csr_waddr(wb_csr_addr),
    .csr_wdata(wb_csr_wdata),
    .csr_wen(wb_csr_wen),
    .csr_rdata(csr_rdata_raw),
    .ecall_commit(ex_commit && ex_is_ecall),
    .pc(ex_pc),
    .mepc(mepc), .mtvec(mtvec),
    .mstatus_out(mstatus), .mcause_out(mcause),
    .mcycle_lo_out(mcycle_lo), .mcycle_hi_out(mcycle_hi)
  );

  // =====================================================================
  //  AXI 仲裁与存储
  // =====================================================================
`ifndef SOC_MODE
  wire        mem_arvalid, mem_arready;
  wire [31:0] mem_araddr;
  wire [3:0]  mem_arid;
  wire [7:0]  mem_arlen;
  wire [2:0]  mem_arsize;
  wire [1:0]  mem_arburst;
  wire        mem_rvalid, mem_rready;
  wire [1:0]  mem_rresp;
  wire [31:0] mem_rdata;
  wire        mem_rlast;
  wire [3:0]  mem_rid;
  wire        mem_awvalid, mem_awready;
  wire [31:0] mem_awaddr;
  wire [3:0]  mem_awid;
  wire [7:0]  mem_awlen;
  wire [2:0]  mem_awsize;
  wire [1:0]  mem_awburst;
  wire        mem_wvalid, mem_wready;
  wire [31:0] mem_wdata;
  wire [3:0]  mem_wstrb;
  wire        mem_wlast;
  wire        mem_bvalid, mem_bready;
  wire [1:0]  mem_bresp;
  wire [3:0]  mem_bid;
`endif

  Arbiter u_arbiter(
    .clk(clk), .rst(rst),
    .ifu_arvalid(ifu_arvalid), .ifu_arready(ifu_arready),
    .ifu_araddr(ifu_araddr), .ifu_arlen(ifu_arlen),
    .ifu_rvalid(ifu_rvalid), .ifu_rready(ifu_rready),
    .ifu_rdata(ifu_rdata), .ifu_rlast(ifu_rlast),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr), .lsu_arid(lsu_arid), .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready),
    .lsu_rresp(lsu_rresp), .lsu_rdata(lsu_rdata),
    .lsu_rlast(lsu_rlast), .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr), .lsu_awid(lsu_awid), .lsu_awlen(lsu_awlen),
    .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready),
    .lsu_wdata(lsu_wdata), .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp), .lsu_bid(lsu_bid),
    .mem_arvalid(mem_arvalid), .mem_arready(mem_arready),
    .mem_araddr(mem_araddr), .mem_arid(mem_arid), .mem_arlen(mem_arlen),
    .mem_arsize(mem_arsize), .mem_arburst(mem_arburst),
    .mem_rvalid(mem_rvalid), .mem_rready(mem_rready),
    .mem_rresp(mem_rresp), .mem_rdata(mem_rdata),
    .mem_rlast(mem_rlast), .mem_rid(mem_rid),
    .mem_awvalid(mem_awvalid), .mem_awready(mem_awready),
    .mem_awaddr(mem_awaddr), .mem_awid(mem_awid), .mem_awlen(mem_awlen),
    .mem_awsize(mem_awsize), .mem_awburst(mem_awburst),
    .mem_wvalid(mem_wvalid), .mem_wready(mem_wready),
    .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_wlast(mem_wlast),
    .mem_bvalid(mem_bvalid), .mem_bready(mem_bready),
    .mem_bresp(mem_bresp), .mem_bid(mem_bid)
  );

`ifndef SOC_MODE
`ifndef SYNTHESIS
  PMEM u_pmem(
    .clk(clk), .rst(rst),
    .mem_arvalid(mem_arvalid), .mem_arready(mem_arready),
    .mem_araddr(mem_araddr), .mem_arid(mem_arid), .mem_arlen(mem_arlen),
    .mem_arsize(mem_arsize), .mem_arburst(mem_arburst),
    .mem_rvalid(mem_rvalid), .mem_rready(mem_rready),
    .mem_rresp(mem_rresp), .mem_rdata(mem_rdata),
    .mem_rlast(mem_rlast), .mem_rid(mem_rid),
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

  // =====================================================================
  //  仿真 DPI
  // =====================================================================
`ifndef SYNTHESIS
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val);
  import "DPI-C" function void mtrace_event(input int pc_val, input int addr, input int data, input int len, input int is_store);
  import "DPI-C" function void commit_instruction(input int pc_val, input int inst_val, input int next_pc_val);
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_csr_values(input int mstatus, input int mtvec, input int mepc, input int mcause, input int mcycle_lo, input int mcycle_hi);
  import "DPI-C" function void update_reg_value(input int idx, input int value);
  import "DPI-C" function void difftest_skip_ref();

  // ebreak 的 a0 需要把 WB 级正在写回的值也算进去
  wire [31:0] a0_fwd = (ex_fwd_wen && (ex_rd == 5'd10)) ? ex_wb_data :
                       (wb_fwd_wen && (wb_rd == 5'd10)) ? wb_data : a0_rf;

  wire [31:0] mtrace_data = ex_is_store ? ex_rs2 : lsu_rdata_ext;
  wire [31:0] mtrace_len  = (ex_mem_op == 4'd1) || (ex_mem_op == 4'd4) || (ex_mem_op == 4'd6) ? 32'd1 :
                            (ex_mem_op == 4'd2) || (ex_mem_op == 4'd5) || (ex_mem_op == 4'd7) ? 32'd2 : 32'd4;

  always @(posedge clk) begin
    if (rst) begin
`ifdef SOC_MODE
      update_pc_value(32'h3000_0000);
`else
      update_pc_value(32'h8000_0000);
`endif
      update_csr_values(32'h0000_1800, 32'b0, 32'b0, 32'b0, 32'b0, 32'b0);
    end else if (ex_commit) begin
      update_csr_values(mstatus, mtvec, mepc, mcause, mcycle_lo, mcycle_hi);
      commit_instruction(ex_pc, ex_inst, ex_pc_next);

      if (ex_reg_wen && (ex_rd != 5'b0)) begin
        update_reg_value({27'b0, ex_rd}, ex_wb_data);
      end

      if (ex_mem_valid) begin
        mtrace_event(ex_pc, ex_alu_result, mtrace_data, mtrace_len, {31'b0, ex_is_store});
      end

`ifdef SOC_MODE
      if (ex_mem_valid &&
          ((ex_alu_result >= 32'h1000_0000 && ex_alu_result < 32'h1002_0000) ||
           (ex_alu_result >= 32'h2100_0000 && ex_alu_result < 32'h2200_0000))) begin
        difftest_skip_ref();
      end
`endif

      if (ex_is_ebreak) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x", ex_pc, a0_fwd);
        ebreak_handler(a0_fwd);
      end

      if (ex_is_jalr) begin
        if (ex_rd == 5'd1) ftrace_call_handler(ex_pc, {ex_alu_result[31:1], 1'b0});
        else if ((ex_rd == 5'd0) && (ex_inst[19:15] == 5'd1)) ftrace_ret_handler(ex_pc);
      end
      if (ex_is_jal && (ex_rd == 5'd1)) begin
        ftrace_call_handler(ex_pc, ex_pc_target);
      end
    end
  end
`endif

  // =====================================================================
  //  性能计数器
  // =====================================================================
`ifndef SYNTHESIS
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

  import "DPI-C" function void perf_event(input int event_id);

  wire perf_is_alu    = (ex_inst[6:0] == 7'b0110011) || (ex_inst[6:0] == 7'b0010011);
  wire perf_is_upper  = (ex_inst[6:0] == 7'b0110111) || (ex_inst[6:0] == 7'b0010111);

  always @(posedge clk) begin
    if (!rst) begin
      if (ex_commit) begin
        perf_event(PERF_COMMIT);
        perf_event(PERF_IF_FETCH);

        perf_event(PERF_IC_ACCESS);
        if (ex_miss) perf_event(PERF_IC_MISS);
        else         perf_event(PERF_IC_HIT);

        if (perf_is_alu) begin
          perf_event(PERF_ALU);
          if (ex_inst[6:0] == 7'b0110011) perf_event(PERF_ALU_R);
          else                             perf_event(PERF_ALU_I);
        end
        if (ex_is_load) begin
          perf_event(PERF_LOAD);
          if (ex_mem_op == 4'd1 || ex_mem_op == 4'd4) perf_event(PERF_LD_BYTE);
          else if (ex_mem_op == 4'd2 || ex_mem_op == 4'd5) perf_event(PERF_LD_HALF);
          else perf_event(PERF_LD_WORD);
        end
        if (ex_is_store) begin
          perf_event(PERF_STORE);
          if (ex_mem_op == 4'd6) perf_event(PERF_ST_BYTE);
          else if (ex_mem_op == 4'd7) perf_event(PERF_ST_HALF);
          else perf_event(PERF_ST_WORD);
        end
        if (ex_is_branch) begin
          perf_event(PERF_BRANCH);
          if (ex_branch_taken) perf_event(PERF_BRANCH_TAKEN);
          else                 perf_event(PERF_BRANCH_NOT_TAKEN);
        end
        if (ex_is_jal)  begin perf_event(PERF_JUMP); perf_event(PERF_JAL);  end
        if (ex_is_jalr) begin perf_event(PERF_JUMP); perf_event(PERF_JALR); end
        if (perf_is_upper) perf_event(PERF_UPPER);
        if (ex_csr_op != 2'd0) begin
          perf_event(PERF_CSR);
          if (ex_csr_op == 2'd1) perf_event(PERF_CSRRW);
          else                   perf_event(PERF_CSRRS);
        end
        if (ex_is_ecall)  perf_event(PERF_ECALL);
        if (ex_is_mret)   perf_event(PERF_MRET);
        if (ex_is_ebreak) perf_event(PERF_EBREAK);
        if (ex_is_fence_i) perf_event(PERF_FENCE_I);

        if (ex_is_load)  perf_event(PERF_LD_DONE);
        if (ex_is_store) perf_event(PERF_ST_DONE);
      end

      if (ex_mem_valid && !ex_is_store && !ex_commit) perf_event(PERF_LD_WAIT);
      if (ex_mem_valid &&  ex_is_store && !ex_commit) perf_event(PERF_ST_WAIT);

      if (ifu_arvalid && !ifu_arready) perf_event(PERF_IF_STALL_BUS);
      if (!ifu_valid)                  perf_event(PERF_IF_STALL_MEM);
      if (ifu_arvalid && ifu_arready)  perf_event(PERF_IC_REFILL);

      if (mem_arvalid && mem_arready)  perf_event(PERF_BUS_AR);
      if (mem_rvalid  && mem_rready)   perf_event(PERF_BUS_R);
      if (mem_awvalid && mem_awready)  perf_event(PERF_BUS_AW);
      if (mem_wvalid  && mem_wready)   perf_event(PERF_BUS_W);
      if (mem_bvalid  && mem_bready)   perf_event(PERF_BUS_B);
      if (mem_arvalid && !mem_arready) perf_event(PERF_BUS_AR_STALL);
    end
  end
`endif
`endif

endmodule
