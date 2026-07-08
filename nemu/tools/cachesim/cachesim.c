/***************************************************************************************
 * cachesim - 简易 cache 功能模拟器 (离线统计 icache 缺失次数 / 命中率 / TMT)
 *
 * 参考: 讲义 B4 "实现cachesim"
 *   - 接收 NEMU 用 --dump-pc 导出的指令流 PC 序列 (二进制, 每条 4 字节 uint32)
 *   - 仅维护 cache 元数据 (valid + tag), 不需要数据部分 (讲义: 缺失次数与访存内容无关)
 *   - 命令行可配置 cache 参数 (块大小 / 块数 / 关联度), 便于设计空间探索
 *   - 可缓存地址判定与 NPC ICache (ICache.v 的 req_cacheable) 完全一致:
 *       高 4 位 ∈ {0x3 Flash, 0x8 PSRAM, 0xa SDRAM}; 其余视为不可缓存 (uncacheable)
 *
 * 用法:
 *   ./cachesim -i pc.bin [-s sets] [-b block] [-w ways] [-m miss_penalty] [-q]
 *
 * 性能 DiffTest:
 *   以 -s 16 -b 4 -w 1 (与当前 ICache 相同配置) 运行, 统计的 "缺失次数" 应与
 *   NPC `make run SOC=1 PERF=1` 报告中的 "icache misses" 完全一致.
 ***************************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <getopt.h>

/* ------------------------------------------------------------------ */
/* 默认参数 (与 NPC ICache.v 当前配置一致: 4B 块, 16 块, 直接映射)      */
/* ------------------------------------------------------------------ */
#define DEFAULT_SETS         16
#define DEFAULT_BLOCK        4      /* 字节 */
#define DEFAULT_WAYS         1      /* 直接映射 */
#define DEFAULT_MISS_PENALTY 39     /* 周期 (取自 ysyxSoC PerfCounter 实测平均缺失代价) */

/* 可缓存地址判定: 高 4 位 ∈ {0x3 Flash, 0x8 PSRAM, 0xa SDRAM}
 * 与 ICache.v 的 req_cacheable 完全一致, 保证 DiffTest 对齐. */
static int is_cacheable(uint32_t addr) {
  uint32_t hi = (addr >> 28) & 0xF;
  return hi == 0x3 || hi == 0x8 || hi == 0xa;
}

/* ------------------------------------------------------------------ */
/* cache 元数据 (讲义: 只保留元数据, 不需要数据部分)                    */
/*   每个 cache 行: valid + tag; 组相联时每组 ways 行, 用 LRU 替换       */
/* ------------------------------------------------------------------ */
typedef struct {
  uint8_t  valid;   /* 有效位 */
  uint32_t tag;     /* 标签 (去除 offset/index 后的高位) */
  uint64_t last;    /* LRU: 最近一次访问的序号 (仅 ways>1 时使用) */
} cache_line_t;

static cache_line_t *cache = NULL;  /* 按 [组][路] 线性存放: cache[group*ways + way] */
static uint32_t nr_ways;
static uint32_t offset_bits, index_mask;

/* 统计计数 */
static uint64_t cnt_access    = 0;  /* 总取指访问 */
static uint64_t cnt_hit       = 0;  /* 命中 (可缓存) */
static uint64_t cnt_miss      = 0;  /* 缺失 (可缓存) */
static uint64_t cnt_uncache   = 0;  /* 不可缓存访问 */
static uint64_t access_seq    = 0;  /* 全局访问序号, 供 LRU */

/* ------------------------------------------------------------------ */
/* log2 (仅对 2 的幂返回正确值; 否则返回 -1) */
static int log2_pow2(uint32_t v) {
  if (v == 0) return -1;
  int r = 0;
  while ((1u << r) < v) r++;
  return (1u << r) == v ? r : -1;
}

