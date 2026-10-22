// ============================================================================
//  top - 优化后的 NPC 单周期退休核
//
//  微架构: 8 项指令 FIFO + 128B 流式 ICache + 单周期执行/退休
//    - ALU/分支/jal 等指令每周期退休一条;
//    - load/store 在 LSU 完成的那一拍退休, 代价约 +1 周期;
//    - 取指由 ICache 自主顺序预取, 与执行解耦.
//
//  对外接口与 npc/vsrc/top.v 保持一致, 便于复用 npc/csrc 的仿真框架.
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
  wire [31:0] ifu_pc;
  wire [31:0] ifu_inst;
  wire        ifu_valid;
  wire        ifu_head_miss;

  wire [31:0] ic_out_data;
  wire        ic_out_valid;
  wire        ic_out_ready;
  wire        ic_line_miss;
  wire [31:0] ic_fetch_addr;

  wire [31:0] ifu_araddr;
  wire [7:0]  ifu_arlen;
  wire        ifu_arvalid, ifu_arready;
  wire        ifu_rvalid, ifu_rready, ifu_rlast;
  wire [31:0] ifu_rdata;

  // =====================================================================
  //  IDU / EXU / RF
  // =====================================================================
  wire [4:0] rd, rs1, rs2;
  wire [3:0] alu_op;
  wire [1:0] alu_a_sel, alu_b_sel, wb_sel;
  wire [3:0] mem_op;
  wire [1:0] csr_op;
  wire       dec_reg_wen, dec_is_branch, dec_is_jal, dec_is_jalr;
  wire       dec_is_ecall, dec_is_mret, dec_is_ebreak, dec_is_fence_i;
  wire       dec_is_load, dec_is_store;
  wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  wire [31:0] rs1_data, rs2_data;
  wire [31:0] a0_value;
  wire [31:0] alu_result;
  wire        branch_taken;
  wire [31:0] pc_plus4, pc_target;

  // =====================================================================
  //  LSU / CSR / WBU
  // =====================================================================
  wire [31:0] lsu_rdata_ext;
  wire        lsu_done;

  wire [31:0] mepc, mtvec, mstatus, mcause, mcycle_lo, mcycle_hi;
  wire [31:0] csr_rdata;

  wire [31:0] wb_data;
  wire [31:0] pc_next;

  // =====================================================================
  //  译码级寄存器 (FIFO -> ID/EX)
  //
  //  把 FIFO 的 8:1 读 mux 挡在 id_inst 寄存器之前, 使执行关键路径从
  //  id_inst / id_pc 触发器出发 (与原来的 inst_reg 结构一致), 避免
  //  "FIFO 读 mux -> 译码 -> 寄存器堆读 -> ALU -> 写回" 这一整条长路径.
  // =====================================================================
  reg [31:0] id_inst;
  reg [31:0] id_pc;
  reg        id_valid;
  reg        id_miss;

  wire [31:0] pc_cur   = id_pc;
  wire [31:0] inst_cur = id_inst;

  wire mem_valid = id_valid && (dec_is_load || dec_is_store);
  wire mem_wen   = id_valid && dec_is_store;
  wire retire    = id_valid && (!mem_valid || lsu_done);
  wire id_stall  = id_valid && mem_valid && !lsu_done;

  // FIFO 为空时, 直接把 ICache 当拍输出旁路进译码级, 避免"先入 FIFO
  // 再读出来"多耗一拍. 此时 IFU 的同拍 push/pop 相互抵消.
  wire ic_fill_fire = ic_out_valid && ic_out_ready;

  wire [31:0] id_load_inst  = ifu_valid ? ifu_inst      : ic_out_data;
  wire [31:0] id_load_pc    = ifu_valid ? ifu_pc        : ic_fetch_addr;
  wire        id_load_miss  = ifu_valid ? ifu_head_miss : ic_line_miss;
  wire        id_load_valid = ifu_valid || ic_fill_fire;

  wire load_next = !redirect && !id_stall && id_load_valid;

  always @(posedge clk) begin
    if (rst) begin
      id_inst  <= 32'b0;
      id_pc    <= BOOT_PC;
      id_valid <= 1'b0;
      id_miss  <= 1'b0;
    end else if (redirect) begin
      id_valid <= 1'b0;
    end else if (!id_stall) begin
      id_inst  <= id_load_inst;
      id_pc    <= id_load_pc;
      id_valid <= id_load_valid;
      id_miss  <= id_load_miss;
    end
  end

  wire reg_wen_commit = retire && dec_reg_wen && (rd != 5'b0);
  wire csr_wen_commit = retire && (csr_op != 2'd0);
  wire ecall_commit   = retire && dec_is_ecall;

  wire [31:0] csr_wdata = (csr_op == 2'd1) ? rs1_data : (rs1_data | csr_rdata);

  // 访存地址 = ALU 结果 (load: rs1+imm_i, store: rs1+imm_s)
  wire [31:0] mem_addr = alu_result;

  // 写回数据
  assign wb_data = (wb_sel == 2'd1) ? pc_plus4 :
                   (wb_sel == 2'd2) ? lsu_rdata_ext :
                   (wb_sel == 2'd3) ? csr_rdata : alu_result;

  // 下一条 PC
  assign pc_next = dec_is_ecall ? mtvec :
                   dec_is_mret  ? mepc :
                   dec_is_jalr  ? {alu_result[31:1], 1'b0} :
                   (dec_is_jal || branch_taken) ? pc_target :
                   dec_is_ebreak ? pc_cur :
                   pc_plus4;

  wire redirect = retire && (dec_is_jal || dec_is_jalr || branch_taken ||
                             dec_is_ecall || dec_is_mret || dec_is_fence_i ||
                             dec_is_ebreak);
  wire [31:0] redirect_addr = pc_next;
  wire ic_flush = retire && dec_is_fence_i;

  assign pc        = pc_cur;
  assign inst      = inst_cur;
  assign imem_addr = ic_fetch_addr;

  // =====================================================================
  //  模块实例化
  // =====================================================================
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

  IFU #(.BOOT_PC(BOOT_PC)) u_ifu(
    .clk(clk),
    .rst(rst),
    .redirect(redirect),
    .redirect_addr(redirect_addr),
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
    .clk(clk),
    .rst(rst),
    .flush(ic_flush),
    .redirect(redirect),
    .redirect_addr(redirect_addr),
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

  IDU u_idu(
    .inst(inst_cur),
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
    .clk(clk),
    .rst(rst),
    .wdata(wb_data),
    .waddr(rd),
    .wen(reg_wen_commit),
    .raddr1(rs1),
    .rdata1(rs1_data),
    .raddr2(rs2),
    .rdata2(rs2_data),
    .a0_value(a0_value)
  );

  EXU u_exu(
    .rs1(rs1_data),
    .rs2(rs2_data),
    .pc(pc_cur),
    .imm_i(imm_i),
    .imm_s(imm_s),
    .imm_b(imm_b),
    .imm_j(imm_j),
    .imm_u(imm_u),
    .alu_op(alu_op),
    .alu_a_sel(alu_a_sel),
    .alu_b_sel(alu_b_sel),
    .is_branch(dec_is_branch),
    .is_jal(dec_is_jal),
    .funct3(inst_cur[14:12]),
    .alu_result(alu_result),
    .branch_taken(branch_taken),
    .pc_plus4(pc_plus4),
    .pc_target(pc_target)
  );

  LSU u_lsu(
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_wen(mem_wen),
    .mem_op(mem_op),
    .addr(mem_addr),
    .wdata(rs2_data),
    .rdata(lsu_rdata_ext),
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
    .lsu_done(lsu_done)
  );

  CSR u_csr(
    .clk(clk),
    .rst(rst),
    .csr_addr(inst_cur[31:20]),
    .csr_wdata(csr_wdata),
    .csr_wen(csr_wen_commit),
    .csr_rdata(csr_rdata),
    .ecall_commit(ecall_commit),
    .pc(pc_cur),
    .mepc(mepc),
    .mtvec(mtvec),
    .mstatus_out(mstatus),
    .mcause_out(mcause),
    .mcycle_lo_out(mcycle_lo),
    .mcycle_hi_out(mcycle_hi)
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
    .clk(clk),
    .rst(rst),
    .ifu_arvalid(ifu_arvalid),
    .ifu_arready(ifu_arready),
    .ifu_araddr(ifu_araddr),
    .ifu_arlen(ifu_arlen),
    .ifu_rvalid(ifu_rvalid),
    .ifu_rready(ifu_rready),
    .ifu_rdata(ifu_rdata),
    .ifu_rlast(ifu_rlast),
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

`ifndef SOC_MODE
`ifndef SYNTHESIS
  PMEM u_pmem(
    .clk(clk),
    .rst(rst),
    .mem_arvalid(mem_arvalid), .mem_arready(mem_arready),
    .mem_araddr(mem_araddr), .mem_arid(mem_arid),
    .mem_arlen(mem_arlen), .mem_arsize(mem_arsize), .mem_arburst(mem_arburst),
    .mem_rvalid(mem_rvalid), .mem_rready(mem_rready),
    .mem_rresp(mem_rresp), .mem_rdata(mem_rdata), .mem_rlast(mem_rlast),
    .mem_rid(mem_rid),
    .mem_awvalid(mem_awvalid), .mem_awready(mem_awready),
    .mem_awaddr(mem_awaddr), .mem_awid(mem_awid),
    .mem_awlen(mem_awlen), .mem_awsize(mem_awsize), .mem_awburst(mem_awburst),
    .mem_wvalid(mem_wvalid), .mem_wready(mem_wready),
    .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_wlast(mem_wlast),
    .mem_bvalid(mem_bvalid), .mem_bready(mem_bready),
    .mem_bresp(mem_bresp), .mem_bid(mem_bid)
  );
`endif
`endif

`ifndef SOC_MODE
`ifdef SYNTHESIS
  // 综合用单 beat 存储模型: 仅用于得到面积/时序, 不参与仿真
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
  //  仿真专用: DPI-C trace / difftest / ebreak
  // =====================================================================
`ifndef SYNTHESIS
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val);
  import "DPI-C" function void mtrace_event(input int pc_val, input int addr, input int data, input int len, input int is_store);
  import "DPI-C" function void commit_instruction(input int pc_val, input int inst_val, input int next_pc_val);
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_csr_values(input int mstatus, input int mtvec, input int mepc, input int mcause, input int mcycle_lo, input int mcycle_hi);
  import "DPI-C" function void difftest_skip_ref();


  wire [31:0] mtrace_data = dec_is_store ? rs2_data : lsu_rdata_ext;
  wire [31:0] mtrace_len  = (mem_op == 4'd1) || (mem_op == 4'd4) || (mem_op == 4'd6) ? 32'd1 :
                            (mem_op == 4'd2) || (mem_op == 4'd5) || (mem_op == 4'd7) ? 32'd2 : 32'd4;

  always @(posedge clk) begin
    if (rst) begin
`ifdef SOC_MODE
      update_pc_value(32'h3000_0000);
`else
      update_pc_value(32'h8000_0000);
`endif
      update_csr_values(32'h0000_1800, 32'b0, 32'b0, 32'b0, 32'b0, 32'b0);
    end else begin
      if (retire) begin
        update_csr_values(mstatus, mtvec, mepc, mcause, mcycle_lo, mcycle_hi);
        commit_instruction(pc_cur, inst_cur, pc_next);
      end

      if (retire && mem_valid) begin
        mtrace_event(pc_cur, mem_addr, mtrace_data, mtrace_len, {31'b0, dec_is_store});
      end

`ifdef SOC_MODE
      if (retire && mem_valid &&
          ((mem_addr >= 32'h1000_0000 && mem_addr < 32'h1002_0000) ||
           (mem_addr >= 32'h2100_0000 && mem_addr < 32'h2200_0000))) begin
        difftest_skip_ref();
      end
`endif

      if (retire && dec_is_ebreak) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x", pc_cur, a0_value);
        ebreak_handler(a0_value);
      end

      if (retire && dec_is_jalr) begin
        if (rd == 5'd1) ftrace_call_handler(pc_cur, {alu_result[31:1], 1'b0});
        else if (rd == 5'd0 && rs1 == 5'd1) ftrace_ret_handler(pc_cur);
      end
      if (retire && dec_is_jal && rd == 5'd1) begin
        ftrace_call_handler(pc_cur, pc_target);
      end
    end
  end
`endif

  // =====================================================================
  //  仿真专用: 性能计数器 (仅在 ENABLE_PERF 时编译)
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

  wire perf_is_alu    = (inst_cur[6:0] == 7'b0110011) || (inst_cur[6:0] == 7'b0010011);
  wire perf_is_branch = dec_is_branch;
  wire perf_is_upper  = (inst_cur[6:0] == 7'b0110111) || (inst_cur[6:0] == 7'b0010111);

  wire perf_ld_done = retire && dec_is_load;
  wire perf_st_done = retire && dec_is_store;

  always @(posedge clk) begin
    if (!rst) begin
      if (retire) begin
        perf_event(PERF_COMMIT);
        perf_event(PERF_IF_FETCH);

        perf_event(PERF_IC_ACCESS);
        if (id_miss)       perf_event(PERF_IC_MISS);
        else               perf_event(PERF_IC_HIT);

        if (perf_is_alu) begin
          perf_event(PERF_ALU);
          if (inst_cur[6:0] == 7'b0110011) perf_event(PERF_ALU_R);
          else                             perf_event(PERF_ALU_I);
        end
        if (dec_is_load) begin
          perf_event(PERF_LOAD);
          if (mem_op == 4'd1 || mem_op == 4'd4) perf_event(PERF_LD_BYTE);
          else if (mem_op == 4'd2 || mem_op == 4'd5) perf_event(PERF_LD_HALF);
          else perf_event(PERF_LD_WORD);
        end
        if (dec_is_store) begin
          perf_event(PERF_STORE);
          if (mem_op == 4'd6) perf_event(PERF_ST_BYTE);
          else if (mem_op == 4'd7) perf_event(PERF_ST_HALF);
          else perf_event(PERF_ST_WORD);
        end
        if (dec_is_branch) begin
          perf_event(PERF_BRANCH);
          if (branch_taken) perf_event(PERF_BRANCH_TAKEN);
          else              perf_event(PERF_BRANCH_NOT_TAKEN);
        end
        if (dec_is_jal) begin
          perf_event(PERF_JUMP);
          perf_event(PERF_JAL);
        end
        if (dec_is_jalr) begin
          perf_event(PERF_JUMP);
          perf_event(PERF_JALR);
        end
        if (perf_is_upper) perf_event(PERF_UPPER);
        if (csr_op != 2'd0) begin
          perf_event(PERF_CSR);
          if (csr_op == 2'd1) perf_event(PERF_CSRRW);
          else                perf_event(PERF_CSRRS);
        end
        if (dec_is_ecall)  perf_event(PERF_ECALL);
        if (dec_is_mret)   perf_event(PERF_MRET);
        if (dec_is_ebreak) perf_event(PERF_EBREAK);
        if (dec_is_fence_i) perf_event(PERF_FENCE_I);

        if (perf_ld_done) perf_event(PERF_LD_DONE);
        if (perf_st_done) perf_event(PERF_ST_DONE);
      end

      if (mem_valid && !dec_is_store && !retire) perf_event(PERF_LD_WAIT);
      if (mem_valid &&  dec_is_store && !retire) perf_event(PERF_ST_WAIT);

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
