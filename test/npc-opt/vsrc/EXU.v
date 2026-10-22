//------------------------------------------------------------------------------
// EXU: 紧凑 ALU + 分支比较
//
// 与旧实现相比：
//   * 加法/减法结果在 ID 级由共享 adder 算好并寄存（add_result），
//     EX 只做逻辑/移位/比较/结果选择，缩短 EX 关键路径；
//   * 分支比较与 slt/sltu 共享 eq/lt/ltu 三个比较结果；
//   * 分支目标同样在 ID 级预计算（add_result），EX 不再放 32 位加法器
//     到“比较 -> 选 PC”的关键路径上。
//------------------------------------------------------------------------------
module EXU(
  input  [31:0] rs1_data,
  input  [31:0] rs2_data,
  input  [31:0] alu_b,
  input  [31:0] add_result,     // ID 级共享 adder 的结果（已寄存）
  input  [31:0] pc,
  input  [ 4:0] shamt,

  input  [3:0]  alu_op,
  input  [2:0]  branch_op,
  input         is_branch,

  output reg [31:0] alu_result,
  output reg        branch_taken,
  output [31:0]     link_value
);

  localparam [3:0] ALU_ADD  = 4'd0;
  localparam [3:0] ALU_SUB  = 4'd1;
  localparam [3:0] ALU_AND  = 4'd2;
  localparam [3:0] ALU_OR   = 4'd3;
  localparam [3:0] ALU_XOR  = 4'd4;
  localparam [3:0] ALU_SLL  = 4'd5;
  localparam [3:0] ALU_SRL  = 4'd6;
  localparam [3:0] ALU_SRA  = 4'd7;
  localparam [3:0] ALU_SLT  = 4'd8;
  localparam [3:0] ALU_SLTU = 4'd9;

  localparam [2:0] BR_EQ  = 3'd0;
  localparam [2:0] BR_NE  = 3'd1;
  localparam [2:0] BR_LT  = 3'd2;
  localparam [2:0] BR_GE  = 3'd3;
  localparam [2:0] BR_LTU = 3'd4;
  localparam [2:0] BR_GEU = 3'd5;

  wire eq      = (rs1_data == rs2_data);
  wire lt_alu  = ($signed(rs1_data) < $signed(alu_b));
  wire ltu_alu = (rs1_data < alu_b);
  wire lt_br   = ($signed(rs1_data) < $signed(rs2_data));
  wire ltu_br  = (rs1_data < rs2_data);

  always @(*) begin
    case (alu_op)
      ALU_ADD:  alu_result = add_result;
      ALU_SUB:  alu_result = add_result;
      ALU_AND:  alu_result = rs1_data & alu_b;
      ALU_OR:   alu_result = rs1_data | alu_b;
      ALU_XOR:  alu_result = rs1_data ^ alu_b;
      ALU_SLL:  alu_result = rs1_data << shamt;
      ALU_SRL:  alu_result = rs1_data >> shamt;
      ALU_SRA:  alu_result = $signed(rs1_data) >>> shamt;
      ALU_SLT:  alu_result = {31'b0, lt_alu};
      ALU_SLTU: alu_result = {31'b0, ltu_alu};
      default:  alu_result = 32'b0;
    endcase
  end

  always @(*) begin
    case (branch_op)
      BR_EQ:  branch_taken = eq;
      BR_NE:  branch_taken = ~eq;
      BR_LT:  branch_taken = lt_br;
      BR_GE:  branch_taken = ~lt_br;
      BR_LTU: branch_taken = ltu_br;
      BR_GEU: branch_taken = ~ltu_br;
      default: branch_taken = 1'b0;
    endcase
  end

  assign link_value = pc + 32'd4;

endmodule
