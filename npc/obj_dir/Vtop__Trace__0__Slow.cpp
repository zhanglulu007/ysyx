// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Tracing implementation internals

#include "verilated_fst_c.h"
#include "Vtop__Syms.h"


VL_ATTR_COLD void Vtop___024root__trace_init_sub__TOP__0(Vtop___024root* vlSelf, VerilatedFst* tracep) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_init_sub__TOP__0\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const int c = vlSymsp->__Vm_baseCode;
    tracep->pushPrefix("$rootio", VerilatedTracePrefixType::SCOPE_MODULE);
    tracep->declBit(c+67,0,"clk",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+68,0,"rst",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->popPrefix();
    tracep->pushPrefix("top", VerilatedTracePrefixType::SCOPE_MODULE);
    tracep->declBit(c+67,0,"clk",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+68,0,"rst",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBus(c+1,0,"pc",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+2,0,"inst",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+3,0,"opcode",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 6,0);
    tracep->declBus(c+4,0,"rd",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBus(c+5,0,"rs1",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBus(c+6,0,"rs2",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBus(c+7,0,"funct3",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 2,0);
    tracep->declBus(c+8,0,"funct7",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 6,0);
    tracep->declBus(c+9,0,"imm_i",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+10,0,"imm_s",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+11,0,"imm_u",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBit(c+12,0,"is_addi",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+13,0,"is_jalr",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+14,0,"is_ebreak",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+15,0,"is_lui",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+16,0,"is_add",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+17,0,"is_lw",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+18,0,"is_lbu",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+19,0,"is_sw",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+20,0,"is_sb",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+21,0,"reg_wen",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+22,0,"mem_valid",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+23,0,"mem_wen",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBus(c+24,0,"rs1_data",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+25,0,"rs2_data",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+26,0,"a0_value",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+27,0,"alu_result",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+28,0,"jump_target",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+29,0,"mem_rdata",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+30,0,"rd_data",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+31,0,"pc_next",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+32,0,"mem_addr",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->pushPrefix("u_exu", VerilatedTracePrefixType::SCOPE_MODULE);
    tracep->declBus(c+24,0,"rs1_data",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+25,0,"rs2_data",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+9,0,"imm_i",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+1,0,"pc",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBit(c+16,0,"is_add",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+13,0,"is_jalr",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBus(c+27,0,"alu_result",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+28,0,"jump_target",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->popPrefix();
    tracep->pushPrefix("u_idu", VerilatedTracePrefixType::SCOPE_MODULE);
    tracep->declBus(c+2,0,"inst",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+3,0,"opcode",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 6,0);
    tracep->declBus(c+4,0,"rd",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBus(c+5,0,"rs1",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBus(c+6,0,"rs2",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBus(c+7,0,"funct3",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 2,0);
    tracep->declBus(c+8,0,"funct7",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 6,0);
    tracep->declBus(c+9,0,"imm_i",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+10,0,"imm_s",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+11,0,"imm_u",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBit(c+12,0,"is_addi",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+13,0,"is_jalr",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+14,0,"is_ebreak",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+15,0,"is_lui",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+16,0,"is_add",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+17,0,"is_lw",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+18,0,"is_lbu",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+19,0,"is_sw",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+20,0,"is_sb",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+21,0,"reg_wen",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+22,0,"mem_valid",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+23,0,"mem_wen",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->popPrefix();
    tracep->pushPrefix("u_ifu", VerilatedTracePrefixType::SCOPE_MODULE);
    tracep->declBit(c+67,0,"clk",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+68,0,"rst",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBus(c+31,0,"pc_next",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+1,0,"pc",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+2,0,"inst",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->popPrefix();
    tracep->pushPrefix("u_lsu", VerilatedTracePrefixType::SCOPE_MODULE);
    tracep->declBit(c+67,0,"clk",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+68,0,"rst",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+22,0,"mem_valid",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+23,0,"mem_wen",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+17,0,"is_lw",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+18,0,"is_lbu",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+19,0,"is_sw",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+20,0,"is_sb",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBus(c+32,0,"mem_addr",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+25,0,"wdata",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+29,0,"rdata",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+33,0,"mem_offset",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 1,0);
    tracep->declBus(c+34,0,"mem_rdata_raw",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::VAR, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+29,0,"mem_rdata_selected",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::VAR, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->popPrefix();
    tracep->pushPrefix("u_regfile", VerilatedTracePrefixType::SCOPE_MODULE);
    tracep->declBit(c+67,0,"clk",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBus(c+30,0,"wdata",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+4,0,"waddr",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBit(c+21,0,"wen",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBus(c+5,0,"raddr1",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBus(c+24,0,"rdata1",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+6,0,"raddr2",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 4,0);
    tracep->declBus(c+25,0,"rdata2",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+26,0,"a0_value",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->pushPrefix("rf", VerilatedTracePrefixType::ARRAY_UNPACKED);
    for (int i = 0; i < 32; ++i) {
        tracep->declBus(c+35+i*1,0,"",-1, VerilatedTraceSigDirection::NONE, VerilatedTraceSigKind::VAR, VerilatedTraceSigType::LOGIC, true,(i+0), 31,0);
    }
    tracep->popPrefix();
    tracep->popPrefix();
    tracep->pushPrefix("u_wbu", VerilatedTracePrefixType::SCOPE_MODULE);
    tracep->declBus(c+1,0,"pc",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+27,0,"alu_result",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+29,0,"mem_rdata",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+11,0,"imm_u",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+28,0,"jump_target",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBit(c+13,0,"is_jalr",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+15,0,"is_lui",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+17,0,"is_lw",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+18,0,"is_lbu",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBit(c+14,0,"is_ebreak",-1, VerilatedTraceSigDirection::INPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1);
    tracep->declBus(c+30,0,"rd_data",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->declBus(c+31,0,"pc_next",-1, VerilatedTraceSigDirection::OUTPUT, VerilatedTraceSigKind::WIRE, VerilatedTraceSigType::LOGIC, false,-1, 31,0);
    tracep->popPrefix();
    tracep->popPrefix();
}

VL_ATTR_COLD void Vtop___024root__trace_init_top(Vtop___024root* vlSelf, VerilatedFst* tracep) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_init_top\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vtop___024root__trace_init_sub__TOP__0(vlSelf, tracep);
}

VL_ATTR_COLD void Vtop___024root__trace_const_0(void* voidSelf, VerilatedFst::Buffer* bufp);
VL_ATTR_COLD void Vtop___024root__trace_full_0(void* voidSelf, VerilatedFst::Buffer* bufp);
void Vtop___024root__trace_chg_0(void* voidSelf, VerilatedFst::Buffer* bufp);
void Vtop___024root__trace_cleanup(void* voidSelf, VerilatedFst* /*unused*/);

VL_ATTR_COLD void Vtop___024root__trace_register(Vtop___024root* vlSelf, VerilatedFst* tracep) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_register\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    tracep->addConstCb(&Vtop___024root__trace_const_0, 0, vlSelf);
    tracep->addFullCb(&Vtop___024root__trace_full_0, 0, vlSelf);
    tracep->addChgCb(&Vtop___024root__trace_chg_0, 0, vlSelf);
    tracep->addCleanupCb(&Vtop___024root__trace_cleanup, vlSelf);
}

VL_ATTR_COLD void Vtop___024root__trace_const_0(void* voidSelf, VerilatedFst::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_const_0\n"); );
    // Body
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
}

VL_ATTR_COLD void Vtop___024root__trace_full_0_sub_0(Vtop___024root* vlSelf, VerilatedFst::Buffer* bufp);

VL_ATTR_COLD void Vtop___024root__trace_full_0(void* voidSelf, VerilatedFst::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_full_0\n"); );
    // Body
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    Vtop___024root__trace_full_0_sub_0((&vlSymsp->TOP), bufp);
}

VL_ATTR_COLD void Vtop___024root__trace_full_0_sub_0(Vtop___024root* vlSelf, VerilatedFst::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_full_0_sub_0\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    uint32_t* const oldp VL_ATTR_UNUSED = bufp->oldp(vlSymsp->__Vm_baseCode);
    bufp->fullIData(oldp+1,(vlSelfRef.top__DOT__pc),32);
    bufp->fullIData(oldp+2,(vlSelfRef.top__DOT__inst),32);
    bufp->fullCData(oldp+3,((0x0000007fU & vlSelfRef.top__DOT__inst)),7);
    bufp->fullCData(oldp+4,((0x0000001fU & (vlSelfRef.top__DOT__inst 
                                            >> 7U))),5);
    bufp->fullCData(oldp+5,((0x0000001fU & (vlSelfRef.top__DOT__inst 
                                            >> 0x0000000fU))),5);
    bufp->fullCData(oldp+6,((0x0000001fU & (vlSelfRef.top__DOT__inst 
                                            >> 0x00000014U))),5);
    bufp->fullCData(oldp+7,((7U & (vlSelfRef.top__DOT__inst 
                                   >> 0x0000000cU))),3);
    bufp->fullCData(oldp+8,((vlSelfRef.top__DOT__inst 
                             >> 0x00000019U)),7);
    bufp->fullIData(oldp+9,((((- (IData)((vlSelfRef.top__DOT__inst 
                                          >> 0x0000001fU))) 
                              << 0x0000000cU) | (vlSelfRef.top__DOT__inst 
                                                 >> 0x00000014U))),32);
    bufp->fullIData(oldp+10,((((- (IData)((vlSelfRef.top__DOT__inst 
                                           >> 0x0000001fU))) 
                               << 0x0000000cU) | ((0x00000fe0U 
                                                   & (vlSelfRef.top__DOT__inst 
                                                      >> 0x00000014U)) 
                                                  | (0x0000001fU 
                                                     & (vlSelfRef.top__DOT__inst 
                                                        >> 7U))))),32);
    bufp->fullIData(oldp+11,((0xfffff000U & vlSelfRef.top__DOT__inst)),32);
    bufp->fullBit(oldp+12,((IData)((0x00000013U == 
                                    (0x0000707fU & vlSelfRef.top__DOT__inst)))));
    bufp->fullBit(oldp+13,(vlSelfRef.top__DOT__u_exu__DOT__is_jalr));
    bufp->fullBit(oldp+14,((0x00100073U == vlSelfRef.top__DOT__inst)));
    bufp->fullBit(oldp+15,((0x37U == (0x0000007fU & vlSelfRef.top__DOT__inst))));
    bufp->fullBit(oldp+16,(vlSelfRef.top__DOT__u_exu__DOT__is_add));
    bufp->fullBit(oldp+17,(vlSelfRef.top__DOT__u_idu__DOT__is_lw));
    bufp->fullBit(oldp+18,(vlSelfRef.top__DOT__u_idu__DOT__is_lbu));
    bufp->fullBit(oldp+19,(vlSelfRef.top__DOT__u_idu__DOT__is_sw));
    bufp->fullBit(oldp+20,(vlSelfRef.top__DOT__u_idu__DOT__is_sb));
    bufp->fullBit(oldp+21,((((IData)((0x00000013U == 
                                      (0x0000707fU 
                                       & vlSelfRef.top__DOT__inst))) 
                             | ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr) 
                                | ((0x37U == (0x0000007fU 
                                              & vlSelfRef.top__DOT__inst)) 
                                   | ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_add) 
                                      | (IData)(vlSelfRef.top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5))))) 
                            & (0U != (0x0000001fU & 
                                      (vlSelfRef.top__DOT__inst 
                                       >> 7U))))));
    bufp->fullBit(oldp+22,(((IData)(vlSelfRef.top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5) 
                            | (IData)(vlSelfRef.top__DOT__u_idu__DOT__mem_wen))));
    bufp->fullBit(oldp+23,(vlSelfRef.top__DOT__u_idu__DOT__mem_wen));
    bufp->fullIData(oldp+24,(vlSelfRef.top__DOT__u_exu__DOT__rs1_data),32);
    bufp->fullIData(oldp+25,(((0U == (0x0000001fU & 
                                      (vlSelfRef.top__DOT__inst 
                                       >> 0x00000014U)))
                               ? 0U : vlSelfRef.top__DOT__u_regfile__DOT__rf
                              [(0x0000001fU & (vlSelfRef.top__DOT__inst 
                                               >> 0x00000014U))])),32);
    bufp->fullIData(oldp+26,(vlSelfRef.top__DOT__u_regfile__DOT__rf
                             [0x0aU]),32);
    bufp->fullIData(oldp+27,(((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_add)
                               ? (vlSelfRef.top__DOT__u_exu__DOT__rs1_data 
                                  + ((0U == (0x0000001fU 
                                             & (vlSelfRef.top__DOT__inst 
                                                >> 0x00000014U)))
                                      ? 0U : vlSelfRef.top__DOT__u_regfile__DOT__rf
                                     [(0x0000001fU 
                                       & (vlSelfRef.top__DOT__inst 
                                          >> 0x00000014U))]))
                               : vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0)),32);
    bufp->fullIData(oldp+28,((0xfffffffeU & vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0)),32);
    bufp->fullIData(oldp+29,(((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw)
                               ? vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw
                               : ((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lbu)
                                   ? ((2U & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)
                                       ? ((1U & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)
                                           ? VL_SHIFTR_III(32,32,32, vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw, 0x00000018U)
                                           : (0x000000ffU 
                                              & (vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw 
                                                 >> 0x00000010U)))
                                       : ((1U & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)
                                           ? (0x000000ffU 
                                              & (vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw 
                                                 >> 8U))
                                           : (0x000000ffU 
                                              & vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw)))
                                   : 0U))),32);
    bufp->fullIData(oldp+30,(((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr)
                               ? ((IData)(4U) + vlSelfRef.top__DOT__pc)
                               : ((0x37U == (0x0000007fU 
                                             & vlSelfRef.top__DOT__inst))
                                   ? (0xfffff000U & vlSelfRef.top__DOT__inst)
                                   : (((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lbu) 
                                       | (IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw))
                                       ? ((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw)
                                           ? vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw
                                           : ((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lbu)
                                               ? ((2U 
                                                   & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)
                                                   ? 
                                                  ((1U 
                                                    & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)
                                                    ? 
                                                   VL_SHIFTR_III(32,32,32, vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw, 0x00000018U)
                                                    : 
                                                   (0x000000ffU 
                                                    & (vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw 
                                                       >> 0x00000010U)))
                                                   : 
                                                  ((1U 
                                                    & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)
                                                    ? 
                                                   (0x000000ffU 
                                                    & (vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw 
                                                       >> 8U))
                                                    : 
                                                   (0x000000ffU 
                                                    & vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw)))
                                               : 0U))
                                       : ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_add)
                                           ? (vlSelfRef.top__DOT__u_exu__DOT__rs1_data 
                                              + ((0U 
                                                  == 
                                                  (0x0000001fU 
                                                   & (vlSelfRef.top__DOT__inst 
                                                      >> 0x00000014U)))
                                                  ? 0U
                                                  : 
                                                 vlSelfRef.top__DOT__u_regfile__DOT__rf
                                                 [(0x0000001fU 
                                                   & (vlSelfRef.top__DOT__inst 
                                                      >> 0x00000014U))]))
                                           : vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0))))),32);
    bufp->fullIData(oldp+31,(((0x00100073U == vlSelfRef.top__DOT__inst)
                               ? vlSelfRef.top__DOT__pc
                               : ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr)
                                   ? (0xfffffffeU & vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0)
                                   : ((IData)(4U) + vlSelfRef.top__DOT__pc)))),32);
    bufp->fullIData(oldp+32,(vlSelfRef.top__DOT__u_lsu__DOT__mem_addr),32);
    bufp->fullCData(oldp+33,((3U & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)),2);
    bufp->fullIData(oldp+34,(vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw),32);
    bufp->fullIData(oldp+35,(vlSelfRef.top__DOT__u_regfile__DOT__rf[0]),32);
    bufp->fullIData(oldp+36,(vlSelfRef.top__DOT__u_regfile__DOT__rf[1]),32);
    bufp->fullIData(oldp+37,(vlSelfRef.top__DOT__u_regfile__DOT__rf[2]),32);
    bufp->fullIData(oldp+38,(vlSelfRef.top__DOT__u_regfile__DOT__rf[3]),32);
    bufp->fullIData(oldp+39,(vlSelfRef.top__DOT__u_regfile__DOT__rf[4]),32);
    bufp->fullIData(oldp+40,(vlSelfRef.top__DOT__u_regfile__DOT__rf[5]),32);
    bufp->fullIData(oldp+41,(vlSelfRef.top__DOT__u_regfile__DOT__rf[6]),32);
    bufp->fullIData(oldp+42,(vlSelfRef.top__DOT__u_regfile__DOT__rf[7]),32);
    bufp->fullIData(oldp+43,(vlSelfRef.top__DOT__u_regfile__DOT__rf[8]),32);
    bufp->fullIData(oldp+44,(vlSelfRef.top__DOT__u_regfile__DOT__rf[9]),32);
    bufp->fullIData(oldp+45,(vlSelfRef.top__DOT__u_regfile__DOT__rf[10]),32);
    bufp->fullIData(oldp+46,(vlSelfRef.top__DOT__u_regfile__DOT__rf[11]),32);
    bufp->fullIData(oldp+47,(vlSelfRef.top__DOT__u_regfile__DOT__rf[12]),32);
    bufp->fullIData(oldp+48,(vlSelfRef.top__DOT__u_regfile__DOT__rf[13]),32);
    bufp->fullIData(oldp+49,(vlSelfRef.top__DOT__u_regfile__DOT__rf[14]),32);
    bufp->fullIData(oldp+50,(vlSelfRef.top__DOT__u_regfile__DOT__rf[15]),32);
    bufp->fullIData(oldp+51,(vlSelfRef.top__DOT__u_regfile__DOT__rf[16]),32);
    bufp->fullIData(oldp+52,(vlSelfRef.top__DOT__u_regfile__DOT__rf[17]),32);
    bufp->fullIData(oldp+53,(vlSelfRef.top__DOT__u_regfile__DOT__rf[18]),32);
    bufp->fullIData(oldp+54,(vlSelfRef.top__DOT__u_regfile__DOT__rf[19]),32);
    bufp->fullIData(oldp+55,(vlSelfRef.top__DOT__u_regfile__DOT__rf[20]),32);
    bufp->fullIData(oldp+56,(vlSelfRef.top__DOT__u_regfile__DOT__rf[21]),32);
    bufp->fullIData(oldp+57,(vlSelfRef.top__DOT__u_regfile__DOT__rf[22]),32);
    bufp->fullIData(oldp+58,(vlSelfRef.top__DOT__u_regfile__DOT__rf[23]),32);
    bufp->fullIData(oldp+59,(vlSelfRef.top__DOT__u_regfile__DOT__rf[24]),32);
    bufp->fullIData(oldp+60,(vlSelfRef.top__DOT__u_regfile__DOT__rf[25]),32);
    bufp->fullIData(oldp+61,(vlSelfRef.top__DOT__u_regfile__DOT__rf[26]),32);
    bufp->fullIData(oldp+62,(vlSelfRef.top__DOT__u_regfile__DOT__rf[27]),32);
    bufp->fullIData(oldp+63,(vlSelfRef.top__DOT__u_regfile__DOT__rf[28]),32);
    bufp->fullIData(oldp+64,(vlSelfRef.top__DOT__u_regfile__DOT__rf[29]),32);
    bufp->fullIData(oldp+65,(vlSelfRef.top__DOT__u_regfile__DOT__rf[30]),32);
    bufp->fullIData(oldp+66,(vlSelfRef.top__DOT__u_regfile__DOT__rf[31]),32);
    bufp->fullBit(oldp+67,(vlSelfRef.clk));
    bufp->fullBit(oldp+68,(vlSelfRef.rst));
}
