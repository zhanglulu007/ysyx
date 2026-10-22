// tracesim: replay a committed-PC trace and model a 2/3-stage in-order core.
// usage: tracesim <trace.pc> <insn_class.csv> [options]
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unordered_map>
#include <vector>
#include <string>
#include <cmath>
#include <algorithm>

struct InsnInfo { uint8_t cls; uint32_t word; };

enum { C_ALU=0, C_BRANCH=1, C_JUMP=2, C_LOAD=3, C_STORE=4, C_UPPER=5, C_CSR=6 };

struct BtbEntry {
    bool valid = false;
    uint32_t tag = 0;
    uint32_t target = 0;
    uint8_t cnt = 3; // for BHT mode
};

struct Config {
    int sets = 4;
    int block = 32;
    int ways = 1;
    int miss_penalty = 3;     // fixed penalty per line miss (cycles)
    int branch_penalty = 1;   // bubbles per mispredict (2-stage=1, 3-stage=2)
    int btb_entries = 0;      // 0 = no BTB
    int btb_tag_bits = 12;
    int bht_bits = 0;         // >0: use 2-bit counters (bht_bits = index bits)
    bool ras = false;
    bool static_back = false; // oracle target, static backward direction
    int btb_hash = 0;         // 0 = no hash; else shift amount for XOR
};

struct CacheLine {
    bool valid = false;
    uint32_t tag = 0;
};

static inline int ilog2(int v) { int n=0; while ((1<<n) < v) n++; return n; }

struct Sim {
    Config cfg;
    std::vector<CacheLine> lines;
    std::vector<BtbEntry> btb;
    std::vector<uint8_t> bht;
    std::vector<uint32_t> ras;
    uint64_t inst=0, loads=0, stores=0, branches=0, taken=0, jumps=0;
    uint64_t btb_lookups=0, btb_hits=0, btb_target_hits=0, btb_misses=0;
    uint64_t ras_hits=0, ras_lookups=0;
    uint64_t mispredict=0, miss=0;
    uint64_t cycles=0;

    Sim(Config c): cfg(c), lines(size_t(c.sets)*c.ways), btb(c.btb_entries),
                   bht(c.bht_bits ? (1u<<c.bht_bits) : 0) {}

    uint32_t line_tag(uint32_t pc) const { return pc >> (ilog2(cfg.block)); }
    uint32_t line_index(uint32_t pc) const {
        int off = ilog2(cfg.block);
        int idx = ilog2(cfg.sets);
        return (pc >> off) & ((1u<<idx)-1);
    }

