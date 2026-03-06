// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtop.h for the primary calling header

#ifndef VERILATED_VTOP___024ROOT_H_
#define VERILATED_VTOP___024ROOT_H_  // guard

#include "verilated.h"


class Vtop__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtop___024root final {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(clk,0,0);
    VL_IN8(rst,0,0);
    CData/*0:0*/ top__DOT__u_idu__DOT__is_lw;
    CData/*0:0*/ top__DOT__u_idu__DOT__is_lbu;
    CData/*0:0*/ top__DOT__u_idu__DOT__is_sw;
    CData/*0:0*/ top__DOT__u_idu__DOT__is_sb;
    CData/*0:0*/ top__DOT__u_idu__DOT__mem_wen;
    CData/*0:0*/ top__DOT__u_idu__DOT____VdfgRegularize_h52656aab_0_5;
    CData/*0:0*/ top__DOT__u_exu__DOT__is_add;
    CData/*0:0*/ top__DOT__u_exu__DOT__is_jalr;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
    IData/*31:0*/ top__DOT__pc;
    IData/*31:0*/ top__DOT__inst;
    IData/*31:0*/ top__DOT__u_ifu__DOT__pc_next;
    IData/*31:0*/ top__DOT__u_exu__DOT__rs1_data;
    IData/*31:0*/ top__DOT__u_exu__DOT__rs2_data;
    IData/*31:0*/ top__DOT__u_exu__DOT____VdfgRegularize_haeb391f3_0_0;
    IData/*31:0*/ top__DOT__u_lsu__DOT__mem_addr;
    IData/*31:0*/ top__DOT__u_lsu__DOT__mem_rdata_raw;
    IData/*31:0*/ __Vfunc_top__DOT__u_ifu__DOT__pmem_read__1__Vfuncout;
    IData/*31:0*/ __Vfunc_top__DOT__u_lsu__DOT__pmem_read__2__Vfuncout;
    IData/*31:0*/ __VactIterCount;
    VlUnpacked<IData/*31:0*/, 32> top__DOT__u_regfile__DOT__rf;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;
    VlUnpacked<CData/*0:0*/, 2> __Vm_traceActivity;

    // INTERNAL VARIABLES
    Vtop__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vtop___024root(Vtop__Syms* symsp, const char* namep);
    ~Vtop___024root();
    VL_UNCOPYABLE(Vtop___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
