/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <cpu/cpu.h>
#include <cpu/decode.h>
#include <cpu/difftest.h>
#include <locale.h>
#include <string.h>
#include <stdio.h>
#include "../monitor/sdb/sdb.h"

/* The assembly code of instructions executed is only output to the screen
 * when the number of instructions executed is less than this value.
 * This is useful when you use the `si' command.
 * You can modify this value as you want.
 */
#define MAX_INST_TO_PRINT 10
#define IRINGBUF_SIZE 16

CPU_state cpu = {};
uint64_t g_nr_guest_inst = 0;
static uint64_t g_timer = 0; // unit: us
static bool g_print_step = false;

void device_update();
#ifdef CONFIG_ITRACE
typedef struct {
  vaddr_t pc;
  uint32_t inst;
  char logbuf[128];
} IringBufEntry;

static IringBufEntry iringbuf[IRINGBUF_SIZE];
static int iringbuf_idx = 0;
static bool iringbuf_full = false;

static void iringbuf_write(vaddr_t pc, uint32_t inst, const char *logbuf) {
  iringbuf[iringbuf_idx].pc = pc;
  iringbuf[iringbuf_idx].inst = inst;
  size_t len = strlen(logbuf);
  if (len >= sizeof(iringbuf[iringbuf_idx].logbuf)) {
    len = sizeof(iringbuf[iringbuf_idx].logbuf) - 1;
  }
  memcpy(iringbuf[iringbuf_idx].logbuf, logbuf, len);
  iringbuf[iringbuf_idx].logbuf[len] = '\0';
  
  iringbuf_idx = (iringbuf_idx + 1) % IRINGBUF_SIZE;
  if (iringbuf_idx == 0) {
    iringbuf_full = true;
  }
}

void display_iringbuf() {
  printf("\n" ANSI_FMT("Recent executed instructions (iringbuf):", ANSI_FG_CYAN) "\n");
  
  int start = iringbuf_full ? iringbuf_idx : 0;
  int count = iringbuf_full ? IRINGBUF_SIZE : iringbuf_idx;
  
  if (count == 0) {
    printf("  (empty)\n");
    return;
  }
  
  for (int i = 0; i < count; i++) {
    int idx = (start + i) % IRINGBUF_SIZE;
    
    // 标记最后一条指令（出错的指令）
    if (i == count - 1) {
      printf(ANSI_FMT("-->", ANSI_FG_RED) " %s\n", iringbuf[idx].logbuf);
    } else {
      printf("    %s\n", iringbuf[idx].logbuf);
    }
  }
  printf("\n");
}
#endif

#ifdef CONFIG_ITRACE
static FILE *itrace_fp = NULL;       /* RLE 输出文件 (复用 -l 指定的 log_fp) */
static bool  itrace_active = false;  /* 是否启用 RLE 输出 */
static vaddr_t rle_seg_pc = 0;       /* 当前顺序段的起始 PC */
static uint32_t rle_seg_cnt = 0;     /* 当前顺序段已累计的指令数 */
static bool rle_have_seg = false;    /* 当前是否有未 flush 的段 */
static vaddr_t rle_prev_snpc = 0;    /* 上一条指令的静态下一条 PC (用于判断顺序连续) */

#ifdef CONFIG_ISA_riscv
static FILE *btrace_fp = NULL;
static bool  btrace_active = false;
static uint64_t btrace_branch_count = 0;
#endif

/* flush 当前顺序段为一个 record 写入文件 */
static void itracerle_flush_seg() {
  if (!itrace_active || !rle_have_seg) return;
  /* 定长 record: pc(4) + count(4) */
  fwrite(&rle_seg_pc,   sizeof(rle_seg_pc),   1, itrace_fp);
  fwrite(&rle_seg_cnt,  sizeof(rle_seg_cnt),  1, itrace_fp);
  rle_have_seg = false;
}

static void itracerle_step(vaddr_t pc, vaddr_t snpc, vaddr_t dnpc) {
  if (!itrace_active) return;
  /* 顺序连续判定: 本条 pc == 上一条的静态下一条 snpc (即上一条未跳转, 顺序流到本条) */
  if (rle_have_seg && pc == rle_prev_snpc) {
    rle_seg_cnt++;
  } else {
    /* 段首 或 上一条发生跳转(其 dnpc != snpc, 故本条 pc != rle_prev_snpc): 开新段 */
    itracerle_flush_seg();
    rle_seg_pc = pc;
    rle_seg_cnt = 1;
    rle_have_seg = true;
  }
  rle_prev_snpc = snpc;  /* 记录本条 snpc 供下一条判定 */
  (void)dnpc;            /* dnpc 由下一条的 pc 与 rle_prev_snpc 的比较间接体现 */
}

/* 初始化: 传入 -l 指定的 log 文件路径, 派生 .bin 路径并独立 fopen.
 * 例: log_path="run.log" -> itrace 写到 "run.bin"; "/tmp/x.txt" -> "/tmp/x.bin".
 * log_path 为 NULL 时不启用 RLE 输出. */
