module IFU(
  input clk,
  input rst,
  input commit,
  input [31:0] pc_next,

  output ifu_arvalid,
  input  ifu_arready,
  output [31:0] ifu_araddr,

  input  ifu_rvalid,
  output ifu_rready,
  input  [31:0] ifu_rdata,

  output reg [31:0] pc,
  output [31:0] inst,
  output ifu_valid,
  output ifu_pre_valid
);

  localparam IDLE = 2'b00, WAIT = 2'b01, EXEC = 2'b10;

  reg [1:0] state;
  reg [31:0] inst_q;

  assign ifu_arvalid = !rst && (state == IDLE);
  assign ifu_araddr  = pc;

  // Miss/bypass data is accepted in WAIT; stateless hit is consumed in IDLE.
  assign ifu_rready  = !rst && (state == WAIT);
  assign inst        = inst_q;
  assign ifu_valid   = !rst && (state == EXEC);

  // Pre-read strobe: the instruction word is available this cycle.
  assign ifu_pre_valid = !rst && ifu_rvalid &&
                         ((state == IDLE) || (state == WAIT));

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
`ifdef SOC_MODE
      pc <= 32'h30000000;
`else
      pc <= 32'h80000000;
`endif
      inst_q <= 32'h00000013;
    end else begin
      case (state)
        IDLE: begin
          if (ifu_rvalid) begin
            inst_q <= ifu_rdata;       // stateless hit
            state  <= EXEC;
          end else if (ifu_arvalid && ifu_arready) begin
            state  <= WAIT;
          end
        end

        WAIT: begin
          if (ifu_rvalid) begin
            inst_q <= ifu_rdata;
            state  <= EXEC;
          end
        end

        EXEC: begin
          if (commit) begin
            pc    <= pc_next;
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