/* ------------------------------------------------------------------ */
static void usage(const char *prog) {
  printf("cachesim - 简易 cache 功能模拟器 (统计 icache 缺失/命中率/TMT)\n\n");
  printf("用法: %s -i PC_FILE [选项]\n\n", prog);
  printf("选项:\n");
  printf("  -i, --input=FILE       PC 流文件 (NEMU --dump-pc 导出, 4B/inst 二进制)\n");
  printf("  -s, --sets=N           cache 块数 (默认 %d, 须为 2 的幂)\n", DEFAULT_SETS);
  printf("  -b, --block=B          块大小字节 (默认 %d, 须为 2 的幂)\n", DEFAULT_BLOCK);
  printf("  -w, --ways=W           关联度 (默认 %d, 1=直接映射)\n", DEFAULT_WAYS);
  printf("  -m, --miss-penalty=P   每次缺失代价周期 (默认 %d, 用于估算 TMT)\n", DEFAULT_MISS_PENALTY);
  printf("  -q, --quiet            精简输出 (仅一行 TSV: sets\\tblock\\tways\\thits\\tmisses\\tuncache\\thitrate\\tTMT)\n");
  printf("  -h, --help             显示本帮助\n\n");
  printf("示例:\n");
  printf("  %s -i pc.bin                       # 默认配置 (与当前 ICache 一致, 可做 DiffTest)\n", prog);
  printf("  %s -i pc.bin -s 64 -b 16 -w 4      # 评估 64组/16B块/4路 组相联\n", prog);
}