void init_itracerle(const char *log_path) {
  itrace_fp = NULL;
  itrace_active = false;
  rle_seg_pc = 0;
  rle_seg_cnt = 0;
  rle_have_seg = false;
  rle_prev_snpc = 0;
  if (log_path == NULL) return;

  /* 派生 .bin 路径: 去掉原后缀(若有), 加 .bin */
  char bin_path[4096];
  size_t n = strlen(log_path);
  if (n >= sizeof(bin_path)) n = sizeof(bin_path) - 5;
  memcpy(bin_path, log_path, n);
  bin_path[n] = '\0';
  /* 去掉最后一个 '.' 之后的扩展名 (仅当 '.' 在最后一个路径分隔符之后) */
  char *dot = strrchr(bin_path, '.');
  const char *slash = strrchr(bin_path, '/');
  if (dot && (!slash || dot > slash)) *dot = '\0';
  if (strlen(bin_path) + 4 >= sizeof(bin_path)) return;
  strcat(bin_path, ".bin");

  itrace_fp = fopen(bin_path, "wb");
  if (itrace_fp == NULL) {
    fprintf(stderr, "[itracerle] cannot open %s for writing, RLE itrace disabled\n", bin_path);
    return;
  }
  itrace_active = true;
  Log("binary RLE itrace -> %s", bin_path);
}

#ifdef CONFIG_ISA_riscv
void init_btrace(const char *log_path) {
  btrace_fp = NULL;
  btrace_active = false;
  btrace_branch_count = 0;
  if (log_path == NULL) return;

  char btrace_path[4096];
  size_t n = strlen(log_path);
  if (n >= sizeof(btrace_path)) n = sizeof(btrace_path) - 8;
  memcpy(btrace_path, log_path, n);
  btrace_path[n] = '\0';
  char *dot = strrchr(btrace_path, '.');
  const char *slash = strrchr(btrace_path, '/');
  if (dot && (!slash || dot > slash)) *dot = '\0';
  if (strlen(btrace_path) + strlen(".btrace") >= sizeof(btrace_path)) return;
  strcat(btrace_path, ".btrace");

  btrace_fp = fopen(btrace_path, "w");
  if (btrace_fp == NULL) {
    fprintf(stderr, "[btrace] cannot open %s for writing, btrace disabled\n", btrace_path);
    return;
  }
  fprintf(btrace_fp, "# branchsim-btrace v1\n");
  fprintf(btrace_fp, "# fields: pc instruction taken\n");
  btrace_active = true;
  Log("branchsim btrace -> %s", btrace_path);
}

static bool btrace_is_conditional_branch(uint32_t inst) {
  if ((inst & 0x7fu) != 0x63u) return false;
  switch ((inst >> 12) & 0x7u) {
    case 0x0: case 0x1: case 0x4: case 0x5: case 0x6: case 0x7:
      return true;
    default:
      return false;
  }
}

static bool btrace_branch_taken(uint32_t inst) {
  unsigned int rs1 = (inst >> 15) & 0x1fu;
  unsigned int rs2 = (inst >> 20) & 0x1fu;
  word_t lhs = rs1 == 0 ? 0 : cpu.gpr[rs1];
  word_t rhs = rs2 == 0 ? 0 : cpu.gpr[rs2];

  switch ((inst >> 12) & 0x7u) {
    case 0x0: return lhs == rhs;                 /* beq  */
    case 0x1: return lhs != rhs;                 /* bne  */
    case 0x4: return (sword_t)lhs < (sword_t)rhs;/* blt  */
    case 0x5: return (sword_t)lhs >= (sword_t)rhs;/* bge */
    case 0x6: return lhs < rhs;                  /* bltu */
    case 0x7: return lhs >= rhs;                 /* bgeu */
    default:  return false;
  }
}

static void btrace_step(const Decode *s) {
  if (!btrace_active) return;

  uint32_t inst = s->isa.inst;
  if (!btrace_is_conditional_branch(inst)) return;

  int taken = btrace_branch_taken(inst);
  fprintf(btrace_fp, "0x%08" PRIx32 " 0x%08" PRIx32 " %d\n",
          (uint32_t)s->pc, inst, taken);
  btrace_branch_count++;
}
#endif

/* 程序结束/退出时调用: flush 最后一个未写出的段 */
void finish_itracerle() {
  if (!itrace_active) return;
  itracerle_flush_seg();
  if (itrace_fp) { fflush(itrace_fp); fclose(itrace_fp); }
  itrace_active = false;
}

#ifdef CONFIG_ISA_riscv
void finish_btrace() {
  if (!btrace_active) return;
  fprintf(btrace_fp, "# total-instructions=%" PRIu64 "\n", g_nr_guest_inst);
  fprintf(btrace_fp, "# conditional-branches=%" PRIu64 "\n", btrace_branch_count);
  fflush(btrace_fp);
  fclose(btrace_fp);
  btrace_fp = NULL;
  btrace_active = false;
}
#endif
#endif /* CONFIG_ITRACE */

