// ============================================================================
//  EXU - 执行单元
//
//  面积/时序优化点:
//   * 只保留一个 32-bit 主加法器, 加法/减法/SLT/SLTU/分支比较/访存地址共用;
//   * 逻辑运算与移位器并行计算, 结果 mux 选出, 取代原先的一长串优先级 case;
//   * branch_taken 复用主加法器的借位/符号位, 不再单独做比较器.
// ============================================================================
module EXU(
  input  [31:0] rs1,
  input  [31:0] rs2,
  input  [31:0] pc,
  input  [31:0] imm_i,
  input  [31:0] imm_s,
  input  [31:0] imm_b,
  input  [31:0] imm_j,
  input  [31:0] imm_u,

  input  [3:0]  alu_op,
  input  [1:0]  alu_a_sel,
  input  [1:0]  alu_b_sel,
  input         is_branch,
  input         is_jal,
  input  [2:0]  funct3,

  output [31:0] alu_result,
  output        branch_taken,
  output [31:0] pc_plus4,
  output [31:0] pc_target
);

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

  localparam [1:0] A_RS1 = 2'd0, A_PC = 2'd1, A_ZERO = 2'd2;
  localparam [1:0] B_RS2 = 2'd0, B_IMM_I = 2'd1, B_IMM_S = 2'd2, B_IMM_U = 2'd3;

  // ---------------------------------------------------------- 操作数选择
  wire [31:0] src_a = (alu_a_sel == A_PC)   ? pc :
                      (alu_a_sel == A_ZERO) ? 32'b0 : rs1;

  wire [31:0] src_b = (alu_b_sel == B_IMM_I) ? imm_i :
                      (alu_b_sel == B_IMM_S) ? imm_s :
                      (alu_b_sel == B_IMM_U) ? imm_u : rs2;

  // ---------------------------------------------------------- 主加法器
  // SLT/SLTU 复用减法器; 分支在 IDU 中已编码为 ALU_SUB
  wire sub = (alu_op == ALU_SUB) || (alu_op == ALU_SLT) || (alu_op == ALU_SLTU);
  wire [31:0] b_inv = sub ? ~src_b : src_b;
  wire [32:0] sum33 = {1'b0, src_a} + {1'b0, b_inv} + {32'b0, sub};
  wire [31:0] addsub = sum33[31:0];
  wire        carry  = sum33[32];

  // 有符号溢出: 仅减法结果有意义 (SLT/分支)
  wire ovf  = (src_a[31] != src_b[31]) && (addsub[31] != src_a[31]);
  wire slt  = addsub[31] ^ ovf;
  wire sltu = ~carry;

  // ---------------------------------------------------------- 并行逻辑/移位
  wire [4:0]  shamt = src_b[4:0];
  wire [31:0] shl   = src_a << shamt;
  wire [31:0] shr   = src_a >> shamt;
  wire [31:0] sar   = $signed(src_a) >>> shamt;
  wire [31:0] v_xor = src_a ^ src_b;
  wire [31:0] v_or  = src_a | src_b;
  wire [31:0] v_and = src_a & src_b;

  reg [31:0] res;
  always @(*) begin
    case (alu_op)
      ALU_ADD : res = addsub;
      ALU_SUB : res = addsub;
      ALU_SLL : res = shl;
      ALU_SLT : res = {31'b0, slt};
      ALU_SLTU: res = {31'b0, sltu};
      ALU_XOR : res = v_xor;
      ALU_SRL : res = shr;
      ALU_SRA : res = sar;
      ALU_OR  : res = v_or;
      ALU_AND : res = v_and;
      default : res = addsub;
    endcase
  end
  assign alu_result = res;

  // ---------------------------------------------------------- 分支判断
  // 分支时 IDU 已把 alu_op 置为 SUB, 故 addsub/carry/ovf 就是 rs1-rs2 的结果
  wire eq  = (src_a == src_b);
  reg  taken;
  always @(*) begin
    // funct3 来自指令, 由 top 直接连入
    case (funct3)
      3'b000: taken = eq;        // beq
      3'b001: taken = ~eq;       // bne
      3'b100: taken = slt;       // blt
      3'b101: taken = ~slt;      // bge
      3'b110: taken = sltu;      // bltu
      3'b111: taken = ~sltu;     // bgeu
      default: taken = 1'b0;
    endcase
  end
  assign branch_taken = is_branch && taken;

  // ---------------------------------------------------------- PC 相关
  assign pc_plus4  = pc + 32'd4;
  assign pc_target = pc + (is_jal ? imm_j : imm_b);

endmodule
