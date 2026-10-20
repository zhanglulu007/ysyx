#!/usr/bin/env bash
# Build a PC trace with NEMU, then sweep ICache parameters with cachesim.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${YSYX_HOME:-$(cd "$HERE/../../.." && pwd)}
NEMU_HOME=${NEMU_HOME:-$ROOT/nemu}
NPC_HOME=${NPC_HOME:-$ROOT/npc}
AM_KERNELS_HOME=${AM_KERNELS_HOME:-$ROOT/am-kernels}

CHECK=0
if [ "${1:-}" = "--check" ]; then
  CHECK=1
  shift
fi

IMAGE=${1:-$AM_KERNELS_HOME/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.bin}
TRACE=${2:-$NEMU_HOME/build/cachesim.trace}
NEMU_BIN=$NEMU_HOME/build/riscv32-nemu-interpreter-ysyxsoc
OUT=${OUT:-$HERE/dse.csv}

SIZES=${SIZES:-"256 512 1024 2048 4096 8192 16384 32768"}
BLOCKS=${BLOCKS:-"4 8 16 32 64"}
WAYS=${WAYS:-"1 2 4 8"}

if [ ! -f "$IMAGE" ]; then
  echo "[dse] missing image: $IMAGE" >&2
  echo "[dse] build it with: make -C $AM_KERNELS_HOME/benchmarks/microbench ARCH=riscv32e-ysyxsoc" >&2
  exit 1
fi

make -C "$HERE" cachesim >/dev/null

NEMU_STALE=0
if [ -x "$NEMU_BIN" ] && [ -n "$(find "$NEMU_HOME/src" "$NEMU_HOME/include" \
  -type f \( -name '*.c' -o -name '*.h' \) -newer "$NEMU_BIN" -print -quit 2>/dev/null)" ]; then
  NEMU_STALE=1
fi
if [ ! -x "$NEMU_BIN" ] || [ "$NEMU_HOME/Makefile" -nt "$NEMU_BIN" ] || \
   [ "$NEMU_HOME/configs/riscv32-ysyxsoc_defconfig" -nt "$NEMU_BIN" ] || \
   [ "$NEMU_STALE" = 1 ]; then
  echo "[dse] building NEMU trace binary..."
  make -C "$NEMU_HOME" cachesim-nemu
fi

if [ ! -s "$TRACE" ] || [ "$IMAGE" -nt "$TRACE" ]; then
  echo "[dse] generating PC trace: $TRACE"
  "$NEMU_BIN" -b -c "$TRACE" "$IMAGE" >"$NEMU_HOME/build/cachesim-nemu.log" 2>&1
fi

PENALTY=${PENALTY:-}
if [ -z "$PENALTY" ] && [ -f "$NPC_HOME/build/perf-microbench.log" ]; then
  PENALTY=$(awk '/avg miss latency/ {
    for (i = 1; i <= NF; i ++)
      if ($i ~ /^[0-9]+([.][0-9]+)?$/) { print $i; exit }
  }' "$NPC_HOME/build/perf-microbench.log")
fi
PENALTY=${PENALTY:-30}
CHECK_TOL=${CHECK_TOL:-0.001}

echo "size,block,ways,sets,accesses,hits,misses,bypass,hit_rate,miss_penalty,tmt,compulsory,replace" > "$OUT"
for size in $SIZES; do
  for block in $BLOCKS; do
    for ways in $WAYS; do
      if (( size % (block * ways) != 0 )); then continue; fi
      sets=$((size / (block * ways)))
      if (( (sets & (sets - 1)) != 0 )); then continue; fi
      "$HERE/cachesim" --trace "$TRACE" --size "$size" --block "$block" \
        --ways "$ways" --miss-penalty "$PENALTY" --csv >> "$OUT"
    done
  done
done

echo
echo "[dse] miss penalty = $PENALTY cycles"
echo "[dse] top configurations by TMT:"
if command -v column >/dev/null 2>&1; then
  { head -1 "$OUT"; tail -n +2 "$OUT" | sort -t, -k11,11n | head -15; } | column -t -s,
else
  { head -1 "$OUT"; tail -n +2 "$OUT" | sort -t, -k11,11n | head -15; }
fi

echo
echo "[dse] current NPC ICache (64B, 4B block, 1-way):"
"$HERE/cachesim" --trace "$TRACE" --size 64 --block 4 --ways 1 --miss-penalty "$PENALTY"

if [ "$CHECK" = 1 ]; then
  LOG=${NPC_PERF_LOG:-$NPC_HOME/build/perf-microbench.log}
  if [ -f "$LOG" ]; then
    ACCESS=$(grep -o 'icache_access=[0-9]*' "$LOG" | tail -1 | cut -d= -f2)
    HIT=$(grep -o 'icache_hit=[0-9]*' "$LOG" | tail -1 | cut -d= -f2)
    MISS=$(grep -o 'icache_miss=[0-9]*' "$LOG" | tail -1 | cut -d= -f2)
    REF=$("$HERE/cachesim" --trace "$TRACE" --size 64 --block 4 --ways 1 \
      --miss-penalty "$PENALTY" --csv)
    REF_ACCESS=$(echo "$REF" | cut -d, -f5)
    REF_HIT=$(echo "$REF" | cut -d, -f6)
    REF_MISS=$(echo "$REF" | cut -d, -f7)
    REF_COMP=$(echo "$REF" | cut -d, -f12)
    REF_REPL=$(echo "$REF" | cut -d, -f13)
    echo
    echo "[dse] performance DiffTest vs NPC (misses determine TMT):"
    echo "  NPC      access=$ACCESS hit=$HIT miss=$MISS"
    echo "  cachesim access=$REF_ACCESS hit=$REF_HIT miss=$REF_MISS"
    CR=$(grep -o 'compulsory / replace: [0-9]* / [0-9]*' "$LOG" | tail -1 || true)
    if [ -n "$CR" ]; then
      NPC_COMP=$(echo "$CR" | awk '{print $4}')
      NPC_REPL=$(echo "$CR" | awk '{print $6}')
      echo "  NPC      compulsory=$NPC_COMP replace=$NPC_REPL"
      echo "  cachesim compulsory=$REF_COMP replace=$REF_REPL"
    fi
    if [ -z "$MISS" ] || [ -z "$REF_MISS" ]; then
      echo "  SKIP (icache_miss not found in NPC log)"
    else
      DELTA=$((MISS - REF_MISS))
      ABS_DELTA=${DELTA#-}
      if [ "$ABS_DELTA" -eq 0 ]; then
        echo "  PASS (misses identical)"
      elif awk -v d="$ABS_DELTA" -v m="$MISS" -v t="$CHECK_TOL" \
        'BEGIN { exit !(m > 0 && d / m <= t) }'; then
        echo "  PASS (miss delta=$DELTA, within CHECK_TOL=$CHECK_TOL)"
      else
        echo "  MISMATCH (miss delta=$DELTA; use CHECK_TOL=0 for exact check)"
      fi
    fi
    # NEMU does not model UART THRE timing, so a program that polls UART
    # can have extra all-hit instructions in its PC stream.  Miss count is
    # still the right metric for TMT comparison.
  else
    echo "[dse] --check: $LOG not found; run 'make -C $NPC_HOME perf' first" >&2
  fi
fi

echo
echo "[dse] csv: $OUT"
