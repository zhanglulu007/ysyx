/***************************************************************************************
 * cachesim —— 简易 cache 功能模拟器 (B4.md "实现 cachesim")
 *
 * 设计依据 (讲义 B4.md 768-793 行):
 *   - 只维护 cache 元数据 (valid/tag/lru), 不含数据阵列 —— 给定 PC 序列,
 *     缺失次数与访存内容无关 (讲义 770 行).
 *   - 接收 NEMU 生成的简化 itrace (PC 序列), 统计 命中/缺失次数、命中率、
 *     AMAT 与 TMT, 用于 icache 设计空间探索 (Design Space Exploration).
 *   - 支持命令行传参, 便于脚本并行评估多组 cache 参数组合 (讲义 791 行).
 *   - 支持 popen("bzcat ...") 读压缩 itrace (讲义 787 行 "压缩 trace").
 *
 * 地址划分 (讲义 411-419 行, 组相联):
 *    31                  m+n   m-1        m-1     0
 *   +---------------------+------+----------+
 *   |        tag          | index|  offset  |      block_size = 2^m
 *   +---------------------+------+----------+      index 位数 n = log2(total/ways)
 *
 * 缺失代价模型 (讲义 B4.md 796-826 行 "块大小和缺失代价"):
 *   SDRAM 单次独立总线传输事务开销 = a + b + c + d (4 阶段),
 *   其中 a=AR 握手, b=状态转移, c=SDRAM 读数据, d=R 握手.
 *   总线数据位宽 = bus_width 字节, cache 块大小 = block_size 字节,
 *   独立传输方式下需要 beats = block_size / bus_width 次独立总线事务,
 *   总缺失代价 = beats × miss_penalty_per_beat.
 *   本版本默认块大小为总线数据位宽的 4 倍 (16B / 4B 总线 = 4 beats).
 *
 * 地址空间过滤 (讲义 B4.md 436 行 "适合缓存的地址空间"):
 *   只有存储器类型的地址空间才适合缓存; MMIO 设备寄存器 (UART, CLINT 等)
 *   具有副作用和异步可变性, 不应缓存. 与 ICache.v 的 req_cacheable 一致:
 *     Flash=0x3, PSRAM=0x8, SDRAM=0xa (按地址高 4 位判断).
 *   可通过 --cacheable-regions 配置.
 *
 * 用法:
 *   ./cachesim [选项] <itrace文件>
 *     --ways=<n>           组相联路数 (1=直接映射; 等于块数=全相联)  默认 1
 *     --block=<B>          块大小(字节, 须为 2 的幂)                默认 16
 *     --bus-width=<W>      总线数据位宽(字节, 须为 2 的幂)          默认 4
 *     --total=<T>          cache 块总数(须为 2 的幂)                默认 16
 *     --replace=<alg>      替换算法: lru | random                   默认 lru
 *     --miss-penalty=<cyc> 单次总线传输缺失代价(周期/beat)         默认 100
 *     --access-time=<cyc>  命中访问时间(周期)                        默认 1
 *     --cacheable-regions=<hex,...>  可缓存地址空间高4位           默认 3,8,a
 *     --no-filter-uncache  关闭地址过滤 (所有地址视为可缓存)        默认关
 *     --bz2                itrace 为 bzip2 压缩, 用 bzcat 读取       默认关
 *     -h, --help
 ***************************************************************************************/

/* popen/pclose 需要 _POSIX_C_SOURCE (c99 默认不暴露), 必须置于所有系统头文件之前 */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>

