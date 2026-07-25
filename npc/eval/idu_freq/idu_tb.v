`timescale 1ns/1ps
module idu_tb;
  reg clk = 0;
  reg [31:0] inst;
  reg ifu_valid;
  always #5 clk = ~clk;

  `define IDU_SIGNALS(P) \
    wire [6:0] P``_opcode; wire [4:0] P``_rd, P``_rs1, P``_rs2; wire [2:0] P``_funct3; wire [6:0] P``_funct7; \
    wire [31:0] P``_imm_i, P``_imm_s, P``_imm_b, P``_imm_u, P``_imm_j; \
    wire P``_is_add, P``_is_sub, P``_is_and, P``_is_or, P``_is_xor, P``_is_sll, P``_is_srl, P``_is_sra, P``_is_slt, P``_is_sltu; \
    wire P``_is_addi, P``_is_slti, P``_is_sltiu, P``_is_xori, P``_is_ori, P``_is_andi, P``_is_slli, P``_is_srli, P``_is_srai; \
    wire P``_is_lb, P``_is_lh, P``_is_lw, P``_is_lbu, P``_is_lhu, P``_is_sb, P``_is_sh, P``_is_sw; \
    wire P``_is_beq, P``_is_bne, P``_is_blt, P``_is_bge, P``_is_bltu, P``_is_bgeu; \
    wire P``_is_lui, P``_is_auipc, P``_is_jal, P``_is_jalr, P``_is_ebreak, P``_is_ecall, P``_is_mret, P``_is_fencei, P``_icache_flush; \
    wire P``_is_csrrw, P``_is_csrrs, P``_reg_wen, P``_mem_valid, P``_mem_wen, P``_csr_wen;

  `define IDU_PORTS(P) \
    .inst(inst), .ifu_valid(ifu_valid), .opcode(P``_opcode), .rd(P``_rd), .rs1(P``_rs1), .rs2(P``_rs2), .funct3(P``_funct3), .funct7(P``_funct7), \
    .imm_i(P``_imm_i), .imm_s(P``_imm_s), .imm_b(P``_imm_b), .imm_u(P``_imm_u), .imm_j(P``_imm_j), \
    .is_add(P``_is_add), .is_sub(P``_is_sub), .is_and(P``_is_and), .is_or(P``_is_or), .is_xor(P``_is_xor), .is_sll(P``_is_sll), .is_srl(P``_is_srl), .is_sra(P``_is_sra), .is_slt(P``_is_slt), .is_sltu(P``_is_sltu), \
    .is_addi(P``_is_addi), .is_slti(P``_is_slti), .is_sltiu(P``_is_sltiu), .is_xori(P``_is_xori), .is_ori(P``_is_ori), .is_andi(P``_is_andi), .is_slli(P``_is_slli), .is_srli(P``_is_srli), .is_srai(P``_is_srai), \
    .is_lb(P``_is_lb), .is_lh(P``_is_lh), .is_lw(P``_is_lw), .is_lbu(P``_is_lbu), .is_lhu(P``_is_lhu), .is_sb(P``_is_sb), .is_sh(P``_is_sh), .is_sw(P``_is_sw), \
    .is_beq(P``_is_beq), .is_bne(P``_is_bne), .is_blt(P``_is_blt), .is_bge(P``_is_bge), .is_bltu(P``_is_bltu), .is_bgeu(P``_is_bgeu), \
    .is_lui(P``_is_lui), .is_auipc(P``_is_auipc), .is_jal(P``_is_jal), .is_jalr(P``_is_jalr), .is_ebreak(P``_is_ebreak), .is_ecall(P``_is_ecall), .is_mret(P``_is_mret), .is_fencei(P``_is_fencei), .icache_flush(P``_icache_flush), \
    .is_csrrw(P``_is_csrrw), .is_csrrs(P``_is_csrrs), .reg_wen(P``_reg_wen), .mem_valid(P``_mem_valid), .mem_wen(P``_mem_wen), .csr_wen(P``_csr_wen)

  `IDU_SIGNALS(ref)
  `IDU_SIGNALS(classified)
  `IDU_SIGNALS(grouped)
  `IDU_SIGNALS(cz)
  IDU u_ref(`IDU_PORTS(ref));
  IDU_classified u_classified(`IDU_PORTS(classified));
  IDU_grouped u_grouped(`IDU_PORTS(grouped));
  IDU_casez u_casez(`IDU_PORTS(cz));

  wire [239:0] ref_sig = {
    ref_opcode, ref_rd, ref_rs1, ref_rs2, ref_funct3, ref_funct7, ref_imm_i, ref_imm_s, ref_imm_b, ref_imm_u, ref_imm_j,
    ref_is_add, ref_is_sub, ref_is_and, ref_is_or, ref_is_xor, ref_is_sll, ref_is_srl, ref_is_sra, ref_is_slt, ref_is_sltu,
    ref_is_addi, ref_is_slti, ref_is_sltiu, ref_is_xori, ref_is_ori, ref_is_andi, ref_is_slli, ref_is_srli, ref_is_srai,
    ref_is_lb, ref_is_lh, ref_is_lw, ref_is_lbu, ref_is_lhu, ref_is_sb, ref_is_sh, ref_is_sw,
    ref_is_beq, ref_is_bne, ref_is_blt, ref_is_bge, ref_is_bltu, ref_is_bgeu, ref_is_lui, ref_is_auipc, ref_is_jal, ref_is_jalr,
    ref_is_ebreak, ref_is_ecall, ref_is_mret, ref_is_fencei, ref_icache_flush, ref_is_csrrw, ref_is_csrrs, ref_reg_wen, ref_mem_valid, ref_mem_wen, ref_csr_wen};
  wire [239:0] grouped_sig = {
    grouped_opcode, grouped_rd, grouped_rs1, grouped_rs2, grouped_funct3, grouped_funct7, grouped_imm_i, grouped_imm_s, grouped_imm_b, grouped_imm_u, grouped_imm_j,
    grouped_is_add, grouped_is_sub, grouped_is_and, grouped_is_or, grouped_is_xor, grouped_is_sll, grouped_is_srl, grouped_is_sra, grouped_is_slt, grouped_is_sltu,
    grouped_is_addi, grouped_is_slti, grouped_is_sltiu, grouped_is_xori, grouped_is_ori, grouped_is_andi, grouped_is_slli, grouped_is_srli, grouped_is_srai,
    grouped_is_lb, grouped_is_lh, grouped_is_lw, grouped_is_lbu, grouped_is_lhu, grouped_is_sb, grouped_is_sh, grouped_is_sw,
    grouped_is_beq, grouped_is_bne, grouped_is_blt, grouped_is_bge, grouped_is_bltu, grouped_is_bgeu, grouped_is_lui, grouped_is_auipc, grouped_is_jal, grouped_is_jalr,
    grouped_is_ebreak, grouped_is_ecall, grouped_is_mret, grouped_is_fencei, grouped_icache_flush, grouped_is_csrrw, grouped_is_csrrs, grouped_reg_wen, grouped_mem_valid, grouped_mem_wen, grouped_csr_wen};
  wire [239:0] classified_sig = {
    classified_opcode, classified_rd, classified_rs1, classified_rs2, classified_funct3, classified_funct7, classified_imm_i, classified_imm_s, classified_imm_b, classified_imm_u, classified_imm_j,
    classified_is_add, classified_is_sub, classified_is_and, classified_is_or, classified_is_xor, classified_is_sll, classified_is_srl, classified_is_sra, classified_is_slt, classified_is_sltu,
    classified_is_addi, classified_is_slti, classified_is_sltiu, classified_is_xori, classified_is_ori, classified_is_andi, classified_is_slli, classified_is_srli, classified_is_srai,
    classified_is_lb, classified_is_lh, classified_is_lw, classified_is_lbu, classified_is_lhu, classified_is_sb, classified_is_sh, classified_is_sw,
    classified_is_beq, classified_is_bne, classified_is_blt, classified_is_bge, classified_is_bltu, classified_is_bgeu, classified_is_lui, classified_is_auipc, classified_is_jal, classified_is_jalr,
    classified_is_ebreak, classified_is_ecall, classified_is_mret, classified_is_fencei, classified_icache_flush, classified_is_csrrw, classified_is_csrrs, classified_reg_wen, classified_mem_valid, classified_mem_wen, classified_csr_wen};
  wire [239:0] casez_sig = {
    cz_opcode, cz_rd, cz_rs1, cz_rs2, cz_funct3, cz_funct7, cz_imm_i, cz_imm_s, cz_imm_b, cz_imm_u, cz_imm_j,
    cz_is_add, cz_is_sub, cz_is_and, cz_is_or, cz_is_xor, cz_is_sll, cz_is_srl, cz_is_sra, cz_is_slt, cz_is_sltu,
    cz_is_addi, cz_is_slti, cz_is_sltiu, cz_is_xori, cz_is_ori, cz_is_andi, cz_is_slli, cz_is_srli, cz_is_srai,
    cz_is_lb, cz_is_lh, cz_is_lw, cz_is_lbu, cz_is_lhu, cz_is_sb, cz_is_sh, cz_is_sw,
    cz_is_beq, cz_is_bne, cz_is_blt, cz_is_bge, cz_is_bltu, cz_is_bgeu, cz_is_lui, cz_is_auipc, cz_is_jal, cz_is_jalr,
    cz_is_ebreak, cz_is_ecall, cz_is_mret, cz_is_fencei, cz_icache_flush, cz_is_csrrw, cz_is_csrrs, cz_reg_wen, cz_mem_valid, cz_mem_wen, cz_csr_wen};

  task check;
    input [31:0] value;
    input valid;
    begin
      @(negedge clk); inst = value; ifu_valid = valid;
      @(posedge clk); #1;
      if (ref_sig !== classified_sig || ref_sig !== grouped_sig || ref_sig !== casez_sig) begin
        $display("MISMATCH inst=%h ref=%h classified=%h grouped=%h casez=%h", value, ref_sig, classified_sig, grouped_sig, casez_sig);
        $finish(1);
      end
    end
  endtask

  integer i;
  initial begin
    inst = 0; ifu_valid = 0;
    check(32'h00000033, 1'b1); check(32'h40000033, 1'b1); check(32'h00007033, 1'b1); check(32'h00500093, 1'b1);
    check(32'h40005013, 1'b1); check(32'h00002283, 1'b1); check(32'h00502223, 1'b1); check(32'h00000063, 1'b1);
    check(32'h0000006f, 1'b1); check(32'h00000073, 1'b1); check(32'h00100073, 1'b1); check(32'h30200073, 1'b1);
    check(32'h0000100f, 1'b1); check(32'h00109073, 1'b1); check(32'h00012073, 1'b1);
    for (i = 0; i < 1000; i = i + 1) check($random, i[0]);
    $display("IDU equivalence checks passed");
    $finish;
  end
endmodule
