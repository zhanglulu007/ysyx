// IFU - Instruction Fetch Unit
// 取指单元：通过 AXI4-Lite 从 MEM 模块取指令 (通过仲裁器)
// 两状态状态机: IDLE (等待arready握手) / WAIT (等待rvalid握手/指令执行完成)

module IFU(
  input clk,
  input rst,
  input [31:0] pc_next,        // 下一个PC值 (来自WBU)
  input mem_valid,              // 访存有效 (load/store, 来自IDU)
  input mem_wen,                // 写使能 (store, 来自IDU)
  input [4:0] rd,              // 目的寄存器 (来自IDU)

  // ===== AXI4-Lite AR 通道 (读地址) =====
  input  ifu_arready,          
  output ifu_arvalid,          
  output [31:0] ifu_araddr,    

  // ===== AXI4-Lite R 通道 (读数据) =====
  input  ifu_rvalid,           
  output ifu_rready,           
  input  [31:0] ifu_rdata,     
  input  [ 1:0] ifu_rresp,     

  // ===== LSU 完成信号 (来自 MEM 的 R/B 通道) =====
  input  lsu_rvalid,           
  input  lsu_bvalid,           

  // ===== 输出 =====
  output reg [31:0] pc,        // 当前PC
  output [31:0] inst,          // -> IDU: 当前指令
  output ifu_valid,            // -> IDU: 指令有效 (译码/执行周期)
  output load_wb,              // -> top: load 写回触发
  output [4:0] load_rd,         // -> top: load 目的寄存器

  output reg insdone
);

  wire insdone_comb;
  assign insdone_comb = (state == WAIT) && (
    (!lsu_pending && ifu_rvalid && ifu_rready && !mem_valid) ||   // 非访存指令完成
    (lsu_pending && is_load_pending && lsu_rvalid) ||             // load 完成
    (lsu_pending && !is_load_pending && lsu_bvalid)               // store 完成
  );

  always @(posedge clk) begin
    if (rst)
        insdone <= 1'b0;
    else
        insdone <= insdone_comb;
  end

  localparam IDLE = 1'b0 , WAIT = 1'b1;

  reg state;
  reg lsu_pending;          // 1 = 在 WAIT 状态中等待 LSU 响应
  reg is_load_pending;      // 1 = 等待中的 LSU 操作是 load (需要写回)
  reg [4:0] load_rd_saved;  // load 指令的目的寄存器

  assign ifu_araddr = pc;
  assign ifu_arvalid = (state == IDLE) && !rst;
  assign ifu_rready = (state == WAIT) && !lsu_pending && !rst;
  assign ifu_valid = (state == WAIT) && ifu_rvalid && ifu_rready && !lsu_pending && !rst;
  assign inst = ifu_valid ? ifu_rdata : 32'h00000013;  // nop 
  assign load_wb = (state == WAIT) && lsu_pending && lsu_rvalid && is_load_pending;
  assign load_rd = load_rd_saved;

  always @(posedge clk) begin
    if (rst) begin
      state           <= IDLE;
      lsu_pending     <= 1'b0;
      is_load_pending <= 1'b0;
      load_rd_saved   <= 5'b0;
      pc              <= 32'h80000000;
    end else begin
      case (state)
        IDLE: begin
          if (ifu_arready) begin
            state       <= WAIT;
            lsu_pending <= 1'b0;
          end
        end

        WAIT: begin
          if (lsu_pending) begin
            if (lsu_rvalid || lsu_bvalid) begin
                pc               <= pc_next;
                state            <= IDLE;
                lsu_pending      <= 1'b0;
                is_load_pending  <= 1'b0;
            end
          end else if (ifu_rvalid && ifu_rready) begin
            if (mem_valid) begin
              // Load 或 Store: 需要等待 LSU 完成
              lsu_pending     <= 1'b1;
              is_load_pending <= !mem_wen;  // mem_wen=0 -> load, mem_wen=1 -> store
              load_rd_saved   <= rd;
            end else begin
              // 非访存指令: 本周期完成执行, 写回寄存器 (由 top.v 处理)
              pc               <= pc_next;
              state            <= IDLE;
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
