#include "core/npc.h"
#include "trace/ftrace.h"

extern "C" void ftrace_call_handler(int pc_val, int target_val) {
#ifdef ENABLE_TRACE
    ftrace_call(static_cast<uint32_t>(pc_val), static_cast<uint32_t>(target_val));
#else
    (void)pc_val;
    (void)target_val;
#endif
}

extern "C" void ftrace_ret_handler(int pc_val, int target_val) {
#ifdef ENABLE_TRACE
    ftrace_ret(static_cast<uint32_t>(pc_val), static_cast<uint32_t>(target_val));
#else
    (void)pc_val;
    (void)target_val;
#endif
}
