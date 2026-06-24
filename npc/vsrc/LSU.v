// LSU - Load-Store Unit
// 访存单元：负责存储器的读写操作
// SimpleBus 协议: 读操作有 1 周期延迟

module LSU(
  input clk,
  input rst,

  // 控制信号
  input mem_valid,            // 访存有效
  input mem_wen,              // 写使能

  // 加载指令
  input is_lb,                // 加载有符号字节
  input is_lh,                // 加载有符号半字
  input is_lw,                // 加载字
  input is_lbu,               // 加载无符号字节
  input is_lhu,               // 加载无符号半字

  // 存储指令
  input is_sb,                // 存储字节
  input is_sh,                // 存储半字
  input is_sw,                // 存储字

  // 地址和数据
  input [31:0] mem_addr,      // 访存地址
  input [31:0] wdata,         // 写入数据（来自rs2）

  // 输出
  output [31:0] rdata,        // 读出数据（已做字节/半字选择，load 请求后 1 周期有效）
  output lsu_busy             // LSU 忙碌信号（load 等待数据返回期间为 1）
);

  // DPI-C函数：存储器读写
  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

  // 地址低2位，用于字节/半字选择
  wire [1:0] mem_offset;
  assign mem_offset = mem_addr[1:0];

  // ========== SimpleBus 读操作（posedge, 1 周期延迟） ==========
  // 在 load 请求的 posedge: 保存 pmem_read 原始结果 + load 类型 + 地址偏移
  // 下一周期: 组合逻辑用保存的类型做字节/半字选择，输出正确的 rdata

  reg [31:0] lsu_rdata_raw;       // 寄存器化的原始读数据（posedge 采样）
  reg lsu_busy;                    // 忙碌标志

  // 保存的 load 类型和地址偏移（load 请求时保存，下一周期用于选择）
  reg        saved_is_lw;
  reg        saved_is_lh;
  reg        saved_is_lhu;
  reg        saved_is_lb;
  reg        saved_is_lbu;
  reg [1:0]  saved_mem_offset;

  always @(posedge clk) begin
    if (rst) begin
      lsu_rdata_raw    <= 32'b0;
      lsu_busy         <= 1'b0;
      saved_is_lw      <= 1'b0;
      saved_is_lh      <= 1'b0;
      saved_is_lhu     <= 1'b0;
      saved_is_lb      <= 1'b0;
      saved_is_lbu     <= 1'b0;
      saved_mem_offset <= 2'b0;
    end else begin
      // -------- Load 请求：寄存器化读结果 --------
      if (mem_valid && !mem_wen) begin
        // 发出读请求，结果下一周期可用
        lsu_rdata_raw <= pmem_read(mem_addr);
        lsu_busy      <= 1'b1;
        // 保存 load 类型，供下一周期组合逻辑做字节/半字选择
        saved_is_lw      <= is_lw;
        saved_is_lh      <= is_lh;
        saved_is_lhu     <= is_lhu;
        saved_is_lb      <= is_lb;
        saved_is_lbu     <= is_lbu;
        saved_mem_offset <= mem_offset;
      end else begin
        lsu_busy <= 1'b0;
      end

      // -------- Store 写入（立即完成） --------
      if (mem_valid && mem_wen) begin
        if (is_sw) begin
          // SW：写入4字节，写掩码全1
          pmem_write(mem_addr, wdata, 8'hFF);
        end
        else if (is_sh) begin
          // SH：根据地址低1位写入2字节
          case (mem_offset[1])
            1'b0: pmem_write(mem_addr, wdata,          8'h03);  // 写入低半字
            1'b1: pmem_write(mem_addr, wdata << 16,    8'h0C);  // 写入高半字
          endcase
        end
        else if (is_sb) begin
          // SB：根据地址低2位写入1字节
          case (mem_offset)
            2'b00: pmem_write(mem_addr, wdata,          8'h01);
            2'b01: pmem_write(mem_addr, wdata << 8,     8'h02);
            2'b10: pmem_write(mem_addr, wdata << 16,    8'h04);
            2'b11: pmem_write(mem_addr, wdata << 24,    8'h08);
          endcase
        end
        lsu_busy <= 1'b0;
      end
    end
  end

  // ========== 组合逻辑：字节/半字选择 ==========
  // 使用上一周期保存的 load 类型 + 本周期刚寄存器化的原始数据
  // 在 load 请求的下一周期（STALL），输出正确结果供延迟写回
  reg [31:0] rdata_selected;
  always @(*) begin
    if (saved_is_lw) begin
      // LW：直接返回32位数据
      rdata_selected = lsu_rdata_raw;
    end
    else if (saved_is_lh) begin
      // LH：根据保存的地址低1位选择半字并符号扩展
      case (saved_mem_offset[1])
        1'b0: rdata_selected = {{16{lsu_rdata_raw[15]}}, lsu_rdata_raw[15:0]};
        1'b1: rdata_selected = {{16{lsu_rdata_raw[31]}}, lsu_rdata_raw[31:16]};
      endcase
    end
    else if (saved_is_lhu) begin
      // LHU：根据保存的地址低1位选择半字并零扩展
      case (saved_mem_offset[1])
        1'b0: rdata_selected = {16'b0, lsu_rdata_raw[15:0]};
        1'b1: rdata_selected = {16'b0, lsu_rdata_raw[31:16]};
      endcase
    end
    else if (saved_is_lb) begin
      // LB：根据保存的地址低2位选择字节并符号扩展
      case (saved_mem_offset)
        2'b00: rdata_selected = {{24{lsu_rdata_raw[7]}},  lsu_rdata_raw[7:0]};
        2'b01: rdata_selected = {{24{lsu_rdata_raw[15]}}, lsu_rdata_raw[15:8]};
        2'b10: rdata_selected = {{24{lsu_rdata_raw[23]}}, lsu_rdata_raw[23:16]};
        2'b11: rdata_selected = {{24{lsu_rdata_raw[31]}}, lsu_rdata_raw[31:24]};
      endcase
    end
    else if (saved_is_lbu) begin
      // LBU：根据保存的地址低2位选择字节并零扩展
      case (saved_mem_offset)
        2'b00: rdata_selected = {24'b0, lsu_rdata_raw[7:0]};
        2'b01: rdata_selected = {24'b0, lsu_rdata_raw[15:8]};
        2'b10: rdata_selected = {24'b0, lsu_rdata_raw[23:16]};
        2'b11: rdata_selected = {24'b0, lsu_rdata_raw[31:24]};
      endcase
    end
    else begin
      rdata_selected = 32'b0;
    end
  end

  assign rdata = rdata_selected;

endmodule
