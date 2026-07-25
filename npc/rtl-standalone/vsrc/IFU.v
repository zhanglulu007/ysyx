module IFU(
  input clk,
  input rst,
  input commit,
  input [31:0] pc_next,

  // AXI4 AR 
  output ifu_arvalid,
  input ifu_arready,
  output [31:0] ifu_araddr,
  output [3:0] ifu_arid,
  output [7:0] ifu_arlen,
  output [2:0] ifu_arsize,
  output [1:0] ifu_arburst,

  // AXI4 R 
  input ifu_rvalid,
  output ifu_rready,
  input [1:0] ifu_rresp,
  input [31:0] ifu_rdata,
  input ifu_rlast,
  input [3:0] ifu_rid,

  output reg [31:0] pc,
  output [31:0] inst,
  output ifu_valid
);

  localparam IDLE = 1'b0, WAIT = 1'b1;

  reg state;
  reg [31:0] inst_reg;
  reg inst_valid;

  assign ifu_arvalid = !rst && (state == IDLE);
  assign ifu_araddr = pc;
  assign ifu_arid = 4'b0001;
  assign ifu_arlen = 8'b0;
  assign ifu_arsize = 3'b010;
  assign ifu_arburst = 2'b01;

  assign ifu_rready = !rst && (state == WAIT) && !inst_valid;
  assign inst = (ifu_rvalid && ifu_rready) ? ifu_rdata : inst_reg;
  assign ifu_valid = !rst && (inst_valid || (ifu_rvalid && ifu_rready && ifu_rlast));

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      pc <= 32'h80000000;
      inst_reg <= 32'h00000013;
      inst_valid <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          if (ifu_arvalid && ifu_arready) begin
            state <= WAIT;
          end
        end
        WAIT: begin
          if (ifu_rvalid && ifu_rready && ifu_rlast) begin
            inst_reg <= ifu_rdata;
            inst_valid <= 1'b1;
          end
          if (commit) begin
            pc <= pc_next;
            state <= IDLE;
            inst_valid <= 1'b0;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end

endmodule