/* ----------------------------------------------------------------------- */
/* 配置参数 (可由命令行覆盖)                                                */
/* ----------------------------------------------------------------------- */
typedef struct {
    int      ways;         /* 组相联路数 */
    int      block_size;   /* 块大小 (字节) */
    int      bus_width;    /* 总线数据位宽 (字节), 默认 4 */
    int      num_beats;    /* block_size / bus_width, 一次缺失所需总线传输次数 */
    int      total_blocks; /* cache 块总数 */
    int      offset_bits;  /* log2(block_size) */
    int      index_bits;   /* log2(total_blocks / ways) */
    int      tag_bits;     /* 32 - offset_bits - index_bits */
    int      num_sets;     /* 组数 = total_blocks / ways */
    enum { REPLACE_LRU, REPLACE_RANDOM } replace;
    long     miss_penalty;        /* 单次总线传输缺失代价 (周期/beat), 即讲义中的 a+b+c+d */
    long     access_time;         /* 命中访问时间 (周期) */
    uint16_t cacheable_mask;      /* 可缓存地址空间高 4 位 bitmask: bit[i]=1 表示 0xi... 可缓存 */
    bool     filter_uncache;      /* 是否过滤不可缓存地址 (默认开启, --no-filter-uncache 关闭) */
    bool     use_bz2;             /* 是否用 bzcat 读取压缩 itrace */
    bool     use_bin;             /* 是否读取 NEMU 生成的二进制 RLE 格式 itrace */
    const char *itrace_path;
} cache_config_t;

/* ----------------------------------------------------------------------- */
/* cache 元数据: 每路每 index 一组 {valid, tag, lru_stamp}                  */
/* ----------------------------------------------------------------------- */
typedef struct {
    bool     valid;
    uint32_t tag;
    uint64_t lru_stamp;  /* LRU 用: 最近访问的逻辑时间戳, 越小越久未用 */
} cache_line_t;

static cache_line_t *cache = NULL;  /* num_sets * ways 的扁平数组 */

/* ----------------------------------------------------------------------- */
/* 辅助: log2 (仅对 2 的幂)                                                 */
/* ----------------------------------------------------------------------- */
static int log2_exact(int v, const char *name) {
    if (v < 1 || (v & (v - 1)) != 0) {
        fprintf(stderr, "cachesim: --%s=%d 必须是 2 的幂\n", name, v);
        exit(1);
    }
    int r = 0;
    while ((1 << r) < v) r++;
    return r;
}

