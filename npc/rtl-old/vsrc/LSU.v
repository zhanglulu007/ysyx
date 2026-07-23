// LSU - Load-Store Unit
// 访存单元：负责存储器的读写操作

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
  output [31:0] rdata         // 读出数据
);

`ifndef SYNTHESIS
  // DPI-C函数：存储器读写
  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);
`endif
  
  // 地址低2位，用于字节/半字选择
  wire [1:0] mem_offset;
  assign mem_offset = mem_addr[1:0];
  
  // ========== 读操作 ==========
  reg [31:0] mem_rdata_raw;
  always @(*) begin
`ifdef SYNTHESIS
    mem_rdata_raw = 32'b0;
`else
    if (mem_valid && !mem_wen) begin
      mem_rdata_raw = pmem_read(mem_addr);
    end else begin
      mem_rdata_raw = 0;
    end
`endif
  end
  
  // 根据指令类型和地址偏移选择读取的数据
  reg [31:0] mem_rdata_selected;
  always @(*) begin
    if (is_lw) begin
      // LW：直接返回32位数据
      mem_rdata_selected = mem_rdata_raw;
    end 
    else if (is_lh) begin
      // LH：根据地址低1位选择半字并符号扩展
      case (mem_offset[1])
        1'b0: mem_rdata_selected = {{16{mem_rdata_raw[15]}}, mem_rdata_raw[15:0]};
        1'b1: mem_rdata_selected = {{16{mem_rdata_raw[31]}}, mem_rdata_raw[31:16]};
      endcase
    end
    else if (is_lhu) begin
      // LHU：根据地址低1位选择半字并零扩展
      case (mem_offset[1])
        1'b0: mem_rdata_selected = {16'b0, mem_rdata_raw[15:0]};
        1'b1: mem_rdata_selected = {16'b0, mem_rdata_raw[31:16]};
      endcase
    end
    else if (is_lb) begin
      // LB：根据地址低2位选择字节并符号扩展
      case (mem_offset)
        2'b00: mem_rdata_selected = {{24{mem_rdata_raw[7]}},  mem_rdata_raw[7:0]};
        2'b01: mem_rdata_selected = {{24{mem_rdata_raw[15]}}, mem_rdata_raw[15:8]};
        2'b10: mem_rdata_selected = {{24{mem_rdata_raw[23]}}, mem_rdata_raw[23:16]};
        2'b11: mem_rdata_selected = {{24{mem_rdata_raw[31]}}, mem_rdata_raw[31:24]};
      endcase
    end
    else if (is_lbu) begin
      // LBU：根据地址低2位选择字节并零扩展
      case (mem_offset)
        2'b00: mem_rdata_selected = {24'b0, mem_rdata_raw[7:0]};
        2'b01: mem_rdata_selected = {24'b0, mem_rdata_raw[15:8]};
        2'b10: mem_rdata_selected = {24'b0, mem_rdata_raw[23:16]};
        2'b11: mem_rdata_selected = {24'b0, mem_rdata_raw[31:24]};
      endcase
    end 
    else begin
      mem_rdata_selected = 0;
    end
  end
  
  assign rdata = mem_rdata_selected;
  
  // ========== 写操作 ==========
`ifndef SYNTHESIS
  always @(posedge clk) begin
    if (!rst && mem_valid && mem_wen) begin
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
    end
  end
`endif

endmodule
