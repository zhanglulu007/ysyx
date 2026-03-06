// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtop.h for the primary calling header

#include "Vtop__pch.h"

extern "C" void ebreak_handler(int a0_value);

void Vtop___024root____Vdpiimwrap_top__DOT__ebreak_handler_TOP(IData/*31:0*/ a0_value) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root____Vdpiimwrap_top__DOT__ebreak_handler_TOP\n"); );
    // Body
    int a0_value__Vcvt;
    a0_value__Vcvt = a0_value;
    ebreak_handler(a0_value__Vcvt);
}

extern "C" int pmem_read(int raddr);

void Vtop___024root____Vdpiimwrap_top__DOT__u_ifu__DOT__pmem_read_TOP(IData/*31:0*/ raddr, IData/*31:0*/ &pmem_read__Vfuncrtn) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root____Vdpiimwrap_top__DOT__u_ifu__DOT__pmem_read_TOP\n"); );
    // Body
    int raddr__Vcvt;
    raddr__Vcvt = raddr;
    int pmem_read__Vfuncrtn__Vcvt;
    pmem_read__Vfuncrtn__Vcvt = pmem_read(raddr__Vcvt);
    pmem_read__Vfuncrtn = (pmem_read__Vfuncrtn__Vcvt);
}

extern "C" void pmem_write(int waddr, int wdata, char wmask);

void Vtop___024root____Vdpiimwrap_top__DOT__u_lsu__DOT__pmem_write_TOP(IData/*31:0*/ waddr, IData/*31:0*/ wdata, CData/*7:0*/ wmask) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root____Vdpiimwrap_top__DOT__u_lsu__DOT__pmem_write_TOP\n"); );
    // Body
    int waddr__Vcvt;
    waddr__Vcvt = waddr;
    int wdata__Vcvt;
    wdata__Vcvt = wdata;
    char wmask__Vcvt;
    wmask__Vcvt = wmask;
    pmem_write(waddr__Vcvt, wdata__Vcvt, wmask__Vcvt);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void Vtop___024root___eval_triggers__act(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_triggers__act\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VactTriggered[0U] = (QData)((IData)(
                                                    ((IData)(vlSelfRef.clk) 
                                                     & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__clk__0)))));
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vtop___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
}

bool Vtop___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___trigger_anySet__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