/* ----------------------------------------------------------------------- */
/* 解析命令行参数                                                            */
/* ----------------------------------------------------------------------- */
static void parse_args(int argc, char *argv[], cache_config_t *cfg) {
    /* 默认值: 直接映射, 块=16B (总线宽度4B×4), 16块, LRU, miss_penalty=100/beat */
    /* 块大小为总线数据位宽的4倍 (讲义 B4.md 808-809 行) */
    cfg->ways = 1;
    cfg->block_size = 16;    /* 4 × bus_width(4) */
    cfg->bus_width   = 4;    /* AXI 数据位宽 32bit = 4B */
    cfg->total_blocks = 16;
    cfg->replace = REPLACE_LRU;
    cfg->miss_penalty = 100; /* 单次总线传输事务 (一个 beat) 的缺失代价 */
    cfg->access_time = 1;
    /* 地址过滤: 默认与 ICache.v 一致 — Flash(bit3), PSRAM(bit8), SDRAM(bit10) */
    cfg->cacheable_mask = (1u << 3) | (1u << 8) | (1u << 10);
    cfg->filter_uncache = true;
    cfg->use_bz2 = false;
    cfg->use_bin = false;
    cfg->itrace_path = NULL;

    /* 解析 --key=value 选项 */
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
            printf(
                "Usage: cachesim [options] <itrace-file>\n"
                "  --ways=<n>           associativity (1=direct, =total=fully-assoc)  default 1\n"
                "  --block=<B>          block size in bytes (power of 2)             default 16\n"
                "  --bus-width=<W>      bus data width in bytes (power of 2)        default 4\n"
                "  --total=<T>          total number of cache blocks (power of 2)     default 16\n"
                "  --replace=<alg>      replacement: lru | random                    default lru\n"
                "  --miss-penalty=<cyc> miss penalty per beat in cycles (a+b+c+d)    default 100\n"
                "                       total_miss_penalty = beats * miss_penalty\n"
                "                       where beats = block / bus_width\n"
                "  --access-time=<cyc>  hit access time in cycles                    default 1\n"
                "  --cacheable-regions=<hex,...>  address high-nibble bitmap (as hex)\n"
                "                        default 0x508 (bit3|bit8|bit10: Flash/PSRAM/SDRAM)\n"
                "  --no-filter-uncache  disable address filtering (all addr cacheable)\n"
                "  --bz2                itrace is bzip2-compressed, read via bzcat   default off\n"
                "  --bin                itrace is NEMU binary-RLE format (8-byte records)  default off\n"
                "                       (auto-detected from .bin extension if not set)\n"
                "  -h, --help           show this help\n");
            exit(0);
        } else if (strncmp(a, "--ways=", 7) == 0) {
            cfg->ways = atoi(a + 7);
        } else if (strncmp(a, "--block=", 8) == 0) {
            cfg->block_size = atoi(a + 8);
        } else if (strncmp(a, "--bus-width=", 12) == 0) {
            cfg->bus_width = atoi(a + 12);
        } else if (strncmp(a, "--total=", 8) == 0) {
            cfg->total_blocks = atoi(a + 8);
        } else if (strncmp(a, "--replace=", 10) == 0) {
            if (strcmp(a + 10, "lru") == 0) cfg->replace = REPLACE_LRU;
            else if (strcmp(a + 10, "random") == 0) cfg->replace = REPLACE_RANDOM;
            else { fprintf(stderr, "cachesim: --replace 仅支持 lru | random\n"); exit(1); }
        } else if (strncmp(a, "--miss-penalty=", 15) == 0) {
            cfg->miss_penalty = atol(a + 15);
        } else if (strncmp(a, "--access-time=", 14) == 0) {
            cfg->access_time = atol(a + 14);
        } else if (strcmp(a, "--no-filter-uncache") == 0) {
            cfg->filter_uncache = false;
        } else if (strncmp(a, "--cacheable-regions=", 20) == 0) {
            cfg->cacheable_mask = (uint16_t)strtol(a + 20, NULL, 16);
        } else if (strcmp(a, "--bz2") == 0) {
            cfg->use_bz2 = true;
        } else if (strcmp(a, "--bin") == 0) {
            cfg->use_bin = true;
        } else if (a[0] == '-' && a[1] == '-') {
            fprintf(stderr, "cachesim: 未知选项 '%s' (用 -h 查看帮助)\n", a);
            exit(1);
        } else if (a[0] == '-' && a[1] != '\0') {
            fprintf(stderr, "cachesim: 未知选项 '%s'\n", a);
            exit(1);
        } else {
            /* 位置参数 = itrace 文件 */
            cfg->itrace_path = a;
            /* 自动识别: .bin 后缀视为二进制 RLE 格式 (除非显式 --bz2) */
            if (!cfg->use_bin && !cfg->use_bz2) {
                size_t plen = strlen(a);
                if (plen >= 4 && strcmp(a + plen - 4, ".bin") == 0) {
                    cfg->use_bin = true;
                }
            }
        }
    }

    if (cfg->itrace_path == NULL) {
        fprintf(stderr, "cachesim: 缺少 itrace 文件参数 (用 -h 查看帮助)\n");
        exit(1);
    }
    if (cfg->ways < 1) {
        fprintf(stderr, "cachesim: --ways 必须 >= 1\n");
        exit(1);
    }
    if (cfg->ways > cfg->total_blocks) {
        fprintf(stderr, "cachesim: --ways(%d) 不能大于 --total(%d)\n", cfg->ways, cfg->total_blocks);
        exit(1);
    }
    if (cfg->bus_width < 1) {
        fprintf(stderr, "cachesim: --bus-width 必须 >= 1\n");
        exit(1);
    }
    if ((cfg->bus_width & (cfg->bus_width - 1)) != 0) {
        fprintf(stderr, "cachesim: --bus-width=%d 必须是 2 的幂\n", cfg->bus_width);
        exit(1);
    }
    if (cfg->block_size % cfg->bus_width != 0) {
        fprintf(stderr, "cachesim: --block(%d) 必须是 --bus-width(%d) 的整数倍\n",
                cfg->block_size, cfg->bus_width);
        exit(1);
    }

    /* 派生字段 */
    cfg->offset_bits = log2_exact(cfg->block_size, "block");
    cfg->num_beats   = cfg->block_size / cfg->bus_width;
    log2_exact(cfg->total_blocks, "total");  /* 仅校验 */
    if (cfg->total_blocks % cfg->ways != 0) {
        fprintf(stderr, "cachesim: --total(%d) 必须是 --ways(%d) 的整数倍\n", cfg->total_blocks, cfg->ways);
        exit(1);
    }
    cfg->num_sets = cfg->total_blocks / cfg->ways;
    cfg->index_bits = log2_exact(cfg->num_sets, "total/ways");
    cfg->tag_bits = 32 - cfg->offset_bits - cfg->index_bits;
}

