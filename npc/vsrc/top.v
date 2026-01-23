module top(
    input  [15:0] sw,     // NVBoard 会自动绑定 sw 到开关
    output [15:0] led,
    input         clk
);

    // 双控开关逻辑：当两个开关状态不同时，灯亮 (异或逻辑)
    // 我们使用 sw[0] 和 sw[1] 控制 led[0]
    assign led[0] = sw[0] ^ sw[1];

    // 其他 LED 关闭 
    assign led[15:1] = 15'h0;

endmodule
