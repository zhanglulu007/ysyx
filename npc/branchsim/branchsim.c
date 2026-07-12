/* Static RISC-V conditional-branch predictor simulator with a BTB model. */
#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum predictor {
  PRED_ALWAYS_NOT_TAKEN,
  PRED_ALWAYS_TAKEN,
  PRED_BTFN,
  PRED_ALL,
};

#define DEFAULT_BTB_ENTRIES 8u

typedef struct {
  enum predictor predictor;
  uint64_t total_insts;
  bool total_insts_from_cli;
  uint64_t mispredict_penalty;
  size_t btb_entries;
  const char *btrace_path;
} config_t;

typedef struct {
  uint64_t branches;
  uint64_t taken;
  uint64_t not_taken;
  uint64_t direction_correct;
  uint64_t direction_incorrect;
  uint64_t next_pc_correct;
  uint64_t next_pc_incorrect;
} stats_t;

typedef struct {
  uint64_t lines;
  uint64_t blank_or_comment;
  uint64_t malformed;
  uint64_t invalid_opcode;
  uint64_t invalid_funct3;
} input_stats_t;

typedef struct {
  bool valid;
  uint32_t pc;
  uint32_t target;
  bool backward;
} btb_entry_t;

typedef struct {
  btb_entry_t *entries;
  size_t entry_count;
} btb_t;

typedef struct {
  uint64_t lookups;
  uint64_t hits;
  uint64_t misses;
  uint64_t cold_misses;
  uint64_t conflict_misses;
  uint64_t updates;
  uint64_t cold_fills;
  uint64_t replacements;
  uint64_t target_mismatches;
} btb_stats_t;

typedef struct {
  bool taken;
  uint32_t next_pc;
} prediction_t;

static void usage(FILE *stream) {
  fprintf(stream,
          "Usage: branchsim [options] <btrace-file>\n"
          "\n"
          "Evaluate static RISC-V conditional-branch predictors against btrace.\n"
          "Records are: <pc> <inst> <taken>, where taken is 0 or 1.\n"
          "\n"
          "Options:\n"
          "  --predictor=<name>       all | always-not-taken | always-taken | btfn\n"
          "  --predict=<name>         alias for --predictor\n"
          "                           default: all\n"
          "  --total-insts=<N>        dynamic instruction count; overrides trace metadata\n"
          "  --mispredict-penalty=<N> extra cycles per wrong prediction, default: 2\n"
          "  --btb-entries=<N>        direct-mapped BTB entries (power of two); default: 8\n"
          "                           0 disables the finite BTB model (ideal target baseline)\n"
          "  -h, --help               show this help\n"
          "\n"
          "With a finite BTB, a miss always predicts PC+4. BTFN uses the\n"
          "backward bit stored in a matching BTB entry.\n");
}

static bool parse_u64(const char *text, uint64_t *value) {
  char *end = NULL;
  unsigned long long parsed;

  if (*text == '\0' || *text == '-') return false;
  errno = 0;
  parsed = strtoull(text, &end, 0);
  if (errno == ERANGE || end == text || *end != '\0') return false;
  *value = (uint64_t)parsed;
  return true;
}

static bool parse_u32(const char *text, uint32_t *value) {
  uint64_t parsed;
  if (!parse_u64(text, &parsed) || parsed > UINT32_MAX) return false;
  *value = (uint32_t)parsed;
  return true;
}

static bool parse_size(const char *text, size_t *value) {
  uint64_t parsed;
  if (!parse_u64(text, &parsed) || parsed > SIZE_MAX) return false;
  *value = (size_t)parsed;
  return true;
}

static bool is_power_of_two(size_t value) {
  return value != 0 && (value & (value - 1)) == 0;
}

static const char *predictor_name(enum predictor predictor) {
  switch (predictor) {
    case PRED_ALWAYS_NOT_TAKEN: return "always-not-taken";
    case PRED_ALWAYS_TAKEN: return "always-taken";
    case PRED_BTFN: return "btfn";
    case PRED_ALL: return "all";
  }
  return "unknown";
}