/* ----------------------------------------------------------------------- */
/* 打开 itrace: 普通文件用 fopen, 压缩文件用 popen("bzcat ...")             */
/* 返回一个可读 FILE* 与是否 popen 的标志 (调用方据此选 fclose/pclose)      */
/* ----------------------------------------------------------------------- */
static FILE *open_itrace(const cache_config_t *cfg, bool *used_popen) {
    FILE *fp;
    if (cfg->use_bz2) {
        /* 讲义 787 行: popen("bzcat 文件", "r") 读取压缩 trace */
        char cmd[4096];
        snprintf(cmd, sizeof(cmd), "bzcat '%s'", cfg->itrace_path);
        fp = popen(cmd, "r");
        *used_popen = true;
    } else {
        fp = fopen(cfg->itrace_path, "r");
        *used_popen = false;
    }
    if (fp == NULL) {
        fprintf(stderr, "cachesim: 无法打开 itrace 文件 '%s'\n", cfg->itrace_path);
        exit(1);
    }
    return fp;
}

/* ----------------------------------------------------------------------- */
/* 从一行 itrace 文本中提取首个 0x 开头的 PC (十六进制).
 * 兼容 NEMU log 格式: "0x30000000: 00 00 04 13 mv  s0, zero"
 * 成功返回 true 并写入 *pc, 失败(无可解析 PC)返回 false.
 * ----------------------------------------------------------------------- */
static bool parse_pc_line(const char *line, uint32_t *pc) {
    const char *p = line;
    /* 跳过前导空白 */
    while (*p && isspace((unsigned char)*p)) p++;
    if (p[0] != '0' || (p[1] != 'x' && p[1] != 'X')) return false;
    p += 2;
    if (!isxdigit((unsigned char)*p)) return false;
    /* strtoul 解析十六进制 */
    char *end;
    unsigned long val = strtoul(p, &end, 16);
    if (end == p) return false;
    *pc = (uint32_t)val;
    return true;
}

/* ----------------------------------------------------------------------- */
/* 地址空间过滤: 与 NPC ICache.v 的 req_cacheable 判断一致                 */
/* 只对存储器类型地址 (Flash/PSRAM/SDRAM) 启用缓存 (讲义 B4.md 436 行)      */
/* ----------------------------------------------------------------------- */
static bool is_cacheable(const cache_config_t *cfg, uint32_t addr) {
    if (!cfg->filter_uncache) return true;  /* --no-filter-uncache 关闭过滤 */
    int region = (int)((addr >> 28) & 0xf);
    return (cfg->cacheable_mask >> region) & 1;
}

/* ----------------------------------------------------------------------- */
/* cache 访问模拟 (核心): 给定地址, 更新元数据并判定 hit/miss/uncache       */
/* ----------------------------------------------------------------------- */
static uint64_t g_time = 0;  /* 全局逻辑时钟, 供 LRU 时间戳使用 */

