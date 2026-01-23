// DESCRIPTION: Verilator: Verilog example module
//
// This file ONLY is placed under the Creative Commons Public Domain, for
// any use, without warranty, 2017 by Wilson Snyder.
// SPDX-License-Identifier: CC0-1.0
//======================================================================

#include <iostream>
#include <nvboard.h>
#include <verilated.h>
#include <verilated_fst_c.h>
#include "Vtop.h"

int main(int argc, char** argv) {
    
    VerilatedContext* const contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vtop* const top = new Vtop{contextp};
    nvboard_bind_all_pins(&top);
    Verilated::traceEverOn(true);
    VerilatedFstC* tfp = new VerilatedFstC;
    top->trace(tfp, 99); 
    tfp->open("wave/dump.fst");
    
    int cycles = 100;
    
    while (!contextp->gotFinish() && cycles--) {

        contextp->timeInc(1); 


        top->eval();
        
        tfp->dump(contextp->time());

    }

    top->final();
    tfp->close();

    delete top;
    delete tfp;
    delete contextp;

    return 0;
}

