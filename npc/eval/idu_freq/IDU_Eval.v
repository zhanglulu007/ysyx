// Registered wrapper used to compare IDU combinational implementations.
// The input/output flops create a repeatable reg-to-reg timing path.
module IDU_Eval(
  input clk,
  input [31:0] inst_in,
  input ifu_valid_in,
  output reg [239:0] signature
);
  reg [31:0] inst_q;
  reg ifu_valid_q;
  always @(posedge clk) begin
    inst_q <= inst_in;
    ifu_valid_q <= ifu_valid_in;
  end

  wire [6:0] opcode;
  wire [4:0] rd, rs1, rs2;
  wire [2:0] funct3;
  wire [6:0] funct7;
  wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  wire is_add, is_sub, is_and, is_or, is_xor, is_sll, is_srl, is_sra, is_slt, is_sltu;
  wire is_addi, is_slti, is_sltiu, is_xori, is_ori, is_andi, is_slli, is_srli, is_srai;
  wire is_lb, is_lh, is_lw, is_lbu, is_lhu, is_sb, is_sh, is_sw;
  wire is_beq, is_bne, is_blt, is_bge, is_bltu, is_bgeu;
  wire is_lui, is_auipc, is_jal, is_jalr;
  wire is_ebreak, is_ecall, is_mret, is_fencei, icache_flush;
  wire is_csrrw, is_csrrs, reg_wen, mem_valid, mem_wen, csr_wen;

`ifdef IDU_IMPL_GROUPED
  IDU_grouped u_idu(
`elsif IDU_IMPL_CLASSIFIED
  IDU_classified u_idu(
`elsif IDU_IMPL_CASEZ
  IDU_casez u_idu(
`else
  IDU u_idu(
`endif
    .inst(inst_q), .ifu_valid(ifu_valid_q), .opcode(opcode), .rd(rd), .rs1(rs1), .rs2(rs2),
    .funct3(funct3), .funct7(funct7), .imm_i(imm_i), .imm_s(imm_s), .imm_b(imm_b),
    .imm_u(imm_u), .imm_j(imm_j), .is_add(is_add), .is_sub(is_sub), .is_and(is_and),
    .is_or(is_or), .is_xor(is_xor), .is_sll(is_sll), .is_srl(is_srl), .is_sra(is_sra),
    .is_slt(is_slt), .is_sltu(is_sltu), .is_addi(is_addi), .is_slti(is_slti),
    .is_sltiu(is_sltiu), .is_xori(is_xori), .is_ori(is_ori), .is_andi(is_andi),
    .is_slli(is_slli), .is_srli(is_srli), .is_srai(is_srai), .is_lb(is_lb), .is_lh(is_lh),
    .is_lw(is_lw), .is_lbu(is_lbu), .is_lhu(is_lhu), .is_sb(is_sb), .is_sh(is_sh), .is_sw(is_sw),
    .is_beq(is_beq), .is_bne(is_bne), .is_blt(is_blt), .is_bge(is_bge), .is_bltu(is_bltu),
    .is_bgeu(is_bgeu), .is_lui(is_lui), .is_auipc(is_auipc), .is_jal(is_jal), .is_jalr(is_jalr),
    .is_ebreak(is_ebreak), .is_ecall(is_ecall), .is_mret(is_mret), .is_fencei(is_fencei),
    .icache_flush(icache_flush), .is_csrrw(is_csrrw), .is_csrrs(is_csrrs), .reg_wen(reg_wen),
    .mem_valid(mem_valid), .mem_wen(mem_wen), .csr_wen(csr_wen)
  );

  wire [239:0] signature_d = {
    opcode, rd, rs1, rs2, funct3, funct7,
    imm_i, imm_s, imm_b, imm_u, imm_j,
    is_add, is_sub, is_and, is_or, is_xor, is_sll, is_srl, is_sra, is_slt, is_sltu,
    is_addi, is_slti, is_sltiu, is_xori, is_ori, is_andi, is_slli, is_srli, is_srai,
    is_lb, is_lh, is_lw, is_lbu, is_lhu, is_sb, is_sh, is_sw,
    is_beq, is_bne, is_blt, is_bge, is_bltu, is_bgeu,
    is_lui, is_auipc, is_jal, is_jalr, is_ebreak, is_ecall, is_mret, is_fencei,
    icache_flush, is_csrrw, is_csrrs, reg_wen, mem_valid, mem_wen, csr_wen
  };
  always @(posedge clk) signature <= signature_d;
endmodule
