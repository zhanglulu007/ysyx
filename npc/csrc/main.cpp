#include <cstdio>
#include <cstring>
#include "core/npc.h"
#include "core/cpu.h"
#include "core/memory.h"
#include "core/device.h"
#include "core/perf.h"
#include "core/reg.h"
#include "sdb/sdb.h"
#include "utils/log.h"
#include "utils/difftest.h"
#include "trace/trace_config.h"

#ifdef ENABLE_TRACE
#include "trace/itrace.h"
#include "trace/mtrace.h"
#include "trace/ftrace.h"
#include "trace/trace_manager.h"
#include <cstdlib>
#include <csignal>
#endif

static void print_usage(const char* prog_name) {
    printf("Usage: %s <program.bin> [-b] [-l log_file] [-e elf_file] [-d ref_so]\n", prog_name);
    printf("       [--trace=TYPES] [--trace-out=FILE] [--trace-text=MODE]\n");
    printf("       [--trace-range=BEG-END ...] [--trace-outside=drop|ring|critical]\n");
    printf("       [--trace-range-unit=cycle|commit] [--trace-ring=N]\n");
    printf("       [--log-file=FILE] [--log-level=error|warn|info|debug|trace]\n");
    printf("  -b: batch mode (non-interactive)\n");
    printf("  -l log_file: specify log file (default: npc.log)\n");
    printf("  -e elf_file: specify ELF file for ftrace\n");
    printf("  -d ref_so: specify REF shared object for DiffTest\n");
    printf("  --trace=TYPES: comma list from itrace,mtrace,ftrace,etrace,ctrace,\n");
    printf("                 dtrace,atrace,btrace,difftest,perf,all\n");
    printf("                 (default when TRACE=1: itrace,mtrace,ftrace)\n");
    printf("  --trace-text=MODE: deferred|live|both|off\n");
    printf("Example: %s build/dummy-riscv32e-npc.bin\n", prog_name);
}

static bool parse_args(int argc, char** argv, 
                      const char** program_file,
                      bool* batch_mode,
                      const char** log_file,
                      const char** elf_file,
                      const char** ref_so_file,
                      npctrace::TraceCliConfig* trace_cfg) {
    if (argc < 2) {
        return false;
    }
    
    *program_file = argv[1];
    *batch_mode = false;
    *log_file = NULL;
    *elf_file = NULL;
    *ref_so_file = NULL;
    
    std::string err;
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-b") == 0) {
            *batch_mode = true;
        } else if (strcmp(argv[i], "-l") == 0 && i + 1 < argc) {
            *log_file = argv[i + 1];
            i++;
        } else if (strcmp(argv[i], "-e") == 0 && i + 1 < argc) {
            *elf_file = argv[i + 1];
            i++;
        } else if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) {
            *ref_so_file = argv[i + 1];
            i++;
        } else if (npctrace::is_trace_option(argv[i])) {
            if (!npctrace::parse_trace_option(argc, argv, &i, trace_cfg, &err)) {
                fprintf(stderr, "ERROR: %s\n", err.c_str());
                return false;
            }
        } else if (strncmp(argv[i], "--trace", 7) == 0 ||
                   strncmp(argv[i], "--log", 5) == 0) {
            // 以 --trace/--log 开头但不认识: 大概率是拼错, 明确报错而不是静默忽略
            fprintf(stderr, "ERROR: unknown option '%s'\n", argv[i]);
            return false;
        }
        // 其余参数(如 Verilator 的 +args)保持原有宽容行为
    }

    if (!npctrace::finalize_trace_config(trace_cfg, &err)) {
        fprintf(stderr, "ERROR: %s\n", err.c_str());
        return false;
    }
    
    return true;
}

static bool init_subsystems(const char* log_file, const char* elf_file) {
    init_log(log_file);

#ifdef ENABLE_TRACE
    init_itrace();
    init_mtrace();
    init_ftrace(elf_file);
#endif

    init_device();
    init_sdb();
    return true;
}

// 初始化DiffTest
static void init_difftest_if_needed(const char* ref_so_file, const char* program_file) {
    if (ref_so_file != NULL) {
        // 获取程序大小
        FILE* fp = fopen(program_file, "rb");
        if (fp) {
            fseek(fp, 0, SEEK_END);
            long img_size = ftell(fp);
            fclose(fp);
            init_difftest(ref_so_file, img_size);
        }
    } else {
        Log("DiffTest is disabled (no REF specified)");
        printf("DiffTest: OFF\n\n");
    }
}

static void print_welcome() {
    printf("NPC - RISC-V processor simulator with Simple Debugger\n");
    printf("======================================================\n\n");
}

#ifdef ENABLE_TRACE
#ifndef NPC_GIT_COMMIT
#define NPC_GIT_COMMIT ""
#endif

// 收集 trace.npct 的 meta(配置 + 程序信息)
static npctrace::TraceMeta build_trace_meta(const char* program_file,
                                            const char* elf_file) {
    npctrace::TraceMeta meta;
#ifdef SOC_MODE
    meta.soc = true;
#else
    meta.soc = false;
#endif
    meta.program = program_file ? program_file : "";
    meta.elf = elf_file ? elf_file : "";
    meta.git_commit = NPC_GIT_COMMIT;
    meta.cycle_per_time = 2;   // exec_once 每 cycle 调 2 次 eval_half_cycle
    return meta;
}

