/***************************************************************************************
* NPC - RISC-V Processor Simulator
* 主程序入口
***************************************************************************************/

#include <cstdio>
#include <cstring>
#include "core/npc.h"
#include "core/cpu.h"
#include "core/memory.h"
#include "core/device.h"
#include "core/reg.h"
#include "sdb/sdb.h"
#include "utils/log.h"
#include "utils/difftest.h"

#ifdef ENABLE_TRACE
#include "trace/itrace.h"
#include "trace/mtrace.h"
#include "trace/ftrace.h"
#endif

// 打印使用说明
static void print_usage(const char* prog_name) {
    printf("Usage: %s <program.bin> [-b] [-l log_file] [-e elf_file] [-d ref_so]\n", prog_name);
    printf("  -b: batch mode (non-interactive)\n");
    printf("  -l log_file: specify log file (default: npc.log)\n");
    printf("  -e elf_file: specify ELF file for ftrace\n");
    printf("  -d ref_so: specify REF shared object for DiffTest\n");
    printf("Example: %s build/dummy-riscv32e-npc.bin\n", prog_name);
}

// 解析命令行参数
static bool parse_args(int argc, char** argv, 
                      const char** program_file,
                      bool* batch_mode,
                      const char** log_file,
                      const char** elf_file,
                      const char** ref_so_file) {
    if (argc < 2) {
        return false;
    }
    
    *program_file = argv[1];
    *batch_mode = false;
    *log_file = NULL;
    *elf_file = NULL;
    *ref_so_file = NULL;
    
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
        }
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
    
    // 解析命令行参数
    if (!parse_args(argc, argv, &program_file, &batch_mode, &log_file, &elf_file, &ref_so_file)) {
        print_usage(argv[0]);
        return 1;
    }
    
    // 初始化子系统
    init_subsystems(log_file, elf_file);

    Log("NPC - RISC-V processor simulator with Simple Debugger");
    Log("Build time: %s, %s", __TIME__, __DATE__);

    // 打印欢迎信息
    print_welcome();

    // // 加载程序
    // if (!load_program(program_file)) {
    //     return 1;
    // }

    // // 将程序镜像同时作为 MROM 内容 (NPC 复位后从 0x20000000 取指)
    // if (!mrom_load(program_file)) {
    //     return 1;
    // }

    flash_init(program_file);

    printf("\n");

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
    
    Log("Starting simulation from PC=0x%08x", FLASH_BASE);
    
    // 进入sdb主循环
    sdb_mainloop();
    
    // 打印退出信息
    Log("Simulation finished");
    printf("\nSimulation finished.\n");
    print_exit_info();
    
    // 清理资源
    cleanup_cpu();
    
    return npc_get_exit_code();
}