void Vtop___024root___nba_sequent__TOP__0(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___nba_sequent__TOP__0\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VdlyVal__top__DOT__u_regfile__DOT__rf__v0;
    __VdlyVal__top__DOT__u_regfile__DOT__rf__v0 = 0;
    CData/*4:0*/ __VdlyDim0__top__DOT__u_regfile__DOT__rf__v0;
    __VdlyDim0__top__DOT__u_regfile__DOT__rf__v0 = 0;
    CData/*0:0*/ __VdlySet__top__DOT__u_regfile__DOT__rf__v0;
    __VdlySet__top__DOT__u_regfile__DOT__rf__v0 = 0;
    // Body
    if ((((~ (IData)(vlSelfRef.rst)) & ((IData)(vlSelfRef.top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5) 
                                        | (IData)(vlSelfRef.top__DOT__u_idu__DOT__mem_wen))) 
         & (IData)(vlSelfRef.top__DOT__u_idu__DOT__mem_wen))) {
        if (vlSelfRef.top__DOT__u_idu__DOT__is_sw) {
            Vtop___024root____Vdpiimwrap_top__DOT__u_lsu__DOT__pmem_write_TOP(vlSelfRef.top__DOT__u_lsu__DOT__mem_addr, 
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
                                                                                >> 0x00000014U))]), 0xffU);
        } else if (vlSelfRef.top__DOT__u_idu__DOT__is_sb) {
            if ((2U & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)) {
                if ((1U & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)) {
                    Vtop___024root____Vdpiimwrap_top__DOT__u_lsu__DOT__pmem_write_TOP(vlSelfRef.top__DOT__u_lsu__DOT__mem_addr, 
                                                                                VL_SHIFTL_III(32,32,32, 
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
                                                                                >> 0x00000014U))]), 0x00000018U), 8U);
                } else {
                    Vtop___024root____Vdpiimwrap_top__DOT__u_lsu__DOT__pmem_write_TOP(vlSelfRef.top__DOT__u_lsu__DOT__mem_addr, 
                                                                                VL_SHIFTL_III(32,32,32, 
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
                                                                                >> 0x00000014U))]), 0x00000010U), 4U);
                }
            } else if ((1U & vlSelfRef.top__DOT__u_lsu__DOT__mem_addr)) {
                Vtop___024root____Vdpiimwrap_top__DOT__u_lsu__DOT__pmem_write_TOP(vlSelfRef.top__DOT__u_lsu__DOT__mem_addr, 
                                                                                VL_SHIFTL_III(32,32,32, 
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
                                                                                >> 0x00000014U))]), 8U), 2U);
            } else {
                Vtop___024root____Vdpiimwrap_top__DOT__u_lsu__DOT__pmem_write_TOP(vlSelfRef.top__DOT__u_lsu__DOT__mem_addr, 
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
                                                                                >> 0x00000014U))]), 1U);
            }
        }
    }
    if (VL_UNLIKELY((((~ (IData)(vlSelfRef.rst)) & 
                      (0x00100073U == vlSelfRef.top__DOT__inst))))) {
        VL_WRITEF_NX("EBREAK detected at PC=0x%08x, a0=0x%08x\n",0,
                     32,vlSelfRef.top__DOT__pc,32,vlSelfRef.top__DOT__u_regfile__DOT__rf
                     [0x0aU]);
        Vtop___024root____Vdpiimwrap_top__DOT__ebreak_handler_TOP(
                                                                  vlSelfRef.top__DOT__u_regfile__DOT__rf
                                                                  [0x0aU]);
    }
    __VdlySet__top__DOT__u_regfile__DOT__rf__v0 = 0U;
    if (((((IData)((0x00000013U == (0x0000707fU & vlSelfRef.top__DOT__inst))) 
           | ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr) 
              | ((0x37U == (0x0000007fU & vlSelfRef.top__DOT__inst)) 
                 | ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_add) 
                    | (IData)(vlSelfRef.top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5))))) 
          & (0U != (0x0000001fU & (vlSelfRef.top__DOT__inst 
                                   >> 7U)))) & (0U 
                                                != 
                                                (0x0000001fU 
                                                 & (vlSelfRef.top__DOT__inst 
                                                    >> 7U))))) {
        __VdlyVal__top__DOT__u_regfile__DOT__rf__v0 
            = ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr)
                ? ((IData)(4U) + vlSelfRef.top__DOT__pc)
                : ((0x37U == (0x0000007fU & vlSelfRef.top__DOT__inst))
                    ? (0xfffff000U & vlSelfRef.top__DOT__inst)
                    : (((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lbu) 
                        | (IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw))
                        ? ((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw)
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
                                : 0U)) : ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_add)
                                           ? (vlSelfRef.top__DOT__u_exu__DOT__rs1_data 
                                              + vlSelfRef.top__DOT__u_exu__DOT__rs2_data)
                                           : vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0))));
        __VdlyDim0__top__DOT__u_regfile__DOT__rf__v0 
            = (0x0000001fU & (vlSelfRef.top__DOT__inst 
                              >> 7U));
        __VdlySet__top__DOT__u_regfile__DOT__rf__v0 = 1U;
    }
    if (__VdlySet__top__DOT__u_regfile__DOT__rf__v0) {
        vlSelfRef.top__DOT__u_regfile__DOT__rf[__VdlyDim0__top__DOT__u_regfile__DOT__rf__v0] 
            = __VdlyVal__top__DOT__u_regfile__DOT__rf__v0;
    }
    vlSelfRef.top__DOT__pc = ((IData)(vlSelfRef.rst)
                               ? 0U : vlSelfRef.top__DOT__u_ifu__DOT__pc_next);
    Vtop___024root____Vdpiimwrap_top__DOT__u_ifu__DOT__pmem_read_TOP(vlSelfRef.top__DOT__pc, vlSelfRef.__Vfunc_top__DOT__u_ifu__DOT__pmem_read__1__Vfuncout);
    vlSelfRef.top__DOT__inst = vlSelfRef.__Vfunc_top__DOT__u_ifu__DOT__pmem_read__1__Vfuncout;
    vlSelfRef.top__DOT__u_exu__DOT__is_add = (IData)(
                                                     (0x00000033U 
                                                      == 
                                                      (0xfe00707fU 
                                                       & vlSelfRef.top__DOT__inst)));
    vlSelfRef.top__DOT__u_exu__DOT__rs2_data = ((0U 
                                                 == 
                                                 (0x0000001fU 
                                                  & (vlSelfRef.top__DOT__inst 
                                                     >> 0x00000014U)))
                                                 ? 0U
                                                 : 
                                                vlSelfRef.top__DOT__u_regfile__DOT__rf
                                                [(0x0000001fU 
                                                  & (vlSelfRef.top__DOT__inst 
                                                     >> 0x00000014U))]);
    vlSelfRef.top__DOT__u_exu__DOT__is_jalr = (IData)(
                                                      (0x00000067U 
                                                       == 
                                                       (0x0000707fU 
                                                        & vlSelfRef.top__DOT__inst)));
    vlSelfRef.top__DOT__u_idu__DOT__is_lw = (IData)(
                                                    (0x00002003U 
                                                     == 
                                                     (0x0000707fU 
                                                      & vlSelfRef.top__DOT__inst)));
    vlSelfRef.top__DOT__u_idu__DOT__is_lbu = (IData)(
                                                     (0x00004003U 
                                                      == 
                                                      (0x0000707fU 
                                                       & vlSelfRef.top__DOT__inst)));
    vlSelfRef.top__DOT__u_idu__DOT__is_sw = (IData)(
                                                    (0x00002023U 
                                                     == 
                                                     (0x0000707fU 
                                                      & vlSelfRef.top__DOT__inst)));
    vlSelfRef.top__DOT__u_idu__DOT__is_sb = (IData)(
                                                    (0x00000023U 
                                                     == 
                                                     (0x0000707fU 
                                                      & vlSelfRef.top__DOT__inst)));
    vlSelfRef.top__DOT__u_exu__DOT__rs1_data = ((0U 
                                                 == 
                                                 (0x0000001fU 
                                                  & (vlSelfRef.top__DOT__inst 
                                                     >> 0x0000000fU)))
                                                 ? 0U
                                                 : 
                                                vlSelfRef.top__DOT__u_regfile__DOT__rf
                                                [(0x0000001fU 
                                                  & (vlSelfRef.top__DOT__inst 
                                                     >> 0x0000000fU))]);
    vlSelfRef.top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5 
        = ((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lw) 
           | (IData)(vlSelfRef.top__DOT__u_idu__DOT__is_lbu));
    vlSelfRef.top__DOT__u_idu__DOT__mem_wen = ((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_sw) 
                                               | (IData)(vlSelfRef.top__DOT__u_idu__DOT__is_sb));
    vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0 
        = ((((- (IData)((vlSelfRef.top__DOT__inst >> 0x0000001fU))) 
             << 0x0000000cU) | (vlSelfRef.top__DOT__inst 
                                >> 0x00000014U)) + vlSelfRef.top__DOT__u_exu__DOT__rs1_data);
    vlSelfRef.top__DOT__u_ifu__DOT__pc_next = ((0x00100073U 
                                                == vlSelfRef.top__DOT__inst)
                                                ? vlSelfRef.top__DOT__pc
                                                : ((IData)(vlSelfRef.top__DOT__u_exu__DOT__is_jalr)
                                                    ? 
                                                   (0xfffffffeU 
                                                    & vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0)
                                                    : 
                                                   ((IData)(4U) 
                                                    + vlSelfRef.top__DOT__pc)));
    vlSelfRef.top__DOT__u_lsu__DOT__mem_addr = (((IData)(vlSelfRef.top__DOT__u_idu__DOT__is_sb) 
                                                 | (IData)(vlSelfRef.top__DOT__u_idu__DOT__is_sw))
                                                 ? 
                                                ((((- (IData)(
                                                              (vlSelfRef.top__DOT__inst 
                                                               >> 0x0000001fU))) 
                                                   << 0x0000000cU) 
                                                  | ((0x00000fe0U 
                                                      & (vlSelfRef.top__DOT__inst 
                                                         >> 0x00000014U)) 
                                                     | (0x0000001fU 
                                                        & (vlSelfRef.top__DOT__inst 
                                                           >> 7U)))) 
                                                 + vlSelfRef.top__DOT__u_exu__DOT__rs1_data)
                                                 : vlSelfRef.top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0);
    if ((((IData)(vlSelfRef.top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5) 
          | (IData)(vlSelfRef.top__DOT__u_idu__DOT__mem_wen)) 
         & (~ (IData)(vlSelfRef.top__DOT__u_idu__DOT__mem_wen)))) {
        Vtop___024root____Vdpiimwrap_top__DOT__u_ifu__DOT__pmem_read_TOP(vlSelfRef.top__DOT__u_lsu__DOT__mem_addr, vlSelfRef.__Vfunc_top__DOT__u_lsu__DOT__pmem_read__2__Vfuncout);
        vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw 
            = vlSelfRef.__Vfunc_top__DOT__u_lsu__DOT__pmem_read__2__Vfuncout;
    } else {
        vlSelfRef.top__DOT__u_lsu__DOT__mem_rdata_raw = 0U;
    }
}