static bool parse_predictor(const char *name, enum predictor *predictor) {
  if (strcmp(name, "all") == 0) {
    *predictor = PRED_ALL;
  } else if (strcmp(name, "always-not-taken") == 0 || strcmp(name, "ant") == 0) {
    *predictor = PRED_ALWAYS_NOT_TAKEN;
  } else if (strcmp(name, "always-taken") == 0 || strcmp(name, "at") == 0) {
    *predictor = PRED_ALWAYS_TAKEN;
  } else if (strcmp(name, "btfn") == 0) {
    *predictor = PRED_BTFN;
  } else {
    return false;
  }
  return true;
}

static void parse_args(int argc, char **argv, config_t *cfg) {
  int i;

  cfg->predictor = PRED_ALL;
  cfg->total_insts = 0;
  cfg->total_insts_from_cli = false;
  cfg->mispredict_penalty = 2;
  cfg->btb_entries = DEFAULT_BTB_ENTRIES;
  cfg->btrace_path = NULL;

  for (i = 1; i < argc; i++) {
    const char *arg = argv[i];
    if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
      usage(stdout);
      exit(EXIT_SUCCESS);
    } else if (strncmp(arg, "--predictor=", 12) == 0 ||
               strncmp(arg, "--predict=", 10) == 0) {
      const char *value = strncmp(arg, "--predictor=", 12) == 0 ?
          arg + 12 : arg + 10;
      if (!parse_predictor(value, &cfg->predictor)) {
        fprintf(stderr, "branchsim: unsupported predictor '%s'\n", value);
        exit(EXIT_FAILURE);
      }
    } else if (strncmp(arg, "--total-insts=", 14) == 0) {
      if (!parse_u64(arg + 14, &cfg->total_insts)) {
        fprintf(stderr, "branchsim: invalid --total-insts value '%s'\n", arg + 14);
        exit(EXIT_FAILURE);
      }
      cfg->total_insts_from_cli = true;
    } else if (strncmp(arg, "--mispredict-penalty=", 21) == 0) {
      if (!parse_u64(arg + 21, &cfg->mispredict_penalty)) {
        fprintf(stderr, "branchsim: invalid --mispredict-penalty value '%s'\n", arg + 21);
        exit(EXIT_FAILURE);
      }
    } else if (strncmp(arg, "--btb-entries=", 14) == 0) {
      if (!parse_size(arg + 14, &cfg->btb_entries)) {
        fprintf(stderr, "branchsim: invalid --btb-entries value '%s'\n", arg + 14);
        exit(EXIT_FAILURE);
      }
    } else if (arg[0] == '-') {
      fprintf(stderr, "branchsim: unknown option '%s'\n", arg);
      exit(EXIT_FAILURE);
    } else if (cfg->btrace_path == NULL) {
      cfg->btrace_path = arg;
    } else {
      fprintf(stderr, "branchsim: only one btrace file may be specified\n");
      exit(EXIT_FAILURE);
    }
  }

  if (cfg->btrace_path == NULL) {
    fprintf(stderr, "branchsim: missing btrace file\n");
    usage(stderr);
    exit(EXIT_FAILURE);
  }
  if (cfg->btb_entries != 0 && !is_power_of_two(cfg->btb_entries)) {
    fprintf(stderr,
            "branchsim: --btb-entries must be 0 or a power of two (got %zu)\n",
            cfg->btb_entries);
    exit(EXIT_FAILURE);
  }
}

static char *trim(char *text) {
  char *end;
  while (isspace((unsigned char)*text)) text++;
  end = text + strlen(text);
  while (end > text && isspace((unsigned char)end[-1])) end--;
  *end = '\0';
  return text;
}

