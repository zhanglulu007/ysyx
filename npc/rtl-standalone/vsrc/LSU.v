module LSU(
  input clk,
  input rst,

  input mem_valid,
  input mem_wen,

  input is_lb,
  input is_lh,
  input is_lw,
  input is_lbu,
  input is_lhu,

  input is_sb,
  input is_sh,
  input is_sw,

  // AXI4 AR
  output lsu_arvalid,
  input lsu_arready,
  output [31:0] lsu_araddr,
  output [3:0] lsu_arid,
  output [7:0] lsu_arlen,
  output reg [2:0] lsu_arsize,
  output [1:0] lsu_arburst,

  // AXI4 R
  input lsu_rvalid,
  output lsu_rready,
  input [1:0] lsu_rresp,
  input [31:0] lsu_rdata,
  input lsu_rlast,
  input [3:0] lsu_rid,

  // AXI4 AW
  output lsu_awvalid,
  input lsu_awready,
  output [31:0] lsu_awaddr,
  output [3:0] lsu_awid,
  output [7:0] lsu_awlen,
  output reg [2:0] lsu_awsize,
  output [1:0] lsu_awburst,

  // AXI4 W
  output lsu_wvalid,
  input lsu_wready,
  output [31:0] lsu_wdata,
  output [3:0] lsu_wstrb,
  output lsu_wlast,

  // AXI4 B
  input lsu_bvalid,
  output lsu_bready,
  input [1:0] lsu_bresp,
  input [3:0] lsu_bid,

  input [31:0] addr,
  input [31:0] wdata,

  output reg [31:0] rdata,
  output lsu_done
);

  assign lsu_arvalid = mem_valid && !mem_wen && !lsu_rvalid;
  assign lsu_araddr = addr;
  assign lsu_arid = 4'b0010;
  assign lsu_arlen = 8'b0;
  assign lsu_arburst = 2'b01;
  
  assign lsu_rready = mem_valid && !mem_wen;

  assign lsu_awvalid = mem_valid && mem_wen;
  assign lsu_awaddr = addr;
  assign lsu_awid = 4'b0010;
  assign lsu_awlen = 8'b0;
  assign lsu_awburst = 2'b01;

  assign lsu_wvalid = mem_valid && mem_wen;
  assign lsu_wlast = lsu_wvalid;

  assign lsu_bready = mem_valid && mem_wen;


  assign lsu_done = !rst && mem_valid &&
                    ((!mem_wen && lsu_rvalid && lsu_rready && lsu_rlast) ||
                     (mem_wen && lsu_bvalid && lsu_bready));

  always @(*) begin

    case (1'b1)

      // LHU：根据地址低1位选择半字并零扩展
      is_lhu: begin
      case (addr[1])
        1'b0: rdata = {16'b0, lsu_rdata[15:0]};
        1'b1: rdata = {16'b0, lsu_rdata[31:16]};
      endcase
      lsu_arsize = 3'b001;
      lsu_awsize = 3'b001;
    end

      // LBU：根据地址低2位选择字节并零扩展
      is_lbu: begin
      case (addr[1:0])
        2'b00: rdata = {24'b0, lsu_rdata[7:0]};
        2'b01: rdata = {24'b0, lsu_rdata[15:8]};
        2'b10: rdata = {24'b0, lsu_rdata[23:16]};
        2'b11: rdata = {24'b0, lsu_rdata[31:24]};
      endcase
      lsu_arsize = 3'b000;
      lsu_awsize = 3'b000;
    end

      is_lw: begin 
        rdata = lsu_rdata; // LW
        lsu_arsize = 3'b010;
        lsu_awsize = 3'b010;
      end

      is_lh:begin
      // LH：根据地址低1位选择半字并符号扩展
      case (addr[1])
        1'b0: rdata = {{16{lsu_rdata[15]}}, lsu_rdata[15:0]};
        1'b1: rdata = {{16{lsu_rdata[31]}}, lsu_rdata[31:16]};
      endcase
      lsu_arsize = 3'b001;
      lsu_awsize = 3'b001;
    end

      is_lb: begin
      // LB：根据地址低2位选择字节并符号扩展
      case (addr[1:0])
        2'b00: rdata = {{24{lsu_rdata[7]}},  lsu_rdata[7:0]};
        2'b01: rdata = {{24{lsu_rdata[15]}}, lsu_rdata[15:8]};
        2'b10: rdata = {{24{lsu_rdata[23]}}, lsu_rdata[23:16]};
        2'b11: rdata = {{24{lsu_rdata[31]}}, lsu_rdata[31:24]};
      endcase
      lsu_arsize = 3'b000;
      lsu_awsize = 3'b000;
    end

      default:  rdata = 32'b0;

    endcase
  end

  always @(*) begin

    case (1'b1)

        // SW：写入4字节，写掩码全1
      is_sw: begin
        lsu_wstrb = 4'b1111;
        lsu_wdata = wdata;
        lsu_arsize = 3'b010;
        lsu_awsize = 3'b010;
      end

        // SH：根据地址低1位写入2字节
      is_sh: begin
        case (addr[1])
          1'b0: begin
            lsu_wstrb = 4'b0011;  // 写入低半字
            lsu_wdata = wdata;
          end
          1'b1: begin
            lsu_wstrb = 4'b1100;  // 写入高半字
            lsu_wdata = wdata << 16;
          end
        endcase
        lsu_arsize = 3'b001;
        lsu_awsize = 3'b001;
      end

        // SB：根据地址低2位写入1字节
      is_sb: begin
        case (addr[1:0])
          2'b00: begin
            lsu_wstrb = 4'b0001;
            lsu_wdata = wdata;
          end
          2'b01: begin
            lsu_wstrb = 4'b0010;
            lsu_wdata = wdata << 8;
          end
          2'b10: begin
            lsu_wstrb = 4'b0100;
            lsu_wdata = wdata << 16;
          end
          2'b11: begin
            lsu_wstrb = 4'b1000;
            lsu_wdata = wdata << 24;
          end
        endcase
        lsu_arsize = 3'b000;
        lsu_awsize = 3'b000;
      end

      default: begin
        lsu_wstrb = 4'b0;
        lsu_wdata = 32'b0;
      end

    endcase

  end

endmodule