void Vtop___024root___eval_nba(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_nba\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vtop___024root___nba_sequent__TOP__0(vlSelf);
        vlSelfRef.__Vm_traceActivity[1U] = 1U;
    }
}

void Vtop___024root___trigger_orInto__act(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___trigger_orInto__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vtop___024root___eval_phase__act(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_phase__act\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vtop___024root___eval_triggers__act(vlSelf);
    Vtop___024root___trigger_orInto__act(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    return (0U);
}

void Vtop___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vtop___024root___eval_phase__nba(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_phase__nba\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vtop___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        Vtop___024root___eval_nba(vlSelf);
        Vtop___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void Vtop___024root___eval(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VnbaIterCount;
    // Body
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vtop___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("vsrc/top.v", 4, "", "NBA region did not converge after 100 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00000064U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vtop___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("vsrc/top.v", 4, "", "Active region did not converge after 100 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
        } while (Vtop___024root___eval_phase__act(vlSelf));
    } while (Vtop___024root___eval_phase__nba(vlSelf));
}

#ifdef VL_DEBUG
void Vtop___024root___eval_debug_assertions(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_debug_assertions\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.clk & 0xfeU)))) {
        Verilated::overWidthError("clk");
    }
    if (VL_UNLIKELY(((vlSelfRef.rst & 0xfeU)))) {
        Verilated::overWidthError("rst");
    }
}
#endif  // VL_DEBUG
