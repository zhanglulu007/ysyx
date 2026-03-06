module LSU(
  input clk,
  input rst,
  
  input mem_valid,            // 访存有效
  input mem_wen,              // 写使能
  input is_lw,                // 加载字
  input is_lbu,               // 加载无符号字节
  input is_sw,                // 存储字
  input is_sb,                // 存储字节
  
  input [31:0] mem_addr,      // 访存地址
  input [31:0] wdata,         // 写入数据（来自rs2）

  output [31:0] rdata         // 读出数据
);

  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);
  
  // 地址低2位，用于字节选择
  wire [1:0] mem_offset;
  assign mem_offset = mem_addr[1:0];
  
  // 读操作
  reg [31:0] mem_rdata_raw;
  always @(*) begin
    if (mem_valid && !mem_wen) begin
      mem_rdata_raw = pmem_read(mem_addr);
    end else begin
      mem_rdata_raw = 0;
    end
  end
  
  // 根据指令类型和地址偏移选择读取的数据
  reg [31:0] mem_rdata_selected;
  always @(*) begin
    if (is_lw) begin
      // LW：直接返回32位数据
      mem_rdata_selected = mem_rdata_raw;
    end else if (is_lbu) begin
      // LBU：根据地址低2位选择字节并零扩展
      case (mem_offset)
        2'b00: mem_rdata_selected = {24'b0, mem_rdata_raw[7:0]};
        2'b01: mem_rdata_selected = {24'b0, mem_rdata_raw[15:8]};
        2'b10: mem_rdata_selected = {24'b0, mem_rdata_raw[23:16]};
        2'b11: mem_rdata_selected = {24'b0, mem_rdata_raw[31:24]};
      endcase
    end else begin
      mem_rdata_selected = 0;
    end
  end
  
  assign rdata = mem_rdata_selected;
  
  // 写操作
  always @(posedge clk) begin
    if (!rst && mem_valid && mem_wen) begin
      if (is_sw) begin
        // SW：写入4字节，写掩码全1
        pmem_write(mem_addr, wdata, 8'hFF);
      end else if (is_sb) begin
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

endmodule