/* 返回值: 0=不可缓存, 1=命中, 2=缺失 */
#define RESULT_UNCACHEABLE 0
#define RESULT_HIT         1
#define RESULT_MISS        2

static int cache_access(const cache_config_t *cfg, uint32_t addr) {
    /* 不可缓存地址: 不更新元数据, 不计入命中/缺失 (讲义 B4.md 436 行) */
    if (!is_cacheable(cfg, addr)) return RESULT_UNCACHEABLE;

    uint32_t offset = addr & ((1u << cfg->offset_bits) - 1);
    (void)offset;  /* 模拟缺失次数不需要 offset */
    uint32_t index = (addr >> cfg->offset_bits) & ((1u << cfg->index_bits) - 1);
    uint32_t tag   = addr >> (cfg->offset_bits + cfg->index_bits);

    cache_line_t *set = &cache[index * cfg->ways];

    /* 1. 查命中: 组内任一路 valid 且 tag 匹配 */
    int hit_way = -1;
    for (int w = 0; w < cfg->ways; w++) {
        if (set[w].valid && set[w].tag == tag) { hit_way = w; break; }
    }
    if (hit_way >= 0) {
        if (cfg->replace == REPLACE_LRU) set[hit_way].lru_stamp = ++g_time;
        return RESULT_HIT;  /* hit */
    }

    /* 2. 缺失: 优先选无效路 */
    int victim = -1;
    for (int w = 0; w < cfg->ways; w++) {
        if (!set[w].valid) { victim = w; break; }
    }
    /* 3. 组满: 按替换算法选淘汰路 */
    if (victim < 0) {
        if (cfg->replace == REPLACE_RANDOM) {
            victim = rand() % cfg->ways;
        } else { /* LRU */
            victim = 0;
            for (int w = 1; w < cfg->ways; w++) {
                if (set[w].lru_stamp < set[victim].lru_stamp) victim = w;
            }
        }
    }

    /* 4. 填入新块 */
    set[victim].valid = true;
    set[victim].tag = tag;
    set[victim].lru_stamp = ++g_time;
    return RESULT_MISS;  /* miss */
}

/* ----------------------------------------------------------------------- */
/* 二进制 RLE itrace 处理 (讲义 B4.md "压缩 trace" 二进制 + RLE).
 *
 * NEMU 生成的二进制 RLE 格式: 一串定长 record, 每个 8 字节:
 *   uint32_t pc;    // 顺序段起始 PC (小端)
 *   uint32_t count; // 该段连续顺序指令数, PC = pc, pc+4, ..., pc+4*(count-1)
 *
 * 本函数逐 record 读取, 展开段内 PC 序列并对每个 PC 做 cache 访问.
 * 注意: NEMU 恒为 4 字节定长指令 (RISC-V), 故段内 PC 步进固定为 4.
 * ----------------------------------------------------------------------- */
static void run_binary_rle(const cache_config_t *cfg, FILE *fp,
                           uint64_t *p_access, uint64_t *p_hit,
                           uint64_t *p_miss, uint64_t *p_uncache) {
    uint64_t total_access = 0, total_hit = 0, total_miss = 0, total_uncache = 0;
    uint32_t rec[2];  /* rec[0]=pc, rec[1]=count */
    size_t nr = 0;
    while (fread(rec, sizeof(uint32_t), 2, fp) == 2) {
        nr++;
        uint32_t pc   = rec[0];
        uint32_t cnt  = rec[1];
        /* 展开段内 count 条顺序指令 (PC 每次 +4) */
        for (uint32_t i = 0; i < cnt; i++) {
            total_access++;
            int result = cache_access(cfg, pc);
            if      (result == RESULT_HIT)         total_hit++;
            else if (result == RESULT_MISS)        total_miss++;
            else /* RESULT_UNCACHEABLE */          total_uncache++;
            pc += 4;  /* RISC-V 定长 4 字节指令 */
        }
    }
    *p_access  = total_access;
    *p_hit     = total_hit;
    *p_miss    = total_miss;
    *p_uncache = total_uncache;
    fprintf(stderr, "[cachesim] read %zu binary-RLE records\n", nr);
}

