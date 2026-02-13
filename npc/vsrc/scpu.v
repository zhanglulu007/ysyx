module scpu(
    input wire clk,          // 时钟
    input wire rst,          // 复位
    output wire [6:0] seg0,  // 七段数码管 0 (显示高位)
    output wire [6:0] seg1   // 七段数码管 1 (显示低位)
);

    reg [3:0] pc_reg;
    wire [3:0] pc_next;
    assign pc_next = (opcode == 2'b11 && branch_taken) ? branch_addr : (pc_reg + 1'b1);

    reg [7:0] rom [0:15];  
    initial begin
        rom[0] = 8'h8A; 
        rom[1] = 8'h90; 
        rom[2] = 8'hA0; 
        rom[3] = 8'hB1; 
        rom[4] = 8'h17; 
        rom[5] = 8'h29; 
        rom[6] = 8'h42; // out r2
        rom[7] = 8'hD1; // bner0 4, r1
        rom[8] = 8'hE3; // bner0 8, r3
    end
    
    wire [7:0] ir; //IR指令寄存器
    assign ir = rom[pc_reg];

    // ---------------------------------------------------------
    // Decode (译码)
    // ---------------------------------------------------------
    wire [1:0] opcode;
    wire [1:0] rd;
    wire [1:0] rs1;
    wire [1:0] rs2;
    wire [3:0] imm;
    wire [3:0] branch_addr;
    
    assign opcode = ir[7:6];
    assign rd = ir[5:4];
    assign rs1 = ir[3:2];
    assign rs2 = ir[1:0];
    assign imm = ir[3:0];
    assign branch_addr = ir[5:2];

    // ---------------------------------------------------------
    // GPR
    // ---------------------------------------------------------
    reg [7:0] gpr [0:3];
    
    wire [7:0] rdata1;
    wire [7:0] rdata2;
    assign rdata1 = gpr[rs1];
    assign rdata2 = gpr[rs2];
    
    // 显示寄存器 (用于锁存要输出的值)
    reg [7:0] display_reg;

    wire [7:0] alu_result;
    wire [7:0] li_data;
    wire branch_taken;
    
    assign alu_result = rdata1 + rdata2;
    assign li_data = {4'b0000, imm};
    assign branch_taken = (gpr[0] != rdata2);

    function [6:0] hex_to_seg;
        input [3:0] hex;
        begin
            case (hex)
                4'h0: hex_to_seg = 7'b0000001; 
                4'h1: hex_to_seg = 7'b1001111; 
                4'h2: hex_to_seg = 7'b0010010; 
                4'h3: hex_to_seg = 7'b0000110; 
                4'h4: hex_to_seg = 7'b1001100; 
                4'h5: hex_to_seg = 7'b0100100; 
                4'h6: hex_to_seg = 7'b0100000; 
                4'h7: hex_to_seg = 7'b0001111; 
                4'h8: hex_to_seg = 7'b0000000; 
                4'h9: hex_to_seg = 7'b0000100; 
                4'hA: hex_to_seg = 7'b0001000; 
                4'hB: hex_to_seg = 7'b1100000; 
                4'hC: hex_to_seg = 7'b0110001; 
                4'hD: hex_to_seg = 7'b1000010; 
                4'hE: hex_to_seg = 7'b0110000; 
                4'hF: hex_to_seg = 7'b0111000;
                default: hex_to_seg = 7'b1111111;
            endcase
        end
    endfunction

    // 将 display_reg 的值分解为两个半字节进行译码
    assign seg1 = hex_to_seg(display_reg[7:4]); // 高位
    assign seg0 = hex_to_seg(display_reg[3:0]); // 低位

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_reg <= 4'd0;
            gpr = '{0, 0, 0, 0};
            display_reg <= 8'd0;
        end else begin
            pc_reg <= pc_next;
            case (opcode)
                2'b00: gpr[rd] <= alu_result;      // add
                2'b01: display_reg <= gpr[rs2];     // out rs (rs在rs2位置)
                2'b10: gpr[rd] <= li_data;         // li
                2'b11: ; //bner0 (无写回)
            endcase
        end
    end

endmodule