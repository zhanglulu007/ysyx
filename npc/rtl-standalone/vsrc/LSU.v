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

  input [31:0] mem_rdata,            
  
  input [31:0] addr,   
  input [31:0] wdata,       

  output [31:0] mem_addr,
  output reg [31:0] mem_wdata,
  output reg [7:0] mem_wmask,

  output reg [31:0] rdata        
);
  
  always @(*) begin

    case (1'b1)

      // LHU：根据地址低1位选择半字并零扩展
      is_lhu: begin
      case (addr[1])
        1'b0: rdata = {16'b0, mem_rdata[15:0]};
        1'b1: rdata = {16'b0, mem_rdata[31:16]};
      endcase
    end

      // LBU：根据地址低2位选择字节并零扩展
      is_lbu: begin
      case (addr[1:0])
        2'b00: rdata = {24'b0, mem_rdata[7:0]};
        2'b01: rdata = {24'b0, mem_rdata[15:8]};
        2'b10: rdata = {24'b0, mem_rdata[23:16]};
        2'b11: rdata = {24'b0, mem_rdata[31:24]};
      endcase
    end

      is_lw: rdata = mem_rdata; // LW

      is_lh:begin
      // LH：根据地址低1位选择半字并符号扩展
      case (addr[1])
        1'b0: rdata = {{16{mem_rdata[15]}}, mem_rdata[15:0]};
        1'b1: rdata = {{16{mem_rdata[31]}}, mem_rdata[31:16]};
      endcase
    end

      is_lb: begin
      // LB：根据地址低2位选择字节并符号扩展
      case (addr[1:0])
        2'b00: rdata = {{24{mem_rdata[7]}},  mem_rdata[7:0]};
        2'b01: rdata = {{24{mem_rdata[15]}}, mem_rdata[15:8]};
        2'b10: rdata = {{24{mem_rdata[23]}}, mem_rdata[23:16]};
        2'b11: rdata = {{24{mem_rdata[31]}}, mem_rdata[31:24]};
      endcase
    end

      default:  rdata = 32'b0;

    endcase
  end

  always @(*) begin

    case (1'b1)

        // SW：写入4字节，写掩码全1
      is_sw: begin
        mem_wmask = 8'b00001111;
        mem_wdata = wdata;
      end

        // SH：根据地址低1位写入2字节
      is_sh: begin
        case (addr[1])
          1'b0: begin
            mem_wmask = 8'b00000011;  // 写入低半字           
            mem_wdata = wdata;
          end
          1'b1: begin
            mem_wmask = 8'b00001100;  // 写入高半字
            mem_wdata = wdata << 16;
          end
        endcase
      end

        // SB：根据地址低2位写入1字节
      is_sb: begin
        case (addr[1:0])
          2'b00: begin
            mem_wmask = 8'b00000001;
            mem_wdata = wdata;
          end
          2'b01: begin
            mem_wmask = 8'b00000010;
            mem_wdata = wdata << 8;
          end
          2'b10: begin
            mem_wmask = 8'b00000100;
            mem_wdata = wdata << 16;
          end
          2'b11: begin
            mem_wmask = 8'b00001000;
            mem_wdata = wdata << 24;
          end
        endcase
      end

      default: begin
        mem_wmask = 8'b0;
        mem_wdata = 32'b0;
      end

    endcase
    
  end

  assign mem_addr = addr;

endmodule