int main(int argc, char *argv[]) {
  const char *input_file = NULL;
  uint32_t sets        = DEFAULT_SETS;
  uint32_t block       = DEFAULT_BLOCK;
  uint32_t ways        = DEFAULT_WAYS;
  uint32_t miss_pen    = DEFAULT_MISS_PENALTY;
  int      quiet       = 0;

  static const struct option long_opts[] = {
    {"input",        required_argument, NULL, 'i'},
    {"sets",         required_argument, NULL, 's'},
    {"block",        required_argument, NULL, 'b'},
    {"ways",         required_argument, NULL, 'w'},
    {"miss-penalty", required_argument, NULL, 'm'},
    {"quiet",        no_argument,       NULL, 'q'},
    {"help",         no_argument,       NULL, 'h'},
    {0, 0, 0, 0}
  };
  int o;
  while ((o = getopt_long(argc, argv, "i:s:b:w:m:qh", long_opts, NULL)) != -1) {
    switch (o) {
      case 'i': input_file = optarg; break;
      case 's': sets       = (uint32_t)strtoul(optarg, NULL, 0); break;
      case 'b': block      = (uint32_t)strtoul(optarg, NULL, 0); break;
      case 'w': ways       = (uint32_t)strtoul(optarg, NULL, 0); break;
      case 'm': miss_pen   = (uint32_t)strtoul(optarg, NULL, 0); break;
      case 'q': quiet      = 1; break;
      case 'h': usage(argv[0]); return 0;
      default:  usage(argv[0]); return 1;
    }
  }

  if (input_file == NULL) {
    fprintf(stderr, "错误: 必须用 -i 指定 PC 流文件\n\n");
    usage(argv[0]);
    return 1;
  }

  /* 参数合法性: sets/block/ways 必须是 2 的幂, ways<=sets */
  int ob = log2_pow2(block), oi = log2_pow2(sets);
  if (ob < 0) { fprintf(stderr, "错误: 块大小必须是 2 的幂 (当前 %u)\n", block); return 1; }
  if (oi < 0) { fprintf(stderr, "错误: 块数必须是 2 的幂 (当前 %u)\n", sets); return 1; }
  if (ways == 0 || (ways & (ways - 1)) != 0) {
    fprintf(stderr, "错误: 关联度必须是 2 的幂 (当前 %u)\n", ways); return 1;
  }
  if (ways > sets) { fprintf(stderr, "错误: 关联度 (%u) 不能大于块数 (%u)\n", ways, sets); return 1; }
  if ((sets % ways) != 0) { fprintf(stderr, "错误: 块数 (%u) 必须是关联度 (%u) 的整数倍\n", sets, ways); return 1; }

  offset_bits = (uint32_t)ob;
  nr_ways     = ways;

  /* 组相联模型: 总 cache 行数 = sets, 分成 (sets/ways) 组, 每组 ways 路.
   *   ways=1 -> sets 组每组 1 路 = 直接映射
   *   组号 group = (addr >> offset_bits) & (nr_groups-1)
   *   tag       = addr >> (offset_bits + group_bits)
   * cache 数组按 [组][路] 线性存放: cache[group*ways + way] */
  uint32_t nr_groups  = sets / ways;
  uint32_t group_bits = (uint32_t)log2_pow2(nr_groups);
  index_mask          = nr_groups - 1;   /* 用于 group 索引 */

  cache = calloc(sets, sizeof(cache_line_t));
  if (!cache) { perror("calloc"); return 1; }

  FILE *fp = fopen(input_file, "rb");
  if (!fp) { fprintf(stderr, "错误: 无法打开 PC 流文件 '%s'\n", input_file); free(cache); return 1; }

  uint32_t pc;
  while (fread(&pc, sizeof(uint32_t), 1, fp) == 1) {
    cnt_access++;
    if (!is_cacheable(pc)) { cnt_uncache++; continue; }
    uint32_t group = (pc >> offset_bits) & index_mask;
    uint32_t tag   = pc >> (offset_bits + group_bits);
    cache_line_t *grp = &cache[group * nr_ways];
    int hit = 0;
    for (uint32_t w = 0; w < nr_ways; w++) {
      if (grp[w].valid && grp[w].tag == tag) { grp[w].last = access_seq++; hit = 1; break; }
    }
    if (hit) { cnt_hit++; continue; }
    cnt_miss++;
    /* 缺失: 优先空行, 否则 LRU */
    uint32_t w;
    for (w = 0; w < nr_ways; w++) if (!grp[w].valid) break;
    if (w == nr_ways) {
      uint32_t victim = 0;
      for (w = 1; w < nr_ways; w++) if (grp[w].last < grp[victim].last) victim = w;
      w = victim;
    }
    grp[w].valid = 1; grp[w].tag = tag; grp[w].last = access_seq++;
  }
  fclose(fp);
  free(cache);

  uint64_t cacheable = cnt_hit + cnt_miss;
  double hit_rate = cacheable ? (double)cnt_hit / (double)cacheable : 0.0;
  double tmt = (double)cnt_miss * (double)miss_pen;

  if (quiet) {
    /* TSV 单行, 便于脚本汇总设计空间探索 */
    printf("%u\t%u\t%u\t%llu\t%llu\t%llu\t%.6f\t%.0f\n",
           sets, block, ways,
           (unsigned long long)cnt_hit, (unsigned long long)cnt_miss,
           (unsigned long long)cnt_uncache, hit_rate, tmt);
    return 0;
  }

  /* 详细报告 */
  printf("============================================================\n");
  printf("            cachesim - icache 模拟报告\n");
  printf("============================================================\n");
  printf("  PC 流文件  input            : %s\n", input_file);
  printf("  cache 配置: 块数=%u  块大小=%uB  关联度=%u", sets, block, ways);
  if (ways == 1) printf("  (直接映射)");
  else printf("  (组相联, %u组×%u路)", nr_groups, ways);
  printf("\n");
  printf("  地址划分: offset=%u位  index=%u位  tag=%u位\n", offset_bits, group_bits, 32 - offset_bits - group_bits);
  printf("  缺失代价 miss_penalty    : %u 周期/次\n", miss_pen);
  printf("------------------------------------------------------------\n");
  printf("  取指访问 accesses         : %llu\n", (unsigned long long)cnt_access);
  printf("  命中 hits                : %llu  (%.2f%%)\n",
         (unsigned long long)cnt_hit, cnt_access ? 100.0 * cnt_hit / cnt_access : 0.0);
  printf("  缺失 misses              : %llu  (%.2f%%)\n",
         (unsigned long long)cnt_miss, cnt_access ? 100.0 * cnt_miss / cnt_access : 0.0);
  printf("  不可缓存 uncacheable     : %llu  (%.2f%%)\n",
         (unsigned long long)cnt_uncache, cnt_access ? 100.0 * cnt_uncache / cnt_access : 0.0);
  printf("  可缓存命中率 p           : %.6f  (hits/(hits+misses))\n", hit_rate);
  printf("  TMT (总缺失时间)         : %.0f 周期  (= misses × miss_penalty)\n", tmt);
  printf("============================================================\n");
  printf("注: 以 -s %u -b %u -w 1 运行时, '缺失次数' 应与 NPC PERF=1 报告的\n", DEFAULT_SETS, DEFAULT_BLOCK);
  printf("    'icache misses' 完全一致 (性能 DiffTest).\n");
  return 0;
}
