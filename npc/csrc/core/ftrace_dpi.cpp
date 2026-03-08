/***************************************************************************************
* NPC FTRACE DPI-C Interface
* FTRACE的DPI-C接口实现
***************************************************************************************/

#include "ftrace_dpi.h"
#include "../trace/ftrace.h"

// DPI-C函数：ftrace函数调用处理
extern "C" void ftrace_call_handler(int pc_val, int target_val) {
    ftrace_call(pc_val, target_val);
}

// DPI-C函数：ftrace函数返回处理
extern "C" void ftrace_ret_handler(int pc_val) {
    ftrace_ret(pc_val);
}
