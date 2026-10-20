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

  // ========== 模块间连接信号 ==========
  

  // IDU输出 - 指令字段
  wire [4:0] rd, rs1, rs2;
  
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
  wire is_ecall, is_mret;
  wire is_csrrw, is_csrrs, csr_wen;
  wire is_csr = is_csrrw || is_csrrs;
  // IDU输出 - 控制信号
  wire reg_wen, mem_valid, mem_wen;
  wire reg_wen_commit = reg_wen && commit;
  wire csr_wen_commit = csr_wen && commit;
  
  // RegisterFile输出
  wire [31:0] rs1_data, rs2_data;
  wire [31:0] a0_value;  // a0寄存器的值
  
  // EXU输出
  wire [31:0] alu_result;
  wire [31:0] jump_target;
  wire [31:0] branch_target;
  wire branch_taken;
  
  // WBU输出
  wire [31:0] rd_data;
  wire [31:0] pc_next;
  
  // 访存地址计算
  wire [31:0] addr = op_store ? (rs1_data + imm_s) : (rs1_data + imm_i);
  wire [31:0] rdata;

  wire op_r_type;
  wire op_load;
  wire op_store;
  wire is_jump;
  wire [31:0] mstatus, mcause, mcycle_lo, mcycle_hi;
  wire [31:0] mepc, mtvec, csr_rdata;
  wire [31:0] csr_wdata = is_csrrw ? rs1_data : (rs1_data | csr_rdata);

  // 数据访存的真实宽度（用于 mtrace）
  wire [31:0] data_len = (is_lb || is_lbu || is_sb) ? 32'd1 :
                         (is_lh || is_lhu || is_sh) ? 32'd2 : 32'd4;

  wire lsu_arvalid;
  wire lsu_arready;
  wire [31:0] lsu_araddr;
  wire [3:0] lsu_arid;
  wire [7:0] lsu_arlen;
  wire [2:0] lsu_arsize;
  wire [1:0] lsu_arburst;
  wire lsu_rvalid;
  wire lsu_rready;
  wire [1:0] lsu_rresp;
  wire [31:0] lsu_rdata;
  wire lsu_rlast;
  wire [3:0] lsu_rid;
  wire lsu_awvalid;
  wire lsu_awready;
  wire [31:0] lsu_awaddr;
  wire [3:0] lsu_awid;
  wire [7:0] lsu_awlen;
  wire [2:0] lsu_awsize;
  wire [1:0] lsu_awburst;
  wire lsu_wvalid;
  wire lsu_wready;
  wire [31:0] lsu_wdata;
  wire [3:0] lsu_wstrb;
  wire lsu_wlast;
  wire lsu_bvalid;
  wire lsu_bready;
  wire [1:0] lsu_bresp;
  wire [3:0] lsu_bid;
  wire lsu_done;

  wire ifu_arvalid;
  wire ifu_arready;
  wire [31:0] ifu_araddr;
  wire [3:0] ifu_arid;
  wire [7:0] ifu_arlen;
  wire [2:0] ifu_arsize;
  wire [1:0] ifu_arburst;
  wire ifu_rvalid;
  wire ifu_rready;
  wire [1:0] ifu_rresp;
  wire [31:0] ifu_rdata;
  wire ifu_rlast;
  wire [3:0] ifu_rid;
  wire ifu_valid;

  wire icache_arvalid;
  wire icache_arready;
  wire [31:0] icache_araddr;
  wire [3:0] icache_arid;
  wire [7:0] icache_arlen;
  wire [2:0] icache_arsize;
  wire [1:0] icache_arburst;
  wire icache_rvalid;
  wire icache_rready;
  wire [1:0] icache_rresp;
  wire [31:0] icache_rdata;
  wire icache_rlast;
  wire [3:0] icache_rid;

  wire icache_access;
  wire icache_hit;
  wire icache_miss;
  wire icache_compulsory;
  wire icache_replace;
  wire icache_refill;
  wire icache_miss_ar_wait;
  wire icache_miss_r_wait;

  wire icache_ifu_arvalid;
  wire icache_ifu_arready;
  wire icache_ifu_rvalid;
  wire [1:0] icache_ifu_rresp;
  wire [31:0] icache_ifu_rdata;
  wire icache_ifu_rlast;
  wire [3:0] icache_ifu_rid;

  wire arb_ifu_arvalid;
  wire arb_ifu_arready;
  wire [31:0] arb_ifu_araddr;
  wire [3:0] arb_ifu_arid;
  wire [7:0] arb_ifu_arlen;
  wire [2:0] arb_ifu_arsize;
  wire [1:0] arb_ifu_arburst;
  wire arb_ifu_rvalid;
  wire arb_ifu_rready;
  wire [1:0] arb_ifu_rresp;
  wire [31:0] arb_ifu_rdata;
  wire arb_ifu_rlast;
  wire [3:0] arb_ifu_rid;

  wire ifu_cacheable;
  reg cache_pending;
  reg bypass_pending;

