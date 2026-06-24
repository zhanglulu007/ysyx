// LSU - Load-Store Unit
// 访存单元：通过 SimpleBus 与 MEM 模块交互
// SimpleBus 协议: 支持有效信号 reqValid/respValid
// 无内部流水线状态, 仅在 load 时保存 funct3/mem_offset 用于字节选择

module LSU(
  input clk,
  input rst,

  // 控制信号
  input mem_valid,            // 访存有效 (来自 IDU)
  input mem_wen,              // 写使能 (来自 IDU)

  // 指令类型
  input [2:0] funct3,         // IDU 输出的 funct3

  // 地址和数据
  input [31:0] mem_addr,      // 访存地址
  input [31:0] wdata,         // 写入数据（来自rs2）

  // ===== SimpleBus 接口 (连接 MEM 模块) =====
  output lsu_reqValid,
  output [31:0] lsu_addr,
  output lsu_wen,
  output [31:0] lsu_wdata,
  output [ 3:0] lsu_wmask,
  input  lsu_respValid,       // MEM 返回的有效信号
  input  [31:0] lsu_rdata,    // MEM 返回的读数据

  // ===== 输出 =====
  output [31:0] rdata         // 字节/半字选择后的数据
);

  wire [1:0] mem_offset;
  assign mem_offset = mem_addr[1:0];

  // ===== SimpleBus 信号到 MEM (组合逻辑) =====
  assign lsu_reqValid = mem_valid;   // 访存请求有效 = IDU 发出的访存有效
  assign lsu_addr     = mem_addr;
  assign lsu_wen      = mem_valid && mem_wen;

  // ===== 写数据和写掩码 (组合逻辑) =====
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

  // ===== 保存 load 类型信息 (用于 LSU 响应周期的字节/半字选择) =====
  // 当 load 指令被译码时 (mem_valid=1, mem_wen=0), 保存 funct3 和 mem_offset.
  // 在下一周期 LSU 响应到达时, inst 已变为 NOP, 需要这些保存的信息来选择字节.
  reg [2:0] saved_funct3;
  reg [1:0] saved_mem_offset;

  always @(posedge clk) begin
    if (rst) begin
      saved_funct3     <= 3'b0;
      saved_mem_offset <= 2'b0;
    end else if (mem_valid && !mem_wen) begin
      // Load: 保存类型信息供下一周期做字节/半字选择
      saved_funct3     <= funct3;
      saved_mem_offset <= mem_offset;
    end
  end

  // ===== 字节/半字选择 (组合逻辑) =====
  // 使用保存的 load 类型 + MEM 返回的数据
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
