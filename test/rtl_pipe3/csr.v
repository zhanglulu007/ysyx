// ============================================================================
//  CSR - 机器模式 CSR (最小集合: mstatus/mtvec/mepc/mcause/mcycle/mcycleh)
// ============================================================================
module CSR(
  input  clk,
  input  rst,

  input  [11:0] csr_raddr,
  input  [11:0] csr_waddr,
  input  [31:0] csr_wdata,
  input         csr_wen,
  output reg [31:0] csr_rdata,

  input         ecall_commit,
  input  [31:0] pc,

  output [31:0] mepc,
  output [31:0] mtvec,
  output [31:0] mstatus_out,
  output [31:0] mcause_out,
  output [31:0] mcycle_lo_out,
  output [31:0] mcycle_hi_out
);

  reg [31:0] mstatus;
  reg [31:0] mtvec_r;
  reg [31:0] mepc_r;
  reg [31:0] mcause;
  reg [63:0] mcycle;

  always @(*) begin
    case (csr_raddr)
      12'h300: csr_rdata = mstatus;
      12'h305: csr_rdata = mtvec_r;
      12'h341: csr_rdata = mepc_r;
      12'h342: csr_rdata = mcause;
      12'hb00: csr_rdata = mcycle[31:0];
      12'hb80: csr_rdata = mcycle[63:32];
      default: csr_rdata = 32'b0;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      mstatus <= 32'h0000_1800;
      mtvec_r <= 32'b0;
      mepc_r  <= 32'b0;
      mcause  <= 32'b0;
      mcycle  <= 64'b0;
    end else begin
      mcycle <= mcycle + 64'd1;

      if (ecall_commit) begin
        mepc_r <= pc;
        mcause <= 32'd11;           // ecall from M-mode
      end else if (csr_wen) begin
        case (csr_waddr)
          12'h300: mstatus <= csr_wdata;
          12'h305: mtvec_r <= csr_wdata;
          12'h341: mepc_r  <= csr_wdata;
          12'h342: mcause  <= csr_wdata;
          default: ;
        endcase
      end
    end
  end

  assign mepc          = mepc_r;
  assign mtvec         = mtvec_r;
  assign mstatus_out   = mstatus;
  assign mcause_out    = mcause;
  assign mcycle_lo_out = mcycle[31:0];
  assign mcycle_hi_out = mcycle[63:32];

endmodule
