// IDU_grouped - opcode first, then funct3/funct7 hierarchical decoder.
// This module intentionally has the same interface and behavior as IDU.v.

module IDU_grouped(
  input [31:0] inst,
  input ifu_valid,
  output [6:0] opcode,
  output [4:0] rd,
  output [4:0] rs1,
  output [4:0] rs2,
  output [2:0] funct3,
  output [6:0] funct7,
  output [31:0] imm_i,
  output [31:0] imm_s,
  output [31:0] imm_b,
  output [31:0] imm_u,
  output [31:0] imm_j,
  output reg is_add,
  output reg is_sub,
  output reg is_and,
  output reg is_or,
  output reg is_xor,
  output reg is_sll,
  output reg is_srl,
  output reg is_sra,
  output reg is_slt,
  output reg is_sltu,
  output reg is_addi,
  output reg is_slti,
  output reg is_sltiu,
  output reg is_xori,
  output reg is_ori,
  output reg is_andi,
  output reg is_slli,
  output reg is_srli,
  output reg is_srai,
  output reg is_lb,
  output reg is_lh,
  output reg is_lw,
  output reg is_lbu,
  output reg is_lhu,
  output reg is_sb,
  output reg is_sh,
  output reg is_sw,
  output reg is_beq,
  output reg is_bne,
  output reg is_blt,
  output reg is_bge,
  output reg is_bltu,
  output reg is_bgeu,
  output reg is_lui,
  output reg is_auipc,
  output reg is_jal,
  output reg is_jalr,
  output reg is_ebreak,
  output reg is_ecall,
  output reg is_mret,
  output reg is_fencei,
  output reg icache_flush,
  output reg is_csrrw,
  output reg is_csrrs,
  output reg reg_wen,
  output reg mem_valid,
  output reg mem_wen,
  output reg csr_wen
);

  localparam [6:0] OP_R      = 7'b0110011;
  localparam [6:0] OP_I      = 7'b0010011;
  localparam [6:0] OP_LOAD   = 7'b0000011;
  localparam [6:0] OP_STORE  = 7'b0100011;
  localparam [6:0] OP_BRANCH = 7'b1100011;
  localparam [6:0] OP_LUI    = 7'b0110111;
  localparam [6:0] OP_AUIPC  = 7'b0010111;
  localparam [6:0] OP_JAL    = 7'b1101111;
  localparam [6:0] OP_JALR   = 7'b1100111;
  localparam [6:0] OP_SYSTEM = 7'b1110011;
  localparam [6:0] OP_FENCE  = 7'b0001111;

  assign opcode = inst[6:0];
  assign rd = inst[11:7];
  assign rs1 = inst[19:15];
  assign rs2 = inst[24:20];
  assign funct3 = inst[14:12];
  assign funct7 = inst[31:25];
  assign imm_i = {{20{inst[31]}}, inst[31:20]};
  assign imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  assign imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
  assign imm_u = {inst[31:12], 12'b0};
  assign imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

  wire is_r_type = is_add || is_sub || is_and || is_or || is_xor || is_sll ||
                   is_srl || is_sra || is_slt || is_sltu;
  wire is_i_arith = is_addi || is_slti || is_sltiu || is_xori || is_ori ||
                    is_andi || is_slli || is_srli || is_srai;
  wire is_load = is_lb || is_lh || is_lw || is_lbu || is_lhu;
  wire is_store = is_sb || is_sh || is_sw;
  wire is_jump = is_jal || is_jalr;
  wire is_u_type = is_lui || is_auipc;
  wire is_csr = is_csrrw || is_csrrs;

  always @(*) begin
    is_add = 1'b0; is_sub = 1'b0; is_and = 1'b0; is_or = 1'b0; is_xor = 1'b0;
    is_sll = 1'b0; is_srl = 1'b0; is_sra = 1'b0; is_slt = 1'b0; is_sltu = 1'b0;
    is_addi = 1'b0; is_slti = 1'b0; is_sltiu = 1'b0; is_xori = 1'b0;
    is_ori = 1'b0; is_andi = 1'b0; is_slli = 1'b0; is_srli = 1'b0; is_srai = 1'b0;
    is_lb = 1'b0; is_lh = 1'b0; is_lw = 1'b0; is_lbu = 1'b0; is_lhu = 1'b0;
    is_sb = 1'b0; is_sh = 1'b0; is_sw = 1'b0;
    is_beq = 1'b0; is_bne = 1'b0; is_blt = 1'b0; is_bge = 1'b0;
    is_bltu = 1'b0; is_bgeu = 1'b0;
    is_lui = 1'b0; is_auipc = 1'b0; is_jal = 1'b0; is_jalr = 1'b0;
    is_ebreak = 1'b0; is_ecall = 1'b0; is_mret = 1'b0; is_fencei = 1'b0;
    icache_flush = 1'b0; is_csrrw = 1'b0; is_csrrs = 1'b0;
    reg_wen = 1'b0; mem_valid = 1'b0; mem_wen = 1'b0; csr_wen = 1'b0;

    case (opcode)
      OP_R: begin
        case (funct3)
          3'b000: if (funct7 == 7'b0000000) is_add = 1'b1;
                  else if (funct7 == 7'b0100000) is_sub = 1'b1;
          3'b001: if (funct7 == 7'b0000000) is_sll = 1'b1;
          3'b010: if (funct7 == 7'b0000000) is_slt = 1'b1;
          3'b011: if (funct7 == 7'b0000000) is_sltu = 1'b1;
          3'b100: if (funct7 == 7'b0000000) is_xor = 1'b1;
          3'b101: if (funct7 == 7'b0000000) is_srl = 1'b1;
                  else if (funct7 == 7'b0100000) is_sra = 1'b1;
          3'b110: if (funct7 == 7'b0000000) is_or = 1'b1;
          3'b111: if (funct7 == 7'b0000000) is_and = 1'b1;
        endcase
      end
      OP_I: begin
        case (funct3)
          3'b000: is_addi = 1'b1;
          3'b010: is_slti = 1'b1;
          3'b011: is_sltiu = 1'b1;
          3'b100: is_xori = 1'b1;
          3'b110: is_ori = 1'b1;
          3'b111: is_andi = 1'b1;
          3'b001: if (funct7 == 7'b0000000) is_slli = 1'b1;
          3'b101: if (funct7 == 7'b0000000) is_srli = 1'b1;
                  else if (funct7 == 7'b0100000) is_srai = 1'b1;
        endcase
      end
      OP_LOAD: begin
        case (funct3)
          3'b000: is_lb = 1'b1;
          3'b001: is_lh = 1'b1;
          3'b010: is_lw = 1'b1;
          3'b100: is_lbu = 1'b1;
          3'b101: is_lhu = 1'b1;
        endcase
      end
      OP_STORE: begin
        case (funct3)
          3'b000: is_sb = 1'b1;
          3'b001: is_sh = 1'b1;
          3'b010: is_sw = 1'b1;
        endcase
      end
      OP_BRANCH: begin
        case (funct3)
          3'b000: is_beq = 1'b1;
          3'b001: is_bne = 1'b1;
          3'b100: is_blt = 1'b1;
          3'b101: is_bge = 1'b1;
          3'b110: is_bltu = 1'b1;
          3'b111: is_bgeu = 1'b1;
        endcase
      end
      OP_LUI: is_lui = 1'b1;
      OP_AUIPC: is_auipc = 1'b1;
      OP_JAL: is_jal = 1'b1;
      OP_JALR: if (funct3 == 3'b000) is_jalr = 1'b1;
      OP_FENCE: if (funct3 == 3'b001) begin is_fencei = 1'b1; icache_flush = 1'b1; end
      OP_SYSTEM: begin
        if (inst == 32'h00100073) is_ebreak = 1'b1;
        else if (inst == 32'h00000073) is_ecall = 1'b1;
        else if (inst == 32'h30200073) is_mret = 1'b1;
        else begin
          if (funct3 == 3'b001) is_csrrw = 1'b1;
          else if (funct3 == 3'b010) is_csrrs = 1'b1;
        end
      end
    endcase

    reg_wen = ifu_valid && (is_r_type || is_i_arith || is_load || is_jump ||
                            is_u_type || is_csr) && (rd != 5'b0);
    mem_valid = ifu_valid && (is_load || is_store);
    mem_wen = ifu_valid && is_store;
    csr_wen = ifu_valid && (is_csrrw || (is_csrrs && (rs1 != 5'b0)));
    icache_flush = ifu_valid && is_fencei;
  end
endmodule