// 进程异常退出(如 DiffTest 失败 exit(1))时也把 trace.npct 收尾, 避免留下半截文件
static void trace_atexit_shutdown() {
    npctrace::TraceManager::instance().shutdown();
}

// SIGINT/SIGTERM: 先落一份失败快照, 再按默认语义退出
static void trace_signal_handler(int sig) {
    npctrace::TraceManager::instance().dump_snapshot(
        sig == SIGINT ? "SIGINT" : "SIGTERM");
    signal(sig, SIG_DFL);
    raise(sig);
}
#endif

static void print_exit_info() {
    if (npc_should_exit()) {
        uint32_t exit_code = npc_get_exit_code();
        Log("Exit reason: EBREAK instruction (program completed)");
        Log("Exit code: %d", exit_code);
        printf("Exit reason: EBREAK instruction (program completed)\n");
        printf("Exit code: %d\n", exit_code);

        if (exit_code != 0) {
#ifdef ENABLE_TRACE
            display_iringbuf();
#endif
        }
    }
}

int main(int argc, char** argv) {
    const char* program_file;
    bool batch_mode;
    const char* log_file;
    const char* elf_file;
    const char* ref_so_file;
    npctrace::TraceCliConfig trace_cfg;
    
    // 解析命令行参数
    if (!parse_args(argc, argv, &program_file, &batch_mode, &log_file, &elf_file, &ref_so_file, &trace_cfg)) {
        print_usage(argv[0]);
        return 1;
    }
    
    // --log-file 优先于 -l
    if (!trace_cfg.log_file.empty()) {
        log_file = trace_cfg.log_file.c_str();
    }

    // 初始化子系统
    init_subsystems(log_file, elf_file);
    
    Log("NPC - RISC-V processor simulator with Simple Debugger");
    Log("Build time: %s, %s", __TIME__, __DATE__);
    
    // 打印 trace/log 配置摘要 (M0: 仅解析与展示, 采集在 M1 接入)
#ifdef ENABLE_TRACE
    if (trace_cfg.enabled) {
        Log("Trace CLI config:\n%s", npctrace::trace_cli_summary(trace_cfg).c_str());
        printf("Trace config:\n%s", npctrace::trace_cli_summary(trace_cfg).c_str());
    } else {
        Log("Trace: default itrace/mtrace/ftrace (no --trace-* given)");
    }
#else
    if (trace_cfg.enabled) {
        Log("Warning: --trace-* given but binary built with TRACE=0; no trace output");
        printf("Warning: --trace-* given but binary built with TRACE=0; no trace output.\n");
        printf("         Rebuild with TRACE=1 to enable trace.\n");
    }
#endif

#ifdef ENABLE_PERF
    Log("PERF: ON (PERF=1 build)");
#else
    Log("PERF: OFF");
#endif

    // 打印欢迎信息
    print_welcome();
    
#ifdef SOC_MODE
    if (!flash_load(program_file)) return 1;
#else
    if (!load_program(program_file)) return 1;   
#endif
    
    printf("\n");

#ifdef ENABLE_TRACE
    // 初始化二进制 trace(仅在显式 --trace-* 或 TRACE=1 下启用)
    {
        npctrace::TraceMeta meta = build_trace_meta(program_file, elf_file);
        std::string terr;
        if (npctrace::TraceManager::instance().init(trace_cfg, meta, &terr)) {
            std::atexit(trace_atexit_shutdown);
            std::signal(SIGINT, trace_signal_handler);
            std::signal(SIGTERM, trace_signal_handler);
            Log("Trace binary output: %s", trace_cfg.out_file.c_str());
            printf("Trace binary   : %s\n", trace_cfg.out_file.c_str());
        } else if (trace_cfg.enabled) {
            Log("ERROR: cannot open trace output: %s", terr.c_str());
            printf("ERROR: cannot open trace output '%s': %s\n",
                   trace_cfg.out_file.c_str(), terr.c_str());
            return 1;
        }
    }
#endif

    // 初始化CPU
    if (!init_cpu(argc, argv)) {
        return 1;
    }
    
    // 复位CPU
    reset_cpu();
    
    // 初始化DiffTest
    init_difftest_if_needed(ref_so_file, program_file);
    
    // 设置批处理模式
    if (batch_mode) {
        sdb_set_batch_mode();
        Log("Running in batch mode");
        printf("Running in batch mode...\n\n");
    } else {
        printf("Entering interactive mode. Type 'help' for commands.\n\n");
    }
    
    Log("Starting simulation from PC=0x%08x", npc_get_pc());
    
    // 进入sdb主循环
    sdb_mainloop();
    
    // 打印退出信息
    Log("Simulation finished");
    printf("\nSimulation finished.\n");
    print_exit_info();

#ifdef ENABLE_PERF
    // 仿真结束时打印性能报告 (仅 PERF=1 构建)
    perf_report();
#endif

#ifdef ENABLE_TRACE
    // 收尾 trace.npct(拼接/回填/改名)。atexit 也会兜底, 这里先正常关闭。
    npctrace::TraceManager::instance().shutdown();
    {
        auto& tm = npctrace::TraceManager::instance();
        Log("Trace written: %s (events=%llu itrace=%llu dropped=%llu)",
            tm.out_path().c_str(),
            (unsigned long long)tm.event_count(),
            (unsigned long long)tm.itrace_count(),
            (unsigned long long)tm.dropped_count());
    }
#endif

    // 清理资源
    cleanup_cpu();
    
    return npc_get_exit_code();
}