static bool parse_metadata_total_insts(char *comment, uint64_t *total_insts) {
  char normalized[256];
  char *key;
  char *equals;
  char *value;
  size_t i;
  size_t out = 0;

  equals = strchr(comment, '=');
  if (equals == NULL) return false;
  *equals = '\0';
  key = trim(comment);
  value = trim(equals + 1);

  /* Permit '-', '_' and whitespace as separators in the metadata key. */
  for (i = 0; key[i] != '\0' && out + 1 < sizeof(normalized); i++) {
    unsigned char c = (unsigned char)key[i];
    if (c != '_' && c != '-' && !isspace(c)) normalized[out++] = (char)tolower(c);
  }
  normalized[out] = '\0';
  return strcmp(normalized, "totalinstructions") == 0 && parse_u64(value, total_insts);
}

static bool is_valid_branch(uint32_t inst, input_stats_t *input) {
  uint32_t opcode = inst & 0x7fu;
  uint32_t funct3 = (inst >> 12) & 0x7u;

  if (opcode != 0x63u) {
    input->invalid_opcode++;
    return false;
  }
  /* 010 and 011 are reserved in the base conditional-branch encoding. */
  if (funct3 == 0x2u || funct3 == 0x3u) {
    input->invalid_funct3++;
    return false;
  }
  return true;
}

static int32_t branch_offset(uint32_t inst) {
  uint32_t immediate = ((inst >> 31) << 12) |
                       (((inst >> 7) & 0x1u) << 11) |
                       (((inst >> 25) & 0x3fu) << 5) |
                       (((inst >> 8) & 0xfu) << 1);

  if ((immediate & UINT32_C(0x1000)) != 0) {
    return (int32_t)immediate - 0x2000;
  }
  return (int32_t)immediate;
}

static uint32_t branch_target(uint32_t pc, uint32_t inst) {
  return pc + (uint32_t)branch_offset(inst);
}

static bool predict_direction(enum predictor predictor, bool backward) {
  switch (predictor) {
    case PRED_ALWAYS_NOT_TAKEN: return false;
    case PRED_ALWAYS_TAKEN: return true;
    case PRED_BTFN: return backward;
    case PRED_ALL: break;
  }
  return false;
}

static void btb_init(btb_t *btb, size_t entry_count) {
  btb->entries = NULL;
  btb->entry_count = entry_count;
  if (entry_count == 0) return;

  if (entry_count > SIZE_MAX / sizeof(*btb->entries)) {
    fprintf(stderr, "branchsim: BTB allocation size overflow\n");
    exit(EXIT_FAILURE);
  }
  btb->entries = calloc(entry_count, sizeof(*btb->entries));
  if (btb->entries == NULL) {
    fprintf(stderr, "branchsim: unable to allocate %zu BTB entries\n", entry_count);
    exit(EXIT_FAILURE);
  }
}

static void btb_destroy(btb_t *btb) {
  free(btb->entries);
  btb->entries = NULL;
  btb->entry_count = 0;
}

static const btb_entry_t *btb_lookup(const btb_t *btb, uint32_t pc,
                                     btb_stats_t *stats) {
  const btb_entry_t *entry;
  size_t index;

  if (btb->entry_count == 0) return NULL;

  stats->lookups++;
  index = ((size_t)(pc >> 2)) & (btb->entry_count - 1);
  entry = &btb->entries[index];
  if (entry->valid && entry->pc == pc) {
    stats->hits++;
    return entry;
  }

  stats->misses++;
  if (entry->valid) stats->conflict_misses++;
  else stats->cold_misses++;
  return NULL;
}

static void btb_update(btb_t *btb, uint32_t pc, uint32_t target, bool backward,
                       btb_stats_t *stats) {
  btb_entry_t *entry;
  size_t index;

  if (btb->entry_count == 0) return;

  index = ((size_t)(pc >> 2)) & (btb->entry_count - 1);
  entry = &btb->entries[index];
  if (!entry->valid) {
    stats->cold_fills++;
  } else if (entry->pc != pc) {
    stats->replacements++;
  }
  entry->valid = true;
  entry->pc = pc;
  entry->target = target;
  entry->backward = backward;
  stats->updates++;
}