    void step(uint32_t pc, const InsnInfo &ii, uint32_t next, bool has_next) {
        inst++;
        // I-cache
        uint32_t tag = line_tag(pc);
        uint32_t idx = line_index(pc);
        bool hit = false;
        for (int w = 0; w < cfg.ways; w++) {
            auto &l = lines[size_t(idx)*cfg.ways + w];
            if (l.valid && l.tag == tag) { hit = true; break; }
        }
        if (!hit) {
            miss++;
            cycles += cfg.miss_penalty;
            // fill: first invalid way, else way 0 (approx LRU irrelevant for metadata)
            int victim = 0;
            for (int w = 0; w < cfg.ways; w++) {
                auto &l = lines[size_t(idx)*cfg.ways + w];
                if (!l.valid) { victim = w; break; }
            }
            auto &l = lines[size_t(idx)*cfg.ways + victim];
            l.valid = true; l.tag = tag;
        }

        bool is_ctrl = (ii.cls == C_BRANCH || ii.cls == C_JUMP);
        bool actual_taken = is_ctrl && has_next && (next != pc + 4);
        if (ii.cls == C_BRANCH) branches++;
        if (ii.cls == C_JUMP) jumps++;
        if (actual_taken) taken++;
        if (ii.cls == C_LOAD) loads++;
        if (ii.cls == C_STORE) stores++;

        if (!is_ctrl) { cycles += 1; return; }

        int idx_b = 0;
        bool pred_taken = false;
        uint32_t pred_target = pc + 4;
        bool used_ras = false;

        uint32_t rd   = (ii.word >> 7) & 0x1f;
        uint32_t rs1  = (ii.word >> 15) & 0x1f;

        // RAS prediction for returns
        if (cfg.ras && ii.cls == C_JUMP && rd == 0 && rs1 == 1 && !ras.empty()) {
            pred_taken = true;
            pred_target = ras.back();
            used_ras = true;
            ras_lookups++;
            if (actual_taken && pred_target == next) ras_hits++;
        } else if (cfg.btb_entries > 0) {
            int nbits = ilog2(cfg.btb_entries);
            uint32_t idx_raw = (pc >> 2);
            if (cfg.btb_hash) idx_raw ^= (pc >> cfg.btb_hash);
            idx_b = idx_raw & (cfg.btb_entries - 1);
            BtbEntry &e = btb[idx_b];
            btb_lookups++;
            uint32_t tag_mask = (cfg.btb_tag_bits >= 32) ? 0xffffffffu
                                : ((1u << cfg.btb_tag_bits) - 1);
            uint32_t want_tag = (pc >> (2 + nbits)) & tag_mask;
            if (e.valid && e.tag == want_tag) {
                btb_hits++;
                if (cfg.bht_bits == 0) {
                    pred_taken = true;
                    pred_target = e.target;
                } else {
                    int bi = (pc >> 2) & ((1u<<cfg.bht_bits)-1);
                    if (bht[bi] >= 2) { pred_taken = true; pred_target = e.target; }
                }
                if (pred_taken && pred_target == next) btb_target_hits++;
            } else {
                btb_misses++;
            }
        } else if (cfg.static_back) {
            // Oracle target, but direction chosen statically: backward branches taken,
            // jal taken, jalr not taken (unless RAS above).
            if (ii.cls == C_JUMP) {
                pred_taken = true;
                pred_target = next; // oracle target
            } else if (ii.cls == C_BRANCH) {
                bool backward = (ii.word >> 31) & 1; // imm sign bit for B-type
                if (backward) { pred_taken = true; pred_target = next; }
            }
        }

        bool correct;
        if (!actual_taken) {
            correct = !pred_taken;
        } else {
            correct = pred_taken && (pred_target == next);
        }
        if (!correct) {
            mispredict++;
            cycles += cfg.branch_penalty;
        }

        // Update BTB/BHT
        if (cfg.btb_entries > 0) {
            int nbits = ilog2(cfg.btb_entries);
            uint32_t idx_raw = (pc >> 2);
            if (cfg.btb_hash) idx_raw ^= (pc >> cfg.btb_hash);
            int bi = idx_raw & (cfg.btb_entries - 1);
            BtbEntry &e = btb[bi];
            if (actual_taken) {
                e.valid = true;
                uint32_t tag_mask = (cfg.btb_tag_bits >= 32) ? 0xffffffffu
                                    : ((1u << cfg.btb_tag_bits) - 1);
                e.tag = (pc >> (2 + nbits)) & tag_mask;
                e.target = next;
            }
            if (cfg.bht_bits) {
                int hi = (pc >> 2) & ((1u<<cfg.bht_bits)-1);
                if (actual_taken) { if (bht[hi] < 3) bht[hi]++; }
                else { if (bht[hi] > 0) bht[hi]--; }
            }
        }

        // RAS update
        if (cfg.ras) {
            bool is_call = (ii.cls == C_JUMP) && (rd == 1);
            bool is_ret  = (ii.cls == C_JUMP) && (rd == 0) && (rs1 == 1);
            if (is_call) {
                if (ras.size() < 8) ras.push_back(pc + 4);
                else { ras.erase(ras.begin()); ras.push_back(pc + 4); }
            } else if (is_ret && !ras.empty()) {
                ras.pop_back();
            }
        }

        cycles += 1;
    }
};

