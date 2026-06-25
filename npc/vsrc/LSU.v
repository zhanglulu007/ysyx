// LSU - Load-Store Unit
// 访存单元：通过 AXI4-Lite 与 MEM 模块交互
//   L_IDLE:      等待 IDU 发出访存请求 (mem_valid)
//   L_WAIT_AR:   等待 arready 握手 (读地址)
//   L_WAIT_R:    等待 rvalid 握手 (读数据), rready=1
//   L_WAIT_AW_W: 等待 awready + wready 握手 (写地址+写数据)
//   L_WAIT_B:    等待 bvalid 握手 (写回复), bready=1

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

  // ===== AXI4-Lite AR 通道 (读地址) =====
  output        lsu_arvalid,
  input         lsu_arready,
  output [31:0] lsu_araddr,

  // ===== AXI4-Lite R 通道 (读数据) =====
  input         lsu_rvalid,
  output        lsu_rready,
  input  [31:0] lsu_rdata,
  input  [ 1:0] lsu_rresp,

  // ===== AXI4-Lite AW 通道 (写地址) =====
  output        lsu_awvalid,
  input         lsu_awready,
  output [31:0] lsu_awaddr,

  // ===== AXI4-Lite W 通道 (写数据) =====
  output        lsu_wvalid,
  input         lsu_wready,
  output reg [31:0] lsu_wdata,
  output reg [ 3:0] lsu_wstrb,

  // ===== AXI4-Lite B 通道 (写回复) =====
  input         lsu_bvalid,
  output        lsu_bready,
  input  [ 1:0] lsu_bresp,

  // ===== 输出 =====
  output reg [31:0] rdata     // 字节/半字选择后的数据
);

  // ========== 状态机定义 ==========
  localparam L_IDLE      = 3'b000;  // 等待访存请求
  localparam L_WAIT_AR   = 3'b001;  // 等待 arready 握手 (读)
  localparam L_WAIT_R    = 3'b010;  // 等待 rvalid 握手 (读)
  localparam L_WAIT_AW_W = 3'b011;  // 等待 awready + wready 握手 (写)
  localparam L_WAIT_B    = 3'b100;  // 等待 bvalid 握手 (写)

  reg [2:0] lsu_state;

  // ========== 锁存请求信号 (在 mem_valid 周期捕获) ==========
  reg [31:0] latched_addr;
  reg        latched_wen;
  reg [31:0] latched_wdata;
  reg [ 3:0] latched_wstrb;

  // ========== 保存 load 类型信息 (用于响应周期的字节/半字选择) ==========
  reg [2:0] saved_funct3;
  reg [1:0] saved_mem_offset;

  // ========== 写通道握手追踪 (AW 和 W 可独立完成) ==========
  reg aw_done;  // AW 握手已完成
  reg w_done;   // W  握手已完成

  wire [1:0] mem_offset;
  assign mem_offset = mem_addr[1:0];

  // ===================================================================
  // AXI4-Lite 输出信号
  // ===================================================================

  assign lsu_arvalid = (lsu_state == L_IDLE) ? (mem_valid && !mem_wen && !rst) :
                       (lsu_state == L_WAIT_AR) ? 1'b1 : 1'b0;

  assign lsu_araddr = (lsu_state == L_IDLE) ? mem_addr : latched_addr;

  assign lsu_rready = (lsu_state == L_WAIT_R);

  assign lsu_awvalid = (lsu_state == L_IDLE) ? (mem_valid && mem_wen && !rst) :
                       (lsu_state == L_WAIT_AW_W && !aw_done) ? 1'b1 : 1'b0;

  assign lsu_awaddr = (lsu_state == L_IDLE) ? mem_addr : latched_addr;

  assign lsu_wvalid = (lsu_state == L_IDLE) ? (mem_valid && mem_wen && !rst) :
                      (lsu_state == L_WAIT_AW_W && !w_done) ? 1'b1 : 1'b0;

  assign lsu_bready = (lsu_state == L_WAIT_B);

  // ===================================================================
  // 写数据和写掩码 (组合逻辑)
  // ===================================================================
  // IDLE 时根据当前 funct3 生成, 其他状态使用锁存值
  reg [31:0] computed_wdata;
  reg [ 3:0] computed_wstrb;

  always @(*) begin
    case (funct3)
      3'b010: begin  // SW
        computed_wdata = wdata;
        computed_wstrb = 4'b1111;
      end
      3'b001: begin  // SH
        case (mem_offset[1])
          1'b0: begin
            computed_wdata = wdata;
            computed_wstrb = 4'b0011;
          end
          1'b1: begin
            computed_wdata = wdata << 16;
            computed_wstrb = 4'b1100;
          end
        endcase
      end
      3'b000: begin  // SB
        case (mem_offset)
          2'b00: begin
            computed_wdata = wdata;
            computed_wstrb = 4'b0001;
          end
          2'b01: begin
            computed_wdata = wdata << 8;
            computed_wstrb = 4'b0010;
          end
          2'b10: begin
            computed_wdata = wdata << 16;
            computed_wstrb = 4'b0100;
          end
          2'b11: begin
            computed_wdata = wdata << 24;
            computed_wstrb = 4'b1000;
          end
        endcase
      end
      default: begin
        computed_wdata = wdata;
        computed_wstrb = 4'b0000;
      end
    endcase
  end

  // 输出到 MEM 的最终 wdata/wstrb
  always @(*) begin
    if (lsu_state == L_IDLE) begin
      lsu_wdata = computed_wdata;
      lsu_wstrb = computed_wstrb;
    end else begin
      lsu_wdata = latched_wdata;
      lsu_wstrb = latched_wstrb;
    end
  end

  // ===================================================================
  // 状态机
  // ===================================================================
  always @(posedge clk) begin
    if (rst) begin
      lsu_state        <= L_IDLE;
      saved_funct3     <= 3'b0;
      saved_mem_offset <= 2'b0;
      latched_addr     <= 32'b0;
      latched_wen      <= 1'b0;
      latched_wdata    <= 32'b0;
      latched_wstrb    <= 4'b0;
      aw_done          <= 1'b0;
      w_done           <= 1'b0;
    end else begin
      case (lsu_state)
        L_IDLE: begin
          if (mem_valid) begin
            // 锁存所有请求信息
            latched_addr  <= mem_addr;
            latched_wen   <= mem_wen;
            latched_wdata <= computed_wdata;
            latched_wstrb <= computed_wstrb;

            if (!mem_wen) begin
              // ===== 读操作 (AR → R) =====
              saved_funct3     <= funct3;
              saved_mem_offset <= mem_offset;

              if (lsu_arready) begin
                // AR 握手立即成功, 直接进入等待读数据
                lsu_state <= L_WAIT_R;
              end else begin
                // 需要等待 arready
                lsu_state <= L_WAIT_AR;
              end
            end else begin
              // ===== 写操作 (AW + W → B) =====
              aw_done <= 1'b0;
              w_done  <= 1'b0;

              // 检查 AW 和 W 是否在本周期握手成功
              if (lsu_awready && lsu_wready) begin
                // 两个通道同时握手成功, 直接进入等待写回复
                lsu_state <= L_WAIT_B;
              end else if (lsu_awready && !lsu_wready) begin
                // AW 握手成功, W 还需要等待
                aw_done   <= 1'b1;
                lsu_state <= L_WAIT_AW_W;
              end else if (!lsu_awready && lsu_wready) begin
                // W 握手成功, AW 还需要等待
                w_done    <= 1'b1;
                lsu_state <= L_WAIT_AW_W;
              end else begin
                // 两个通道都需要等待
                lsu_state <= L_WAIT_AW_W;
              end
            end
          end
        end

        L_WAIT_AR: begin
          // 保持 arvalid=1, 等待 arready 握手
          // AXI 规则: valid 一旦置位必须保持直到握手完成
          if (lsu_arready) begin
            lsu_state <= L_WAIT_R;
          end
        end

        L_WAIT_R: begin
          // rready=1, 等待 rvalid 握手
          if (lsu_rvalid) begin
            // 握手完成: rvalid && rready
            lsu_state <= L_IDLE;
          end
        end

        L_WAIT_AW_W: begin
          // 保持 awvalid/wvalid, 等待两个通道握手完成
          // AXI 规则: valid 一旦置位必须保持直到各自握手完成
          // AW 和 W 可以独立完成握手 (不同周期)

          // 追踪 AW 握手
          if (lsu_awready && !aw_done) begin
            aw_done <= 1'b1;
          end

          // 追踪 W 握手
          if (lsu_wready && !w_done) begin
            w_done <= 1'b1;
          end

          // 两个通道都握手完成后, 进入等待写回复
          // (aw_done || lsu_awready): AW 本周期或之前已完成
          // (w_done  || lsu_wready):  W  本周期或之前已完成
          if ((aw_done || lsu_awready) && (w_done || lsu_wready)) begin
            lsu_state <= L_WAIT_B;
            aw_done   <= 1'b0;
            w_done    <= 1'b0;
          end
        end

        L_WAIT_B: begin
          // bready=1, 等待 bvalid 握手
          if (lsu_bvalid) begin
            // 握手完成: bvalid && bready
            lsu_state <= L_IDLE;
          end
        end

        default: lsu_state <= L_IDLE;
      endcase
    end
  end

  // ===================================================================
  // 字节/半字选择 (组合逻辑)
  // ===================================================================
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
