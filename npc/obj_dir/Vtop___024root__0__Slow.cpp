// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtop.h for the primary calling header

#include "Vtop__pch.h"

VL_ATTR_COLD void Vtop___024root___eval_static(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_static\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
}

VL_ATTR_COLD void Vtop___024root___eval_initial(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_initial\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vtop___024root___eval_final(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_final\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vtop___024root___eval_phase__stl(Vtop___024root* vlSelf);

VL_ATTR_COLD void Vtop___024root___eval_settle(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_settle\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            Vtop___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("vsrc/top.v", 4, "", "Settle region did not converge after 100 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
    } while (Vtop___024root___eval_phase__stl(vlSelf));
}

VL_ATTR_COLD void Vtop___024root___eval_triggers__stl(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_triggers__stl\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VstlTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
    vlSelfRef.__VstlFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vtop___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
}

VL_ATTR_COLD bool Vtop___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(Vtop___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool Vtop___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___trigger_anySet__stl\n"); );
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

void Vtop___024root____Vdpiimwrap_top__DOT__u_ifu__DOT__pmem_read_TOP(IData/*31:0*/ raddr, IData/*31:0*/ &pmem_read__Vfuncrtn);

VL_ATTR_COLD void Vtop___024root___stl_sequent__TOP__0(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___stl_sequent__TOP__0\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
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

VL_ATTR_COLD void Vtop___024root____Vm_traceActivitySetAll(Vtop___024root* vlSelf);

VL_ATTR_COLD void Vtop___024root___eval_stl(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_stl\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
        Vtop___024root___stl_sequent__TOP__0(vlSelf);
        Vtop___024root____Vm_traceActivitySetAll(vlSelf);
    }
}

VL_ATTR_COLD bool Vtop___024root___eval_phase__stl(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_phase__stl\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    Vtop___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = Vtop___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        Vtop___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

bool Vtop___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(Vtop___024root___trigger_anySet__act(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @(posedge clk)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vtop___024root____Vm_traceActivitySetAll(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root____Vm_traceActivitySetAll\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vm_traceActivity[0U] = 1U;
    vlSelfRef.__Vm_traceActivity[1U] = 1U;
}

VL_ATTR_COLD void Vtop___024root___ctor_var_reset(Vtop___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___ctor_var_reset\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->rst = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 18209466448985614591ull);
    vlSelf->top__DOT__pc = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 8764853023528993103ull);
    vlSelf->top__DOT__inst = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 4033626345969658743ull);
    vlSelf->top__DOT__u_ifu__DOT__pc_next = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 11604380589330422589ull);
    vlSelf->top__DOT__u_idu__DOT__is_lw = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 8761690615466674451ull);
    vlSelf->top__DOT__u_idu__DOT__is_lbu = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 14119999851399413551ull);
    vlSelf->top__DOT__u_idu__DOT__is_sw = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 9421649513353505454ull);
    vlSelf->top__DOT__u_idu__DOT__is_sb = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 329348614797551872ull);
    vlSelf->top__DOT__u_idu__DOT__mem_wen = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 11971398921833197507ull);
    vlSelf->top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5 = 0;
    for (int __Vi0 = 0; __Vi0 < 32; ++__Vi0) {
        vlSelf->top__DOT__u_regfile__DOT__rf[__Vi0] = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 11822391510231489933ull);
    }
    vlSelf->top__DOT__u_exu__DOT__rs1_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 12143105676560872862ull);
    vlSelf->top__DOT__u_exu__DOT__rs2_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 5561818497195083765ull);
    vlSelf->top__DOT__u_exu__DOT__is_add = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15059607910603340211ull);
    vlSelf->top__DOT__u_exu__DOT__is_jalr = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 9452527733227502557ull);
    vlSelf->top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0 = 0;
    vlSelf->top__DOT__u_lsu__DOT__mem_addr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 13869452673859275149ull);
    vlSelf->top__DOT__u_lsu__DOT__mem_rdata_raw = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 16159797240278957251ull);
    vlSelf->__Vfunc_top__DOT__u_ifu__DOT__pmem_read__1__Vfuncout = 0;
    vlSelf->__Vfunc_top__DOT__u_lsu__DOT__pmem_read__2__Vfuncout = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VactTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VnbaTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 2; ++__Vi0) {
        vlSelf->__Vm_traceActivity[__Vi0] = 0;
    }
}
