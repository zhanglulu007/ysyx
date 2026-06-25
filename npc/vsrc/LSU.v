// LSU - Load-Store Unit
// 访存单元：通过 SimpleBus 与 MEM 模块交互
// SimpleBus 协议: 支持完整握手信号 reqValid/reqReady + respValid/respReady
// 内部状态机:
//   L_IDLE:      等待 IDU 发出访存请求 (mem_valid)
//   L_WAIT_REQ:  已锁存请求, 等待 reqReady 握手
//   L_WAIT_RESP: 请求已被接受, 等待 respValid, respReady=1

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
  input  lsu_reqReady,        // MEM -> LSU: 从设备就绪接收请求
  output [31:0] lsu_addr,
  output lsu_wen,
  output reg [31:0] lsu_wdata,
  output reg [ 3:0] lsu_wmask,
  input  lsu_respValid,       // MEM -> LSU: 响应有效
  output lsu_respReady,       // LSU -> MEM: 主设备就绪接收响应
  input  [31:0] lsu_rdata,    // MEM -> LSU: 返回的读数据

  // ===== 输出 =====
  output reg [31:0] rdata     // 字节/半字选择后的数据
);

  // ========== 状态机定义 ==========
  localparam L_IDLE      = 2'b00;  // 等待访存请求
  localparam L_WAIT_REQ  = 2'b01;  // 等待 reqReady 握手
  localparam L_WAIT_RESP = 2'b10;  // 等待 respValid, respReady=1

  reg [1:0] lsu_state;

  // ========== 锁存请求信号 (在 mem_valid 周期捕获) ==========
  reg [31:0] latched_addr;
  reg        latched_wen;
  reg [31:0] latched_wdata;
  reg [ 3:0] latched_wmask;

  // ========== 保存 load 类型信息 (用于响应周期的字节/半字选择) ==========
  reg [2:0] saved_funct3;
  reg [1:0] saved_mem_offset;

  wire [1:0] mem_offset;
  assign mem_offset = mem_addr[1:0];

  // ========== SimpleBus 输出信号 ==========
  // reqValid: IDLE 时直通 mem_valid, WAIT_REQ 时保持 1
  assign lsu_reqValid = (lsu_state == L_IDLE) ? (mem_valid && !rst) :
                        (lsu_state == L_WAIT_REQ) ? 1'b1 : 1'b0;

  // addr/wen/wdata/wmask: IDLE 时直通, WAIT_REQ 和 WAIT_RESP 时使用锁存值
  assign lsu_addr = (lsu_state == L_IDLE) ? mem_addr   : latched_addr;
  assign lsu_wen  = (lsu_state == L_IDLE) ? (mem_valid && mem_wen) : latched_wen;

  // respReady: WAIT_RESP 状态时就绪接收响应
  assign lsu_respReady = (lsu_state == L_WAIT_RESP);

  // ========== 写数据和写掩码 (组合逻辑) ==========
  // IDLE 时根据当前 funct3 生成, 其他状态使用锁存值
  wire [31:0] current_wdata;
  wire [ 3:0] current_wmask;

  // 当前周期的 wdata/wmask 计算 (用于 IDLE 直通或锁存)
  reg [31:0] computed_wdata;
  reg [ 3:0] computed_wmask;

  always @(*) begin
    case (funct3)
      3'b010: begin  // SW
        computed_wdata = wdata;
        computed_wmask = 4'b1111;
      end
      3'b001: begin  // SH
        case (mem_offset[1])
          1'b0: begin
            computed_wdata = wdata;
            computed_wmask = 4'b0011;
          end
          1'b1: begin
            computed_wdata = wdata << 16;
            computed_wmask = 4'b1100;
          end
        endcase
      end
      3'b000: begin  // SB
        case (mem_offset)
          2'b00: begin
            computed_wdata = wdata;
            computed_wmask = 4'b0001;
          end
          2'b01: begin
            computed_wdata = wdata << 8;
            computed_wmask = 4'b0010;
          end
          2'b10: begin
            computed_wdata = wdata << 16;
            computed_wmask = 4'b0100;
          end
          2'b11: begin
            computed_wdata = wdata << 24;
            computed_wmask = 4'b1000;
          end
        endcase
      end
      default: begin
        computed_wdata = wdata;
        computed_wmask = 4'b0000;
      end
    endcase
  end

  // 输出到 MEM 的最终 wdata/wmask
  always @(*) begin
    if (lsu_state == L_IDLE) begin
      lsu_wdata = computed_wdata;
      lsu_wmask = computed_wmask;
    end else begin
      lsu_wdata = latched_wdata;
      lsu_wmask = latched_wmask;
    end
  end

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      lsu_state        <= L_IDLE;
      saved_funct3     <= 3'b0;
      saved_mem_offset <= 2'b0;
      latched_addr     <= 32'b0;
      latched_wen      <= 1'b0;
      latched_wdata    <= 32'b0;
      latched_wmask    <= 4'b0;
    end else begin
      case (lsu_state)
        L_IDLE: begin
          if (mem_valid) begin
            // 锁存所有请求信息
            latched_addr     <= mem_addr;
            latched_wen      <= mem_wen;
            latched_wdata    <= computed_wdata;
            latched_wmask    <= computed_wmask;

            // 保存 load 类型信息供响应周期使用
            if (!mem_wen) begin
              saved_funct3     <= funct3;
              saved_mem_offset <= mem_offset;
            end

            // 根据 reqReady 决定下一状态
            if (lsu_reqReady) begin
              // 握手立即成功, 直接进入等待响应
              lsu_state <= L_WAIT_RESP;
            end else begin
              // 需要等待 reqReady
              lsu_state <= L_WAIT_REQ;
            end
          end
        end

        L_WAIT_REQ: begin
          // 保持 reqValid=1, 等待 reqReady 握手
          if (lsu_reqReady) begin
            lsu_state <= L_WAIT_RESP;
          end
        end

        L_WAIT_RESP: begin
          // respReady=1, 等待 respValid 握手
          if (lsu_respValid) begin
            // 握手完成: respValid && respReady
            lsu_state <= L_IDLE;
          end
        end

        default: lsu_state <= L_IDLE;
      endcase
    end
  end

  // ========== 字节/半字选择 (组合逻辑) ==========
  // 使用保存的 load 类型 + MEM 返回的数据
  always @(*) begin
    case (saved_funct3)
      3'b010: begin  // LW
        rdata = lsu_rdata;
      end
      3'b001: begin  // LH
        case (saved_mem_offset[1])
          1'b0: rdata = {{16{lsu_rdata[15]}}, lsu_rdata[15:0]};
          1'b1: rdata = {{16{lsu_rdata[31]}}, lsu_rdata[31:16]};
        endcase
      end
      3'b101: begin  // LHU
        case (saved_mem_offset[1])
          1'b0: rdata = {16'b0, lsu_rdata[15:0]};
          1'b1: rdata = {16'b0, lsu_rdata[31:16]};
        endcase
      end
      3'b000: begin  // LB
        case (saved_mem_offset)
          2'b00: rdata = {{24{lsu_rdata[7]}},  lsu_rdata[7:0]};
          2'b01: rdata = {{24{lsu_rdata[15]}}, lsu_rdata[15:8]};
          2'b10: rdata = {{24{lsu_rdata[23]}}, lsu_rdata[23:16]};
          2'b11: rdata = {{24{lsu_rdata[31]}}, lsu_rdata[31:24]};
        endcase
      end
      3'b100: begin  // LBU
        case (saved_mem_offset)
          2'b00: rdata = {24'b0, lsu_rdata[7:0]};
          2'b01: rdata = {24'b0, lsu_rdata[15:8]};
          2'b10: rdata = {24'b0, lsu_rdata[23:16]};
          2'b11: rdata = {24'b0, lsu_rdata[31:24]};
        endcase
      end
      default: begin
        rdata = 32'b0;
      end
    endcase
  end

endmodule
