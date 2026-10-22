// ============================================================================
//  ALU - 三阶段流水线的执行级运算单元
//  操作数已由 ID 级选好并寄存, 这里只做运算与分支比较.
// ============================================================================
module ALU(
  input  [31:0] a,
  input  [31:0] b,
  input  [3:0]  alu_op,
  input         is_branch,
  input  [2:0]  funct3,
  output [31:0] result,
  output        branch_taken
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

  wire sub = (alu_op == ALU_SUB) || (alu_op == ALU_SLT) || (alu_op == ALU_SLTU);
  wire [31:0] b_inv = sub ? ~b : b;
  wire [32:0] sum33 = {1'b0, a} + {1'b0, b_inv} + {32'b0, sub};
  wire [31:0] addsub = sum33[31:0];
  wire        carry  = sum33[32];

  wire ovf  = (a[31] != b[31]) && (addsub[31] != a[31]);
  wire slt  = addsub[31] ^ ovf;
  wire sltu = ~carry;

  wire [4:0]  shamt = b[4:0];
  wire [31:0] shl   = a << shamt;
  wire [31:0] shr   = a >> shamt;
  wire [31:0] sar   = $signed(a) >>> shamt;

  reg [31:0] res;
  always @(*) begin
    case (alu_op)
      ALU_ADD : res = addsub;
      ALU_SUB : res = addsub;
      ALU_SLL : res = shl;
      ALU_SLT : res = {31'b0, slt};
      ALU_SLTU: res = {31'b0, sltu};
      ALU_XOR : res = a ^ b;
      ALU_SRL : res = shr;
      ALU_SRA : res = sar;
      ALU_OR  : res = a | b;
      ALU_AND : res = a & b;
      default : res = addsub;
    endcase
  end
  assign result = res;

  wire eq = (a == b);
  reg  taken;
  always @(*) begin
    case (funct3)
      3'b000: taken = eq;
      3'b001: taken = ~eq;
      3'b100: taken = slt;
      3'b101: taken = ~slt;
      3'b110: taken = sltu;
      3'b111: taken = ~sltu;
      default: taken = 1'b0;
    endcase
  end
  assign branch_taken = is_branch && taken;

endmodule
