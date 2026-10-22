module IFU(
  input clk,
  input rst,

  // IF/ID 握手：ready 表示 top 能接收当前指令
  input ifu_ready,
  // Stage B 正在执行控制指令时暂停取指，避免取到错误路径
  input fetch_hold,
  // 分支/trap 重定向
  input redirect,
  input [31:0] redirect_pc,

  output ifu_arvalid,
  input  ifu_arready,
  output [31:0] ifu_araddr,

  input  ifu_rvalid,
  output ifu_rready,
  input  [31:0] ifu_rdata,

  output reg [31:0] pc,
  output ifu_pre_valid
);

  localparam IDLE = 1'b0, WAIT = 1'b1;

  reg state;

  assign ifu_arvalid = !rst && (state == IDLE) && !fetch_hold;
  assign ifu_araddr  = pc;

  // 命中当拍返回；miss/bypass 在 WAIT 收数
  assign ifu_rready  = !rst && (state == WAIT) && ifu_ready;
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
    end else if (redirect) begin
      pc    <= redirect_pc;
      state <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          if (ifu_rvalid) begin
            // stateless hit：数据已在手边，等 top 接收后 PC 前进
            if (ifu_ready) begin
              pc <= pc + 32'd4;
            end
          end else if (ifu_arvalid && ifu_arready) begin
            state <= WAIT;
          end
        end

        WAIT: begin
          if (ifu_rvalid && ifu_ready) begin
            pc    <= pc + 32'd4;
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