static std::unordered_map<uint32_t, InsnInfo> load_classes(const char *path) {
    std::unordered_map<uint32_t, InsnInfo> m;
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); exit(1); }
    char line[256];
    if (!fgets(line, sizeof(line), f)) { fclose(f); return m; }
    while (fgets(line, sizeof(line), f)) {
        unsigned addr, word; char cls[32];
        if (sscanf(line, "%x,%31[^,],%x", &addr, cls, &word) == 3) {
            InsnInfo ii{};
            if (!strcmp(cls,"alu")) ii.cls=C_ALU;
            else if (!strcmp(cls,"branch")) ii.cls=C_BRANCH;
            else if (!strcmp(cls,"jump")) ii.cls=C_JUMP;
            else if (!strcmp(cls,"load")) ii.cls=C_LOAD;
            else if (!strcmp(cls,"store")) ii.cls=C_STORE;
            else if (!strcmp(cls,"upper")) ii.cls=C_UPPER;
            else ii.cls=C_CSR;
            ii.word = word;
            m[addr] = ii;
        }
    }
    fclose(f);
    return m;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("usage: %s trace.pc insn_class.csv [--sets N --block B --ways W --penalty P --branch-penalty B --btb N --btb-tag T --bht N --ras 0/1 --static-back 0/1]\n", argv[0]);
        return 1;
    }
    auto cls = load_classes(argv[2]);
    Config cfg;
    for (int i = 3; i + 1 < argc; i += 2) {
        const char *k = argv[i]; int v = atoi(argv[i+1]);
        if (!strcmp(k,"--sets")) cfg.sets=v;
        else if (!strcmp(k,"--block")) cfg.block=v;
        else if (!strcmp(k,"--ways")) cfg.ways=v;
        else if (!strcmp(k,"--penalty")) cfg.miss_penalty=v;
        else if (!strcmp(k,"--branch-penalty")) cfg.branch_penalty=v;
        else if (!strcmp(k,"--btb")) cfg.btb_entries=v;
        else if (!strcmp(k,"--btb-tag")) cfg.btb_tag_bits=v;
        else if (!strcmp(k,"--bht")) cfg.bht_bits=v;
        else if (!strcmp(k,"--ras")) cfg.ras=v;
        else if (!strcmp(k,"--static-back")) cfg.static_back=v;
        else if (!strcmp(k,"--btb-hash")) cfg.btb_hash=v;
        else { fprintf(stderr,"unknown %s\n",k); return 1; }
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    Sim sim(cfg);
    const size_t N = 1<<20;
    std::vector<uint32_t> buf(N);
    size_t got;
    uint32_t prev = 0; bool have_prev = false;
    uint64_t unknown = 0;
    while ((got = fread(buf.data(), 4, N, f)) > 0) {
        for (size_t i = 0; i < got; i++) {
            if (have_prev) {
                uint32_t cur = prev;
                auto it = cls.find(cur);
                if (it != cls.end()) sim.step(cur, it->second, buf[i], true);
                else { sim.inst++; sim.cycles++; unknown++; }
            }
            prev = buf[i]; have_prev = true;
        }
    }
    fclose(f);
    // last instruction: no next pc; treat as not taken, just count
    auto it = cls.find(prev);
    if (it != cls.end()) sim.step(prev, it->second, prev+4, false);
    else { sim.inst++; sim.cycles++; }

    double cpi = double(sim.cycles)/sim.inst;
    printf("inst=%llu cycles=%llu CPI=%.4f IPC=%.4f  (loads=%llu stores=%llu branch=%llu taken=%llu jump=%llu)\n",
        (unsigned long long)sim.inst,(unsigned long long)sim.cycles,cpi,1.0/cpi,
        (unsigned long long)sim.loads,(unsigned long long)sim.stores,
        (unsigned long long)sim.branches,(unsigned long long)sim.taken,(unsigned long long)sim.jumps);
    printf("icache: sets=%d ways=%d block=%dB miss=%llu (%.2f%%) penalty=%d\n",
        cfg.sets,cfg.ways,cfg.block,(unsigned long long)sim.miss,
        100.0*sim.miss/sim.inst,cfg.miss_penalty);
    printf("branch: penalty=%d BTB=%d tag=%d BHT=%d RAS=%d static=%d mispred=%llu (%.2f%%) ",
        cfg.branch_penalty,cfg.btb_entries,cfg.btb_tag_bits,cfg.bht_bits,cfg.ras,cfg.static_back,
        (unsigned long long)sim.mispredict,100.0*sim.mispredict/sim.inst);
    if (cfg.btb_entries) printf("btb_lookup=%llu hit=%.2f%% target_correct=%.2f%%",
        (unsigned long long)sim.btb_lookups,100.0*sim.btb_hits/std::max<uint64_t>(1,sim.btb_lookups),
        100.0*sim.btb_target_hits/std::max<uint64_t>(1,sim.btb_lookups));
    if (cfg.ras) printf(" ras_hit=%.2f%%",100.0*sim.ras_hits/std::max<uint64_t>(1,sim.ras_lookups));
    printf(" unknown=%llu\n",(unsigned long long)unknown);
    return 0;
}
