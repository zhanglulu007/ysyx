/***************************************************************************************
* Cache trace writer for cachesim
*
* Format (little endian, same host):
*   uint32_t magic   = 0x43535431 ("CST1")
*   uint32_t version = 1
*   record[] = { uint32_t pc, uint32_t run_len }
*
* A record means: execute run_len consecutive 4-byte instructions starting at pc.
***************************************************************************************/

#include <utils.h>
#include <stdio.h>
#include <stdlib.h>

#define CACHE_TRACE_MAGIC   0x43535431u
#define CACHE_TRACE_VERSION 1u

static FILE *trace_fp = NULL;
static uint32_t run_pc = 0;
static uint32_t run_len = 0;

static void write_run(void) {
  if (trace_fp == NULL || run_len == 0) return;
  uint32_t rec[2] = { run_pc, run_len };
  if (fwrite(rec, sizeof(rec), 1, trace_fp) != 1) {
    fprintf(stderr, "cache trace: write failed\n");
    exit(1);
  }
  run_len = 0;
}

static void close_trace(void) {
  if (trace_fp == NULL) return;
  write_run();
  fclose(trace_fp);
  trace_fp = NULL;
}

void init_cache_trace(const char *file) {
  if (file == NULL) return;

  trace_fp = fopen(file, "wb");
  Assert(trace_fp != NULL, "Can not open cache trace file '%s'", file);

  uint32_t header[2] = { CACHE_TRACE_MAGIC, CACHE_TRACE_VERSION };
  if (fwrite(header, sizeof(header), 1, trace_fp) != 1) {
    fprintf(stderr, "cache trace: write header failed\n");
    exit(1);
  }
  setvbuf(trace_fp, NULL, _IOFBF, 1 << 20);
  atexit(close_trace);
}

void cache_trace_pc(vaddr_t pc) {
  if (trace_fp == NULL) return;

  uint32_t cur = (uint32_t)pc;
  if (run_len != 0 && cur == run_pc + 4u * run_len) {
    run_len ++;
  } else {
    write_run();
    run_pc = cur;
    run_len = 1;
  }
}

void cache_trace_flush(void) {
  if (trace_fp == NULL) return;
  write_run();
  fflush(trace_fp);
}
