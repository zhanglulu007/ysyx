// ============================================================================
//  IDU - 指令译码单元 (RV32E, 编码式控制)
//
//  与 npc/vsrc/IDU.v 的 one-hot (~40 根 is_* 信号) 译码不同, 这里把控制
//  压缩成少量编码字段:
//    alu_op   : ALU 运算
//    a_sel    : ALU A 口来源 (rs1 / pc / 0)
//    b_sel    : ALU B 口来源 (rs2 / imm_i / imm_s / imm_u)
//    wb_sel   : 写回来源 (alu / pc+4 / load / csr)
//    mem_op   : 访存宽度/方向 (none/lb/lh/lw/lbu/lhu/sb/sh/sw)
//    csr_op   : CSR 操作 (none/csrrw/csrrs)
//  这样可以省掉大量 opcode/funct3/funct7 比较器与 one-hot 优先级 mux.
// ============================================================================
module IDU(
  input  [31:0] inst,

  output [4:0]  rd,
  output [4:0]  rs1,
  output [4:0]  rs2,

  output [3:0]  alu_op,
  output [1:0]  alu_a_sel,
  output [1:0]  alu_b_sel,
  output [1:0]  wb_sel,
  output [3:0]  mem_op,
  output [1:0]  csr_op,

  output        reg_wen,
  output        is_branch,
  output        is_jal,
  output        is_jalr,
  output        is_ecall,
  output        is_mret,
  output        is_ebreak,
  output        is_fence_i,
  output        is_load,
  output        is_store,

  output [31:0] imm_i,
  output [31:0] imm_s,
  output [31:0] imm_b,
  output [31:0] imm_u,
  output [31:0] imm_j
);

  // ---------------- ALU 运算编码 ----------------
  localparam [3:0] ALU_ADD  = 4'd0,
                   ALU_SUB  = 4'd1,
                   ALU_SLL  = 4'd2,
                   ALU_SLT  = 4'd3,
                   ALU_SLTU = 4'd4,
                   ALU_XOR  = 4'd5,
                   ALU_SRL  = 4'd6,
                   ALU_SRA  = 4'd7,
                   ALU_OR   = 4'd8,
                   ALU_AND  = 4'd9;

  // ---------------- ALU A 口 ----------------
  localparam [1:0] A_RS1 = 2'd0,
                   A_PC  = 2'd1,
                   A_ZERO= 2'd2;

  // ---------------- ALU B 口 ----------------
  localparam [1:0] B_RS2   = 2'd0,
                   B_IMM_I = 2'd1,
                   B_IMM_S = 2'd2,
                   B_IMM_U = 2'd3;

  // ---------------- 写回来源 ----------------
  localparam [1:0] WB_ALU  = 2'd0,
                   WB_PC4  = 2'd1,
                   WB_LOAD = 2'd2,
                   WB_CSR  = 2'd3;

  // ---------------- 访存操作 ----------------
  localparam [3:0] M_NONE = 4'd0,
                   M_LB   = 4'd1,
                   M_LH   = 4'd2,
                   M_LW   = 4'd3,
                   M_LBU  = 4'd4,
                   M_LHU  = 4'd5,
                   M_SB   = 4'd6,
                   M_SH   = 4'd7,
                   M_SW   = 4'd8;

  // ---------------- CSR 操作 ----------------
  localparam [1:0] CSR_NONE = 2'd0,
                   CSR_RW   = 2'd1,
                   CSR_RS   = 2'd2;

  wire [6:0] opcode = inst[6:0];
  wire [2:0] funct3 = inst[14:12];
  wire [6:0] funct7 = inst[31:25];

  assign rd  = inst[11:7];
  assign rs1 = inst[19:15];
  assign rs2 = inst[24:20];

  // 立即数并行生成, 均在指令进入 FIFO 后保持稳定, 不在关键路径上
  assign imm_i = {{20{inst[31]}}, inst[31:20]};
  assign imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  assign imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
  assign imm_u = {inst[31:12], 12'b0};
  assign imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

  reg [3:0] alu_op_r;
  reg [1:0] a_sel_r, b_sel_r, wb_sel_r;
  reg [3:0] mem_op_r;
  reg [1:0] csr_op_r;
  reg       reg_wen_r, branch_r, jal_r, jalr_r;
  reg       ecall_r, mret_r, ebreak_r, fence_i_r;

  always @(*) begin
    // 默认: nop (pc+4, 不写回)
    alu_op_r  = ALU_ADD;
    a_sel_r   = A_RS1;
    b_sel_r   = B_RS2;
    wb_sel_r  = WB_ALU;
    mem_op_r  = M_NONE;
    csr_op_r  = CSR_NONE;
    reg_wen_r = 1'b0;
    branch_r  = 1'b0;
    jal_r     = 1'b0;
    jalr_r    = 1'b0;
    ecall_r   = 1'b0;
    mret_r    = 1'b0;
    ebreak_r  = 1'b0;
    fence_i_r = 1'b0;

    case (opcode)
      // ---------------------------------------------------------------- R
      7'b0110011: begin
        reg_wen_r = 1'b1;
        a_sel_r   = A_RS1;
        b_sel_r   = B_RS2;
        case (funct3)
          3'b000: alu_op_r = funct7[5] ? ALU_SUB : ALU_ADD;
          3'b001: alu_op_r = ALU_SLL;
          3'b010: alu_op_r = ALU_SLT;
          3'b011: alu_op_r = ALU_SLTU;
          3'b100: alu_op_r = ALU_XOR;
          3'b101: alu_op_r = funct7[5] ? ALU_SRA : ALU_SRL;
          3'b110: alu_op_r = ALU_OR;
          3'b111: alu_op_r = ALU_AND;
          default: alu_op_r = ALU_ADD;
        endcase
      end

      // ------------------------------------------------------------ I arith
      7'b0010011: begin
        reg_wen_r = 1'b1;
        a_sel_r   = A_RS1;
        b_sel_r   = B_IMM_I;
        case (funct3)
          3'b000: alu_op_r = ALU_ADD;
          3'b001: alu_op_r = ALU_SLL;
          3'b010: alu_op_r = ALU_SLT;
          3'b011: alu_op_r = ALU_SLTU;
          3'b100: alu_op_r = ALU_XOR;
          3'b101: alu_op_r = inst[30] ? ALU_SRA : ALU_SRL;
          3'b110: alu_op_r = ALU_OR;
          3'b111: alu_op_r = ALU_AND;
          default: alu_op_r = ALU_ADD;
        endcase
      end

      // -------------------------------------------------------------- load
      7'b0000011: begin
        a_sel_r  = A_RS1;
        b_sel_r  = B_IMM_I;
        wb_sel_r = WB_LOAD;
        case (funct3)
          3'b000: mem_op_r = M_LB;
          3'b001: mem_op_r = M_LH;
          3'b010: mem_op_r = M_LW;
          3'b100: mem_op_r = M_LBU;
          3'b101: mem_op_r = M_LHU;
          default: mem_op_r = M_NONE;
        endcase
        reg_wen_r = (mem_op_r != M_NONE);
      end

      // ------------------------------------------------------------- store
      7'b0100011: begin
        a_sel_r = A_RS1;
        b_sel_r = B_IMM_S;
        case (funct3)
          3'b000: mem_op_r = M_SB;
          3'b001: mem_op_r = M_SH;
          3'b010: mem_op_r = M_SW;
          default: mem_op_r = M_NONE;
        endcase
      end

      // ------------------------------------------------------------ branch
      7'b1100011: begin
        branch_r = 1'b1;
        a_sel_r  = A_RS1;
        b_sel_r  = B_RS2;
        alu_op_r = ALU_SUB;      // 主加法器顺带算 rs1-rs2, 供比较使用
      end

      // --------------------------------------------------------------- lui
      7'b0110111: begin
        reg_wen_r = 1'b1;
        a_sel_r   = A_ZERO;
        b_sel_r   = B_IMM_U;
        alu_op_r  = ALU_ADD;
      end

      // ------------------------------------------------------------- auipc
      7'b0010111: begin
        reg_wen_r = 1'b1;
        a_sel_r   = A_PC;
        b_sel_r   = B_IMM_U;
        alu_op_r  = ALU_ADD;
      end

      // --------------------------------------------------------------- jal
      7'b1101111: begin
        reg_wen_r = 1'b1;
        jal_r     = 1'b1;
        wb_sel_r  = WB_PC4;
      end

      // -------------------------------------------------------------- jalr
      7'b1100111: begin
        reg_wen_r = 1'b1;
        jalr_r    = 1'b1;
        a_sel_r   = A_RS1;
        b_sel_r   = B_IMM_I;
        alu_op_r  = ALU_ADD;     // alu_result = 跳转目标
        wb_sel_r  = WB_PC4;
      end

      // ------------------------------------------------------------ system
      7'b1110011: begin
        if (inst == 32'h00100073) begin
          ebreak_r = 1'b1;
        end else if (inst == 32'h00000073) begin
          ecall_r = 1'b1;
        end else if (inst == 32'h30200073) begin
          mret_r = 1'b1;
        end else begin
          case (funct3)
            3'b001: begin
              csr_op_r  = CSR_RW;
              reg_wen_r = 1'b1;
              wb_sel_r  = WB_CSR;
            end
            3'b010: begin
              csr_op_r  = CSR_RS;
              reg_wen_r = 1'b1;
              wb_sel_r  = WB_CSR;
            end
            default: ;
          endcase
        end
      end

      // --------------------------------------------------------------- misc
      7'b0001111: begin
        // fence.i = 0x0000100F; 普通 fence 当作 nop
        if (inst == 32'h0000100F) fence_i_r = 1'b1;
      end

      default: ;
    endcase
  end

  assign alu_op   = alu_op_r;
  assign alu_a_sel= a_sel_r;
  assign alu_b_sel= b_sel_r;
  assign wb_sel   = wb_sel_r;
  assign mem_op   = mem_op_r;
  assign csr_op   = csr_op_r;
  assign reg_wen  = reg_wen_r;
  assign is_branch= branch_r;
  assign is_jal   = jal_r;
  assign is_jalr  = jalr_r;
  assign is_ecall = ecall_r;
  assign is_mret  = mret_r;
  assign is_ebreak= ebreak_r;
  assign is_fence_i = fence_i_r;
  assign is_load  = (mem_op_r == M_LB)  || (mem_op_r == M_LH)  ||
                    (mem_op_r == M_LW)  || (mem_op_r == M_LBU) ||
                    (mem_op_r == M_LHU);
  assign is_store = (mem_op_r == M_SB)  || (mem_op_r == M_SH)  ||
                    (mem_op_r == M_SW);

endmodule
