module PipelineCore(
  input clk, input rst,
  output mem_arvalid, input mem_arready, output [31:0] mem_araddr,
  output [3:0] mem_arid, output [7:0] mem_arlen,
  output [2:0] mem_arsize, output [1:0] mem_arburst,
  input mem_rvalid, output mem_rready, input [31:0] mem_rdata,
  input [1:0] mem_rresp, input mem_rlast, input [3:0] mem_rid,
  output mem_awvalid, input mem_awready, output [31:0] mem_awaddr,
  output [3:0] mem_awid, output [7:0] mem_awlen,
  output [2:0] mem_awsize, output [1:0] mem_awburst,
  output mem_wvalid, input mem_wready, output [31:0] mem_wdata,
  output [3:0] mem_wstrb, output mem_wlast,
  input mem_bvalid, output mem_bready, input [1:0] mem_bresp,
  input [3:0] mem_bid
);

  localparam OP_R      = 7'b0110011;
  localparam OP_I      = 7'b0010011;
  localparam OP_LOAD   = 7'b0000011;
  localparam OP_STORE  = 7'b0100011;
  localparam OP_BRANCH = 7'b1100011;
  localparam OP_JAL    = 7'b1101111;
  localparam OP_JALR   = 7'b1100111;
  localparam OP_LUI    = 7'b0110111;
  localparam OP_AUIPC  = 7'b0010111;
  localparam OP_SYSTEM = 7'b1110011;
  localparam OP_FENCE  = 7'b0001111;

  // ---------------- ID decode ----------------
  reg id_valid;
  reg [31:0] id_pc, id_inst;

  wire [6:0] id_op = id_inst[6:0];
  wire [2:0] id_f3 = id_inst[14:12];
  wire [4:0] id_rs1 = id_inst[19:15];
  wire [4:0] id_rs2 = id_inst[24:20];
  wire [4:0] id_rd_full = id_inst[11:7];
  wire [3:0] id_rd = id_rd_full[3:0];
  wire id_rd_valid = id_rd_full != 0 && !id_rd_full[4];

  wire id_is_rtype  = id_op == OP_R;
  wire id_is_itype  = id_op == OP_I;
  wire id_is_load   = id_op == OP_LOAD;
  wire id_is_store  = id_op == OP_STORE;
  wire id_is_branch = id_op == OP_BRANCH;
  wire id_is_jal    = id_op == OP_JAL;
  wire id_is_jalr   = id_op == OP_JALR;
  wire id_is_lui    = id_op == OP_LUI;
  wire id_is_auipc  = id_op == OP_AUIPC;
  wire id_is_csr    = id_op == OP_SYSTEM && id_f3 != 0;
  wire id_is_ecall  = id_inst == 32'h00000073;
  wire id_is_ebreak = id_inst == 32'h00100073;
  wire id_is_mret   = id_inst == 32'h30200073;
  wire id_is_fencei = id_op == OP_FENCE && id_f3 == 3'b001;
  wire id_is_serial = id_op == OP_SYSTEM || id_is_fencei;
  wire id_known = id_is_rtype || id_is_itype || id_is_load || id_is_store ||
                  id_is_branch || id_is_jal || id_is_jalr || id_is_lui ||
                  id_is_auipc || id_is_csr || id_is_ecall || id_is_ebreak ||
                  id_is_mret || id_is_fencei;
  wire id_reg_write = id_rd_valid && (id_is_rtype || id_is_itype || id_is_load ||
                       id_is_jal || id_is_jalr || id_is_lui || id_is_auipc || id_is_csr);
  wire id_uses_rs1 = id_is_rtype || id_is_itype || id_is_load || id_is_store ||
                     id_is_branch || id_is_jalr || id_is_csr;
  wire id_uses_rs2 = id_is_rtype || id_is_store || id_is_branch;
  wire id_exception = id_valid && (id_is_ecall || id_is_ebreak || !id_known);
  wire [3:0] id_excause = id_is_ecall ? 4'd11 : id_is_ebreak ? 4'd3 : 4'd2;

  wire [31:0] id_imm_i = {{20{id_inst[31]}}, id_inst[31:20]};
  wire [31:0] id_imm_s = {{20{id_inst[31]}}, id_inst[31:25], id_inst[11:7]};
  wire [31:0] id_imm_b = {{19{id_inst[31]}}, id_inst[31], id_inst[7],
                           id_inst[30:25], id_inst[11:8], 1'b0};
  wire [31:0] id_imm_u = {id_inst[31:12], 12'b0};
  wire [31:0] id_imm_j = {{11{id_inst[31]}}, id_inst[31], id_inst[19:12],
                           id_inst[20], id_inst[30:21], 1'b0};
  reg [31:0] id_exec_imm;
  always @(*) begin
    case (id_op)
      OP_STORE:  id_exec_imm = id_imm_s;
      OP_BRANCH: id_exec_imm = id_imm_b;
      OP_JAL:    id_exec_imm = id_imm_j;
      OP_LUI,
      OP_AUIPC:  id_exec_imm = id_imm_u;
      default:   id_exec_imm = id_imm_i;
    endcase
  end
  wire [31:0] id_early_target = id_pc + (id_is_jal ? id_imm_j : id_imm_b);

  // ---------------- Compact pipeline state ----------------
  reg ex_valid, ls_valid;
  reg [31:0] ex_pc, ex_rs1, ex_rs2, ex_imm;
  reg [11:0] ex_csr_addr;
  reg [3:0] ex_rd;
  reg [2:0] ex_f3;
  reg ex_f7_bit5, ex_rs1_nonzero;
  reg ex_reg_write, ex_is_rtype, ex_is_itype, ex_is_load, ex_is_store;
  reg ex_is_branch, ex_is_jal, ex_is_jalr, ex_is_lui, ex_is_auipc;
  reg ex_is_csr, ex_is_ecall, ex_is_ebreak, ex_is_mret, ex_is_fencei;
  reg ex_exception;
  reg [3:0] ex_excause;

  reg [31:0] ls_pc, ls_value, ls_aux;
  reg [3:0] ls_rd;
  reg [2:0] ls_f3;
  reg ls_rs1_nonzero, ls_reg_write, ls_is_load, ls_is_store, ls_is_branch;
  reg ls_is_jal, ls_is_jalr, ls_is_csr, ls_is_ecall, ls_is_ebreak;
  reg ls_is_mret, ls_is_fencei, ls_is_calc, ls_is_utype;
  reg ls_branch_taken, ls_exception;
  reg [3:0] ls_excause;

  reg prev_lsu_fault;

`ifndef SYNTHESIS
  reg [31:0] ex_inst_dbg, ls_inst_dbg;
`endif

  // ---------------- Register file and forwarding ----------------
  wire [31:0] rf_rs1, rf_rs2, a0_value;
  wire ls_retire = ls_valid && ls_done;
  wire ls_commit_exception = ls_exception || ls_misaligned || (ls_is_mem && lsu_fault_rise);
  wire [3:0] ls_commit_excause = ls_exception ? ls_excause : ls_misaligned ?
                                   (ls_is_load ? 4'd4 : 4'd6) :
                                   (ls_is_load ? 4'd5 : 4'd7);
  wire [31:0] ls_commit_data = ls_is_load ? lsu_rdata : ls_value;
  wire ls_reg_wen = ls_retire && ls_reg_write && !ls_commit_exception;
  RegisterFile u_rf(
    .clk(clk), .wdata(ls_commit_data), .waddr({1'b0, ls_rd}), .wen(ls_reg_wen),
    .raddr1(id_rs1), .rdata1(rf_rs1), .raddr2(id_rs2), .rdata2(rf_rs2),
    .a0_value(a0_value)
  );

  // ---------------- EX execute ----------------
  reg [31:0] ex_alu;
  always @(*) begin
    ex_alu = 0;
    if (ex_is_rtype) begin
      case (ex_f3)
        3'b000: ex_alu = ex_f7_bit5 ? ex_rs1 - ex_rs2 : ex_rs1 + ex_rs2;
        3'b001: ex_alu = ex_rs1 << ex_rs2[4:0];
        3'b010: ex_alu = {31'b0, $signed(ex_rs1) < $signed(ex_rs2)};
        3'b011: ex_alu = {31'b0, ex_rs1 < ex_rs2};
        3'b100: ex_alu = ex_rs1 ^ ex_rs2;
        3'b101: begin
          if (ex_f7_bit5) ex_alu = $signed(ex_rs1) >>> ex_rs2[4:0];
          else ex_alu = ex_rs1 >> ex_rs2[4:0];
        end
        3'b110: ex_alu = ex_rs1 | ex_rs2;
        3'b111: ex_alu = ex_rs1 & ex_rs2;
      endcase
    end else if (ex_is_itype) begin
      case (ex_f3)
        3'b000: ex_alu = ex_rs1 + ex_imm;
        3'b001: ex_alu = ex_rs1 << ex_imm[4:0];
        3'b010: ex_alu = {31'b0, $signed(ex_rs1) < $signed(ex_imm)};
        3'b011: ex_alu = {31'b0, ex_rs1 < ex_imm};
        3'b100: ex_alu = ex_rs1 ^ ex_imm;
        3'b101: begin
          if (ex_f7_bit5) ex_alu = $signed(ex_rs1) >>> ex_imm[4:0];
          else ex_alu = ex_rs1 >> ex_imm[4:0];
        end
        3'b110: ex_alu = ex_rs1 | ex_imm;
        3'b111: ex_alu = ex_rs1 & ex_imm;
      endcase
    end
  end

  reg ex_branch_taken;
  always @(*) begin
    case (ex_f3)
      3'b000: ex_branch_taken = ex_rs1 == ex_rs2;
      3'b001: ex_branch_taken = ex_rs1 != ex_rs2;
      3'b100: ex_branch_taken = $signed(ex_rs1) < $signed(ex_rs2);
      3'b101: ex_branch_taken = $signed(ex_rs1) >= $signed(ex_rs2);
      3'b110: ex_branch_taken = ex_rs1 < ex_rs2;
      3'b111: ex_branch_taken = ex_rs1 >= ex_rs2;
      default: ex_branch_taken = 1'b0;
    endcase
  end

  wire [31:0] ex_mem_addr = ex_rs1 + ex_imm;
  wire [31:0] ex_jalr_target = (ex_rs1 + ex_imm) & ~32'h1;
  wire [31:0] ex_branch_target = ex_pc + ex_imm;
  // Branch and JAL are predicted taken in ID. Only a not-taken branch needs correction.
  wire ex_redirect_kind = (ex_is_branch && !ex_branch_taken) || ex_is_jalr ||
                          ex_is_ecall || ex_is_mret || ex_is_fencei;
  reg [31:0] ex_redirect_target;
  always @(*) begin
    case ({ex_is_branch, ex_is_jalr, ex_is_ecall, ex_is_mret, ex_is_fencei})
      5'b01000: ex_redirect_target = ex_jalr_target;
      5'b00100: ex_redirect_target = mtvec;
      5'b00010: ex_redirect_target = mepc;
      default:  ex_redirect_target = ex_pc + 4;
    endcase
  end

  wire [31:0] csr_rdata, mepc, mtvec;
  wire [63:0] core_time;
  wire [31:0] ex_csr_wdata = ex_f3 == 3'b001 ? ex_rs1 : csr_rdata | ex_rs1;
  wire ls_csr_wen = ls_retire && ls_is_csr && !ls_commit_exception &&
                    (ls_f3 == 3'b001 || ls_rs1_nonzero);
  CSR u_csr(
    .clk(clk), .rst(rst), .csr_addr(ex_csr_addr),
    .csr_wdata(ls_aux), .csr_wen(ls_csr_wen), .csr_rdata(csr_rdata),
    .exception_en(ls_retire && ls_commit_exception),
    .exception_pc(ls_pc), .exception_cause({28'b0, ls_commit_excause}),
    .mret_en(ls_retire && ls_is_mret),
    .mepc_out(mepc), .mtvec_out(mtvec), .mcycle_out(core_time)
  );

  reg [31:0] ex_result;
  always @(*) begin
    case ({ex_is_csr, (ex_is_jal || ex_is_jalr), ex_is_lui, ex_is_auipc})
      4'b1000: ex_result = csr_rdata;
      4'b0100: ex_result = ex_pc + 4;
      4'b0010: ex_result = ex_imm;
      4'b0001: ex_result = ex_pc + ex_imm;
      default: ex_result = ex_alu;
    endcase
  end

  // ---------------- LSU ----------------
  wire ls_is_mem = ls_is_load || ls_is_store;
  wire [31:0] lsu_rdata;
  wire lsu_fault, lsu_r_hs, lsu_b_hs;
  wire lsu_arvalid, lsu_arready, lsu_rvalid, lsu_rready;
  wire [31:0] lsu_araddr, lsu_bus_rdata;
  wire [3:0] lsu_arid, lsu_bus_rid;
  wire [7:0] lsu_arlen;
  wire [2:0] lsu_arsize;
  wire [1:0] lsu_arburst, lsu_bus_rresp;
  wire lsu_bus_rlast;
  wire lsu_awvalid, lsu_awready, lsu_wvalid, lsu_wready, lsu_wlast;
  wire [31:0] lsu_awaddr, lsu_wdata;
  wire [3:0] lsu_awid, lsu_wstrb, lsu_bid;
  wire [7:0] lsu_awlen;
  wire [2:0] lsu_awsize;
  wire [1:0] lsu_awburst, lsu_bresp;
  wire lsu_bvalid, lsu_bready;
  wire lsu_load_req, lsu_store_req, lsu_wait_ar, lsu_wait_r, lsu_wait_aw_w, lsu_wait_b;

  LSU u_lsu(
    .clk(clk), .rst(rst), .mem_valid(ls_valid && ls_is_mem),
    .mem_wen(ls_is_store), .funct3(ls_f3), .mem_addr(ls_value),
    .wdata(ls_aux), .cpu_pc(ls_pc),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready), .lsu_araddr(lsu_araddr),
    .lsu_arid(lsu_arid), .lsu_arlen(lsu_arlen), .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready), .lsu_rdata(lsu_bus_rdata),
    .lsu_rresp(lsu_bus_rresp), .lsu_rlast(lsu_bus_rlast), .lsu_rid(lsu_bus_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready), .lsu_awaddr(lsu_awaddr),
    .lsu_awid(lsu_awid), .lsu_awlen(lsu_awlen), .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready), .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready), .lsu_bresp(lsu_bresp), .lsu_bid(lsu_bid),
    .rdata(lsu_rdata), .lsu_access_fault(lsu_fault), .lsu_state_o(),
    .lsu_load_req(lsu_load_req), .lsu_store_req(lsu_store_req), .lsu_r_handshake(lsu_r_hs),
    .lsu_b_handshake(lsu_b_hs), .lsu_wait_ar(lsu_wait_ar), .lsu_wait_r(lsu_wait_r),
    .lsu_wait_aw_w(lsu_wait_aw_w), .lsu_wait_b(lsu_wait_b)
  );

  wire ls_done = !ls_is_mem || (ls_is_load ? lsu_r_hs : lsu_b_hs);
  wire ls_ready = !ls_valid || ls_done;
  wire ex_ready = !ex_valid || ls_ready;

  wire ex_fwd_ready = ex_valid && ex_reg_write && !ex_is_load;
  wire ls_fwd_ready = ls_valid && ls_reg_write && (!ls_is_load || lsu_r_hs);
  wire rs1_ex_match = id_uses_rs1 && ex_valid && ex_reg_write && !id_rs1[4] && id_rs1[3:0] == ex_rd;
  wire rs1_ls_match = id_uses_rs1 && ls_valid && ls_reg_write && !id_rs1[4] && id_rs1[3:0] == ls_rd;
  wire rs2_ex_match = id_uses_rs2 && ex_valid && ex_reg_write && !id_rs2[4] && id_rs2[3:0] == ex_rd;
  wire rs2_ls_match = id_uses_rs2 && ls_valid && ls_reg_write && !id_rs2[4] && id_rs2[3:0] == ls_rd;
  reg rs1_wait, rs2_wait;
  wire unresolved_raw = rs1_wait || rs2_wait;
  wire [31:0] ls_fwd_data = ls_is_load ? lsu_rdata : ls_value;
  reg [31:0] id_rs1_value, id_rs2_value;
  always @(*) begin
    rs1_wait = 1'b0;
    id_rs1_value = rf_rs1;
    case ({rs1_ex_match, rs1_ls_match})
      2'b01: begin
        rs1_wait = !ls_fwd_ready;
        id_rs1_value = ls_fwd_data;
      end
      2'b10,
      2'b11: begin
        rs1_wait = !ex_fwd_ready;
        id_rs1_value = ex_result;
      end
      default: ;
    endcase

    rs2_wait = 1'b0;
    id_rs2_value = rf_rs2;
    case ({rs2_ex_match, rs2_ls_match})
      2'b01: begin
        rs2_wait = !ls_fwd_ready;
        id_rs2_value = ls_fwd_data;
      end
      2'b10,
      2'b11: begin
        rs2_wait = !ex_fwd_ready;
        id_rs2_value = ex_result;
      end
      default: ;
    endcase
  end

  wire serial_in_pipe = (ex_valid && (ex_is_csr || ex_is_ecall || ex_is_ebreak || ex_is_mret || ex_is_fencei)) ||
                        (ls_valid && (ls_is_csr || ls_is_ecall || ls_is_ebreak || ls_is_mret || ls_is_fencei));
  wire serial_hazard = (id_is_serial && (ex_valid || ls_valid)) || serial_in_pipe;
  wire id_hazard = id_valid && (unresolved_raw || serial_hazard);
  wire id_issue = id_valid && !id_hazard && ex_ready;
  wire id_ready = !id_valid || id_issue;
  wire ex_advance = ex_valid && ls_ready;
  wire ex_redirect = ex_advance && ex_redirect_kind;
  wire id_early_redirect = id_issue && (id_is_branch || id_is_jal) && !ex_redirect;

  wire ls_misaligned = ls_is_mem && ls_valid &&
    (((ls_f3 == 3'b010) && ls_value[1:0] != 0) ||
     ((ls_f3 == 3'b001 || ls_f3 == 3'b101) && ls_value[0]));
  wire lsu_fault_rise = lsu_fault && !prev_lsu_fault;

  // ---------------- I-Cache and bus fabric ----------------
  wire icache_access, icache_hit, icache_miss, icache_uncache;
  wire icache_refill_req, icache_refill_req_pulse, icache_wait_ar, icache_wait_r;
  wire if_arvalid, if_arready, if_rvalid, if_rready;
  wire [31:0] if_araddr, if_rdata;
  wire [3:0] if_arid, if_rid;
  wire [7:0] if_arlen;
  wire [2:0] if_arsize;
  wire [1:0] if_arburst, if_rresp;
  wire if_rlast;
  wire ic_arvalid, ic_arready, ic_rvalid, ic_rready;
  wire [31:0] ic_araddr, ic_rdata;
  wire [3:0] ic_arid, ic_rid;
  wire [7:0] ic_arlen;
  wire [2:0] ic_arsize;
  wire [1:0] ic_arburst, ic_rresp;
  wire ic_rlast;
  wire icache_flush = ex_advance && ex_is_fencei;

  ICache u_icache(
    .clk(clk), .rst(rst), .cpu_arvalid(if_arvalid), .cpu_arready(if_arready),
    .cpu_araddr(if_araddr), .cpu_arid(if_arid), .cpu_arlen(if_arlen),
    .cpu_arsize(if_arsize), .cpu_arburst(if_arburst), .cpu_rvalid(if_rvalid),
    .cpu_rready(if_rready), .cpu_rdata(if_rdata), .cpu_rresp(if_rresp),
    .cpu_rlast(if_rlast), .cpu_rid(if_rid), .bus_arvalid(ic_arvalid),
    .bus_arready(ic_arready), .bus_araddr(ic_araddr), .bus_arid(ic_arid),
    .bus_arlen(ic_arlen), .bus_arsize(ic_arsize), .bus_arburst(ic_arburst),
    .bus_rvalid(ic_rvalid), .bus_rready(ic_rready), .bus_rdata(ic_rdata),
    .bus_rresp(ic_rresp), .bus_rlast(ic_rlast), .bus_rid(ic_rid),
    .icache_access(icache_access), .icache_hit(icache_hit), .icache_miss(icache_miss),
    .icache_uncache(icache_uncache), .icache_refill_req(icache_refill_req),
    .icache_refill_req_pulse(icache_refill_req_pulse), .icache_wait_ar(icache_wait_ar),
    .icache_wait_r(icache_wait_r), .flush(icache_flush)
  );

  wire cl_arvalid, cl_arready, cl_rvalid, cl_rready;
  wire [31:0] cl_araddr, cl_rdata;
  wire [3:0] cl_arid, cl_rid;
  wire [7:0] cl_arlen;
  wire [2:0] cl_arsize;
  wire [1:0] cl_arburst, cl_rresp;
  wire cl_rlast, cl_awvalid, cl_awready, cl_wvalid, cl_wready, cl_wlast;
  wire [31:0] cl_awaddr, cl_wdata;
  wire [3:0] cl_awid, cl_wstrb, cl_bid;
  wire [7:0] cl_awlen;
  wire [2:0] cl_awsize;
  wire [1:0] cl_awburst, cl_bresp;
  wire cl_bvalid, cl_bready;
  CLINT u_clint(
    .clk(clk), .rst(rst), .mtime(core_time),
    .clint_arvalid(cl_arvalid), .clint_arready(cl_arready), .clint_araddr(cl_araddr),
    .clint_arid(cl_arid), .clint_arlen(cl_arlen), .clint_arsize(cl_arsize),
    .clint_arburst(cl_arburst), .clint_rvalid(cl_rvalid), .clint_rready(cl_rready),
    .clint_rdata(cl_rdata), .clint_rresp(cl_rresp), .clint_rlast(cl_rlast), .clint_rid(cl_rid),
    .clint_awvalid(cl_awvalid), .clint_awready(cl_awready), .clint_awaddr(cl_awaddr),
    .clint_awid(cl_awid), .clint_awlen(cl_awlen), .clint_awsize(cl_awsize),
    .clint_awburst(cl_awburst), .clint_wvalid(cl_wvalid), .clint_wready(cl_wready),
    .clint_wdata(cl_wdata), .clint_wstrb(cl_wstrb), .clint_wlast(cl_wlast),
    .clint_bvalid(cl_bvalid), .clint_bready(cl_bready), .clint_bresp(cl_bresp), .clint_bid(cl_bid)
  );

  AXIArbiter u_arbiter(
    .clk(clk), .rst(rst),
    .ifu_arvalid(ic_arvalid), .ifu_arready(ic_arready), .ifu_araddr(ic_araddr),
    .ifu_arid(ic_arid), .ifu_arlen(ic_arlen), .ifu_arsize(ic_arsize), .ifu_arburst(ic_arburst),
    .ifu_rvalid(ic_rvalid), .ifu_rready(ic_rready), .ifu_rdata(ic_rdata),
    .ifu_rresp(ic_rresp), .ifu_rlast(ic_rlast), .ifu_rid(ic_rid),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready), .lsu_araddr(lsu_araddr),
    .lsu_arid(lsu_arid), .lsu_arlen(lsu_arlen), .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready), .lsu_rdata(lsu_bus_rdata),
    .lsu_rresp(lsu_bus_rresp), .lsu_rlast(lsu_bus_rlast), .lsu_rid(lsu_bus_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready), .lsu_awaddr(lsu_awaddr),
    .lsu_awid(lsu_awid), .lsu_awlen(lsu_awlen), .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready), .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast), .lsu_bvalid(lsu_bvalid),
    .lsu_bready(lsu_bready), .lsu_bresp(lsu_bresp), .lsu_bid(lsu_bid),
    .clint_arvalid(cl_arvalid), .clint_arready(cl_arready), .clint_araddr(cl_araddr),
    .clint_arid(cl_arid), .clint_arlen(cl_arlen), .clint_arsize(cl_arsize), .clint_arburst(cl_arburst),
    .clint_rvalid(cl_rvalid), .clint_rready(cl_rready), .clint_rdata(cl_rdata),
    .clint_rresp(cl_rresp), .clint_rlast(cl_rlast), .clint_rid(cl_rid),
    .clint_awvalid(cl_awvalid), .clint_awready(cl_awready), .clint_awaddr(cl_awaddr),
    .clint_awid(cl_awid), .clint_awlen(cl_awlen), .clint_awsize(cl_awsize), .clint_awburst(cl_awburst),
    .clint_wvalid(cl_wvalid), .clint_wready(cl_wready), .clint_wdata(cl_wdata),
    .clint_wstrb(cl_wstrb), .clint_wlast(cl_wlast), .clint_bvalid(cl_bvalid),
    .clint_bready(cl_bready), .clint_bresp(cl_bresp), .clint_bid(cl_bid),
    .mem_arvalid(mem_arvalid), .mem_arready(mem_arready), .mem_araddr(mem_araddr),
    .mem_arid(mem_arid), .mem_arlen(mem_arlen), .mem_arsize(mem_arsize), .mem_arburst(mem_arburst),
    .mem_rvalid(mem_rvalid), .mem_rready(mem_rready), .mem_rdata(mem_rdata),
    .mem_rresp(mem_rresp), .mem_rlast(mem_rlast), .mem_rid(mem_rid),
    .mem_awvalid(mem_awvalid), .mem_awready(mem_awready), .mem_awaddr(mem_awaddr),
    .mem_awid(mem_awid), .mem_awlen(mem_awlen), .mem_awsize(mem_awsize), .mem_awburst(mem_awburst),
    .mem_wvalid(mem_wvalid), .mem_wready(mem_wready), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_wlast(mem_wlast), .mem_bvalid(mem_bvalid),
    .mem_bready(mem_bready), .mem_bresp(mem_bresp), .mem_bid(mem_bid)
  );

  // ---------------- Non-pipelined fetch engine ----------------
  localparam F_REQ = 1'b0, F_WAIT = 1'b1;
  reg fetch_state, fetch_discard;
  reg [31:0] fetch_pc, requested_pc;
  wire exception_redirect = ls_retire && ls_commit_exception;
  wire fetch_flush = ex_redirect || id_early_redirect || exception_redirect;
  assign if_arvalid = !rst && !fetch_flush && !fetch_discard && id_ready && fetch_state == F_REQ;
  assign if_araddr = fetch_pc;
  assign if_arid = 0;
  assign if_arlen = 0;
  assign if_arsize = 3'b010;
  assign if_arburst = 2'b01;
  assign if_rready = fetch_state == F_WAIT && id_ready && !rst;