static prediction_t make_prediction(enum predictor predictor,
                                    const btb_entry_t *entry, uint32_t pc,
                                    uint32_t actual_target, bool backward,
                                    bool btb_disabled) {
  prediction_t prediction;

  if (btb_disabled) {
    bool predicted_taken = predict_direction(predictor, backward);
    prediction.taken = predicted_taken;
    prediction.next_pc = predicted_taken ? actual_target : pc + 4;
    return prediction;
  }
  if (entry == NULL) {
    prediction.taken = false;
    prediction.next_pc = pc + 4;
    return prediction;
  }

  prediction.taken = predict_direction(predictor, entry->backward);
  prediction.next_pc = prediction.taken ? entry->target : pc + 4;
  return prediction;
}

static void update_stats(stats_t *stats, prediction_t prediction,
                         bool actual_taken, uint32_t actual_next_pc) {
  stats->branches++;
  if (actual_taken) stats->taken++;
  else stats->not_taken++;
  if (prediction.taken == actual_taken) stats->direction_correct++;
  else stats->direction_incorrect++;
  if (prediction.next_pc == actual_next_pc) stats->next_pc_correct++;
  else stats->next_pc_incorrect++;
}

static bool parse_record(char *line, uint32_t *pc, uint32_t *inst, bool *taken) {
  char *token[4];
  char *save = NULL;
  char *part;
  unsigned int count = 0;
  uint64_t taken_value;

  for (part = strtok_r(line, " \t\r\n", &save); part != NULL && count < 4;
       part = strtok_r(NULL, " \t\r\n", &save)) {
    token[count++] = part;
  }
  if (count != 3 || !parse_u32(token[0], pc) || !parse_u32(token[1], inst) ||
      !parse_u64(token[2], &taken_value) || taken_value > 1) {
    return false;
  }
  *taken = taken_value != 0;
  return true;
}

static bool add_overflows(uint64_t lhs, uint64_t rhs) {
  return UINT64_MAX - lhs < rhs;
}

static bool multiply_overflows(uint64_t lhs, uint64_t rhs) {
  return lhs != 0 && rhs > UINT64_MAX / lhs;
}

static uint64_t cycles_for(const stats_t *stats, uint64_t total_insts,
                           uint64_t penalty, enum predictor predictor) {
  uint64_t penalty_cycles;
  if (multiply_overflows(stats->next_pc_incorrect, penalty)) {
    fprintf(stderr, "branchsim: cycle count overflow for predictor %s\n",
            predictor_name(predictor));
    exit(EXIT_FAILURE);
  }
  penalty_cycles = stats->next_pc_incorrect * penalty;
  if (add_overflows(total_insts, penalty_cycles)) {
    fprintf(stderr, "branchsim: cycle count overflow for predictor %s\n",
            predictor_name(predictor));
    exit(EXIT_FAILURE);
  }
  return total_insts + penalty_cycles;
}

static void print_accuracy(const char *label, uint64_t correct, uint64_t incorrect,
                           uint64_t branches) {
  double accuracy = branches == 0 ? 0.0 :
      100.0 * (double)correct / (double)branches;

  printf("    %-10s correct: %" PRIu64 ", incorrect: %" PRIu64
         ", accuracy: %.2f%%\n",
         label, correct, incorrect, accuracy);
}

