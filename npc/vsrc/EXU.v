// ============================================================================
// EXU - 执行单元 (E stage)
//
// 控制信号在 D 段已经译码并寄存在 IDEX, 这里不再做 opcode/funct 译码,
// 因此 ALU 的关键路径只包含  forwarded operands -> ALU -> 写回。
//
// alu_op:
//   0 ADD, 1 SUB, 2 SLL, 3 SLT, 4 SLTU, 5 XOR, 6 SRL, 7 SRA, 8 OR, 9 AND
// load/store 使用 ADD 产生地址 (rs1 + imm_i/imm_s)。
// ============================================================================
module EXU(
  input [31:0] rs1_data,
  input [31:0] rs2_data,
  input [31:0] imm_i,
  input [31:0] imm_s,
  input [31:0] imm_b,
  input [31:0] imm_j,
  input [31:0] imm_u,
  input [31:0] pc,

  input [3:0] alu_op,
  input       alu_rs2,        // R 型: 第二操作数取 rs2
  input       alu_imm_s,      // store: 地址用 imm_s

  input [2:0] branch_type,
  input       is_branch,
  input       is_jal,
  input       is_auipc,

  output reg [31:0] alu_result,
  output [31:0] jump_target,
  output [31:0] branch_target,
  output [31:0] pc_imm,
  output reg        branch_taken
);

  localparam ALU_ADD  = 4'd0;
  localparam ALU_SUB  = 4'd1;
  localparam ALU_SLL  = 4'd2;
  localparam ALU_SLT  = 4'd3;
  localparam ALU_SLTU = 4'd4;
  localparam ALU_XOR  = 4'd5;
  localparam ALU_SRL  = 4'd6;
  localparam ALU_SRA  = 4'd7;
  localparam ALU_OR   = 4'd8;
  localparam ALU_AND  = 4'd9;

  wire [31:0] alu_src2 = alu_rs2 ? rs2_data : (alu_imm_s ? imm_s : imm_i);
  wire [4:0]  shamt    = alu_rs2 ? rs2_data[4:0] : imm_i[4:0];

  always @(*) begin
    case (alu_op)
      ALU_ADD : alu_result = rs1_data + alu_src2;
      ALU_SUB : alu_result = rs1_data - alu_src2;
      ALU_SLL : alu_result = rs1_data << shamt;
      ALU_SLT : alu_result = ($signed(rs1_data) < $signed(alu_src2)) ? 32'd1 : 32'd0;
      ALU_SLTU: alu_result = (rs1_data < alu_src2) ? 32'd1 : 32'd0;
      ALU_XOR : alu_result = rs1_data ^ alu_src2;
      ALU_SRL : alu_result = rs1_data >> shamt;
      ALU_SRA : alu_result = $signed(rs1_data) >>> shamt;
      ALU_OR  : alu_result = rs1_data | alu_src2;
      ALU_AND : alu_result = rs1_data & alu_src2;
      default : alu_result = 32'b0;
    endcase
  end

  // 分支条件: 0 beq, 1 bne, 2 blt, 3 bge, 4 bltu, 5 bgeu
  always @(*) begin
    branch_taken = 1'b0;
    if (is_branch) begin
      case (branch_type)
        3'd0: branch_taken = (rs1_data == rs2_data);
        3'd1: branch_taken = (rs1_data != rs2_data);
        3'd2: branch_taken = ($signed(rs1_data) <  $signed(rs2_data));
        3'd3: branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
        3'd4: branch_taken = (rs1_data <  rs2_data);
        3'd5: branch_taken = (rs1_data >= rs2_data);
        default: branch_taken = 1'b0;
      endcase
    end
  end

  assign jump_target = (rs1_data + imm_i) & ~32'h1;
  // 分支/JAL/AUIPC 共用同一个 PC 加法器
  assign pc_imm       = pc + (is_jal ? imm_j : (is_auipc ? imm_u : imm_b));
  assign branch_target = pc_imm;

endmodule