static void trace_and_difftest(Decode *_this, vaddr_t dnpc) {

#ifdef CONFIG_ITRACE
  /* 二进制 RLE itrace: 用本条 pc/snpc/dnpc 推进 RLE 状态机 */
  itracerle_step(_this->pc, _this->snpc, _this->dnpc);
#ifdef CONFIG_ISA_riscv
  btrace_step(_this);
#endif
#endif

  if (g_print_step) { IFDEF(CONFIG_ITRACE, puts(_this->logbuf)); }

  IFDEF(CONFIG_DIFFTEST, difftest_step(_this->pc, dnpc));

#ifdef CONFIG_WATCHPOINT
  if (check_watchpoints()) {
    if (nemu_state.state != NEMU_END) nemu_state.state = NEMU_STOP;
  }
#endif
}

static void exec_once(Decode *s, vaddr_t pc) {
  s->pc = pc;
  s->snpc = pc;
  isa_exec_once(s);
  cpu.pc = s->dnpc;
#ifdef CONFIG_ITRACE
  char *p = s->logbuf;
  p += snprintf(p, sizeof(s->logbuf), FMT_WORD ":", s->pc);
  int ilen = s->snpc - s->pc;
  int i;
  uint8_t *inst = (uint8_t *)&s->isa.inst;
#ifdef CONFIG_ISA_x86
  for (i = 0; i < ilen; i ++) {
#else
  for (i = ilen - 1; i >= 0; i --) {
#endif
    p += snprintf(p, 4, " %02x", inst[i]);
  }
  int ilen_max = MUXDEF(CONFIG_ISA_x86, 8, 4);
  int space_len = ilen_max - ilen;
  if (space_len < 0) space_len = 0;
  space_len = space_len * 3 + 1;
  memset(p, ' ', space_len);
  p += space_len;

  void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);
  disassemble(p, s->logbuf + sizeof(s->logbuf) - p,
      MUXDEF(CONFIG_ISA_x86, s->snpc, s->pc), (uint8_t *)&s->isa.inst, ilen);
#endif
  
  // 将指令写入环形缓冲区
  IFDEF(CONFIG_ITRACE, iringbuf_write(s->pc, s->isa.inst, s->logbuf));
}

static void execute(uint64_t n) {
  Decode s;
  for (;n > 0; n --) {
    exec_once(&s, cpu.pc);
    g_nr_guest_inst ++;
    trace_and_difftest(&s, cpu.pc);
    if (nemu_state.state != NEMU_RUNNING) break;
    IFDEF(CONFIG_DEVICE, device_update());
  }
}

static void statistic() {
  IFNDEF(CONFIG_TARGET_AM, setlocale(LC_NUMERIC, ""));
#define NUMBERIC_FMT MUXDEF(CONFIG_TARGET_AM, "%", "%'") PRIu64
  Log("host time spent = " NUMBERIC_FMT " us", g_timer);
  Log("total guest instructions = " NUMBERIC_FMT, g_nr_guest_inst);
  if (g_timer > 0) Log("simulation frequency = " NUMBERIC_FMT " inst/s", g_nr_guest_inst * 1000000 / g_timer);
  else Log("Finish running in less than 1 us and can not calculate the simulation frequency");
}

void assert_fail_msg() {
  IFDEF(CONFIG_ITRACE, display_iringbuf());
  isa_reg_display();
  statistic();
}

/* Simulate how the CPU works. */
void cpu_exec(uint64_t n) {
  g_print_step = (n < MAX_INST_TO_PRINT);
  switch (nemu_state.state) {
    case NEMU_END: case NEMU_ABORT: case NEMU_QUIT:
      printf("Program execution has ended. To restart the program, exit NEMU and run again.\n");
      return;
    default: nemu_state.state = NEMU_RUNNING;
  }

  uint64_t timer_start = get_time();

  execute(n);

  uint64_t timer_end = get_time();
  g_timer += timer_end - timer_start;

  switch (nemu_state.state) {
    case NEMU_RUNNING: nemu_state.state = NEMU_STOP; break;

    case NEMU_END: case NEMU_ABORT:
      Log("nemu: %s at pc = " FMT_WORD,
          (nemu_state.state == NEMU_ABORT ? ANSI_FMT("ABORT", ANSI_FG_RED) :
           (nemu_state.halt_ret == 0 ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN) :
            ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED))),
          nemu_state.halt_pc);
      // 在程序异常终止时显示 iringbuf
      if (nemu_state.state == NEMU_ABORT || nemu_state.halt_ret != 0) {
        IFDEF(CONFIG_ITRACE, display_iringbuf());
      }
      // fall through
    case NEMU_QUIT: statistic();
  }
}
