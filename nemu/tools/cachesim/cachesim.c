/***************************************************************************************
* cachesim - metadata-only cache simulator for the NPC instruction cache
*
* Input is a PC trace produced by NEMU:
*   cachesim --trace build/cachesim.trace --size 4K --block 4 --ways 1
*
* The default cacheable ranges match npc/vsrc/ICache.v:
*   FLASH [0x30000000, 0x31000000) and SDRAM [0xa0000000, 0xa2000000)
* Other fetches are counted as "bypass" and are not accesses/hits/misses.
*
* TMT (total miss time) = misses * miss_penalty.
***************************************************************************************/

#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TRACE_MAGIC   0x43535431u
#define TRACE_VERSION 1u

typedef struct {
  uint64_t size;
  uint64_t block;
  uint64_t ways;
  uint64_t sets;
  uint32_t offset_bits;
  uint32_t index_bits;
  uint32_t *tags;
  uint8_t *valid;
  uint64_t *age;
  uint64_t clock;
  uint64_t accesses;
  uint64_t hits;
  uint64_t misses;
  uint64_t bypass;
  uint64_t compulsory;
  uint64_t replace;
} Cache;

static bool is_pow2(uint64_t x) {
  return x != 0 && (x & (x - 1)) == 0;
}

static uint32_t log2_u64(uint64_t x) {
  uint32_t n = 0;
  while (x > 1) { x >>= 1; n ++; }
  return n;
}

static void usage(FILE *out, const char *prog) {
  fprintf(out,
    "Usage: %s --trace FILE [options]\n"
    "  --trace FILE        PC trace from NEMU (binary RLE or text itrace)\n"
    "  --size BYTES        total cache size, default 64 (suffix K/M allowed)\n"
    "  --block BYTES       cache block size, default 4\n"
    "  --ways N            associativity, default 1\n"
    "  --miss-penalty N    cycles per miss, default 0\n"
    "  --cache-all         cache every PC (default: only FLASH/SDRAM)\n"
    "  --csv               print one CSV data line only\n"
    "  -h, --help          show this help\n",
    prog);
}

static uint64_t parse_size(const char *s, const char *what) {
  char *end = NULL;
  errno = 0;
  unsigned long long v = strtoull(s, &end, 0);
  if (errno != 0 || end == s) {
    fprintf(stderr, "cachesim: invalid %s '%s'\n", what, s);
    exit(1);
  }
  if (*end == 'k' || *end == 'K') { v <<= 10; end ++; }
  else if (*end == 'm' || *end == 'M') { v <<= 20; end ++; }
  if (*end != '\0') {
    fprintf(stderr, "cachesim: invalid %s '%s'\n", what, s);
    exit(1);
  }
  return (uint64_t)v;
}

static bool cacheable(uint32_t addr, bool cache_all) {
  if (cache_all) return true;
  return (addr >= 0x30000000u && addr < 0x31000000u) ||
         (addr >= 0xa0000000u && addr < 0xa2000000u);
}

static bool cache_access(Cache *c, uint32_t addr, bool cache_all) {
  if (!cacheable(addr, cache_all)) {
    c->bypass ++;
    return false;
  }

  c->accesses ++;
  uint32_t index = (addr >> c->offset_bits) & (uint32_t)(c->sets - 1);
  uint32_t tag = addr >> (c->offset_bits + c->index_bits);
  size_t base = (size_t)index * (size_t)c->ways;
  uint64_t stamp = ++ c->clock;

  for (uint32_t w = 0; w < c->ways; w ++) {
    size_t i = base + w;
    if (c->valid[i] && c->tags[i] == tag) {
      c->hits ++;
      c->age[i] = stamp;
      return true;
    }
  }

  c->misses ++;
  size_t victim = base;
  bool victim_invalid = false;
  for (uint32_t w = 0; w < c->ways; w ++) {
    size_t i = base + w;
    if (!c->valid[i]) { victim = i; victim_invalid = true; break; }
    if (c->age[i] < c->age[victim]) victim = i;
  }
  if (victim_invalid) c->compulsory ++;
  else c->replace ++;
  c->valid[victim] = 1;
  c->tags[victim] = tag;
  c->age[victim] = stamp;
  return false;
}

static void run_text_trace(FILE *fp, Cache *c, bool cache_all) {
  char line[512];
  while (fgets(line, sizeof(line), fp) != NULL) {
    char *p = line;
    while (*p == ' ' || *p == '\t') p ++;
    if (*p == '\0' || *p == '\n' || *p == '#') continue;

    char *pc = strstr(p, "pc=");
    if (pc != NULL) p = pc + 3;

    char *end = NULL;
    errno = 0;
    unsigned long v = strtoul(p, &end, 0);
    if (errno != 0 || end == p) continue;
    cache_access(c, (uint32_t)v, cache_all);
  }
}

static void run_trace(FILE *fp, Cache *c, bool cache_all) {
  uint32_t header[2];
  size_t n = fread(header, sizeof(header), 1, fp);

  if (n == 1 && header[0] == TRACE_MAGIC) {
    if (header[1] != TRACE_VERSION) {
      fprintf(stderr, "cachesim: unsupported trace version %u\n", header[1]);
      exit(1);
    }
    uint32_t rec[2];
    while (fread(rec, sizeof(rec), 1, fp) == 1) {
      for (uint32_t i = 0; i < rec[1]; i ++) {
        cache_access(c, rec[0] + 4u * i, cache_all);
      }
    }
    return;
  }

  rewind(fp);
  int ch = fgetc(fp);
  if (ch == EOF) return;
  rewind(fp);

  bool text = (ch >= '0' && ch <= '9') || ch == ' ' || ch == '\t' ||
              ch == '[' || ch == '#';
  if (text) {
    run_text_trace(fp, c, cache_all);
  } else {
    uint32_t pc;
    while (fread(&pc, sizeof(pc), 1, fp) == 1) {
      cache_access(c, pc, cache_all);
    }
  }
}