`ifndef SOC_MODE
  wire mem_arvalid;
  wire mem_arready;
  wire [31:0] mem_araddr;
  wire [3:0] mem_arid;
  wire [7:0] mem_arlen;
  wire [2:0] mem_arsize;
  wire [1:0] mem_arburst;
  wire mem_rvalid;
  wire mem_rready;
  wire [1:0] mem_rresp;
  wire [31:0] mem_rdata;
  wire mem_rlast;
  wire [3:0] mem_rid;
  wire mem_awvalid;
  wire mem_awready;
  wire [31:0] mem_awaddr;
  wire [3:0] mem_awid;
  wire [7:0] mem_awlen;
  wire [2:0] mem_awsize;
  wire [1:0] mem_awburst;
  wire mem_wvalid;
  wire mem_wready;
  wire [31:0] mem_wdata;
  wire [3:0] mem_wstrb;
  wire mem_wlast;
  wire mem_bvalid;
  wire mem_bready;
  wire [1:0] mem_bresp;
  wire [3:0] mem_bid;
`endif

  assign ifu_cacheable = ((ifu_araddr >= 32'h3000_0000) &&
                          (ifu_araddr <  32'h3100_0000)) ||
                         ((ifu_araddr >= 32'ha000_0000) &&
                          (ifu_araddr <  32'ha200_0000));

  assign icache_ifu_arvalid = ifu_arvalid && ifu_cacheable;
  assign ifu_arready        = ifu_cacheable ? icache_ifu_arready : arb_ifu_arready;

  assign arb_ifu_arvalid = ifu_cacheable ? icache_arvalid : ifu_arvalid;
  assign arb_ifu_araddr  = ifu_cacheable ? icache_araddr : ifu_araddr;
  assign arb_ifu_arid    = ifu_cacheable ? icache_arid : ifu_arid;
  assign arb_ifu_arlen   = ifu_cacheable ? icache_arlen : ifu_arlen;
  assign arb_ifu_arsize  = ifu_cacheable ? icache_arsize : ifu_arsize;
  assign arb_ifu_arburst = ifu_cacheable ? icache_arburst : ifu_arburst;

  assign icache_arready = ifu_cacheable ? arb_ifu_arready : 1'b0;
  assign icache_rvalid  = cache_pending ? arb_ifu_rvalid : 1'b0;
  assign icache_rresp   = arb_ifu_rresp;
  assign icache_rdata   = arb_ifu_rdata;
  assign icache_rlast   = arb_ifu_rlast;
  assign icache_rid     = arb_ifu_rid;
  assign arb_ifu_rready = cache_pending ? icache_rready :
                          (bypass_pending ? ifu_rready : 1'b0);

  assign ifu_rvalid = cache_pending ? icache_ifu_rvalid :
                      (bypass_pending ? arb_ifu_rvalid : 1'b0);
  assign ifu_rresp  = cache_pending ? icache_ifu_rresp : arb_ifu_rresp;
  assign ifu_rdata  = cache_pending ? icache_ifu_rdata : arb_ifu_rdata;
  assign ifu_rlast  = cache_pending ? icache_ifu_rlast : arb_ifu_rlast;
  assign ifu_rid    = cache_pending ? icache_ifu_rid : arb_ifu_rid;

  // Track which path owns the outstanding IFU fetch.
  always @(posedge clk) begin
    if (rst) begin
      cache_pending  <= 1'b0;
      bypass_pending <= 1'b0;
    end else if (ifu_arvalid && ifu_arready) begin
      cache_pending  <= ifu_cacheable;
      bypass_pending <= !ifu_cacheable;
    end else begin
      if (cache_pending && icache_ifu_rvalid && ifu_rready) begin
        cache_pending <= 1'b0;
      end
      if (bypass_pending && arb_ifu_rvalid && ifu_rready) begin
        bypass_pending <= 1'b0;
      end
    end
  end

  wire commit = ifu_valid && (!mem_valid || lsu_done);

  assign imem_addr = ifu_araddr;

`ifndef SOC_MODE
`ifdef SYNTHESIS
  reg synth_rvalid;
  reg [3:0] synth_rid;
  reg [31:0] synth_rdata;

  assign mem_arready = !synth_rvalid || mem_rready;
  assign mem_rvalid = synth_rvalid;
  assign mem_rresp = 2'b00;
  assign mem_rdata = synth_rdata;
  assign mem_rlast = 1'b1;
  assign mem_rid = synth_rid;
  assign mem_awready = 1'b1;
  assign mem_wready = 1'b1;
  assign mem_bvalid = 1'b1;
  assign mem_bresp = 2'b00;
  assign mem_bid = 4'b0010;

  always @(posedge clk) begin
    if (rst) begin
      synth_rvalid <= 1'b0;
      synth_rid <= 4'b0;
      synth_rdata <= 32'b0;
    end else begin
      if (mem_rvalid && mem_rready) begin
        synth_rvalid <= 1'b0;
      end
      if (mem_arvalid && mem_arready) begin
        synth_rvalid <= 1'b1;
        synth_rid <= mem_arid;
        if (mem_arid == 4'b0001) begin
          synth_rdata <= imem_rdata;
        end else begin
          synth_rdata <= 32'b0;
        end
      end
    end
  end
`endif
`endif

  // ========== 模块实例化 ==========
  
  // IFU - 取指单元
  IFU u_ifu(
    .clk(clk),
    .rst(rst),
    .commit(commit),
    .pc_next(pc_next),
    .ifu_arvalid(ifu_arvalid),
    .ifu_arready(ifu_arready),
    .ifu_araddr(ifu_araddr),
    .ifu_arid(ifu_arid),
    .ifu_arlen(ifu_arlen),
    .ifu_arsize(ifu_arsize),
    .ifu_arburst(ifu_arburst),
    .ifu_rvalid(ifu_rvalid),
    .ifu_rready(ifu_rready),
    .ifu_rresp(ifu_rresp),
    .ifu_rdata(ifu_rdata),
    .ifu_rlast(ifu_rlast),
    .ifu_rid(ifu_rid),
    .pc(pc),
    .inst(inst),
    .ifu_valid(ifu_valid)
  );

  // ICache - 指令缓存 (IFU -> ICache -> Arbiter)
  ICache u_icache(
    .clk(clk),
    .rst(rst),

    .ifu_arvalid(icache_ifu_arvalid),
    .ifu_arready(icache_ifu_arready),
    .ifu_araddr(ifu_araddr),
    .ifu_arid(ifu_arid),
    .ifu_arlen(ifu_arlen),
    .ifu_arsize(ifu_arsize),
    .ifu_arburst(ifu_arburst),

    .ifu_rvalid(icache_ifu_rvalid),
    .ifu_rready(ifu_rready),
    .ifu_rresp(icache_ifu_rresp),
    .ifu_rdata(icache_ifu_rdata),
    .ifu_rlast(icache_ifu_rlast),
    .ifu_rid(icache_ifu_rid),

    .arvalid(icache_arvalid),
    .arready(icache_arready),
    .araddr(icache_araddr),
    .arid(icache_arid),
    .arlen(icache_arlen),
    .arsize(icache_arsize),
    .arburst(icache_arburst),

    .rvalid(icache_rvalid),
    .rready(icache_rready),
    .rresp(icache_rresp),
    .rdata(icache_rdata),
    .rlast(icache_rlast),
    .rid(icache_rid),

    .icache_access(icache_access),
    .icache_hit(icache_hit),
    .icache_miss(icache_miss),
    .icache_compulsory(icache_compulsory),
    .icache_replace(icache_replace),
    .icache_refill(icache_refill),
    .icache_miss_ar_wait(icache_miss_ar_wait),
    .icache_miss_r_wait(icache_miss_r_wait)
  );
  
  // IDU - 译码单元
  IDU u_idu(
    .inst(inst),
    .ifu_valid(ifu_valid),
    .rd(rd),
    .rs1(rs1),
    .rs2(rs2),
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
    .is_jump(is_jump)
  );
  
  // RegisterFile - 寄存器堆
  RegisterFile u_regfile(
    .clk(clk),
    .rst(rst),
    .waddr(rd),
    .wdata(rd_data),
    .wen(reg_wen_commit),
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
    .op_r_type(op_r_type),
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
    .addr(addr),
    .wdata(rs2_data),
    .rdata(rdata),
    .lsu_done(lsu_done)
  );

  // Arbiter - IFU/LSU AXI请求仲裁
  Arbiter u_arbiter(
    .clk(clk),
    .rst(rst),
    .ifu_arvalid(arb_ifu_arvalid),
    .ifu_arready(arb_ifu_arready),
    .ifu_araddr(arb_ifu_araddr),
    .ifu_arid(arb_ifu_arid),
    .ifu_arlen(arb_ifu_arlen),
    .ifu_arsize(arb_ifu_arsize),
    .ifu_arburst(arb_ifu_arburst),
    .ifu_rvalid(arb_ifu_rvalid),
    .ifu_rready(arb_ifu_rready),
    .ifu_rresp(arb_ifu_rresp),
    .ifu_rdata(arb_ifu_rdata),
    .ifu_rlast(arb_ifu_rlast),
    .ifu_rid(arb_ifu_rid),
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

  // CSR - 控制状态寄存器
  CSR u_csr(
    .clk(clk),
    .rst(rst),
    .csr_addr(imm_i[11:0]),
    .csr_wdata(csr_wdata),
    .csr_wen(csr_wen_commit),
    .csr_rdata(csr_rdata),
    .is_ecall(is_ecall),
    .pc(pc),
    .mepc(mepc),
    .mtvec(mtvec),
    .mstatus_out(mstatus),
    .mcause_out(mcause),
    .mcycle_lo_out(mcycle_lo),
    .mcycle_hi_out(mcycle_hi)
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
  import "DPI-C" function void mtrace_event(input int pc_val, input int addr, input int data, input int len, input int is_store);
  import "DPI-C" function void commit_instruction(input int pc_val, input int inst_val, input int next_pc_val);
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_csr_values(input int mstatus, input int mtvec, input int mepc, input int mcause, input int mcycle_lo, input int mcycle_hi);
  import "DPI-C" function void difftest_skip_ref();

`ifdef ENABLE_PERF
  // ========== 性能计数器探针 ==========
  // 仅在仿真(PERF=1)下启用: 事件脉冲经 DPI-C 上报, 计数/聚合/报告都在
  // 仿真环境 csrc/core/perf.cpp 中完成, 不参与综合(见 Makefile 的 PERF 变量).
  // 事件编号必须与 csrc/core/perf.h 的 PerfEventId 保持一致.
  localparam PERF_COMMIT       = 0;   // 提交(动态)指令数
  localparam PERF_IF_FETCH     = 1;   // IFU 取到指令
  localparam PERF_IF_STALL_BUS = 2;   // IFU 等 ICache 接收请求
  localparam PERF_IF_STALL_MEM = 3;   // IFU 等 ICache 返回指令
  localparam PERF_LD_DONE      = 4;   // LSU 取到数据 (load 完成)
  localparam PERF_ST_DONE      = 5;   // LSU 完成 store
  localparam PERF_LD_WAIT      = 6;   // load 等待数据周期数 (统计平均访存延迟)
  localparam PERF_ALU          = 7;   // 计算类指令 (R型/I型算术逻辑)
  localparam PERF_LOAD         = 8;   // load 类指令
  localparam PERF_STORE        = 9;   // store 类指令
  localparam PERF_BRANCH       = 10;  // 分支指令
  localparam PERF_JUMP         = 11;  // 跳转指令
  localparam PERF_UPPER        = 12;  // lui/auipc
  localparam PERF_CSR          = 13;  // CSR 指令
  localparam PERF_ECALL        = 14;  // ecall
  localparam PERF_MRET         = 15;  // mret
  localparam PERF_EBREAK       = 16;  // ebreak
  localparam PERF_IC_ACCESS    = 17;  // ICache 取指请求数
  localparam PERF_IC_HIT       = 18;  // ICache 命中数
  localparam PERF_IC_MISS      = 19;  // ICache 缺失数
  localparam PERF_IC_REFILL    = 20;  // ICache 缺失时发起的总线 AR 数
  localparam PERF_IC_MISS_AR   = 21;  // ICache 缺失等待 AR 的周期数
  localparam PERF_IC_MISS_R    = 22;  // ICache 缺失等待 R 的周期数
  localparam PERF_IF_BYPASS    = 23;  // 非缓存地址直连取指数
  localparam PERF_BRANCH_TAKEN = 24;  // 条件分支 taken
  localparam PERF_BRANCH_NOT_TAKEN = 25; // 条件分支 not taken
  localparam PERF_JAL          = 26;  // jal
  localparam PERF_JALR         = 27;  // jalr
  localparam PERF_LD_BYTE      = 28;  // load byte
  localparam PERF_LD_HALF      = 29;  // load half
  localparam PERF_LD_WORD      = 30;  // load word
  localparam PERF_ST_BYTE      = 31;  // store byte
  localparam PERF_ST_HALF      = 32;  // store half
  localparam PERF_ST_WORD      = 33;  // store word
  localparam PERF_BUS_AR       = 34;  // 总线 AR 握手数
  localparam PERF_BUS_R        = 35;  // 总线 R 握手数
  localparam PERF_BUS_AW       = 36;  // 总线 AW 握手数
  localparam PERF_BUS_W        = 37;  // 总线 W 握手数
  localparam PERF_BUS_B        = 38;  // 总线 B 握手数
  localparam PERF_BUS_AR_STALL = 39;  // AR 有效但未 ready 的周期数
  localparam PERF_IC_COMPULSORY = 40; // ICache 强制缺失 (目标块原先无效)
  localparam PERF_IC_REPLACE   = 41;  // ICache 替换缺失 (目标块原先有效)
  localparam PERF_ALU_R        = 42;  // R 型 ALU 指令
  localparam PERF_ALU_I        = 43;  // I 型 ALU 指令
  localparam PERF_CSRRW        = 44;  // csrrw
  localparam PERF_CSRRS        = 45;  // csrrs
  localparam PERF_ST_WAIT      = 46;  // store 等待完成周期数

  import "DPI-C" function void perf_event(input int event_id);

  wire perf_is_alu    = op_r_type || is_addi || is_slti || is_sltiu || is_xori ||
                        is_ori || is_andi || is_slli || is_srli || is_srai;
  wire perf_is_branch = is_beq || is_bne || is_blt || is_bge || is_bltu || is_bgeu;
  wire perf_is_upper  = is_lui || is_auipc;

  wire perf_if_fetch      = ifu_rvalid && ifu_rready && ifu_rlast;
  wire perf_if_stall_bus  = ifu_arvalid && !ifu_arready;
  wire perf_if_stall_mem  = ifu_rready && !ifu_rvalid;
  wire perf_if_bypass     = ifu_arvalid && ifu_arready && !ifu_cacheable;
  wire perf_ld_done       = lsu_rvalid && lsu_rready && lsu_rlast;
  wire perf_st_done       = lsu_bvalid && lsu_bready;
  wire perf_ld_wait       = mem_valid && !mem_wen && !perf_ld_done;
  wire perf_st_wait       = mem_valid &&  mem_wen && !perf_st_done;

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

      if (icache_access)       perf_event(PERF_IC_ACCESS);
      if (icache_hit)          perf_event(PERF_IC_HIT);
      if (icache_miss)         perf_event(PERF_IC_MISS);
      if (icache_compulsory)   perf_event(PERF_IC_COMPULSORY);
      if (icache_replace)      perf_event(PERF_IC_REPLACE);
      if (icache_refill)       perf_event(PERF_IC_REFILL);
      if (icache_miss_ar_wait) perf_event(PERF_IC_MISS_AR);
      if (icache_miss_r_wait)  perf_event(PERF_IC_MISS_R);

      if (mem_arvalid && mem_arready)  perf_event(PERF_BUS_AR);
      if (mem_rvalid  && mem_rready)   perf_event(PERF_BUS_R);
      if (mem_awvalid && mem_awready)  perf_event(PERF_BUS_AW);
      if (mem_wvalid  && mem_wready)   perf_event(PERF_BUS_W);
      if (mem_bvalid  && mem_bready)   perf_event(PERF_BUS_B);
      if (mem_arvalid && !mem_arready) perf_event(PERF_BUS_AR_STALL);

      if (commit) begin
        if (perf_is_alu) begin
          perf_event(PERF_ALU);
          if (op_r_type) perf_event(PERF_ALU_R);
          else           perf_event(PERF_ALU_I);
        end
        if (op_load) begin
          perf_event(PERF_LOAD);
          if (is_lb || is_lbu)      perf_event(PERF_LD_BYTE);
          else if (is_lh || is_lhu) perf_event(PERF_LD_HALF);
          else if (is_lw)           perf_event(PERF_LD_WORD);
        end
        if (op_store) begin
          perf_event(PERF_STORE);
          if (is_sb)      perf_event(PERF_ST_BYTE);
          else if (is_sh) perf_event(PERF_ST_HALF);
          else if (is_sw) perf_event(PERF_ST_WORD);
        end
        if (perf_is_branch) begin
          perf_event(PERF_BRANCH);
          if (branch_taken) perf_event(PERF_BRANCH_TAKEN);
          else              perf_event(PERF_BRANCH_NOT_TAKEN);
        end
        if (is_jump) begin
          perf_event(PERF_JUMP);
          if (is_jal)  perf_event(PERF_JAL);
          if (is_jalr) perf_event(PERF_JALR);
        end
        if (perf_is_upper)  perf_event(PERF_UPPER);
        if (is_csr) begin
          perf_event(PERF_CSR);
          if (is_csrrw) perf_event(PERF_CSRRW);
          if (is_csrrs) perf_event(PERF_CSRRS);
        end
        if (is_ecall)       perf_event(PERF_ECALL);
        if (is_mret)        perf_event(PERF_MRET);
        if (is_ebreak)      perf_event(PERF_EBREAK);
      end
    end
  end
`endif

  always @(posedge clk) begin
    if (rst) begin
`ifdef SOC_MODE
      update_pc_value(32'h30000000);
`else
      update_pc_value(32'h80000000);
`endif
      update_csr_values(32'h00001800, 32'b0, 32'b0, 32'b0, 32'b0, 32'b0);
    end else begin
      update_csr_values(mstatus, mtvec, mepc, mcause, mcycle_lo, mcycle_hi);

      if (commit) begin
        commit_instruction(pc, inst, pc_next);
      end

      // 只记录真实的数据访存，不把 IFU 取指混进 mtrace
      if (commit && mem_valid) begin
        mtrace_event(pc, addr, op_store ? rs2_data : rdata, data_len, {31'b0, op_store});
      end

`ifdef SOC_MODE
      if (commit && mem_valid &&
          ((addr >= 32'h10000000 && addr < 32'h10020000) ||
          (addr >= 32'h21000000 && addr < 32'h22000000))) begin
        difftest_skip_ref();
      end
`endif

      if (is_ebreak && commit) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x", pc, a0_value);
        ebreak_handler(a0_value);
      end

      if (is_jalr && commit) begin
        if (rd == 5'd1) begin
          ftrace_call_handler(pc, jump_target);
        end
        else if (rd == 5'd0 && rs1 == 5'd1) begin
          ftrace_ret_handler(pc);
        end
      end
      
      if (is_jal && rd == 5'd1 && commit) begin
        ftrace_call_handler(pc, branch_target);
      end
      
    end
  end
`endif

endmodule
