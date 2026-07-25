module top(
  input clk,
  input rst,
  input [31:0] imem_rdata,

  output [31:0] pc,
  output [31:0] inst,
  output [31:0] imem_addr
);

  // ========== 模块间连接信号 ==========
  

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
  wire is_ebreak;
  wire is_ecall, is_mret, is_fencei, icache_flush;
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
  wire op_branch;
  wire op_store;
  wire is_jump;
  wire [31:0] mepc, mtvec, csr_rdata;
  wire [31:0] csr_wdata = is_csrrw ? rs1_data : (rs1_data | csr_rdata);

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

  wire commit = ifu_valid && (!mem_valid || lsu_done);

  assign imem_addr = ifu_araddr;

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
    .is_fencei(is_fencei),
    .icache_flush(icache_flush),
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
    .op_branch(op_branch),
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
    .imm_s(imm_s),
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
    .op_r_type(op_r_type),
    .op_load(op_load),
    .op_store(op_store),
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
    .mret_en(is_mret),
    .mepc(mepc),
    .mtvec(mtvec)
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

  always @(posedge clk) begin
    if (!rst) begin
      // ebreak处理
      if (is_ebreak) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x", pc, a0_value);
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
          ftrace_ret_handler(pc);
        end
      end
      
      // jal也可能是函数调用
      if (is_jal && rd == 5'd1) begin
        ftrace_call_handler(pc, branch_target);
      end
      
    end
  end
`endif

endmodule