/* ----------------------------------------------------------------------- */
/* 主流程                                                                    */
/* ----------------------------------------------------------------------- */
int main(int argc, char *argv[]) {
    cache_config_t cfg;
    parse_args(argc, argv, &cfg);

    /* 分配并初始化 cache 元数据 (全部 invalid) */
    cache = calloc((size_t)cfg.num_sets * (size_t)cfg.ways, sizeof(cache_line_t));
    if (cache == NULL) {
        fprintf(stderr, "cachesim: 内存分配失败\n");
        return 1;
    }

    /* 打开 itrace */
    bool used_popen = false;
    FILE *fp = open_itrace(&cfg, &used_popen);

    uint64_t total_access = 0, total_hit = 0, total_miss = 0, total_uncache = 0;

    if (cfg.use_bin) {
        /* 二进制 RLE 模式: 读定长 record, 展开顺序 PC 序列 */
        if (used_popen) { fprintf(stderr, "cachesim: --bin 与 --bz2 不兼容\n"); return 1; }
        run_binary_rle(&cfg, fp, &total_access, &total_hit, &total_miss, &total_uncache);
    } else {
        /* 文本模式: 逐行解析首个 0x PC */
        char line[1024];
        while (fgets(line, sizeof(line), fp) != NULL) {
            uint32_t pc;
            if (!parse_pc_line(line, &pc)) continue;  /* 跳过非 PC 行 (日志头等) */
            total_access++;
            int result = cache_access(&cfg, pc);
            if      (result == RESULT_HIT)         total_hit++;
            else if (result == RESULT_MISS)        total_miss++;
            else /* RESULT_UNCACHEABLE */          total_uncache++;
        }
    }
    if (used_popen) pclose(fp); else fclose(fp);

    /* ------------------------------------------------------------------ */
    /* 评估报告 (讲义 652-661 行 AMAT 公式; 762-764 行 TMT; 796-826 行 缺失代价) */
    /* ------------------------------------------------------------------ */
    uint64_t total_cacheable = total_hit + total_miss;  /* 可缓存 (命中+缺失) */
    double hit_rate  = total_cacheable ? (double)total_hit  / (double)total_cacheable : 0.0;
    double miss_rate = total_cacheable ? (double)total_miss / (double)total_cacheable : 0.0;
    double uncache_rate = total_access ? (double)total_uncache / (double)total_access : 0.0;
    /* 总缺失代价 = beats × miss_penalty_per_beat (独立总线传输事务方式) */
    long total_miss_penalty = cfg.num_beats * cfg.miss_penalty;
    /* AMAT = access_time + (1 - p) * total_miss_penalty  (p 为可缓存命中率) */
    double amat = (double)cfg.access_time + miss_rate * (double)total_miss_penalty;
    /* TMT = 缺失次数 × 总缺失代价 (不可缓存地址直通总线, 开销与单 beat 相当) */
    double tmt  = (double)total_miss * (double)total_miss_penalty
                + (double)total_uncache * (double)cfg.miss_penalty;

    /* 配置描述 */
    const char *org_str;
    char org_buf[64];
    if (cfg.ways == 1) {
        org_str = "直接映射 (direct-mapped)";
    } else if (cfg.ways == cfg.total_blocks) {
        org_str = "全相联 (fully-associative)";
    } else {
        snprintf(org_buf, sizeof(org_buf), "%d 路组相联", cfg.ways);
        org_str = org_buf;
    }
    const char *rep_str = (cfg.replace == REPLACE_LRU) ? "LRU" : "random";

    /* 可缓存区域描述 */
    char region_desc[128] = "";
    if (cfg.filter_uncache) {
        char *p = region_desc;
        bool first = true;
        for (int r = 0; r < 16; r++) {
            if ((cfg.cacheable_mask >> r) & 1) {
                if (!first) p += snprintf(p, 16, ",");
                p += snprintf(p, 16, "0x%x", r);
                first = false;
            }
        }
    }

    printf("==================== cachesim 评估报告 ====================\n");
    printf("配置         : %s\n", org_str);
    printf("               块大小=%dB | 总线位宽=%dB | 块数=%d | 总容量=%dB | 替换=%s\n",
           cfg.block_size, cfg.bus_width, cfg.total_blocks,
           cfg.block_size * cfg.total_blocks, rep_str);
    printf("               地址划分: tag=%d | index=%d | offset=%d (位)\n",
           cfg.tag_bits, cfg.index_bits, cfg.offset_bits);
    if (cfg.filter_uncache) {
        printf("               地址过滤: ON (仅 [%s]xxx_xxxx 可缓存, 其余不可缓存)\n", region_desc);
    } else {
        printf("               地址过滤: OFF (所有地址可缓存, --no-filter-uncache)\n");
    }
    printf("----------------------------------------------------------\n");
    printf("itrace 文件  : %s%s\n", cfg.itrace_path, cfg.use_bz2 ? " (bzcat 解压)" : "");
    printf("指令访问总数 : %llu\n", (unsigned long long)total_access);
    printf("命中  / 缺失 / 不可缓存 : %llu / %llu / %llu\n",
           (unsigned long long)total_hit, (unsigned long long)total_miss, (unsigned long long)total_uncache);
    printf("  (可缓存) 命中率 / 缺失率 : %.4f%% / %.4f%%\n", hit_rate * 100.0, miss_rate * 100.0);
    printf("  不可缓存占比            : %.4f%%\n", uncache_rate * 100.0);
    printf("  refill_req (缺失+不可缓存) = %llu\n", (unsigned long long)(total_miss + total_uncache));
    printf("----------------------------------------------------------\n");
    printf("传输方式     : %d 次独立总线传输事务 (beats=block/BW=%d/%d=%d)\n",
           cfg.num_beats, cfg.block_size, cfg.bus_width, cfg.num_beats);
    printf("每 beat 代价 : %ld 周期 (a+b+c+d, 讲义 799 行)\n", cfg.miss_penalty);
    printf("总缺失代价   : %ld 周期/缺失 (beats%d * miss_penalty_per_beat%ld)\n",
           total_miss_penalty, cfg.num_beats, cfg.miss_penalty);
    printf("AMAT         : %.4f 周期/访问  (access_time=%ld + 缺失率%.4f * 总缺失代价%ld)\n",
           amat, cfg.access_time, miss_rate, total_miss_penalty);
    printf("TMT(总缺失时间): %.0f 周期 (缺失%llu*%ld + 不可缓存%llu*每beat%ld)\n",
           tmt, (unsigned long long)total_miss, total_miss_penalty,
           (unsigned long long)total_uncache, cfg.miss_penalty);
    printf("----------------------------------------------------------\n");
    printf("说明:\n");
    printf("  - 块大小为总线数据位宽的 4 倍 (B4.md 808-809 行: 支持更大的块大小)\n");
    printf("  - 通过独立总线传输事务方式估算缺失代价 (B4.md 796-809 行)\n");
    printf("  - 地址过滤与 ICache.v 一致: 只对 Flash/PSRAM/SDRAM 启用缓存 (B4.md 436 行)\n");
    printf("  - AMAT 越小代表 cache 性能越好; TMT 越小代表 IPC 趋势越大 (讲义 762-764 行)\n");
    printf("  - 此命中/缺失/不可缓存数应与 NPC PerfCounter 的 icache 统计一致 (讲义 778 行)\n");
    printf("==========================================================\n");

    free(cache);
    return 0;
}
