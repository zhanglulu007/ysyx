#!/usr/bin/env bash
# 汇总仿真 IPC 与综合 PPA (面积/频率), 便于报告复现
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/result"
EVAL="$ROOT/eval/result"

echo "================ NPC TEST SUMMARY ================"
for f in "$RES"/microbench-*.log; do
  [ -f "$f" ] || continue
  echo "-- $(basename "$f")"
  grep -E "Executed .* instructions in .* cycles, IPC=" "$f" | tail -1 || true
  grep -E "MicroBench (PASS|FAIL)" "$f" | tail -1 || true
done

for v in base opt pipe3; do
  d="$EVAL/NPCSynth-$v-1200MHz"
  [ -n "$d" ] || continue
  echo ""
  echo "-- NPCSynth $v ($(basename "$d"))"
  grep -E "Chip area for module|used for sequential elements" "$d/synth_stat.txt" 2>/dev/null | sed 's/^[[:space:]]*/   /'
  awk -F'|' '/core_clock/ && /\| max / {gsub(/ /,"",$9); if ($9 ~ /^[0-9.]+$/ && (min=="" || $9+0<min)) {min=$9+0; ep=$2}} END {if (min!="") {gsub(/^ +| +$/,"",ep); printf "   最高频率: %.3f MHz   关键路径: %s\n", min, ep}}' "$d/NPCSynth.rpt" 2>/dev/null
done

echo ""
echo "指标口径: IPC 来自 standalone microbench train; Fmax 来自 yosys-sta (icsprout55, 1200MHz 约束)"
echo "=================================================="