`ifndef SYNTHESIS
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void commit_instruction(input int pc_val, input int inst_val, input int next_pc_val);
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val, input int target_val);
  import "DPI-C" function void difftest_skip_ref();
  wire ls_peripheral_dbg = ls_is_mem &&
    ((ls_value >= 32'h02000000 && ls_value < 32'h02010000) ||
     (ls_value >= 32'h10000000 && ls_value < 32'h10020000) ||
     (ls_value >= 32'h21000000 && ls_value < 32'h21200000));
  wire [31:0] ls_next_pc_dbg = (ls_is_branch || ls_is_jal || ls_is_jalr ||
                                ls_is_ecall || ls_is_mret) ? ls_aux : ls_pc + 4;
`endif

  always @(posedge clk) begin
    if (rst) begin
      id_valid <= 0; ex_valid <= 0; ls_valid <= 0;
      ex_exception <= 0; ls_exception <= 0;
      prev_lsu_fault <= 0;
      fetch_state <= F_REQ; fetch_discard <= 0;
`ifdef SOC_MODE
      fetch_pc <= 32'h30000000;
      requested_pc <= 32'h30000000;
`ifndef SYNTHESIS
      update_pc_value(32'h30000000);
`endif
`else
      fetch_pc <= 32'h80000000;
      requested_pc <= 32'h80000000;
`ifndef SYNTHESIS
      update_pc_value(32'h80000000);
`endif
`endif
    end else begin
      if (ls_ready) begin
        ls_valid <= ex_valid;
        if (ex_valid) begin
          ls_pc <= ex_pc;
          ls_value <= (ex_is_load || ex_is_store) ? ex_mem_addr : ex_result;
          case ({ex_is_store, ex_is_csr, ex_is_branch, ex_is_jal,
                 ex_is_jalr, ex_is_ecall, ex_is_mret})
            7'b1000000: ls_aux <= ex_rs2;
            7'b0100000: ls_aux <= ex_csr_wdata;
            7'b0010000: begin
              if (ex_branch_taken) ls_aux <= ex_branch_target;
              else ls_aux <= ex_pc + 4;
            end
            7'b0001000: ls_aux <= ex_pc + ex_imm;
            7'b0000100: ls_aux <= ex_jalr_target;
            7'b0000010: ls_aux <= mtvec;
            7'b0000001: ls_aux <= mepc;
            default:    ls_aux <= 32'b0;
          endcase
          ls_rd <= ex_rd; ls_f3 <= ex_f3; ls_rs1_nonzero <= ex_rs1_nonzero;
          ls_reg_write <= ex_reg_write; ls_is_load <= ex_is_load; ls_is_store <= ex_is_store;
          ls_is_branch <= ex_is_branch; ls_is_jal <= ex_is_jal; ls_is_jalr <= ex_is_jalr;
          ls_is_csr <= ex_is_csr; ls_is_ecall <= ex_is_ecall; ls_is_ebreak <= ex_is_ebreak;
          ls_is_mret <= ex_is_mret; ls_is_fencei <= ex_is_fencei;
          ls_is_calc <= ex_is_rtype || ex_is_itype;
          ls_is_utype <= ex_is_lui || ex_is_auipc;
          ls_branch_taken <= ex_branch_taken;
`ifndef SYNTHESIS
          ls_inst_dbg <= ex_inst_dbg;
`endif
        end
        ls_exception <= ex_valid ? ex_exception : 0;
        ls_excause <= ex_excause;
      end

      if (ex_ready) begin
        ex_valid <= id_valid && !id_hazard && !ex_redirect;
        if (id_valid && !id_hazard && !ex_redirect) begin
          ex_pc <= id_pc; ex_rs1 <= id_rs1_value; ex_rs2 <= id_rs2_value;
          ex_imm <= id_exec_imm; ex_csr_addr <= id_inst[31:20]; ex_rd <= id_rd;
          ex_f3 <= id_f3; ex_f7_bit5 <= id_inst[30]; ex_rs1_nonzero <= id_rs1 != 0;
          ex_reg_write <= id_reg_write; ex_is_rtype <= id_is_rtype; ex_is_itype <= id_is_itype;
          ex_is_load <= id_is_load; ex_is_store <= id_is_store; ex_is_branch <= id_is_branch;
          ex_is_jal <= id_is_jal; ex_is_jalr <= id_is_jalr; ex_is_lui <= id_is_lui;
          ex_is_auipc <= id_is_auipc; ex_is_csr <= id_is_csr; ex_is_ecall <= id_is_ecall;
          ex_is_ebreak <= id_is_ebreak; ex_is_mret <= id_is_mret; ex_is_fencei <= id_is_fencei;
          ex_exception <= id_exception; ex_excause <= id_excause;
`ifndef SYNTHESIS
          ex_inst_dbg <= id_inst;
`endif
        end else begin
          ex_exception <= 0;
        end
      end

      if (ex_redirect) begin
        id_valid <= 0;
        fetch_pc <= ex_redirect_target;
        if (ex_is_fencei) begin
          fetch_state <= F_REQ;
          fetch_discard <= 0;
        end else if (fetch_state == F_WAIT) begin
          fetch_discard <= 1;
        end
      end else if (id_early_redirect) begin
        id_valid <= 0;
        fetch_pc <= id_early_target;
        if (fetch_state == F_WAIT) fetch_discard <= 1;
      end else if (id_issue) begin
        id_valid <= 0;
      end

      if (exception_redirect) begin
        id_valid <= 0; ex_valid <= 0;
        fetch_pc <= mtvec;
        if (fetch_state == F_WAIT) fetch_discard <= 1;
      end

      prev_lsu_fault <= lsu_fault;

      if (fetch_state == F_REQ && if_arvalid && if_arready) begin
        requested_pc <= fetch_pc;
        fetch_pc <= fetch_pc + 4;
        fetch_state <= F_WAIT;
      end
      if (fetch_state == F_WAIT && if_rvalid && if_rready) begin
        if (fetch_discard || fetch_flush) begin
          fetch_discard <= 0;
          fetch_state <= F_REQ;
        end else begin
          id_valid <= 1;
          id_pc <= requested_pc;
          id_inst <= if_rresp[1] ? 32'h00100073 : if_rdata;
          fetch_state <= F_REQ;
        end
      end

`ifndef SYNTHESIS
      if (ls_retire) begin
        commit_instruction(ls_pc, ls_inst_dbg, ls_next_pc_dbg);
        if (ls_peripheral_dbg) difftest_skip_ref();
        if (ls_is_ebreak) ebreak_handler(a0_value);
        if (ls_is_jal && ls_rd == 1) ftrace_call_handler(ls_pc, ls_next_pc_dbg);
        if (ls_is_jalr && ls_rd == 1) ftrace_call_handler(ls_pc, ls_next_pc_dbg);
        if (ls_is_jalr && ls_rd == 0 && ls_inst_dbg[19:15] == 1)
          ftrace_ret_handler(ls_pc, ls_next_pc_dbg);
      end
`endif
    end
  end

  wire stall_raw = id_valid && unresolved_raw && ex_ready;
  wire stall_lsu = ex_valid && !ls_ready;
  wire stall_fetch = !id_valid && !fetch_flush && !rst;
  wire pipe_flush = ex_redirect || id_early_redirect;

`ifdef ENABLE_PERF
  PerfCounter u_perf(
    .clk(clk), .rst(rst), .pipe_retire(ls_retire),
    .pipe_stall_raw(stall_raw), .pipe_stall_lsu(stall_lsu),
    .pipe_stall_fetch(stall_fetch), .pipe_flush(pipe_flush),
    .pipe_id_valid(id_valid), .pipe_ex_valid(ex_valid), .pipe_ls_valid(ls_valid),
    .icache_access(icache_access), .icache_hit(icache_hit), .icache_miss(icache_miss),
    .icache_uncache(icache_uncache), .icache_refill_req(icache_refill_req),
    .icache_refill_req_pulse(icache_refill_req_pulse), .icache_wait_ar(icache_wait_ar),
    .icache_wait_r(icache_wait_r), .lsu_r_handshake(lsu_r_hs), .lsu_b_handshake(lsu_b_hs),
    .wb_is_calc(ls_is_calc), .wb_is_load(ls_is_load), .wb_is_store(ls_is_store),
    .wb_is_branch(ls_is_branch), .wb_is_jump(ls_is_jal || ls_is_jalr),
    .wb_is_utype(ls_is_utype), .wb_is_csr_op(ls_is_csr),
    .wb_is_sys_op(ls_is_ecall || ls_is_ebreak || ls_is_mret || ls_is_fencei),
    .pipe_branch_taken(ls_retire && ls_is_branch && ls_branch_taken),
    .pipe_branch_predict_resolved(ex_advance && ex_is_branch),
    .pipe_branch_predict_correct(ex_advance && ex_is_branch && ex_branch_taken),
    .pipe_reg_wen(ls_reg_wen), .pipe_exception(ls_retire && ls_commit_exception)
  );
`endif

endmodule
