// Simple in-order RV32E pipeline used by ysyx_26020070.
// Hazards are handled conservatively: RAW dependencies stall in ID, memory
// operations back-pressure the pipe in MEM, and redirects flush younger work.

module SimplePipeline(
  input         clk,
  input         rst,

  output        mem_arvalid,
  input         mem_arready,
  output [31:0] mem_araddr,
  output [ 3:0] mem_arid,
  output [ 7:0] mem_arlen,
  output [ 2:0] mem_arsize,
  output [ 1:0] mem_arburst,
  input         mem_rvalid,
  output        mem_rready,
  input  [31:0] mem_rdata,
  input  [ 1:0] mem_rresp,
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
);

  localparam [6:0] OP_LOAD   = 7'b0000011;
  localparam [6:0] OP_MISC   = 7'b0001111;
  localparam [6:0] OP_IMM    = 7'b0010011;
  localparam [6:0] OP_AUIPC  = 7'b0010111;
  localparam [6:0] OP_STORE  = 7'b0100011;
  localparam [6:0] OP_REG    = 7'b0110011;
  localparam [6:0] OP_LUI    = 7'b0110111;
  localparam [6:0] OP_BRANCH = 7'b1100011;
  localparam [6:0] OP_JALR   = 7'b1100111;
  localparam [6:0] OP_JAL    = 7'b1101111;
  localparam [6:0] OP_SYSTEM = 7'b1110011;

  function automatic inst_uses_rs1(input [31:0] insn);
    begin
      case (insn[6:0])
        OP_REG, OP_IMM, OP_LOAD, OP_STORE, OP_BRANCH, OP_JALR:
          inst_uses_rs1 = 1'b1;
        OP_SYSTEM:
          inst_uses_rs1 = (insn[14:12] == 3'b001) ||
                          (insn[14:12] == 3'b010);
        default: inst_uses_rs1 = 1'b0;
      endcase
    end
  endfunction

  function automatic inst_uses_rs2(input [31:0] insn);
    begin
      case (insn[6:0])
        OP_REG, OP_STORE, OP_BRANCH: inst_uses_rs2 = 1'b1;
        default: inst_uses_rs2 = 1'b0;
      endcase
    end
  endfunction

  function automatic inst_writes_rd(input [31:0] insn);
    begin
      case (insn[6:0])
        OP_REG, OP_IMM, OP_LOAD, OP_AUIPC, OP_LUI, OP_JALR, OP_JAL:
          inst_writes_rd = (insn[11:7] != 5'b0);
        OP_SYSTEM:
          inst_writes_rd = ((insn[14:12] == 3'b001) ||
                            (insn[14:12] == 3'b010)) &&
                           (insn[11:7] != 5'b0);
        default: inst_writes_rd = 1'b0;
      endcase
    end
  endfunction

  function automatic inst_is_barrier(input [31:0] insn);
    begin
      inst_is_barrier = (insn[6:0] == OP_SYSTEM) ||
                        ((insn[6:0] == OP_MISC) &&
                         (insn[14:12] == 3'b001));
    end
  endfunction

  // ------------------------------------------------------------------
  // Pipeline state
  // ------------------------------------------------------------------
  reg        if_id_valid;
  reg [31:0] if_id_pc;
  reg [31:0] if_id_inst;

  reg        id_ex_valid;
  reg [31:0] id_ex_pc;
  reg [31:0] id_ex_inst;
  reg [31:0] id_ex_rs1;
  reg [31:0] id_ex_rs2;
  reg [31:0] id_ex_csr_old;

  reg        ex_mem_valid;
  reg [31:0] ex_mem_pc;
  reg [31:0] ex_mem_inst;
  reg [31:0] ex_mem_wdata;
  reg [31:0] ex_mem_next_pc;
  reg [31:0] ex_mem_addr;
  reg [31:0] ex_mem_store_data;
  reg [ 4:0] ex_mem_rd;
  reg [ 2:0] ex_mem_funct3;
  reg        ex_mem_reg_wen;
  reg        ex_mem_is_load;
  reg        ex_mem_is_store;
  reg        ex_mem_csr_wen;
  reg [11:0] ex_mem_csr_addr;
  reg [31:0] ex_mem_csr_wdata;
  reg        ex_mem_exception;
  reg [31:0] ex_mem_exception_cause;

  reg        mem_wb_valid;
  reg [31:0] mem_wb_pc;
  reg [31:0] mem_wb_inst;
  reg [31:0] mem_wb_wdata;
  reg [31:0] mem_wb_next_pc;
  reg [31:0] mem_wb_target;
  reg [31:0] mem_wb_mem_addr;
  reg [ 4:0] mem_wb_rd;
  reg        mem_wb_reg_wen;
  reg        mem_wb_csr_wen;
  reg [11:0] mem_wb_csr_addr;
  reg [31:0] mem_wb_csr_wdata;
  reg        mem_wb_exception;
  reg [31:0] mem_wb_exception_cause;

  // ------------------------------------------------------------------
  // Register file and CSR file
  // ------------------------------------------------------------------
  wire [4:0] id_rs1 = if_id_inst[19:15];
  wire [4:0] id_rs2 = if_id_inst[24:20];
  wire [4:0] id_rd  = if_id_inst[11:7];
  wire [31:0] id_rs1_data;
  wire [31:0] id_rs2_data;
  wire [31:0] a0_value;

  wire wb_commit = mem_wb_valid;
  wire wb_reg_wen = wb_commit && mem_wb_reg_wen;

  RegisterFile u_regfile(
    .clk(clk),
    .waddr(mem_wb_rd),
    .wdata(mem_wb_wdata),
    .wen(wb_reg_wen),
    .raddr1(id_rs1),
    .rdata1(id_rs1_data),
    .raddr2(id_rs2),
    .rdata2(id_rs2_data),
    .a0_value(a0_value)
  );

  wire [31:0] csr_rdata;
  wire [31:0] mepc_out;
  wire [31:0] mtvec_out;
  wire [63:0] mcycle_out;

  CSR u_csr(
    .clk(clk),
    .rst(rst),
    .csr_addr(if_id_inst[31:20]),
    .csr_wdata(mem_wb_csr_wdata),
    .csr_wen(wb_commit && mem_wb_csr_wen),
    .csr_rdata(csr_rdata),
    .exception_en(wb_commit && mem_wb_exception),
    .exception_pc(mem_wb_pc),
    .exception_cause(mem_wb_exception_cause),
    .mret_en(1'b0),
    .mepc_out(mepc_out),
    .mtvec_out(mtvec_out),
    .mcycle_out(mcycle_out)
  );

  // ------------------------------------------------------------------
  // ID hazard detection. WB is included deliberately: RF writes and ID
  // operand capture occur on the same edge, so ID waits one extra cycle.
  // ------------------------------------------------------------------
  wire id_raw_rs1 = inst_uses_rs1(if_id_inst) && (id_rs1 != 5'b0) &&
      ((id_ex_valid  && inst_writes_rd(id_ex_inst)  && id_ex_inst[11:7]  == id_rs1) ||
       (ex_mem_valid && ex_mem_reg_wen && ex_mem_rd == id_rs1) ||
       (mem_wb_valid && mem_wb_reg_wen && mem_wb_rd == id_rs1));
  wire id_raw_rs2 = inst_uses_rs2(if_id_inst) && (id_rs2 != 5'b0) &&
      ((id_ex_valid  && inst_writes_rd(id_ex_inst)  && id_ex_inst[11:7]  == id_rs2) ||
       (ex_mem_valid && ex_mem_reg_wen && ex_mem_rd == id_rs2) ||
       (mem_wb_valid && mem_wb_reg_wen && mem_wb_rd == id_rs2));

  wire older_barrier =
      (id_ex_valid  && inst_is_barrier(id_ex_inst)) ||
      (ex_mem_valid && inst_is_barrier(ex_mem_inst)) ||
      (mem_wb_valid && inst_is_barrier(mem_wb_inst));
  wire id_barrier_wait = inst_is_barrier(if_id_inst) &&
                         (id_ex_valid || ex_mem_valid || mem_wb_valid);
  wire id_hazard = id_raw_rs1 || id_raw_rs2 || older_barrier || id_barrier_wait;

  // ------------------------------------------------------------------
  // EX combinational datapath
  // ------------------------------------------------------------------
  wire [6:0] ex_opcode = id_ex_inst[6:0];
  wire [2:0] ex_funct3 = id_ex_inst[14:12];
  wire [6:0] ex_funct7 = id_ex_inst[31:25];
  wire [4:0] ex_rd = id_ex_inst[11:7];
  wire [31:0] ex_imm_i = {{20{id_ex_inst[31]}}, id_ex_inst[31:20]};
  wire [31:0] ex_imm_s = {{20{id_ex_inst[31]}}, id_ex_inst[31:25], id_ex_inst[11:7]};
  wire [31:0] ex_imm_b = {{19{id_ex_inst[31]}}, id_ex_inst[31], id_ex_inst[7],
                           id_ex_inst[30:25], id_ex_inst[11:8], 1'b0};
  wire [31:0] ex_imm_u = {id_ex_inst[31:12], 12'b0};
  wire [31:0] ex_imm_j = {{11{id_ex_inst[31]}}, id_ex_inst[31], id_ex_inst[19:12],
                           id_ex_inst[20], id_ex_inst[30:21], 1'b0};

  reg [31:0] ex_result;
  reg        ex_branch_taken;
  always @(*) begin
    ex_result = 32'b0;
    case (ex_opcode)
      OP_REG: begin
        case (ex_funct3)
          3'b000: ex_result = ex_funct7[5] ? id_ex_rs1 - id_ex_rs2
                                           : id_ex_rs1 + id_ex_rs2;
          3'b001: ex_result = id_ex_rs1 << id_ex_rs2[4:0];
          3'b010: ex_result = {31'b0, ($signed(id_ex_rs1) < $signed(id_ex_rs2))};
          3'b011: ex_result = {31'b0, (id_ex_rs1 < id_ex_rs2)};
          3'b100: ex_result = id_ex_rs1 ^ id_ex_rs2;
          3'b101: ex_result = ex_funct7[5] ? ($signed(id_ex_rs1) >>> id_ex_rs2[4:0])
                                           : (id_ex_rs1 >> id_ex_rs2[4:0]);
          3'b110: ex_result = id_ex_rs1 | id_ex_rs2;
          3'b111: ex_result = id_ex_rs1 & id_ex_rs2;
          default: ex_result = 32'b0;
        endcase
      end
      OP_IMM: begin
        case (ex_funct3)
          3'b000: ex_result = id_ex_rs1 + ex_imm_i;
          3'b001: ex_result = id_ex_rs1 << id_ex_inst[24:20];
          3'b010: ex_result = {31'b0, ($signed(id_ex_rs1) < $signed(ex_imm_i))};
          3'b011: ex_result = {31'b0, (id_ex_rs1 < ex_imm_i)};
          3'b100: ex_result = id_ex_rs1 ^ ex_imm_i;
          3'b101: ex_result = ex_funct7[5] ? ($signed(id_ex_rs1) >>> id_ex_inst[24:20])
                                           : (id_ex_rs1 >> id_ex_inst[24:20]);
          3'b110: ex_result = id_ex_rs1 | ex_imm_i;
          3'b111: ex_result = id_ex_rs1 & ex_imm_i;
          default: ex_result = 32'b0;
        endcase
      end
      OP_LUI:   ex_result = ex_imm_u;
      OP_AUIPC: ex_result = id_ex_pc + ex_imm_u;
      OP_JAL, OP_JALR: ex_result = id_ex_pc + 32'd4;
      OP_SYSTEM: ex_result = id_ex_csr_old;
      default: ex_result = 32'b0;
    endcase

    case (ex_funct3)
      3'b000: ex_branch_taken = (id_ex_rs1 == id_ex_rs2);
      3'b001: ex_branch_taken = (id_ex_rs1 != id_ex_rs2);
      3'b100: ex_branch_taken = ($signed(id_ex_rs1) < $signed(id_ex_rs2));
      3'b101: ex_branch_taken = ($signed(id_ex_rs1) >= $signed(id_ex_rs2));
      3'b110: ex_branch_taken = (id_ex_rs1 < id_ex_rs2);
      3'b111: ex_branch_taken = (id_ex_rs1 >= id_ex_rs2);
      default: ex_branch_taken = 1'b0;
    endcase
  end

  wire ex_is_load  = (ex_opcode == OP_LOAD);
  wire ex_is_store = (ex_opcode == OP_STORE);
  wire ex_is_jal   = (ex_opcode == OP_JAL);
  wire ex_is_jalr  = (ex_opcode == OP_JALR);
  wire ex_is_branch = (ex_opcode == OP_BRANCH);
  wire ex_is_ecall = (id_ex_inst == 32'h00000073);
  wire ex_is_ebreak = (id_ex_inst == 32'h00100073);
  wire ex_is_mret = (id_ex_inst == 32'h30200073);
  wire ex_is_fencei = (ex_opcode == OP_MISC) && (ex_funct3 == 3'b001);
  wire ex_is_csr = (ex_opcode == OP_SYSTEM) &&
                   ((ex_funct3 == 3'b001) || (ex_funct3 == 3'b010));
  wire [31:0] ex_mem_address = id_ex_rs1 + (ex_is_store ? ex_imm_s : ex_imm_i);
  wire [31:0] ex_control_target = ex_is_jalr ? ((id_ex_rs1 + ex_imm_i) & 32'hfffffffe) :
                                  ex_is_jal ? (id_ex_pc + ex_imm_j) :
                                  ex_is_branch ? (id_ex_pc + ex_imm_b) :
                                  ex_is_ecall ? mtvec_out :
                                  ex_is_mret ? mepc_out :
                                  id_ex_pc + 32'd4;
  wire [31:0] ex_next_pc = ex_is_ebreak ? id_ex_pc :
                           (ex_is_jal || ex_is_jalr || ex_is_ecall || ex_is_mret) ? ex_control_target :
                           (ex_is_branch && ex_branch_taken) ? ex_control_target :
                           id_ex_pc + 32'd4;
  wire ex_redirect_needed = ex_is_fencei || (ex_next_pc != (id_ex_pc + 32'd4));
  wire ex_csr_wen = ex_is_csr &&
                    ((ex_funct3 == 3'b001) ||
                     ((ex_funct3 == 3'b010) && (id_ex_inst[19:15] != 5'b0)));
  wire [31:0] ex_csr_wdata = (ex_funct3 == 3'b001) ? id_ex_rs1
                                                   : (id_ex_csr_old | id_ex_rs1);

  // ------------------------------------------------------------------
  // LSU
  // ------------------------------------------------------------------
  wire        lsu_arvalid, lsu_arready;
  wire [31:0] lsu_araddr;
  wire [3:0]  lsu_arid;
  wire [7:0]  lsu_arlen;
  wire [2:0]  lsu_arsize;
  wire [1:0]  lsu_arburst;
  wire        lsu_rvalid, lsu_rready;
  wire [31:0] lsu_rdata;
  wire [1:0]  lsu_rresp;
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
  wire [31:0] lsu_load_data;
  wire        lsu_access_fault;
  wire [2:0]  lsu_state_unused;
  wire lsu_load_req_unused, lsu_store_req_unused;
  wire lsu_wait_ar_unused, lsu_wait_r_unused, lsu_wait_aw_unused, lsu_wait_b_unused;
  wire lsu_r_done, lsu_b_done;

  LSU u_lsu(
    .clk(clk), .rst(rst),
    .mem_valid(ex_mem_valid && (ex_mem_is_load || ex_mem_is_store)),
    .mem_wen(ex_mem_is_store),
    .funct3(ex_mem_funct3),
    .mem_addr(ex_mem_addr),
    .wdata(ex_mem_store_data),
    .cpu_pc(ex_mem_pc),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr), .lsu_arid(lsu_arid), .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready), .lsu_rdata(lsu_rdata),
    .lsu_rresp(lsu_rresp), .lsu_rlast(lsu_rlast), .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr), .lsu_awid(lsu_awid), .lsu_awlen(lsu_awlen),
    .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready), .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready), .lsu_bresp(lsu_bresp),
    .lsu_bid(lsu_bid),
    .rdata(lsu_load_data), .lsu_access_fault(lsu_access_fault),
    .lsu_state_o(lsu_state_unused),
    .lsu_load_req(lsu_load_req_unused), .lsu_store_req(lsu_store_req_unused),
    .lsu_r_handshake(lsu_r_done), .lsu_b_handshake(lsu_b_done),
    .lsu_wait_ar(lsu_wait_ar_unused), .lsu_wait_r(lsu_wait_r_unused),
    .lsu_wait_aw_w(lsu_wait_aw_unused), .lsu_wait_b(lsu_wait_b_unused)
  );

  wire ex_mem_done = !ex_mem_valid ||
                     (!ex_mem_is_load && !ex_mem_is_store) ||
                     (ex_mem_is_load && lsu_r_done) ||
                     (ex_mem_is_store && lsu_b_done);
  wire ex_mem_fire = ex_mem_valid && ex_mem_done;
  wire ex_mem_ready = !ex_mem_valid || ex_mem_fire;
  wire id_ex_fire = id_ex_valid && ex_mem_ready;
  wire id_ex_ready = !id_ex_valid || id_ex_fire;
  wire ex_redirect = id_ex_fire && ex_redirect_needed;
  wire id_fire = if_id_valid && id_ex_ready && !id_hazard && !ex_redirect;

  // ------------------------------------------------------------------
  // IFU and ICache. There is one outstanding fetch and a one-entry IF/ID
  // buffer. A redirect drops any outstanding sequential response.
  // ------------------------------------------------------------------
  reg [31:0] fetch_pc;
  reg [31:0] fetch_req_pc;
  reg        fetch_pending;
  wire       ifu_arvalid = !fetch_pending && (!if_id_valid || id_fire) &&
                           !rst && !ex_redirect;
  wire       ifu_arready;
  wire [31:0] ifu_araddr = fetch_pc;
  wire       ifu_rvalid;
  wire       ifu_rready = fetch_pending;
  wire [31:0] ifu_rdata;
  wire [1:0] ifu_rresp;
  wire       ifu_rlast;
  wire [3:0] ifu_rid;
  wire fetch_ar_fire = ifu_arvalid && ifu_arready;
  wire fetch_r_fire = ifu_rvalid && ifu_rready;

  wire        icache_arvalid, icache_arready;
  wire [31:0] icache_araddr;
  wire [3:0]  icache_arid;
  wire [7:0]  icache_arlen;
  wire [2:0]  icache_arsize;
  wire [1:0]  icache_arburst;
  wire        icache_rvalid, icache_rready;
  wire [31:0] icache_rdata;
  wire [1:0]  icache_rresp;
  wire        icache_rlast;
  wire [3:0]  icache_rid;
  wire icache_access_unused, icache_hit_unused, icache_miss_unused;
  wire icache_uncache_unused, icache_refill_unused, icache_refill_pulse_unused;
  wire icache_wait_ar_unused, icache_wait_r_unused;
  wire icache_flush = id_ex_fire && ex_is_fencei;

  ICache u_icache(
    .clk(clk), .rst(rst),
    .cpu_arvalid(ifu_arvalid), .cpu_arready(ifu_arready),
    .cpu_araddr(ifu_araddr), .cpu_arid(4'b0), .cpu_arlen(8'b0),
    .cpu_arsize(3'b010), .cpu_arburst(2'b01),
    .cpu_rvalid(ifu_rvalid), .cpu_rready(ifu_rready), .cpu_rdata(ifu_rdata),
    .cpu_rresp(ifu_rresp), .cpu_rlast(ifu_rlast), .cpu_rid(ifu_rid),
    .bus_arvalid(icache_arvalid), .bus_arready(icache_arready),
    .bus_araddr(icache_araddr), .bus_arid(icache_arid), .bus_arlen(icache_arlen),
    .bus_arsize(icache_arsize), .bus_arburst(icache_arburst),
    .bus_rvalid(icache_rvalid), .bus_rready(icache_rready), .bus_rdata(icache_rdata),
    .bus_rresp(icache_rresp), .bus_rlast(icache_rlast), .bus_rid(icache_rid),
    .icache_access(icache_access_unused), .icache_hit(icache_hit_unused),
    .icache_miss(icache_miss_unused), .icache_uncache(icache_uncache_unused),
    .icache_refill_req(icache_refill_unused),
    .icache_refill_req_pulse(icache_refill_pulse_unused),
    .icache_wait_ar(icache_wait_ar_unused), .icache_wait_r(icache_wait_r_unused),
    .flush(icache_flush)
  );

  // ------------------------------------------------------------------
  // Local CLINT and external-memory arbiter
  // ------------------------------------------------------------------
  wire clint_arvalid, clint_arready;
  wire [31:0] clint_araddr;
  wire [3:0] clint_arid;
  wire [7:0] clint_arlen;
  wire [2:0] clint_arsize;
  wire [1:0] clint_arburst;
  wire clint_rvalid, clint_rready;
  wire [31:0] clint_rdata;
  wire [1:0] clint_rresp;
  wire clint_rlast;
  wire [3:0] clint_rid;
  wire clint_awvalid, clint_awready;
  wire [31:0] clint_awaddr;
  wire [3:0] clint_awid;
  wire [7:0] clint_awlen;
  wire [2:0] clint_awsize;
  wire [1:0] clint_awburst;
  wire clint_wvalid, clint_wready;
  wire [31:0] clint_wdata;
  wire [3:0] clint_wstrb;
  wire clint_wlast;
  wire clint_bvalid, clint_bready;
  wire [1:0] clint_bresp;
  wire [3:0] clint_bid;

  CLINT u_clint(
    .clk(clk), .rst(rst),
    .clint_arvalid(clint_arvalid), .clint_arready(clint_arready),
    .clint_araddr(clint_araddr), .clint_arid(clint_arid), .clint_arlen(clint_arlen),
    .clint_arsize(clint_arsize), .clint_arburst(clint_arburst),
    .clint_rvalid(clint_rvalid), .clint_rready(clint_rready), .clint_rdata(clint_rdata),
    .clint_rresp(clint_rresp), .clint_rlast(clint_rlast), .clint_rid(clint_rid),
    .clint_awvalid(clint_awvalid), .clint_awready(clint_awready),
    .clint_awaddr(clint_awaddr), .clint_awid(clint_awid), .clint_awlen(clint_awlen),
    .clint_awsize(clint_awsize), .clint_awburst(clint_awburst),
    .clint_wvalid(clint_wvalid), .clint_wready(clint_wready),
    .clint_wdata(clint_wdata), .clint_wstrb(clint_wstrb), .clint_wlast(clint_wlast),
    .clint_bvalid(clint_bvalid), .clint_bready(clint_bready),
    .clint_bresp(clint_bresp), .clint_bid(clint_bid)
  );

  AXIArbiter u_arbiter(
    .clk(clk), .rst(rst),
    .ifu_arvalid(icache_arvalid), .ifu_arready(icache_arready),
    .ifu_araddr(icache_araddr), .ifu_arid(icache_arid), .ifu_arlen(icache_arlen),
    .ifu_arsize(icache_arsize), .ifu_arburst(icache_arburst),
    .ifu_rvalid(icache_rvalid), .ifu_rready(icache_rready), .ifu_rdata(icache_rdata),
    .ifu_rresp(icache_rresp), .ifu_rlast(icache_rlast), .ifu_rid(icache_rid),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready),
    .lsu_araddr(lsu_araddr), .lsu_arid(lsu_arid), .lsu_arlen(lsu_arlen),
    .lsu_arsize(lsu_arsize), .lsu_arburst(lsu_arburst),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready), .lsu_rdata(lsu_rdata),
    .lsu_rresp(lsu_rresp), .lsu_rlast(lsu_rlast), .lsu_rid(lsu_rid),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready),
    .lsu_awaddr(lsu_awaddr), .lsu_awid(lsu_awid), .lsu_awlen(lsu_awlen),
    .lsu_awsize(lsu_awsize), .lsu_awburst(lsu_awburst),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready), .lsu_wdata(lsu_wdata),
    .lsu_wstrb(lsu_wstrb), .lsu_wlast(lsu_wlast),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready),
    .lsu_bresp(lsu_bresp), .lsu_bid(lsu_bid),
    .clint_arvalid(clint_arvalid), .clint_arready(clint_arready),
    .clint_araddr(clint_araddr), .clint_arid(clint_arid), .clint_arlen(clint_arlen),
    .clint_arsize(clint_arsize), .clint_arburst(clint_arburst),
    .clint_rvalid(clint_rvalid), .clint_rready(clint_rready), .clint_rdata(clint_rdata),
    .clint_rresp(clint_rresp), .clint_rlast(clint_rlast), .clint_rid(clint_rid),
    .clint_awvalid(clint_awvalid), .clint_awready(clint_awready),
    .clint_awaddr(clint_awaddr), .clint_awid(clint_awid), .clint_awlen(clint_awlen),
    .clint_awsize(clint_awsize), .clint_awburst(clint_awburst),
    .clint_wvalid(clint_wvalid), .clint_wready(clint_wready),
    .clint_wdata(clint_wdata), .clint_wstrb(clint_wstrb), .clint_wlast(clint_wlast),
    .clint_bvalid(clint_bvalid), .clint_bready(clint_bready),
    .clint_bresp(clint_bresp), .clint_bid(clint_bid),
    .mem_arvalid(mem_arvalid), .mem_arready(mem_arready), .mem_araddr(mem_araddr),
    .mem_arid(mem_arid), .mem_arlen(mem_arlen), .mem_arsize(mem_arsize),
    .mem_arburst(mem_arburst), .mem_rvalid(mem_rvalid), .mem_rready(mem_rready),
    .mem_rdata(mem_rdata), .mem_rresp(mem_rresp), .mem_rlast(mem_rlast), .mem_rid(mem_rid),
    .mem_awvalid(mem_awvalid), .mem_awready(mem_awready), .mem_awaddr(mem_awaddr),
    .mem_awid(mem_awid), .mem_awlen(mem_awlen), .mem_awsize(mem_awsize),
    .mem_awburst(mem_awburst), .mem_wvalid(mem_wvalid), .mem_wready(mem_wready),
    .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_wlast(mem_wlast),
    .mem_bvalid(mem_bvalid), .mem_bready(mem_bready), .mem_bresp(mem_bresp), .mem_bid(mem_bid)
  );

  // ------------------------------------------------------------------
  // Pipeline registers and fetch control
  // ------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      if_id_valid <= 1'b0;
      id_ex_valid <= 1'b0;
      ex_mem_valid <= 1'b0;
      mem_wb_valid <= 1'b0;
      fetch_pending <= 1'b0;
`ifdef SOC_MODE
      fetch_pc <= 32'h30000000;
      fetch_req_pc <= 32'h30000000;
`else
      fetch_pc <= 32'h80000000;
      fetch_req_pc <= 32'h80000000;
`endif
    end else begin
      // WB is always ready, so its entry is replaced or cleared every cycle.
      mem_wb_valid <= ex_mem_fire;
      if (ex_mem_fire) begin
        mem_wb_pc <= ex_mem_pc;
        mem_wb_inst <= ex_mem_inst;
        mem_wb_wdata <= ex_mem_is_load ? lsu_load_data : ex_mem_wdata;
        mem_wb_next_pc <= ex_mem_next_pc;
        mem_wb_target <= ex_mem_next_pc;
        mem_wb_mem_addr <= ex_mem_addr;
        mem_wb_rd <= ex_mem_rd;
        mem_wb_reg_wen <= ex_mem_reg_wen;
        mem_wb_csr_wen <= ex_mem_csr_wen;
        mem_wb_csr_addr <= ex_mem_csr_addr;
        mem_wb_csr_wdata <= ex_mem_csr_wdata;
        mem_wb_exception <= ex_mem_exception;
        mem_wb_exception_cause <= ex_mem_exception_cause;
      end

      if (id_ex_fire) begin
        ex_mem_valid <= 1'b1;
        ex_mem_pc <= id_ex_pc;
        ex_mem_inst <= id_ex_inst;
        ex_mem_wdata <= ex_result;
        ex_mem_next_pc <= ex_next_pc;
        ex_mem_addr <= ex_mem_address;
        ex_mem_store_data <= id_ex_rs2;
        ex_mem_rd <= ex_rd;
        ex_mem_funct3 <= ex_funct3;
        ex_mem_reg_wen <= inst_writes_rd(id_ex_inst);
        ex_mem_is_load <= ex_is_load;
        ex_mem_is_store <= ex_is_store;
        ex_mem_csr_wen <= ex_csr_wen;
        ex_mem_csr_addr <= id_ex_inst[31:20];
        ex_mem_csr_wdata <= ex_csr_wdata;
        ex_mem_exception <= ex_is_ecall;
        ex_mem_exception_cause <= 32'd11;
      end else if (ex_mem_fire) begin
        ex_mem_valid <= 1'b0;
      end

      if (id_fire) begin
        id_ex_valid <= 1'b1;
        id_ex_pc <= if_id_pc;
        id_ex_inst <= if_id_inst;
        id_ex_rs1 <= id_rs1_data;
        id_ex_rs2 <= id_rs2_data;
        id_ex_csr_old <= csr_rdata;
      end else if (id_ex_fire) begin
        id_ex_valid <= 1'b0;
      end

      if (ex_redirect) begin
        if_id_valid <= 1'b0;
        fetch_pending <= 1'b0;
        fetch_pc <= ex_is_fencei ? (id_ex_pc + 32'd4) : ex_next_pc;
      end else begin
        if (id_fire) if_id_valid <= 1'b0;

        if (fetch_ar_fire) begin
          fetch_pending <= 1'b1;
          fetch_req_pc <= fetch_pc;
        end

        if (fetch_r_fire) begin
          fetch_pending <= 1'b0;
          if (ifu_rresp[1]) begin
            if_id_valid <= 1'b0;
            fetch_pc <= 32'b0;
          end else begin
            if_id_valid <= 1'b1;
            if_id_pc <= fetch_req_pc;
            if_id_inst <= ifu_rdata;
            fetch_pc <= fetch_req_pc + 32'd4;
          end
        end
      end
    end
  end

`ifndef SYNTHESIS
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);
  import "DPI-C" function void ebreak_handler(input int a0_val);
  import "DPI-C" function void access_fault_handler(input int pc_val, input int is_store);
  import "DPI-C" function void ftrace_call_handler(input int pc_val, input int target_val);
  import "DPI-C" function void ftrace_ret_handler(input int pc_val, input int target_val);
  import "DPI-C" function void difftest_skip_ref();

  always @(posedge clk) begin
    if (rst) begin
`ifdef SOC_MODE
      update_pc_value(32'h30000000);
`else
      update_pc_value(32'h80000000);
`endif
    end else if (wb_commit) begin
      update_inst_value(mem_wb_pc, mem_wb_inst);
      update_pc_value(mem_wb_next_pc);

      if (mem_wb_inst == 32'h00100073) begin
        $display("EBREAK detected at PC=0x%08x, a0=0x%08x, mcycle=%0d",
                 mem_wb_pc, a0_value, mcycle_out);
        ebreak_handler(a0_value);
      end

      if ((mem_wb_inst[6:0] == OP_LOAD || mem_wb_inst[6:0] == OP_STORE) &&
          (mem_wb_mem_addr[31:12] == 20'h10000)) begin
        difftest_skip_ref();
      end

      if (mem_wb_inst[6:0] == OP_JAL && mem_wb_inst[11:7] == 5'd1)
        ftrace_call_handler(mem_wb_pc, mem_wb_target);
      if (mem_wb_inst[6:0] == OP_JALR) begin
        if (mem_wb_inst[11:7] == 5'd1)
          ftrace_call_handler(mem_wb_pc, mem_wb_target);
        else if (mem_wb_inst[11:7] == 5'd0 && mem_wb_inst[19:15] == 5'd1)
          ftrace_ret_handler(mem_wb_pc, mem_wb_target);
      end

      if (lsu_access_fault)
        access_fault_handler(mem_wb_pc,
                             {31'b0, (mem_wb_inst[6:0] == OP_STORE)});
    end
  end
`endif

endmodule
