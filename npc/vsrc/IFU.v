// IFU - Instruction Fetch Unit
// 取指单元：通过 AXI4-Lite 从 MEM 模块取指令
// AXI4-Lite 协议: AR 通道 (读地址) + R 通道 (读数据)
// IFU 只读, AW/W/B 通道无需连接
// 两状态状态机: IDLE (等待arready握手) / WAIT (等待rvalid握手, 执行指令)

module IFU(
  input clk,
  input rst,
  input [31:0] pc_next,        // 下一个PC值 (来自WBU)
  input mem_valid,              // 访存有效 (load/store, 来自IDU)
  input mem_wen,                // 写使能 (store, 来自IDU)
  input [4:0] rd,              // 目的寄存器 (来自IDU)

  // ===== AXI4-Lite AR 通道 (读地址) =====
  input  ifu_arready,          // MEM -> IFU: 从设备就绪接收读地址
  output ifu_arvalid,          // IFU -> MEM: 读地址有效
  output [31:0] ifu_araddr,    // IFU -> MEM: 读地址

  // ===== AXI4-Lite R 通道 (读数据) =====
  input  ifu_rvalid,           // MEM -> IFU: 读数据有效
  output ifu_rready,           // IFU -> MEM: 主设备就绪接收读数据
  input  [31:0] ifu_rdata,     // MEM -> IFU: 读出的指令
  input  [ 1:0] ifu_rresp,     // MEM -> IFU: 读响应状态

  // ===== LSU 完成信号 (来自 MEM 的 R/B 通道) =====
  input  lsu_rvalid,           // MEM -> LSU R 通道 valid (load 完成)
  input  lsu_bvalid,           // MEM -> LSU B 通道 valid (store 完成)

  // ===== 输出 =====
  output reg [31:0] pc,        // 当前PC
  output [31:0] inst,          // -> IDU: 当前指令
  output ifu_valid,            // -> IDU: 指令有效 (译码/执行周期)
  output load_wb,              // -> top: load 写回触发
  output [4:0] load_rd         // -> top: load 目的寄存器
);

  // DPI-C函数：通知C++侧
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);

  // ========== 两状态状态机 (AXI4-Lite 握手) ==========
  // IDLE - 发送取指请求 (arvalid=1), 等待 arready 握手
  // WAIT - 等待取指响应 (rvalid 握手), 执行指令, 可能等待LSU响应
  localparam IDLE = 1'b0;
  localparam WAIT = 1'b1;

  reg state;
  reg lsu_pending;          // 1 = 在 WAIT 状态中等待 LSU 响应
  reg is_load_pending;      // 1 = 等待中的 LSU 操作是 load (需要写回)
  reg [4:0] load_rd_saved;  // load 指令的目的寄存器

  // 判断当前指令类型 (组合逻辑)
  wire [6:0] cur_opcode = ifu_rdata[6:0];
  wire is_load_inst  = (cur_opcode == 7'b0000011);  // Load opcode
  wire is_store_inst = (cur_opcode == 7'b0100011);  // Store opcode
  wire is_mem_inst   = is_load_inst || is_store_inst;

  // ifu_araddr 恒等于 pc, MEM 仅在 arvalid 有效时采样
  assign ifu_araddr = pc;

  // ifu_arvalid: 在 IDLE 状态发送取指请求
  //   AXI 规则: valid 不依赖 ready, 自主决定
  assign ifu_arvalid = (state == IDLE) && !rst;

  // ifu_rready: 在 WAIT 状态且未等待 LSU 时, 就绪接收取指响应
  //   - 当 lsu_pending=1 时, IFU 正等待 LSU 完成, 不能接收新的取指响应
  assign ifu_rready = (state == WAIT) && !lsu_pending && !rst;

  // ifu_valid: 仅在取指响应握手完成且未等待 LSU 时有效
  //   rvalid && rready 握手成功即表示指令已接收
  assign ifu_valid = (state == WAIT) && ifu_rvalid && ifu_rready && !lsu_pending && !rst;

  // inst: 有效指令或 NOP
  //   - 当 ifu_valid=1 时输出真实指令
  //   - 当等待 LSU 时输出 NOP (防止 IDU 重复译码 load/store)
  assign inst = ifu_valid ? ifu_rdata : 32'h00000013;  // nop = addi x0, x0, 0

  // load_wb: 当 MEM 返回 load 数据时触发写回 (组合逻辑)
  //   AXI4-Lite: R 通道握手完成即 load 数据有效
  assign load_wb = (state == WAIT) && lsu_pending && lsu_rvalid && is_load_pending;
  assign load_rd = load_rd_saved;

  always @(posedge clk) begin
    if (rst) begin
      state           <= IDLE;
      lsu_pending     <= 1'b0;
      is_load_pending <= 1'b0;
      load_rd_saved   <= 5'b0;
      pc              <= 32'h80000000;
      update_pc_value(32'h80000000);
    end else begin
      case (state)
        IDLE: begin
          // 发送取指请求 (ifu_arvalid=1), 等待 arready 握手
          // AXI 规则: valid 一旦置位必须保持直到握手完成
          // 握手成功 (ifu_arvalid && ifu_arready) 后进入 WAIT
          if (ifu_arready) begin
            state       <= WAIT;
            lsu_pending <= 1'b0;
          end
          // 否则保持 IDLE, arvalid 继续有效等待
        end

        WAIT: begin
          if (lsu_pending) begin
            // ===== 等待 LSU 响应 =====
            // AXI4-Lite: load 完成看 lsu_rvalid, store 完成看 lsu_bvalid
            if (is_load_pending) begin
              // 等待 load 数据返回 (R 通道)
              if (lsu_rvalid) begin
                // load 数据已通过 load_wb 写回 (组合逻辑, 本周期 posedge 写入)
                pc               <= pc_next;
                update_pc_value(pc_next);
                state            <= IDLE;
                lsu_pending      <= 1'b0;
                is_load_pending  <= 1'b0;
              end
            end else begin
              // 等待 store 完成 (B 通道)
              if (lsu_bvalid) begin
                // store 写入已完成
                pc               <= pc_next;
                update_pc_value(pc_next);
                state            <= IDLE;
                lsu_pending      <= 1'b0;
                is_load_pending  <= 1'b0;
              end
            end
            // 继续保持 WAIT 等待
          end else if (ifu_rvalid && ifu_rready) begin
            // ===== 取指响应握手完成, 执行指令 =====
            // ifu_rready 在本状态且 !lsu_pending 时恒为 1
            update_inst_value(pc, ifu_rdata);

            // 判断当前指令是否为访存指令
            // 注意: 此时 inst = ifu_rdata (已更新为真实指令)
            // 直接用 inst 字段判断, 而不依赖 IDU 输出的 mem_valid
            wire [6:0] cur_opcode = ifu_rdata[6:0];
            wire is_load_inst  = (cur_opcode == 7'b0000011);  // Load opcode
            wire is_store_inst = (cur_opcode == 7'b0100011);  // Store opcode
            wire is_mem_inst   = is_load_inst || is_store_inst;

            if (is_mem_inst) begin
              // Load 或 Store: 需要等待 LSU 完成
              // LSU 请求在本周期已发送 (mem_valid/mem_wen 由 IDU 组合逻辑产生)
              lsu_pending     <= 1'b1;
              is_load_pending <= is_load_inst;  // load=1, store=0
              load_rd_saved   <= rd;
              // 保持 WAIT 状态 (注意: 下周期 ifu_rready 变 0, 防止误收)
            end else begin
              // 非访存指令: 本周期完成执行, 写回寄存器 (由 top.v 处理)
              pc               <= pc_next;
              update_pc_value(pc_next);
              state            <= IDLE;
            end
          end
          // rvalid == 0: 继续保持 WAIT 等待取指响应
          // (ifu_rready 已为 1, MEM 看到后会尽快返回 rvalid)
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
