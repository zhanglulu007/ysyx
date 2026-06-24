// MEM - Memory Module
// 模拟存储器，内部通过 DPI-C 实现访存，对外呈现 SimpleBus 接口
// 读延迟固定 1 周期（同步存储器/SRAM 特性）

module MEM(
  input clk,
  input rst,

  // IFU SimpleBus (只读)
  input  [31:0] ifu_raddr,
  output [31:0] ifu_rdata,

  // LSU SimpleBus (可读可写)
  input  [31:0] lsu_addr,
  input         lsu_wen,
  input  [31:0] lsu_wdata,
  input  [ 3:0] lsu_wmask,
  output [31:0] lsu_rdata
);

  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

  reg [31:0] ifu_rdata_reg;
  reg [31:0] lsu_rdata_reg;

  always @(posedge clk) begin
    if (rst) begin
      ifu_rdata_reg <= 32'b0;
      lsu_rdata_reg <= 32'b0;
    end else begin
      // IFU: 每周期发出读请求, 下周期数据返回
      ifu_rdata_reg <= pmem_read(ifu_raddr);

      // LSU: 读或写
      if (!lsu_wen) begin
        lsu_rdata_reg <= pmem_read(lsu_addr);
      end else begin
        pmem_write(lsu_addr, lsu_wdata, lsu_wmask);
        lsu_rdata_reg <= 32'b0;
      end
    end
  end

  assign ifu_rdata = ifu_rdata_reg;
  assign lsu_rdata = lsu_rdata_reg;

endmodule
