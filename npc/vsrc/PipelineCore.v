// Simple in-order RV32E pipeline used by the B5 implementation.
// Hazards are handled conservatively: RAW dependencies stall in ID, the LSU
// back-pressures the whole pipe, and EX redirects flush all younger work.
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

  function writes_rd;
    input [31:0] i;
    reg [6:0] op;
    begin
      op = i[6:0];
      writes_rd = (i[11:7] != 0) &&
        (op == 7'b0110011 || op == 7'b0010011 || op == 7'b0000011 ||
         op == 7'b1101111 || op == 7'b1100111 || op == 7'b0110111 ||
         op == 7'b0010111 || (op == 7'b1110011 && i[14:12] != 0));
    end
  endfunction

  function uses_rs1;
    input [31:0] i;
    reg [6:0] op;
    begin
      op = i[6:0];
      uses_rs1 = op == 7'b0110011 || op == 7'b0010011 || op == 7'b0000011 ||
                 op == 7'b0100011 || op == 7'b1100011 || op == 7'b1100111 ||
                 (op == 7'b1110011 && i[14:12] != 0);
    end
  endfunction

  function uses_rs2;
    input [31:0] i;
    reg [6:0] op;
    begin
      op = i[6:0];
      uses_rs2 = op == 7'b0110011 || op == 7'b0100011 || op == 7'b1100011;
    end
  endfunction

  function is_serial;
    input [31:0] i;
    begin
      is_serial = (i[6:0] == 7'b1110011) ||
                  (i[6:0] == 7'b0001111 && i[14:12] == 3'b001);
    end
  endfunction

  // ---------------- Pipeline registers ----------------
  reg id_valid, ex_valid, ls_valid, wb_valid;
  reg [31:0] id_pc, id_inst;
  reg [31:0] ex_pc, ex_inst, ex_rs1, ex_rs2;
  reg [31:0] ls_pc, ls_inst, ls_result, ls_addr, ls_store_data;
  reg [31:0] ls_csr_wdata;
  reg [31:0] wb_pc, wb_inst, wb_data, wb_csr_wdata;
  reg [31:0] wb_next_pc;

  wire [4:0] id_rs1 = id_inst[19:15];
  wire [4:0] id_rs2 = id_inst[24:20];
  wire [4:0] ex_rd = ex_inst[11:7];
  wire [4:0] ls_rd = ls_inst[11:7];
  wire [4:0] wb_rd = wb_inst[11:7];

  wire raw_ex = ex_valid && writes_rd(ex_inst) &&
                ((uses_rs1(id_inst) && id_rs1 == ex_rd) ||
                 (uses_rs2(id_inst) && id_rs2 == ex_rd));
  wire raw_ls = ls_valid && writes_rd(ls_inst) &&
                ((uses_rs1(id_inst) && id_rs1 == ls_rd) ||
                 (uses_rs2(id_inst) && id_rs2 == ls_rd));
  wire raw_wb = wb_valid && writes_rd(wb_inst) &&
                ((uses_rs1(id_inst) && id_rs1 == wb_rd) ||
                 (uses_rs2(id_inst) && id_rs2 == wb_rd));
  wire serial_hazard = (is_serial(id_inst) && (ex_valid || ls_valid || wb_valid)) ||
                       ((ex_valid && is_serial(ex_inst)) ||
                        (ls_valid && is_serial(ls_inst)) ||
                        (wb_valid && is_serial(wb_inst)));
  wire id_hazard = id_valid && (raw_ex || raw_ls || raw_wb || serial_hazard);

  wire [31:0] rf_rs1, rf_rs2, a0_value;
  wire wb_reg_wen = wb_valid && writes_rd(wb_inst);
  RegisterFile u_rf(
    .clk(clk), .wdata(wb_data), .waddr(wb_rd), .wen(wb_reg_wen),
    .raddr1(id_rs1), .rdata1(rf_rs1), .raddr2(id_rs2), .rdata2(rf_rs2),
    .a0_value(a0_value)
  );

  // ---------------- EX stage ----------------
  wire [6:0] ex_op = ex_inst[6:0];
  wire [2:0] ex_f3 = ex_inst[14:12];
  wire [6:0] ex_f7 = ex_inst[31:25];
  wire [31:0] ex_imm_i = {{20{ex_inst[31]}}, ex_inst[31:20]};
  wire [31:0] ex_imm_s = {{20{ex_inst[31]}}, ex_inst[31:25], ex_inst[11:7]};
  wire [31:0] ex_imm_b = {{19{ex_inst[31]}}, ex_inst[31], ex_inst[7], ex_inst[30:25], ex_inst[11:8], 1'b0};
  wire [31:0] ex_imm_u = {ex_inst[31:12], 12'b0};
  wire [31:0] ex_imm_j = {{11{ex_inst[31]}}, ex_inst[31], ex_inst[19:12], ex_inst[20], ex_inst[30:21], 1'b0};
  wire ex_is_load = ex_op == 7'b0000011;
  wire ex_is_store = ex_op == 7'b0100011;
  wire ex_is_branch = ex_op == 7'b1100011;
  wire ex_is_jal = ex_op == 7'b1101111;
  wire ex_is_jalr = ex_op == 7'b1100111;
  wire ex_is_lui = ex_op == 7'b0110111;
  wire ex_is_auipc = ex_op == 7'b0010111;
  wire ex_is_csr = ex_op == 7'b1110011 && ex_f3 != 0;
  wire ex_is_ecall = ex_inst == 32'h00000073;
  wire ex_is_mret = ex_inst == 32'h30200073;
  wire ex_is_ebreak = ex_inst == 32'h00100073;
  wire ex_is_fencei = ex_op == 7'b0001111 && ex_f3 == 3'b001;

  reg [31:0] ex_alu;
  always @(*) begin
    ex_alu = 0;
    if (ex_op == 7'b0110011) begin
      case (ex_f3)
        3'b000: ex_alu = ex_f7[5] ? ex_rs1 - ex_rs2 : ex_rs1 + ex_rs2;
        3'b001: ex_alu = ex_rs1 << ex_rs2[4:0];
        3'b010: ex_alu = $signed(ex_rs1) < $signed(ex_rs2);
        3'b011: ex_alu = ex_rs1 < ex_rs2;
        3'b100: ex_alu = ex_rs1 ^ ex_rs2;
        3'b101: ex_alu = ex_f7[5] ? $signed(ex_rs1) >>> ex_rs2[4:0] : ex_rs1 >> ex_rs2[4:0];
        3'b110: ex_alu = ex_rs1 | ex_rs2;
        3'b111: ex_alu = ex_rs1 & ex_rs2;
      endcase
    end else if (ex_op == 7'b0010011) begin
      case (ex_f3)
        3'b000: ex_alu = ex_rs1 + ex_imm_i;
        3'b001: ex_alu = ex_rs1 << ex_imm_i[4:0];
        3'b010: ex_alu = $signed(ex_rs1) < $signed(ex_imm_i);
        3'b011: ex_alu = ex_rs1 < ex_imm_i;
        3'b100: ex_alu = ex_rs1 ^ ex_imm_i;
        3'b101: ex_alu = ex_f7[5] ? $signed(ex_rs1) >>> ex_imm_i[4:0] : ex_rs1 >> ex_imm_i[4:0];
        3'b110: ex_alu = ex_rs1 | ex_imm_i;
        3'b111: ex_alu = ex_rs1 & ex_imm_i;
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

  wire [31:0] ex_mem_addr = ex_rs1 + (ex_is_store ? ex_imm_s : ex_imm_i);
  wire [31:0] ex_control_target = ex_is_jalr ? ((ex_rs1 + ex_imm_i) & ~32'h1) :
                                        ex_is_jal ? ex_pc + ex_imm_j :
                                        ex_is_ecall ? mtvec :
                                        ex_is_mret ? mepc : ex_pc + ex_imm_b;
  wire ex_redirect_kind = ex_is_jal || ex_is_jalr ||
                          (ex_is_branch && ex_branch_taken) || ex_is_ecall ||
                          ex_is_mret || ex_is_fencei;
  wire [31:0] ex_redirect_target = ex_is_fencei ? ex_pc + 4 : ex_control_target;

  wire [11:0] csr_raddr = ex_inst[31:20];
  wire [31:0] csr_rdata, mepc, mtvec;
  wire [63:0] mcycle;
  wire [31:0] ex_csr_wdata = ex_f3 == 3'b001 ? ex_rs1 : csr_rdata | ex_rs1;
  wire wb_is_csr = wb_inst[6:0] == 7'b1110011 && wb_inst[14:12] != 0;
  wire wb_csr_wen = wb_valid && wb_is_csr &&
                    (wb_inst[14:12] == 3'b001 || wb_inst[19:15] != 0);
  CSR u_csr(
    .clk(clk), .rst(rst), .csr_addr(wb_valid ? wb_inst[31:20] : csr_raddr),
    .csr_wdata(wb_csr_wdata), .csr_wen(wb_csr_wen), .csr_rdata(csr_rdata),
    .exception_en(wb_valid && wb_inst == 32'h00000073),
    .exception_pc(wb_pc), .exception_cause(32'd11),
    .mret_en(wb_valid && wb_inst == 32'h30200073),
    .mepc_out(mepc), .mtvec_out(mtvec), .mcycle_out(mcycle)
  );

  wire [31:0] ex_result = ex_is_csr ? csr_rdata :
                          (ex_is_jal || ex_is_jalr) ? ex_pc + 4 :
                          ex_is_lui ? ex_imm_u :
                          ex_is_auipc ? ex_pc + ex_imm_u : ex_alu;

  // ---------------- LSU and bus fabric ----------------
  wire ls_is_load = ls_inst[6:0] == 7'b0000011;
  wire ls_is_store = ls_inst[6:0] == 7'b0100011;
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
  LSU u_lsu(
    .clk(clk), .rst(rst), .mem_valid(ls_valid && ls_is_mem),
    .mem_wen(ls_is_store), .funct3(ls_inst[14:12]), .mem_addr(ls_addr),
    .wdata(ls_store_data), .cpu_pc(ls_pc),
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
    .lsu_load_req(), .lsu_store_req(), .lsu_r_handshake(lsu_r_hs),
    .lsu_b_handshake(lsu_b_hs), .lsu_wait_ar(), .lsu_wait_r(),
    .lsu_wait_aw_w(), .lsu_wait_b()
  );

  wire ls_done = !ls_is_mem || (ls_is_load ? lsu_r_hs : lsu_b_hs);
  wire ls_ready = !ls_valid || ls_done;
  wire ex_ready = !ex_valid || ls_ready;
  wire id_issue = id_valid && !id_hazard && ex_ready;
  wire id_ready = !id_valid || id_issue;
  wire ex_advance = ex_valid && ls_ready;
  wire redirect = ex_advance && ex_redirect_kind;

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
    .icache_access(), .icache_hit(), .icache_miss(), .icache_uncache(),
    .icache_refill_req(), .icache_refill_req_pulse(), .icache_wait_ar(),
    .icache_wait_r(), .flush(icache_flush)
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
    .clk(clk), .rst(rst), .clint_arvalid(cl_arvalid), .clint_arready(cl_arready),
    .clint_araddr(cl_araddr), .clint_arid(cl_arid), .clint_arlen(cl_arlen),
    .clint_arsize(cl_arsize), .clint_arburst(cl_arburst), .clint_rvalid(cl_rvalid),
    .clint_rready(cl_rready), .clint_rdata(cl_rdata), .clint_rresp(cl_rresp),
    .clint_rlast(cl_rlast), .clint_rid(cl_rid), .clint_awvalid(cl_awvalid),
    .clint_awready(cl_awready), .clint_awaddr(cl_awaddr), .clint_awid(cl_awid),
    .clint_awlen(cl_awlen), .clint_awsize(cl_awsize), .clint_awburst(cl_awburst),
    .clint_wvalid(cl_wvalid), .clint_wready(cl_wready), .clint_wdata(cl_wdata),
    .clint_wstrb(cl_wstrb), .clint_wlast(cl_wlast), .clint_bvalid(cl_bvalid),
    .clint_bready(cl_bready), .clint_bresp(cl_bresp), .clint_bid(cl_bid)
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

  // ---------------- Fetch engine ----------------
  localparam F_REQ = 1'b0, F_WAIT = 1'b1;
  reg fetch_state, fetch_discard;
  reg [31:0] fetch_pc, requested_pc;
  assign if_arvalid = fetch_state == F_REQ && id_ready && !redirect && !rst;
  assign if_araddr = fetch_pc;
  assign if_arid = 0;
  assign if_arlen = 0;
  assign if_arsize = 3'b010;
  assign if_arburst = 2'b01;
  assign if_rready = fetch_state == F_WAIT && !rst;

`ifndef SYNTHESIS
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void commit_instruction(input int pc_val, input int inst_val, input int next_pc_val);
  import "DPI-C" function void ebreak_handler(input int a0_value);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val, input int target_val);
  import "DPI-C" function void difftest_skip_ref();
`endif

  wire [31:0] wb_seq_pc = wb_pc + 4;
  wire wb_peripheral = (wb_inst[6:0] == 7'b0000011 || wb_inst[6:0] == 7'b0100011) &&
    ((wb_data >= 32'h02000000 && wb_data < 32'h02010000) ||
     (wb_data >= 32'h10000000 && wb_data < 32'h10020000) ||
     (wb_data >= 32'h21000000 && wb_data < 32'h21200000));

  always @(posedge clk) begin
    if (rst) begin
      id_valid <= 0; ex_valid <= 0; ls_valid <= 0; wb_valid <= 0;
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
      wb_valid <= ls_valid && ls_done;
      if (ls_valid && ls_done) begin
        wb_pc <= ls_pc;
        wb_inst <= ls_inst;
        wb_data <= ls_is_load ? lsu_rdata : ls_result;
        wb_csr_wdata <= ls_csr_wdata;
        wb_next_pc <= (ls_inst[6:0] == 7'b1101111 || ls_inst[6:0] == 7'b1100111 ||
                       (ls_inst[6:0] == 7'b1100011 && ls_result[0]) ||
                       ls_inst == 32'h00000073 || ls_inst == 32'h30200073) ? ls_store_data : ls_pc + 4;
      end

      if (ls_ready) begin
        ls_valid <= ex_valid;
        if (ex_valid) begin
          ls_pc <= ex_pc; ls_inst <= ex_inst; ls_result <= ex_result;
          ls_addr <= ex_mem_addr; ls_store_data <= ex_redirect_kind ? ex_redirect_target : ex_rs2;
          ls_csr_wdata <= ex_csr_wdata;
          if (ex_is_branch) ls_result[0] <= ex_branch_taken;
        end
      end

      if (ex_ready) begin
        ex_valid <= id_valid && !id_hazard && !redirect;
        if (id_valid && !id_hazard && !redirect) begin
          ex_pc <= id_pc; ex_inst <= id_inst; ex_rs1 <= rf_rs1; ex_rs2 <= rf_rs2;
        end
      end

      if (redirect) begin
        id_valid <= 0;
        fetch_pc <= ex_redirect_target;
        if (fetch_state == F_WAIT) fetch_discard <= 1;
      end else if (id_issue) begin
        id_valid <= 0;
      end

      if (fetch_state == F_REQ && if_arvalid && if_arready) begin
        requested_pc <= fetch_pc;
        fetch_state <= F_WAIT;
      end
      if (fetch_state == F_WAIT && if_rvalid && if_rready) begin
        fetch_state <= F_REQ;
        if (fetch_discard || redirect) begin
          fetch_discard <= 0;
        end else begin
          id_valid <= 1;
          id_pc <= requested_pc;
          id_inst <= if_rresp[1] ? 32'h00100073 : if_rdata;
          fetch_pc <= requested_pc + 4;
        end
      end

`ifndef SYNTHESIS
      if (wb_valid) begin
        commit_instruction(wb_pc, wb_inst, wb_next_pc);
        if (wb_peripheral) difftest_skip_ref();
        if (wb_inst == 32'h00100073) ebreak_handler(a0_value);
        if (wb_inst[6:0] == 7'b1101111 && wb_inst[11:7] == 1)
          ftrace_call_handler(wb_pc, wb_next_pc);
        if (wb_inst[6:0] == 7'b1100111 && wb_inst[11:7] == 1)
          ftrace_call_handler(wb_pc, wb_next_pc);
        if (wb_inst[6:0] == 7'b1100111 && wb_inst[11:7] == 0 && wb_inst[19:15] == 1)
          ftrace_ret_handler(wb_pc, wb_next_pc);
      end
`endif
    end
  end
endmodule
