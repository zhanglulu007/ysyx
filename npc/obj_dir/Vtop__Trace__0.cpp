// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Tracing implementation internals

#include "verilated_fst_c.h"
#include "Vtop__Syms.h"


void Vtop___024root__trace_chg_0_sub_0(Vtop___024root* vlSelf, VerilatedFst::Buffer* bufp);

void Vtop___024root__trace_chg_0(void* voidSelf, VerilatedFst::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_chg_0\n"); );
    // Body
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (VL_UNLIKELY(!vlSymsp->__Vm_activity)) return;
    Vtop___024root__trace_chg_0_sub_0((&vlSymsp->TOP), bufp);
}

void Vtop___024root__trace_chg_0_sub_0(Vtop___024root* vlSelf, VerilatedFst::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_chg_0_sub_0\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    uint32_t* const oldp VL_ATTR_UNUSED = bufp->oldp(vlSymsp->__Vm_baseCode + 1);
    if (VL_UNLIKELY((vlSelfRef.__Vm_traceActivity[1U]))) {
        bufp->chgIData(oldp+0,(vlSelfRef.top__DOT__pc),32);
        bufp->chgIData(oldp+1,(vlSelfRef.top__DOT__inst),32);
        bufp->chgCData(oldp+2,((0x0000007fU & vlSelfRef.top__DOT__inst)),7);
        bufp->chgCData(oldp+3,((0x0000001fU & (vlSelfRef.top__DOT__inst 
                                               >> 7U))),5);
        bufp->chgCData(oldp+4,((0x0000001fU & (vlSelfRef.top__DOT__inst 
                                               >> 0x0000000fU))),5);
        bufp->chgCData(oldp+5,((0x0000001fU & (vlSelfRef.top__DOT__inst 
                                               >> 0x00000014U))),5);
        bufp->chgCData(oldp+6,((7U & (vlSelfRef.top__DOT__inst 
                                      >> 0x0000000cU))),3);
        bufp->chgCData(oldp+7,((vlSelfRef.top__DOT__inst 
                                >> 0x00000019U)),7);
        bufp->chgIData(oldp+8,((((- (IData)((vlSelfRef.top__DOT__inst 
                                             >> 0x0000001fU))) 
                                 << 0x0000000cU) | 
                                (vlSelfRef.top__DOT__inst 
                                 >> 0x00000014U))),32);
        bufp->chgIData(oldp+9,((((- (IData)((vlSelfRef.top__DOT__inst 
                                             >> 0x0000001fU))) 
                                 << 0x0000000cU) | 
                                ((0x00000fe0U & (vlSelfRef.top__DOT__inst 
                                                 >> 0x00000014U)) 
                                 | (0x0000001fU & (vlSelfRef.top__DOT__inst 
                                                   >> 7U))))),32);
        bufp->chgIData(oldp+10,((0xfffff000U & vlSelfRef.top__DOT__inst)),32);
        bufp->chgBit(oldp+11,((IData)((0x00000013U 
                                       == (0x0000707fU 
                                           & vlSelfRef.top__DOT__inst)))));
        bufp->chgBit(oldp+12,(vlSelfRef.top__DOT__u_exu__DOT__is_jalr));
        bufp->chgBit(oldp+13,((0x00100073U == vlSelfRef.top__DOT__inst)));
        bufp->chgBit(oldp+14,((0x37U == (0x0000007fU 
                                         & vlSelfRef.top__DOT__inst))));
        bufp->chgBit(oldp+15,(vlSelfRef.top__DOT__u_exu__DOT__is_add));
        bufp->chgBit(oldp+16,(vlSelfRef.top__DOT__u_idu__DOT__is_lw));
        bufp->chgBit(oldp+17,(vlSelfRef.top__DOT__u_idu__DOT__is_lbu));
        bufp->chgBit(oldp+18,(vlSelfRef.top__DOT__u_idu__DOT__is_sw));
        bufp->chgBit(oldp+19,(vlSelfRef.top__DOT__u_idu__DOT__is_sb));
        bufp->chgBit(oldp+20,((((IData)((0x00000013U 
                                         == (0x0000707fU 
                                             & vlSelfRef.top__DOT__inst))) 
                                | ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr) 
                                   | ((0x37U == (0x0000007fU 
                                                 & vlSelfRef.top__DOT__inst)) 
                                      | ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_add) 
                                         | (IData)(vlSelfRef.top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5))))) 
                               & (0U != (0x0000001fU 
                                         & (vlSelfRef.top__DOT__inst 
                                            >> 7U))))));
        bufp->chgBit(oldp+21,(((IData)(vlSelfRef.top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5) 
                               | (IData)(vlSelfRef.top__DOT__u_idu__DOT__mem_wen))));
        bufp->chgBit(oldp+22,(vlSelfRef.top__DOT__u_idu__DOT__mem_wen));
        bufp->chgIData(oldp+23,(vlSelfRef.top__DOT__u_exu__DOT__rs1_data),32);
        bufp->chgIData(oldp+24,(((0U == (0x0000001fU 
                                         & (vlSelfRef.top__DOT__inst 
                                            >> 0x00000014U)))
                                  ? 0U : vlSelfRef.top__DOT__u_regfile__DOT__rf
                                 [(0x0000001fU & (vlSelfRef.top__DOT__inst 
                                                  >> 0x00000014U))])),32);
        bufp->chgIData(oldp+25,(vlSelfRef.top__DOT__u_regfile__DOT__rf
                                [0x0aU]),32);
        bufp->chgIData(oldp+26,(((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_add)
                                  ? (vlSelfRef.top__DOT__u_exu__DOT__rs1_data 
                                     + ((0U == (0x0000001fU 
                                                & (vlSelfRef.top__DOT__inst 
                                                   >> 0x00000014U)))
                                         ? 0U : vlSelfRef.top__DOT__u_regfile__DOT__rf
                                        [(0x0000001fU 
                                          & (vlSelfRef.top__DOT__inst 
                                             >> 0x00000014U))]))
                                  : vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0)),32);
        bufp->chgIData(oldp+27,((0xfffffffeU & vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0)),32);
        bufp->chgIData(oldp+28,(((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw)
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
        bufp->chgIData(oldp+29,(((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr)
                                  ? ((IData)(4U) + vlSelfRef.top__DOT__pc)
                                  : ((0x37U == (0x0000007fU 
                                                & vlSelfRef.top__DOT__inst))
                                      ? (0xfffff000U 
                                         & vlSelfRef.top__DOT__inst)
                                      : (((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lbu) 
                                          | (IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw))
                                          ? ((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw)
                                              ? vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw
                                              : ((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lbu)
                                                  ? 
                                                 ((2U 
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
                                                 + 
                                                 ((0U 
                                                   == 
                                                   (0x0000001fU 
                                                    & (vlSelfRef.top__DOT__inst 
                                                       >> 0x00000014U)))
                                                   ? 0U
                                                   : 
                                                  vlSelfRef.top__DOT__u_regfile__DOT__rf
                                                  [
                                                  (0x0000001fU 
                                                   & (vlSelfRef.top__DOT__inst 
                                                      >> 0x00000014U))]))
                                              : vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0))))),32);
        bufp->chgIData(oldp+30,(((0x00100073U == vlSelfRef.top__DOT__inst)
                                  ? vlSelfRef.top__DOT__pc
                                  : ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr)
                                      ? (0xfffffffeU 
                                         & vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0)
                                      : ((IData)(4U) 
                                         + vlSelfRef.top__DOT__pc)))),32);
        bufp->chgIData(oldp+31,(vlSelfRef.top__DOT__u_lsu__DOT__mem_addr),32);
        bufp->chgCData(oldp+32,((3U & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)),2);
        bufp->chgIData(oldp+33,(vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw),32);
        bufp->chgIData(oldp+34,(vlSelfRef.top__DOT__u_regfile__DOT__rf[0]),32);
        bufp->chgIData(oldp+35,(vlSelfRef.top__DOT__u_regfile__DOT__rf[1]),32);
        bufp->chgIData(oldp+36,(vlSelfRef.top__DOT__u_regfile__DOT__rf[2]),32);
        bufp->chgIData(oldp+37,(vlSelfRef.top__DOT__u_regfile__DOT__rf[3]),32);
        bufp->chgIData(oldp+38,(vlSelfRef.top__DOT__u_regfile__DOT__rf[4]),32);
        bufp->chgIData(oldp+39,(vlSelfRef.top__DOT__u_regfile__DOT__rf[5]),32);
        bufp->chgIData(oldp+40,(vlSelfRef.top__DOT__u_regfile__DOT__rf[6]),32);
        bufp->chgIData(oldp+41,(vlSelfRef.top__DOT__u_regfile__DOT__rf[7]),32);
        bufp->chgIData(oldp+42,(vlSelfRef.top__DOT__u_regfile__DOT__rf[8]),32);
        bufp->chgIData(oldp+43,(vlSelfRef.top__DOT__u_regfile__DOT__rf[9]),32);
        bufp->chgIData(oldp+44,(vlSelfRef.top__DOT__u_regfile__DOT__rf[10]),32);
        bufp->chgIData(oldp+45,(vlSelfRef.top__DOT__u_regfile__DOT__rf[11]),32);
        bufp->chgIData(oldp+46,(vlSelfRef.top__DOT__u_regfile__DOT__rf[12]),32);
        bufp->chgIData(oldp+47,(vlSelfRef.top__DOT__u_regfile__DOT__rf[13]),32);
        bufp->chgIData(oldp+48,(vlSelfRef.top__DOT__u_regfile__DOT__rf[14]),32);
        bufp->chgIData(oldp+49,(vlSelfRef.top__DOT__u_regfile__DOT__rf[15]),32);
        bufp->chgIData(oldp+50,(vlSelfRef.top__DOT__u_regfile__DOT__rf[16]),32);
        bufp->chgIData(oldp+51,(vlSelfRef.top__DOT__u_regfile__DOT__rf[17]),32);
        bufp->chgIData(oldp+52,(vlSelfRef.top__DOT__u_regfile__DOT__rf[18]),32);
        bufp->chgIData(oldp+53,(vlSelfRef.top__DOT__u_regfile__DOT__rf[19]),32);
        bufp->chgIData(oldp+54,(vlSelfRef.top__DOT__u_regfile__DOT__rf[20]),32);
        bufp->chgIData(oldp+55,(vlSelfRef.top__DOT__u_regfile__DOT__rf[21]),32);
        bufp->chgIData(oldp+56,(vlSelfRef.top__DOT__u_regfile__DOT__rf[22]),32);
        bufp->chgIData(oldp+57,(vlSelfRef.top__DOT__u_regfile__DOT__rf[23]),32);
        bufp->chgIData(oldp+58,(vlSelfRef.top__DOT__u_regfile__DOT__rf[24]),32);
        bufp->chgIData(oldp+59,(vlSelfRef.top__DOT__u_regfile__DOT__rf[25]),32);
        bufp->chgIData(oldp+60,(vlSelfRef.top__DOT__u_regfile__DOT__rf[26]),32);
        bufp->chgIData(oldp+61,(vlSelfRef.top__DOT__u_regfile__DOT__rf[27]),32);
        bufp->chgIData(oldp+62,(vlSelfRef.top__DOT__u_regfile__DOT__rf[28]),32);
        bufp->chgIData(oldp+63,(vlSelfRef.top__DOT__u_regfile__DOT__rf[29]),32);
        bufp->chgIData(oldp+64,(vlSelfRef.top__DOT__u_regfile__DOT__rf[30]),32);
        bufp->chgIData(oldp+65,(vlSelfRef.top__DOT__u_regfile__DOT__rf[31]),32);
    }
    bufp->chgBit(oldp+66,(vlSelfRef.clk));
    bufp->chgBit(oldp+67,(vlSelfRef.rst));
}

void Vtop___024root__trace_cleanup(void* voidSelf, VerilatedFst* /*unused*/) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_cleanup\n"); );
    // Body
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    vlSymsp->__Vm_activity = false;
    vlSymsp->TOP.__Vm_traceActivity[0U] = 0U;
    vlSymsp->TOP.__Vm_traceActivity[1U] = 0U;
}
