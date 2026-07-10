// ysyx_26020070 - RV32E 3-stage pipelined processor for ysyxSoC
// Stage 1: IF (fetch through ICache)
// Stage 2: ID (decode + register read)  
// Stage 3: EX+LS+WB (execute, memory, writeback — combinational)
// Hazard: RAW stall (ID checks EX stage rd), branch flush, fence.i flush
// Keeps ysyxSoC interface compatible

module ysyx_26020070(
  input clock, input reset, input io_interrupt,
  output io_master_arvalid, input io_master_arready, output [31:0] io_master_araddr,
  output [ 3:0] io_master_arid, output [ 7:0] io_master_arlen, output [ 2:0] io_master_arsize, output [ 1:0] io_master_arburst,
  input io_master_rvalid, output io_master_rready, input [31:0] io_master_rdata, input [ 1:0] io_master_rresp, input io_master_rlast, input [ 3:0] io_master_rid,
  output io_master_awvalid, input io_master_awready, output [31:0] io_master_awaddr,
  output [ 3:0] io_master_awid, output [ 7:0] io_master_awlen, output [ 2:0] io_master_awsize, output [ 1:0] io_master_awburst,
  output io_master_wvalid, input io_master_wready, output [31:0] io_master_wdata, output [ 3:0] io_master_wstrb, output io_master_wlast,
  input io_master_bvalid, output io_master_bready, input [ 1:0] io_master_bresp, input [ 3:0] io_master_bid,
  output io_slave_awready, input io_slave_awvalid, input [ 3:0] io_slave_awid, input [31:0] io_slave_awaddr,
  input [ 7:0] io_slave_awlen, input [ 2:0] io_slave_awsize, input [ 1:0] io_slave_awburst,
  output io_slave_wready, input io_slave_wvalid, input [31:0] io_slave_wdata, input [ 3:0] io_slave_wstrb, input io_slave_wlast,
  input io_slave_bready, output io_slave_bvalid, output [ 3:0] io_slave_bid, output [ 1:0] io_slave_bresp,
  output io_slave_arready, input io_slave_arvalid, input [ 3:0] io_slave_arid, input [31:0] io_slave_araddr,
  input [ 7:0] io_slave_arlen, input [ 2:0] io_slave_arsize, input [ 1:0] io_slave_arburst,
  input io_slave_rready, output io_slave_rvalid, output [ 3:0] io_slave_rid, output [31:0] io_slave_rdata, output [ 1:0] io_slave_rresp, output io_slave_rlast
);
  assign io_slave_awready = 1'b0; assign io_slave_wready = 1'b0; assign io_slave_bvalid = 1'b0; assign io_slave_bid = 4'b0; assign io_slave_bresp = 2'b0;
  assign io_slave_arready = 1'b0; assign io_slave_rvalid = 1'b0; assign io_slave_rid = 4'b0; assign io_slave_rdata = 32'b0; assign io_slave_rresp = 2'b0; assign io_slave_rlast = 1'b0;
  wire rst = reset;

  // ===== IF Stage: simple fetch unit (same state machine as original IFU) =====
  reg [31:0] if_pc;
  reg        if_state;
  localparam IF_IDLE=1'b0, IF_WAIT=1'b1;
  wire if_arvalid = (if_state==IF_IDLE) && !rst && !flush_pipe;
  wire [31:0] if_araddr = if_pc;
  wire if_rready = (if_state==IF_WAIT) && !rst && !stall_pipe;
  wire if_valid = (if_state==IF_WAIT) && if_rvalid && if_rready && !rst;
  wire [31:0] if_inst = if_valid ? if_rdata : 32'h00000013;
  wire if_arready, if_rvalid, if_rlast;
  wire [31:0] if_rdata;
  wire [1:0] if_rresp;
  wire [3:0] if_rid;

  always @(posedge clock) begin
    if (rst) begin
      if_state <= IF_IDLE;
`ifdef SOC_MODE
      if_pc <= 32'h30000000;
`else
      if_pc <= 32'h80000000;