int main(int argc, char **argv) {
  const char *trace_path = NULL;
  uint64_t size = 64;
  uint64_t block = 4;
  uint64_t ways = 1;
  double miss_penalty = 0.0;
  bool cache_all = false;
  bool csv = false;

  for (int i = 1; i < argc; i ++) {
    const char *arg = argv[i];
    if (strcmp(arg, "--trace") == 0 && i + 1 < argc) {
      trace_path = argv[++ i];
    } else if (strcmp(arg, "--size") == 0 && i + 1 < argc) {
      size = parse_size(argv[++ i], "size");
    } else if (strcmp(arg, "--block") == 0 && i + 1 < argc) {
      block = parse_size(argv[++ i], "block");
    } else if (strcmp(arg, "--ways") == 0 && i + 1 < argc) {
      ways = parse_size(argv[++ i], "ways");
    } else if (strcmp(arg, "--miss-penalty") == 0 && i + 1 < argc) {
      char *end = NULL;
      errno = 0;
      miss_penalty = strtod(argv[++ i], &end);
      if (errno != 0 || end == argv[i] || *end != '\0' || miss_penalty < 0) {
        fprintf(stderr, "cachesim: invalid miss penalty '%s'\n", argv[i]);
        return 1;
      }
    } else if (strcmp(arg, "--cache-all") == 0) {
      cache_all = true;
    } else if (strcmp(arg, "--csv") == 0) {
      csv = true;
    } else if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
      usage(stdout, argv[0]);
      return 0;
    } else {
      fprintf(stderr, "cachesim: unknown option '%s'\n", arg);
      usage(stderr, argv[0]);
      return 1;
    }
  }

  if (trace_path == NULL) {
    usage(stderr, argv[0]);
    return 1;
  }
  if (size == 0 || block == 0 || ways == 0 ||
      size % block != 0 || size % (block * ways) != 0) {
    fprintf(stderr, "cachesim: size must be a multiple of block*ways\n");
    return 1;
  }
  if (block < 4 || block % 4 != 0) {
    fprintf(stderr, "cachesim: block must be a multiple of 4 bytes\n");
    return 1;
  }

  uint64_t sets = size / (block * ways);
  if (!is_pow2(size) || !is_pow2(block) || !is_pow2(ways) || !is_pow2(sets)) {
    fprintf(stderr, "cachesim: size, block, ways and sets must be powers of two\n");
    return 1;
  }

  Cache c = {0};
  c.size = size;
  c.block = block;
  c.ways = ways;
  c.sets = sets;
  c.offset_bits = log2_u64(block);
  c.index_bits = log2_u64(sets);
  if (c.offset_bits + c.index_bits >= 32) {
    fprintf(stderr, "cachesim: cache is too large for 32-bit PCs\n");
    return 1;
  }

  uint64_t blocks = size / block;
  c.tags = calloc((size_t)blocks, sizeof(*c.tags));
  c.valid = calloc((size_t)blocks, sizeof(*c.valid));
  c.age = calloc((size_t)blocks, sizeof(*c.age));
  if (c.tags == NULL || c.valid == NULL || c.age == NULL) {
    fprintf(stderr, "cachesim: out of memory\n");
    return 1;
  }

  FILE *fp = fopen(trace_path, "rb");
  if (fp == NULL) {
    fprintf(stderr, "cachesim: cannot open '%s': %s\n", trace_path, strerror(errno));
    return 1;
  }
  run_trace(fp, &c, cache_all);
  fclose(fp);

  double hit_rate = c.accesses ? (double)c.hits / (double)c.accesses : 0.0;
  double miss_rate = c.accesses ? (double)c.misses / (double)c.accesses : 0.0;
  double tmt = (double)c.misses * miss_penalty;

  if (csv) {
    printf("%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ","
           "%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ","
           "%.4f,%.4f,%.0f,%" PRIu64 ",%" PRIu64 "\n",
           size, block, ways, sets, c.accesses, c.hits, c.misses, c.bypass,
           hit_rate, miss_penalty, tmt, c.compulsory, c.replace);
  } else {
    printf("cache: size=%" PRIu64 "B block=%" PRIu64 "B ways=%" PRIu64
           " sets=%" PRIu64 "\n", size, block, ways, sets);
    printf("accesses=%" PRIu64 " hits=%" PRIu64 " misses=%" PRIu64
           " bypass=%" PRIu64 "\n", c.accesses, c.hits, c.misses, c.bypass);
    printf("compulsory=%" PRIu64 " replace=%" PRIu64 "\n",
           c.compulsory, c.replace);
    printf("hit_rate=%.4f miss_rate=%.4f\n", hit_rate, miss_rate);
    printf("miss_penalty=%.4f tmt=%.0f cycles\n", miss_penalty, tmt);
  }

  free(c.tags);
  free(c.valid);
  free(c.age);
  return 0;
}