static void print_result(const stats_t *ideal, const stats_t *calibrated,
                         enum predictor predictor, uint64_t total_insts,
                         uint64_t penalty, uint64_t ant_cycles) {
  uint64_t cycles = cycles_for(calibrated, total_insts, penalty, predictor);
  double ipc = cycles == 0 ? 0.0 : (double)total_insts / (double)cycles;
  double speedup = cycles == 0 ? 0.0 : (double)ant_cycles / (double)cycles;

  printf("Predictor: %s\n", predictor_name(predictor));
  printf("  Branches:    %" PRIu64 "\n", calibrated->branches);
  printf("  Taken:       %" PRIu64 "\n", calibrated->taken);
  printf("  Not taken:   %" PRIu64 "\n", calibrated->not_taken);
  printf("  Ideal target availability:\n");
  print_accuracy("Direction", ideal->direction_correct,
                 ideal->direction_incorrect, ideal->branches);
  print_accuracy("Next-PC", ideal->next_pc_correct,
                 ideal->next_pc_incorrect, ideal->branches);
  printf("  BTB-calibrated:\n");
  print_accuracy("Direction", calibrated->direction_correct,
                 calibrated->direction_incorrect, calibrated->branches);
  print_accuracy("Next-PC", calibrated->next_pc_correct,
                 calibrated->next_pc_incorrect, calibrated->branches);
  printf("  Total insts: %" PRIu64 "\n", total_insts);
  printf("  Cycles:      %" PRIu64 " (ideal single-issue + %" PRIu64
         " x %" PRIu64 " calibrated next-PC mispredict penalty)\n",
         cycles, calibrated->next_pc_incorrect, penalty);
  printf("  IPC:         %.6f\n", ipc);
  printf("  Speedup vs always-not-taken: %.6fx\n", speedup);
}

static void print_btb_result(const btb_stats_t *stats, size_t entries) {
  if (entries == 0) {
    printf("BTB: disabled (ideal target availability baseline)\n");
    return;
  }

  printf("BTB: direct-mapped, %zu entries\n", entries);
  printf("  Conditional-branch trace lookups: %" PRIu64 "\n", stats->lookups);
  printf("  Hits:              %" PRIu64 "\n", stats->hits);
  printf("  Misses:            %" PRIu64 " (cold: %" PRIu64 ", conflict: %" PRIu64 ")\n",
         stats->misses, stats->cold_misses, stats->conflict_misses);
  printf("  Hit rate:          %.2f%%\n",
         stats->lookups == 0 ? 0.0 :
         100.0 * (double)stats->hits / (double)stats->lookups);
  printf("  Updates:           %" PRIu64 " (cold fills: %" PRIu64
         ", replacements: %" PRIu64 ")\n",
         stats->updates, stats->cold_fills, stats->replacements);
  printf("  Target mismatches: %" PRIu64 "\n", stats->target_mismatches);
}

