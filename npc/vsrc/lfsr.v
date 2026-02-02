module lfsr(
    input  wire       clk,          // 系统时钟 (由 NVBoard 模拟器提供)
    input  wire       rst_n,        // 复位信号 (对应 KEY0)
    input  wire       btn_step,     // 步进按钮 (对应 KEY1)
    output wire [6:0] hex0,         // 数码管 HEX0
    output wire [6:0] hex1          // 数码管 HEX1
);

    //==================================================
    // 1. 按键边沿检测 (NVBoard 环境下无需长延时去抖)
    //==================================================
    // 在 NVBoard 中，按钮点击是理想的电平跳变，不需要等待 20ms。
    // 这里使用简单的两级寄存器检测下降沿（按下动作）。
    
    reg btn_d0, btn_d1;
    wire btn_pulse; // 按下产生的单周期脉冲

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_d0 <= 1'b1;
            btn_d1 <= 1'b1;
        end else begin
            btn_d0 <= btn_step;
            btn_d1 <= btn_d0;
        end
    end

    // 检测下降沿 (1 -> 0)
    assign btn_pulse = btn_d1 & (~btn_d0);

    //==================================================
    // 2. LFSR 逻辑
    //==================================================
    reg [7:0] lfsr_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_reg <= 8'b0000_0001; // 初始种子
        end else if (btn_pulse) begin
            // 特殊全零处理
            if (lfsr_reg == 8'b0000_0000) begin
                lfsr_reg <= 8'b0000_0001;
            end else begin
                // 多项式: x^8 + x^4 + x^3 + x^2 + 1
                // 抽头: bit 0, bit 2, bit 3, bit 4
                logic feedback;
                feedback = lfsr_reg[0] ^ lfsr_reg[2] ^ lfsr_reg[3] ^ lfsr_reg[4];
                lfsr_reg <= {feedback, lfsr_reg[7:1]};
            end
        end
    end

    //==================================================
    // 3. 数码管译码 (共阳极: 低电平点亮)
    //==================================================
    function [6:0] seg7_decode;
        input [3:0] hex;
        begin
            case (hex)
                4'h0: seg7_decode = 7'b1000000; 
                4'h1: seg7_decode = 7'b1111001; 
                4'h2: seg7_decode = 7'b0100100; 
                4'h3: seg7_decode = 7'b0110000; 
                4'h4: seg7_decode = 7'b0011001; 
                4'h5: seg7_decode = 7'b0010010; 
                4'h6: seg7_decode = 7'b0000010; 
                4'h7: seg7_decode = 7'b1111000; 
                4'h8: seg7_decode = 7'b0000000; 
                4'h9: seg7_decode = 7'b0010000; 
                4'hA: seg7_decode = 7'b0001000; 
                4'hB: seg7_decode = 7'b0000011; 
                4'hC: seg7_decode = 7'b1000110; 
                4'hD: seg7_decode = 7'b0100001; 
                4'hE: seg7_decode = 7'b0000110; 
                4'hF: seg7_decode = 7'b0001110; 
                default: seg7_decode = 7'b1111111;
            endcase
        end
    endfunction

    assign hex0 = seg7_decode(lfsr_reg[3:0]);
    assign hex1 = seg7_decode(lfsr_reg[7:4]);

endmodule
