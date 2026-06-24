// IFU - Instruction Fetch Unit
// 取指单元：负责根据PC从存储器中取出指令
// SimpleBus 协议: 取指有 1 周期延迟, load 指令额外 stall 1 周期

module IFU(
  input clk,
  input rst,
  input idu_ready,
  input mem_valid,            // 访存有效（来自 IDU）
  input mem_wen,              // 写使能（来自 IDU，用于区分 load/store）
  input [31:0] pc_next,      // 下一个PC值
  output reg [31:0] pc,      // 当前PC
  output [31:0] inst,        // 取出的指令
  output ifu_valid           // 取指有效信号
);

  // DPI-C函数：从存储器读取指令
  import "DPI-C" function int pmem_read(input int raddr);
  // DPI-C函数：通知C++侧PC更新
  import "DPI-C" function void update_pc_value(input int pc_val);
  // DPI-C函数：同步指令到C++侧（trace/difftest用）
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);

  // 三状态状态机:
  //   IDLE  - 发送取指地址 (ifu_raddr = pc), 等待 1 周期
  //   WAIT  - 指令有效, 译码并执行
  //   STALL - load 指令等待 LSU 返回数据
  localparam IDLE  = 2'b00;
  localparam WAIT  = 2'b01;
  localparam STALL = 2'b10;

  reg [1:0] state;
  reg [31:0] ifu_rdata;        // 寄存器化的取指结果

  always @(posedge clk) begin
    if (rst) begin
        state       <= IDLE;
        pc          <= 32'h80000000;
        ifu_rdata   <= 32'h00000013;  // nop
        update_pc_value(32'h80000000);
    end else begin
        case (state)
            IDLE: begin
                // 发送读请求: ifu_raddr = pc
                // 寄存读到 pmem_read 的结果, 下一周期(WAIT)可用
                ifu_rdata <= pmem_read(pc);
                // PC 在 IDLE 时不更新 (没有有效指令执行)
                state <= WAIT;
            end

            WAIT: begin
                // ifu_rdata 是有效的指令
                // 同步到 C++ 侧 (trace / difftest)
                update_inst_value(pc, ifu_rdata);

                if (idu_ready) begin
                    if (mem_valid && !mem_wen) begin
                        // ===== Load 指令: 需要等待 LSU 返回数据 =====
                        state <= STALL;
                    end else begin
                        // ===== 非 Load 指令 (ALU/Store/Branch/...): 正常推进 =====
                        pc <= pc_next;
                        update_pc_value(pc_next);
                        ifu_rdata <= pmem_read(pc_next);
                        state <= IDLE;
                    end
                end 
                // idu_ready == 0 时保持 WAIT (流水线互锁)
            end

            STALL: begin
              // Load 数据已就绪，推进到下一条指令
              pc <= pc_next;
              update_pc_value(pc_next);
              ifu_rdata <= pmem_read(pc_next);
              state <= IDLE;
            end


            default: state <= IDLE;
        endcase
    end
  end

  // 取指：仅在 WAIT 状态输出真实指令, 其余时间输出 nop
  assign inst = (state == WAIT) ? ifu_rdata : 32'h00000013;  // nop = addi x0, x0, 0
  assign ifu_valid = (state == WAIT) && !rst;

endmodule
