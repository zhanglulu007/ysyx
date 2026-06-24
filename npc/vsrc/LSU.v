// LSU - Load-Store Unit
// 访存单元：通过 SimpleBus 与 MEM 模块交互
// SimpleBus 协议: 读操作有 1 周期延迟

module LSU(
  input clk,
  input rst,

  // 控制信号
  input mem_valid,            // 访存有效
  input mem_wen,              // 写使能

  // 指令类型
  input [2:0] funct3,         // IDU 输出的 funct3, 用于区分 load/store 类型

  // 地址和数据
  input [31:0] mem_addr,      // 访存地址
  input [31:0] wdata,         // 写入数据（来自rs2）

  // ===== SimpleBus 接口 (连接 MEM 模块) =====
  output [31:0] lsu_addr,
  output        lsu_wen,
  output [31:0] lsu_wdata,
  output [ 3:0] lsu_wmask,
  input  [31:0] lsu_rdata,    // 来自 MEM, load 请求后 1 周期有效

  // ===== 输出 =====
  output [31:0] rdata,        // 字节/半字选择后的数据
  output lsu_busy             // LSU 忙碌信号
);

  wire [1:0] mem_offset;
  assign mem_offset = mem_addr[1:0];

  // ===== SimpleBus 信号到 MEM =====
  assign lsu_addr = mem_addr;
  assign lsu_wen  = mem_valid && mem_wen;

  // ===== 写数据和写掩码 (Store 操作, 组合逻辑) =====
  reg [31:0] lsu_wdata_comb;
  reg [ 3:0] lsu_wmask_comb;
  always @(*) begin
    case (funct3)
      3'b010: begin  // SW
        lsu_wdata_comb = wdata;
        lsu_wmask_comb = 4'b1111;
      end
      3'b001: begin  // SH
        case (mem_offset[1])
          1'b0: begin
            lsu_wdata_comb = wdata;
            lsu_wmask_comb = 4'b0011;
          end
          1'b1: begin
            lsu_wdata_comb = wdata << 16;
            lsu_wmask_comb = 4'b1100;
          end
        endcase
      end
      3'b000: begin  // SB
        case (mem_offset)
          2'b00: begin
            lsu_wdata_comb = wdata;
            lsu_wmask_comb = 4'b0001;
          end
          2'b01: begin
            lsu_wdata_comb = wdata << 8;
            lsu_wmask_comb = 4'b0010;
          end
          2'b10: begin
            lsu_wdata_comb = wdata << 16;
            lsu_wmask_comb = 4'b0100;
          end
          2'b11: begin
            lsu_wdata_comb = wdata << 24;
            lsu_wmask_comb = 4'b1000;
          end
        endcase
      end
      default: begin
        lsu_wdata_comb = wdata;
        lsu_wmask_comb = 4'b0000;
      end
    endcase
  end

  assign lsu_wdata = lsu_wdata_comb;
  assign lsu_wmask = lsu_wmask_comb;

  // ===== Load 类型保存 (WAIT 时保存, STALL 时使用) =====
  // 为什么需要保存?  STALL 周期 ifu_valid=0, IDU 解码的是 nop,
  // funct3 和 mem_offset 全为 0, 无法进行字节/半字选择.
  // 因此必须在 WAIT 周期 (load 被译码时) 保存这些信息.
  reg [2:0] saved_funct3;
  reg [1:0] saved_mem_offset;

  // ===== lsu_busy: load 请求后拉高 1 周期 =====
  reg lsu_busy_reg;
  assign lsu_busy = lsu_busy_reg;

  always @(posedge clk) begin
    if (rst) begin
      lsu_busy_reg     <= 1'b0;
      saved_funct3     <= 3'b0;
      saved_mem_offset <= 2'b0;
    end else begin
      if (mem_valid && !mem_wen) begin
        // Load: 保存类型信息供下一周期做字节/半字选择
        lsu_busy_reg     <= 1'b1;
        saved_funct3     <= funct3;
        saved_mem_offset <= mem_offset;
      end else begin
        lsu_busy_reg <= 1'b0;
      end
    end
  end

  // ===== 字节/半字选择 (组合逻辑, 使用保存的类型 + MEM 返回的数据) =====
  // lsu_rdata 在 load 请求的下一周期有效 (MEM 的读延迟为 1)
  // saved_funct3 / saved_mem_offset 正是上一周期保存的 load 类型
  reg [31:0] rdata_selected;
  always @(*) begin
    case (saved_funct3)
      3'b010: begin  // LW
        rdata_selected = lsu_rdata;
      end
      3'b001: begin  // LH
        case (saved_mem_offset[1])
          1'b0: rdata_selected = {{16{lsu_rdata[15]}}, lsu_rdata[15:0]};
          1'b1: rdata_selected = {{16{lsu_rdata[31]}}, lsu_rdata[31:16]};
        endcase
      end
      3'b101: begin  // LHU
        case (saved_mem_offset[1])
          1'b0: rdata_selected = {16'b0, lsu_rdata[15:0]};
          1'b1: rdata_selected = {16'b0, lsu_rdata[31:16]};
        endcase
      end
      3'b000: begin  // LB
        case (saved_mem_offset)
          2'b00: rdata_selected = {{24{lsu_rdata[7]}},  lsu_rdata[7:0]};
          2'b01: rdata_selected = {{24{lsu_rdata[15]}}, lsu_rdata[15:8]};
          2'b10: rdata_selected = {{24{lsu_rdata[23]}}, lsu_rdata[23:16]};
          2'b11: rdata_selected = {{24{lsu_rdata[31]}}, lsu_rdata[31:24]};
        endcase
      end
      3'b100: begin  // LBU
        case (saved_mem_offset)
          2'b00: rdata_selected = {24'b0, lsu_rdata[7:0]};
          2'b01: rdata_selected = {24'b0, lsu_rdata[15:8]};
          2'b10: rdata_selected = {24'b0, lsu_rdata[23:16]};
          2'b11: rdata_selected = {24'b0, lsu_rdata[31:24]};
        endcase
      end
      default: begin
        rdata_selected = 32'b0;
      end
    endcase
  end

  assign rdata = rdata_selected;

endmodule