int main(int argc, char **argv) {
  config_t cfg;
  FILE *fp;
  char line[1024];
  stats_t ideal_stats[3] = {{0}};
  stats_t calibrated_stats[3] = {{0}};
  input_stats_t input = {0};
  btb_t btb;
  btb_stats_t btb_stats = {0};
  uint64_t trace_total_insts = 0;
  bool trace_total_insts_found = false;
  uint64_t ant_cycles;
  unsigned int i;

  parse_args(argc, argv, &cfg);
  btb_init(&btb, cfg.btb_entries);
  fp = fopen(cfg.btrace_path, "r");
  if (fp == NULL) {
    fprintf(stderr, "branchsim: cannot open '%s': %s\n", cfg.btrace_path,
            strerror(errno));
    btb_destroy(&btb);
    return EXIT_FAILURE;
  }

  while (fgets(line, sizeof(line), fp) != NULL) {
    char *text;
    char *inline_comment;
    uint32_t pc;
    uint32_t inst;
    uint32_t target;
    uint32_t actual_next_pc;
    bool backward;
    bool actual_taken;
    const btb_entry_t *entry;

    input.lines++;
    text = trim(line);
    if (*text == '\0') {
      input.blank_or_comment++;
      continue;
    }
    if (*text == '#') {
      uint64_t metadata_total;
      input.blank_or_comment++;
      if (parse_metadata_total_insts(text + 1, &metadata_total)) {
        trace_total_insts = metadata_total;
        trace_total_insts_found = true;
      }
      continue;
    }
    inline_comment = strchr(text, '#');
    if (inline_comment != NULL) *inline_comment = '\0';
    text = trim(text);
    if (!parse_record(text, &pc, &inst, &actual_taken)) {
      input.malformed++;
      continue;
    }
    if (!is_valid_branch(inst, &input)) continue;

    target = branch_target(pc, inst);
    backward = branch_offset(inst) < 0;
    actual_next_pc = actual_taken ? target : pc + 4;

    /* Lookup precedes any predictor observation and the later decode update. */
    entry = btb_lookup(&btb, pc, &btb_stats);
    if (entry != NULL && entry->target != target) btb_stats.target_mismatches++;
    for (i = PRED_ALWAYS_NOT_TAKEN; i <= PRED_BTFN; i++) {
      enum predictor predictor = (enum predictor)i;
      prediction_t ideal_prediction = make_prediction(
          predictor, NULL, pc, target, backward, true);
      prediction_t calibrated_prediction = make_prediction(
          predictor, entry, pc, target, backward, cfg.btb_entries == 0);

      update_stats(&ideal_stats[i], ideal_prediction, actual_taken, actual_next_pc);
      update_stats(&calibrated_stats[i], calibrated_prediction, actual_taken,
                   actual_next_pc);
    }
    /* Every decoded conditional branch refreshes its entry, including not-taken. */
    btb_update(&btb, pc, target, backward, &btb_stats);
  }
  if (ferror(fp)) {
    fprintf(stderr, "branchsim: error while reading '%s'\n", cfg.btrace_path);
    fclose(fp);
    btb_destroy(&btb);
    return EXIT_FAILURE;
  }
  fclose(fp);

  if (!cfg.total_insts_from_cli && trace_total_insts_found) {
    cfg.total_insts = trace_total_insts;
  }
  if (!cfg.total_insts_from_cli && !trace_total_insts_found) {
    cfg.total_insts = calibrated_stats[PRED_ALWAYS_NOT_TAKEN].branches;
    fprintf(stderr,
            "branchsim: no dynamic instruction count supplied; using branch count "
            "(%" PRIu64 ") for cycle/IPC estimate\n",
            cfg.total_insts);
  }
  if (cfg.total_insts < calibrated_stats[PRED_ALWAYS_NOT_TAKEN].branches) {
    fprintf(stderr,
            "branchsim: total instruction count (%" PRIu64 ") is smaller than "
            "valid branches (%" PRIu64 ")\n",
            cfg.total_insts, calibrated_stats[PRED_ALWAYS_NOT_TAKEN].branches);
    btb_destroy(&btb);
    return EXIT_FAILURE;
  }
  ant_cycles = cycles_for(&calibrated_stats[PRED_ALWAYS_NOT_TAKEN], cfg.total_insts,
                          cfg.mispredict_penalty, PRED_ALWAYS_NOT_TAKEN);

  printf("btrace: %s\n", cfg.btrace_path);
  printf("Input:  %" PRIu64 " lines, %" PRIu64 " comments/blank, %" PRIu64
         " malformed, %" PRIu64 " non-branch opcode, %" PRIu64
         " reserved branch funct3 skipped\n",
         input.lines, input.blank_or_comment, input.malformed,
         input.invalid_opcode, input.invalid_funct3);
  if (cfg.total_insts_from_cli) {
    printf("Total instruction source: --total-insts\n");
  } else if (trace_total_insts_found) {
    printf("Total instruction source: btrace metadata\n");
  } else {
    printf("Total instruction source: valid branch count fallback\n");
  }
  printf("Mispredict penalty: %" PRIu64 " cycles\n", cfg.mispredict_penalty);
  print_btb_result(&btb_stats, cfg.btb_entries);
  printf("Performance uses BTB-calibrated next-PC mispredictions.\n\n");

  if (cfg.predictor == PRED_ALL) {
    for (i = PRED_ALWAYS_NOT_TAKEN; i <= PRED_BTFN; i++) {
      print_result(&ideal_stats[i], &calibrated_stats[i], (enum predictor)i,
                   cfg.total_insts,
                   cfg.mispredict_penalty, ant_cycles);
      if (i != PRED_BTFN) putchar('\n');
    }
  } else {
    print_result(&ideal_stats[cfg.predictor], &calibrated_stats[cfg.predictor],
                 cfg.predictor, cfg.total_insts,
                 cfg.mispredict_penalty, ant_cycles);
  }
  btb_destroy(&btb);
  return EXIT_SUCCESS;
}