`endif
    end else if (flush_pipe) begin
      if_state <= IF_IDLE;
      if_pc    <= redirect_pc;
    end else if (!stall_pipe) begin
      case (if_state)
        IF_IDLE: if (if_arready) if_state <= IF_WAIT;
        IF_WAIT: if (if_rvalid && if_rready) begin
          if_pc    <= if_pc + 32'd4;
          if_state <= IF_IDLE;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);
  // update_inst_value: called at IF stage (for itrace)
  always @(posedge clock) begin
    if (!rst && if_valid && !stall_pipe) begin
      update_inst_value(if_pc, if_rdata);
    end
  end
  // update_pc_value: called at WB stage (after register write, for difftest sync)
  reg wb_done_pulse;
  always @(posedge clock) begin
    if (rst) begin
      wb_done_pulse <= 1'b0;
`ifdef SOC_MODE
      update_pc_value(32'h30000000);
`else
      update_pc_value(32'h80000000);
`endif
    end else begin
      wb_done_pulse <= wb_wen;
      if (wb_wen) update_pc_value(ex_pc + 32'd4);
      else if (flush_pipe) update_pc_value(redirect_pc);
    end
  end
`endif

  // ===== IF/ID Pipeline Register =====
  reg         id_valid;
  reg [31:0]  id_pc, id_inst;
  always @(posedge clock) begin
    if (rst || flush_pipe) id_valid <= 1'b0;
    else if (!stall_pipe) begin
      id_valid <= if_valid;
      if (if_valid) begin id_pc <= if_pc; id_inst <= if_inst; end
    end
  end

  // ===== ID Stage: IDU + RegisterFile =====
  wire [6:0] id_opcode; wire [4:0] id_rd, id_rs1, id_rs2; wire [2:0] id_funct3; wire [6:0] id_funct7;
  wire [31:0] id_imm_i,id_imm_s,id_imm_b,id_imm_u,id_imm_j;
  wire id_is_add,id_is_sub,id_is_and,id_is_or,id_is_xor,id_is_sll,id_is_srl,id_is_sra,id_is_slt,id_is_sltu;
  wire id_is_addi,id_is_slti,id_is_sltiu,id_is_xori,id_is_ori,id_is_andi,id_is_slli,id_is_srli,id_is_srai;
  wire id_is_lb,id_is_lh,id_is_lw,id_is_lbu,id_is_lhu;
  wire id_is_sb,id_is_sh,id_is_sw;
  wire id_is_beq,id_is_bne,id_is_blt,id_is_bge,id_is_bltu,id_is_bgeu;
  wire id_is_lui,id_is_auipc,id_is_jal,id_is_jalr;
  wire id_is_ebreak,id_is_ecall,id_is_mret,id_is_fencei;
  wire id_is_csrrw,id_is_csrrs;
  wire id_reg_wen,id_mem_valid,id_mem_wen,id_csr_wen,id_icache_flush;

  IDU u_idu(.inst(id_inst),.ifu_valid(id_valid),
    .opcode(id_opcode),.rd(id_rd),.rs1(id_rs1),.rs2(id_rs2),.funct3(id_funct3),.funct7(id_funct7),
    .imm_i(id_imm_i),.imm_s(id_imm_s),.imm_b(id_imm_b),.imm_u(id_imm_u),.imm_j(id_imm_j),
    .is_add(id_is_add),.is_sub(id_is_sub),.is_and(id_is_and),.is_or(id_is_or),.is_xor(id_is_xor),
    .is_sll(id_is_sll),.is_srl(id_is_srl),.is_sra(id_is_sra),.is_slt(id_is_slt),.is_sltu(id_is_sltu),
    .is_addi(id_is_addi),.is_slti(id_is_slti),.is_sltiu(id_is_sltiu),.is_xori(id_is_xori),.is_ori(id_is_ori),.is_andi(id_is_andi),
    .is_slli(id_is_slli),.is_srli(id_is_srli),.is_srai(id_is_srai),
    .is_lb(id_is_lb),.is_lh(id_is_lh),.is_lw(id_is_lw),.is_lbu(id_is_lbu),.is_lhu(id_is_lhu),
    .is_sb(id_is_sb),.is_sh(id_is_sh),.is_sw(id_is_sw),
    .is_beq(id_is_beq),.is_bne(id_is_bne),.is_blt(id_is_blt),.is_bge(id_is_bge),.is_bltu(id_is_bltu),.is_bgeu(id_is_bgeu),
    .is_lui(id_is_lui),.is_auipc(id_is_auipc),.is_jal(id_is_jal),.is_jalr(id_is_jalr),
    .is_ebreak(id_is_ebreak),.is_ecall(id_is_ecall),.is_mret(id_is_mret),.is_fencei(id_is_fencei),
    .icache_flush(id_icache_flush),.is_csrrw(id_is_csrrw),.is_csrrs(id_is_csrrs),
    .reg_wen(id_reg_wen),.mem_valid(id_mem_valid),.mem_wen(id_mem_wen),.csr_wen(id_csr_wen)
  );

  wire [31:0] rf_rs1, rf_rs2, rf_a0;
  RegisterFile u_rf(.clk(clock),.waddr(wb_waddr),.wdata(wb_wdata),.wen(wb_wen),
    .raddr1(id_rs1),.rdata1(rf_rs1),.raddr2(id_rs2),.rdata2(rf_rs2),.a0_value(rf_a0));

  // ===== ID/EX Pipeline Register =====
  reg         ex_valid;
  reg [31:0]  ex_pc, ex_rs1, ex_rs2;
  reg [31:0]  ex_imm_i,ex_imm_s,ex_imm_b,ex_imm_u,ex_imm_j;
  reg [4:0]   ex_rd; reg [2:0] ex_funct3; reg [6:0] ex_funct7;
  reg ex_is_add,ex_is_sub,ex_is_and,ex_is_or,ex_is_xor,ex_is_sll,ex_is_srl,ex_is_sra,ex_is_slt,ex_is_sltu;
  reg ex_is_addi,ex_is_slti,ex_is_sltiu,ex_is_xori,ex_is_ori,ex_is_andi,ex_is_slli,ex_is_srli,ex_is_srai;
  reg ex_is_lb,ex_is_lh,ex_is_lw,ex_is_lbu,ex_is_lhu;
  reg ex_is_sb,ex_is_sh,ex_is_sw;
  reg ex_is_beq,ex_is_bne,ex_is_blt,ex_is_bge,ex_is_bltu,ex_is_bgeu;
  reg ex_is_lui,ex_is_auipc,ex_is_jal,ex_is_jalr;
  reg ex_is_ebreak,ex_is_ecall,ex_is_mret,ex_is_fencei;
  reg ex_is_csrrw,ex_is_csrrs;
  reg ex_reg_wen,ex_mem_valid,ex_mem_wen,ex_csr_wen;

  // RAW hazard: stall if ID reads a register that EX will write
  // Only stall when EX result hasn't been written to RF yet
  // wb_wen indicates the writeback happens THIS cycle
  wire raw_stall = id_valid && ex_valid && ex_reg_wen && (ex_rd != 5'd0) &&
                   ((ex_rd == id_rs1) || (ex_rd == id_rs2)) && !wb_wen;

  always @(posedge clock) begin
    if (rst) begin ex_valid <= 1'b0; end
    else begin
      // When WB writes the register, the instruction is done; allow next to enter
      if (wb_wen) ex_valid <= 1'b0;
      else if (id_valid && !raw_stall) begin
        ex_valid <= 1'b1;
        ex_pc<=id_pc; ex_rs1<=rf_rs1; ex_rs2<=rf_rs2;
        ex_imm_i<=id_imm_i; ex_imm_s<=id_imm_s; ex_imm_b<=id_imm_b; ex_imm_u<=id_imm_u; ex_imm_j<=id_imm_j;
        ex_rd<=id_rd; ex_funct3<=id_funct3; ex_funct7<=id_funct7;
        ex_is_add<=id_is_add;ex_is_sub<=id_is_sub;ex_is_and<=id_is_and;ex_is_or<=id_is_or;ex_is_xor<=id_is_xor;
        ex_is_sll<=id_is_sll;ex_is_srl<=id_is_srl;ex_is_sra<=id_is_sra;ex_is_slt<=id_is_slt;ex_is_sltu<=id_is_sltu;
        ex_is_addi<=id_is_addi;ex_is_slti<=id_is_slti;ex_is_sltiu<=id_is_sltiu;ex_is_xori<=id_is_xori;ex_is_ori<=id_is_ori;ex_is_andi<=id_is_andi;
        ex_is_slli<=id_is_slli;ex_is_srli<=id_is_srli;ex_is_srai<=id_is_srai;
        ex_is_lb<=id_is_lb;ex_is_lh<=id_is_lh;ex_is_lw<=id_is_lw;ex_is_lbu<=id_is_lbu;ex_is_lhu<=id_is_lhu;
        ex_is_sb<=id_is_sb;ex_is_sh<=id_is_sh;ex_is_sw<=id_is_sw;
        ex_is_beq<=id_is_beq;ex_is_bne<=id_is_bne;ex_is_blt<=id_is_blt;ex_is_bge<=id_is_bge;ex_is_bltu<=id_is_bltu;ex_is_bgeu<=id_is_bgeu;
        ex_is_lui<=id_is_lui;ex_is_auipc<=id_is_auipc;ex_is_jal<=id_is_jal;ex_is_jalr<=id_is_jalr;
        ex_is_ebreak<=id_is_ebreak;ex_is_ecall<=id_is_ecall;ex_is_mret<=id_is_mret;ex_is_fencei<=id_is_fencei;
        ex_is_csrrw<=id_is_csrrw;ex_is_csrrs<=id_is_csrrs;
        ex_reg_wen<=id_reg_wen;ex_mem_valid<=id_mem_valid;ex_mem_wen<=id_mem_wen;ex_csr_wen<=id_csr_wen;
      end
    end
  end

  // ===== EX Stage: EXU + CSR =====
  wire [31:0] csr_rdata, csr_wdata, mepc_out, mtvec_out;
  wire [63:0] mcycle_out;
  CSR u_csr(.clk(clock),.rst(rst),.csr_addr(ex_imm_i[11:0]),.csr_wdata(csr_wdata),.csr_wen(ex_valid&&ex_csr_wen),
    .csr_rdata(csr_rdata),.exception_en(1'b0),.exception_pc(32'd0),.exception_cause(32'd0),.mret_en(1'b0),
    .mepc_out(mepc_out),.mtvec_out(mtvec_out),.mcycle_out(mcycle_out));

  wire [31:0] ex_alu, ex_jtgt, ex_btgt;
  wire        ex_btaken;
  EXU u_exu(.rs1_data(ex_rs1),.rs2_data(ex_rs2),.imm_i(ex_imm_i),.imm_b(ex_imm_b),.imm_j(ex_imm_j),.pc(ex_pc),
    .is_add(ex_is_add),.is_sub(ex_is_sub),.is_and(ex_is_and),.is_or(ex_is_or),.is_xor(ex_is_xor),
    .is_sll(ex_is_sll),.is_srl(ex_is_srl),.is_sra(ex_is_sra),.is_slt(ex_is_slt),.is_sltu(ex_is_sltu),
    .is_addi(ex_is_addi),.is_slti(ex_is_slti),.is_sltiu(ex_is_sltiu),.is_xori(ex_is_xori),.is_ori(ex_is_ori),.is_andi(ex_is_andi),
    .is_slli(ex_is_slli),.is_srli(ex_is_srli),.is_srai(ex_is_srai),
    .is_beq(ex_is_beq),.is_bne(ex_is_bne),.is_blt(ex_is_blt),.is_bge(ex_is_bge),.is_bltu(ex_is_bltu),.is_bgeu(ex_is_bgeu),
    .is_jal(ex_is_jal),.is_jalr(ex_is_jalr),.is_csrrw(ex_is_csrrw),.is_csrrs(ex_is_csrrs),
    .csr_rdata(csr_rdata),.csr_wdata(csr_wdata),
    .alu_result(ex_alu),.jump_target(ex_jtgt),.branch_target(ex_btgt),.branch_taken(ex_btaken));

  // Branch/jump flush
  wire ex_load  = ex_is_lb||ex_is_lh||ex_is_lw||ex_is_lbu||ex_is_lhu;
  wire ex_store = ex_is_sb||ex_is_sh||ex_is_sw;
  wire ex_branch= ex_is_beq||ex_is_bne||ex_is_blt||ex_is_bge||ex_is_bltu||ex_is_bgeu;
  wire ex_jump  = ex_is_jal||ex_is_jalr;
  wire ex_taken = ex_valid && ((ex_branch&&ex_btaken) || ex_jump);
  wire [31:0] ex_target = ex_is_jalr ? ex_jtgt : ex_btgt;
  wire ex_fencei_hit = ex_valid && ex_is_fencei;

  // ===== LS Stage: LSU =====
  wire [31:0] ls_mem_addr = ex_store ? (ex_rs1+ex_imm_s) : (ex_rs1+ex_imm_i);
  wire lsu_arvalid,lsu_arready,lsu_rvalid,lsu_rready,lsu_rlast,lsu_awvalid,lsu_awready,lsu_wvalid,lsu_wready,lsu_wlast,lsu_bvalid,lsu_bready;
  wire [31:0] lsu_araddr,lsu_rdata,lsu_awaddr,lsu_wdata;
  wire [3:0] lsu_arid,lsu_rid,lsu_awid,lsu_wstrb,lsu_bid;
  wire [7:0] lsu_arlen,lsu_awlen;
  wire [2:0] lsu_arsize,lsu_awsize;
  wire [1:0] lsu_arburst,lsu_rresp,lsu_awburst,lsu_bresp;
  wire [31:0] lsu_mrdata;
  wire lsu_fault;

  LSU u_lsu(.clk(clock),.rst(rst),.mem_valid(ex_valid&&ex_mem_valid),.mem_wen(ex_valid&&ex_mem_wen),
    .funct3(ex_funct3),.mem_addr(ls_mem_addr),.wdata(ex_rs2),.cpu_pc(ex_pc),
    .lsu_arvalid(lsu_arvalid),.lsu_arready(lsu_arready),.lsu_araddr(lsu_araddr),.lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen),.lsu_arsize(lsu_arsize),.lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid),.lsu_rready(lsu_rready),.lsu_rdata(lsu_rdata),.lsu_rresp(lsu_rresp),.lsu_rlast(lsu_rlast),.lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid),.lsu_awready(lsu_awready),.lsu_awaddr(lsu_awaddr),.lsu_awid(lsu_awid),
    .lsu_awlen(lsu_awlen),.lsu_awsize(lsu_awsize),.lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid),.lsu_wready(lsu_wready),.lsu_wdata(lsu_wdata),.lsu_wstrb(lsu_wstrb),.lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid),.lsu_bready(lsu_bready),.lsu_bresp(lsu_bresp),.lsu_bid(lsu_bid),
    .rdata(lsu_mrdata),.lsu_access_fault(lsu_fault),
    .lsu_state_o(),.lsu_load_req(),.lsu_store_req(),.lsu_r_handshake(),.lsu_b_handshake(),
    .lsu_wait_ar(),.lsu_wait_r(),.lsu_wait_aw_w(),.lsu_wait_b());

  // ===== WB Stage =====
  wire wb_is_load = ex_is_lb||ex_is_lh||ex_is_lw||ex_is_lbu||ex_is_lhu;
  wire wb_is_store= ex_is_sb||ex_is_sh||ex_is_sw;
  wire wb_is_jump = ex_is_jal||ex_is_jalr;
  wire wb_is_csr  = ex_is_csrrw||ex_is_csrrs;
  wire [31:0] wb_wdata = wb_is_csr ? csr_rdata : wb_is_jump ? (ex_pc+32'd4) : ex_is_lui ? ex_imm_u :
                          ex_is_auipc ? (ex_pc+ex_imm_u) : wb_is_load ? lsu_mrdata : ex_alu;
  wire [4:0] wb_waddr = ex_rd;
  // wb_wen: only fire when instruction is truly complete
  // For loads: wait for LSU response (lsu_rvalid); for stores: wait for LSU write response (lsu_bvalid)
  // For other instructions: can fire immediately
  wire mem_done = !ex_mem_valid ||  // not a memory op
                  (wb_is_load && lsu_rvalid && lsu_rready) ||  // load: R channel handshake
                  (wb_is_store && lsu_bvalid && lsu_bready);    // store: B channel handshake
  wire wb_wen = ex_valid && ex_reg_wen && mem_done &&
                !ex_is_ebreak && !ex_is_ecall && !ex_is_mret;

  // ===== Pipeline Control =====
  wire stall_pipe = raw_stall;
  wire flush_pipe = ex_taken || ex_fencei_hit;
  wire [31:0] redirect_pc = ex_fencei_hit ? (ex_pc+32'd4) : ex_target;

  // ===== ICache =====
  wire icache_flush = ex_fencei_hit;
  wire ic_arvalid,ic_arready,ic_rvalid,ic_rready,ic_rlast;
  wire [31:0] ic_araddr,ic_rdata;
  wire [3:0] ic_arid,ic_rid;
  wire [7:0] ic_arlen;
  wire [2:0] ic_arsize;
  wire [1:0] ic_arburst,ic_rresp;

  ICache u_icache(.clk(clock),.rst(rst),
    .cpu_arvalid(if_arvalid),.cpu_arready(if_arready),.cpu_araddr(if_araddr),.cpu_arid(4'd0),
    .cpu_arlen(8'd0),.cpu_arsize(3'b010),.cpu_arburst(2'b01),
    .cpu_rvalid(if_rvalid),.cpu_rready(if_rready),.cpu_rdata(if_rdata),.cpu_rresp(if_rresp),.cpu_rlast(if_rlast),.cpu_rid(if_rid),
    .bus_arvalid(ic_arvalid),.bus_arready(ic_arready),.bus_araddr(ic_araddr),.bus_arid(ic_arid),
    .bus_arlen(ic_arlen),.bus_arsize(ic_arsize),.bus_arburst(ic_arburst),
    .bus_rvalid(ic_rvalid),.bus_rready(ic_rready),.bus_rdata(ic_rdata),.bus_rresp(ic_rresp),.bus_rlast(ic_rlast),.bus_rid(ic_rid),
    .icache_access(),.icache_hit(),.icache_miss(),.icache_uncache(),.icache_refill_req(),.icache_refill_req_pulse(),
    .icache_wait_ar(),.icache_wait_r(),.flush(icache_flush));

  // ===== CLINT =====
  wire c_arvalid,c_arready,c_rvalid,c_rready,c_rlast,c_awvalid,c_awready,c_wvalid,c_wready,c_wlast,c_bvalid,c_bready;
  wire [31:0] c_araddr,c_rdata,c_awaddr,c_wdata;
  wire [3:0] c_arid,c_rid,c_awid,c_wstrb,c_bid;
  wire [7:0] c_arlen,c_awlen;
  wire [2:0] c_arsize,c_awsize;
  wire [1:0] c_arburst,c_rresp,c_awburst,c_bresp;
  CLINT u_clint(.clk(clock),.rst(rst),
    .clint_arvalid(c_arvalid),.clint_arready(c_arready),.clint_araddr(c_araddr),.clint_arid(c_arid),
    .clint_arlen(c_arlen),.clint_arsize(c_arsize),.clint_arburst(c_arburst),
    .clint_rvalid(c_rvalid),.clint_rready(c_rready),.clint_rdata(c_rdata),.clint_rresp(c_rresp),.clint_rlast(c_rlast),.clint_rid(c_rid),
    .clint_awvalid(c_awvalid),.clint_awready(c_awready),.clint_awaddr(c_awaddr),.clint_awid(c_awid),
    .clint_awlen(c_awlen),.clint_awsize(c_awsize),.clint_awburst(c_awburst),
    .clint_wvalid(c_wvalid),.clint_wready(c_wready),.clint_wdata(c_wdata),.clint_wstrb(c_wstrb),.clint_wlast(c_wlast),
    .clint_bvalid(c_bvalid),.clint_bready(c_bready),.clint_bresp(c_bresp),.clint_bid(c_bid));

  // ===== AXIArbiter =====
  AXIArbiter u_arb(.clk(clock),.rst(rst),
    .ifu_arvalid(ic_arvalid),.ifu_arready(ic_arready),.ifu_araddr(ic_araddr),.ifu_arid(ic_arid),
    .ifu_arlen(ic_arlen),.ifu_arsize(ic_arsize),.ifu_arburst(ic_arburst),
    .ifu_rvalid(ic_rvalid),.ifu_rready(ic_rready),.ifu_rdata(ic_rdata),.ifu_rresp(ic_rresp),.ifu_rlast(ic_rlast),.ifu_rid(ic_rid),
    .lsu_arvalid(lsu_arvalid),.lsu_arready(lsu_arready),.lsu_araddr(lsu_araddr),.lsu_arid(lsu_arid),
    .lsu_arlen(lsu_arlen),.lsu_arsize(lsu_arsize),.lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid),.lsu_rready(lsu_rready),.lsu_rdata(lsu_rdata),.lsu_rresp(lsu_rresp),.lsu_rlast(lsu_rlast),.lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid),.lsu_awready(lsu_awready),.lsu_awaddr(lsu_awaddr),.lsu_awid(lsu_awid),
    .lsu_awlen(lsu_awlen),.lsu_awsize(lsu_awsize),.lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid),.lsu_wready(lsu_wready),.lsu_wdata(lsu_wdata),.lsu_wstrb(lsu_wstrb),.lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid),.lsu_bready(lsu_bready),.lsu_bresp(lsu_bresp),.lsu_bid(lsu_bid),
    .clint_arvalid(c_arvalid),.clint_arready(c_arready),.clint_araddr(c_araddr),.clint_arid(c_arid),
    .clint_arlen(c_arlen),.clint_arsize(c_arsize),.clint_arburst(c_arburst),
    .clint_rvalid(c_rvalid),.clint_rready(c_rready),.clint_rdata(c_rdata),.clint_rresp(c_rresp),.clint_rlast(c_rlast),.clint_rid(c_rid),
    .clint_awvalid(c_awvalid),.clint_awready(c_awready),.clint_awaddr(c_awaddr),.clint_awid(c_awid),
    .clint_awlen(c_awlen),.clint_awsize(c_awsize),.clint_awburst(c_awburst),
    .clint_wvalid(c_wvalid),.clint_wready(c_wready),.clint_wdata(c_wdata),.clint_wstrb(c_wstrb),.clint_wlast(c_wlast),
    .clint_bvalid(c_bvalid),.clint_bready(c_bready),.clint_bresp(c_bresp),.clint_bid(c_bid),
    .mem_arvalid(io_master_arvalid),.mem_arready(io_master_arready),.mem_araddr(io_master_araddr),.mem_arid(io_master_arid),
    .mem_arlen(io_master_arlen),.mem_arsize(io_master_arsize),.mem_arburst(io_master_arburst),
    .mem_rvalid(io_master_rvalid),.mem_rready(io_master_rready),.mem_rdata(io_master_rdata),.mem_rresp(io_master_rresp),.mem_rlast(io_master_rlast),.mem_rid(io_master_rid),
    .mem_awvalid(io_master_awvalid),.mem_awready(io_master_awready),.mem_awaddr(io_master_awaddr),.mem_awid(io_master_awid),
    .mem_awlen(io_master_awlen),.mem_awsize(io_master_awsize),.mem_awburst(io_master_awburst),
    .mem_wvalid(io_master_wvalid),.mem_wready(io_master_wready),.mem_wdata(io_master_wdata),.mem_wstrb(io_master_wstrb),.mem_wlast(io_master_wlast),
    .mem_bvalid(io_master_bvalid),.mem_bready(io_master_bready),.mem_bresp(io_master_bresp),.mem_bid(io_master_bid));

  // ===== DPI =====
`ifndef SYNTHESIS
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void access_fault_handler(input int pc_val, input int is_store);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val, input int target_val);
  import "DPI-C" function void difftest_skip_ref();

  wire ex_mem_is_periph = ex_valid && (ex_load||ex_store) && !(
    (ls_mem_addr>=32'h0f000000 && ls_mem_addr<32'h0f002000)||(ls_mem_addr>=32'h20000000 && ls_mem_addr<32'h20001000)||
    (ls_mem_addr>=32'h30000000 && ls_mem_addr<32'h31000000)||(ls_mem_addr>=32'h80000000 && ls_mem_addr<32'h80400000)||
    (ls_mem_addr>=32'ha0000000 && ls_mem_addr<32'ha2000000));
  always @(posedge clock) if (!rst && ex_mem_is_periph) difftest_skip_ref();

  always @(posedge clock) if (!rst && ex_valid && ex_is_ebreak) begin
    $display("EBREAK detected at PC=0x%08x, a0=0x%08x, mcycle=%0d", ex_pc, rf_a0, mcycle_out);
    ebreak_handler(rf_a0);
  end

  always @(posedge clock) if (!rst && ex_valid) begin
    if (ex_is_jalr) begin
      if (ex_rd==5'd1) ftrace_call_handler(ex_pc,32'd0);
      else if (ex_rd==5'd0) ftrace_ret_handler(ex_pc, 32'd0);
    end
    if (ex_is_jal && ex_rd==5'd1) ftrace_call_handler(ex_pc,32'd0);
  end
`endif

endmodule
