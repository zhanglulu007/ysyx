#!/usr/bin/env python3
"""Summarise sim + synth results for baseline and optimised NPC."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESULT = os.path.join(HERE, "..", "result")


def sim_info(tag):
    # stdout 每次运行都会覆盖；log 是追加的，因此优先 stdout 并取最后一次
    for name in (f"sim-{tag}.stdout", f"sim-{tag}.log"):
        log = os.path.join(RESULT, name)
        if os.path.exists(log):
            txt = open(log, errors="ignore").read()
            ms = re.findall(r"Executed (\d+) instructions in (\d+) cycles, IPC=([0-9.]+)", txt)
            if ms:
                inst, cyc, ipc = int(ms[-1][0]), int(ms[-1][1]), float(ms[-1][2])
                ok = "HIT GOOD TRAP" in txt or "MicroBench PASS" in txt
                return {"inst": inst, "cycles": cyc, "ipc": ipc, "ok": ok}
    return None


def synth_info(tag):
    d = os.path.join(RESULT, f"synth-{tag}")
    area = freq = seq = wns = None
    stat = os.path.join(d, "synth_stat.txt")
    if os.path.exists(stat):
        txt = open(stat, errors="ignore").read()
        m = re.search(r"Chip area for module '\\\\?NPC[^']*':\s*([0-9.]+)", txt)
        if m:
            area = float(m.group(1))
        m = re.search(r"sequential elements:\s*([0-9.]+)", txt)
        if m:
            seq = float(m.group(1))
    rpt = None
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith(".rpt"):
                rpt = os.path.join(d, f)
    if rpt and os.path.exists(rpt):
        best = None
        for line in open(rpt, errors="ignore"):
            if "core_clock" in line and "| max" in line:
                cols = [c.strip() for c in line.split("|")]
                try:
                    f = float(cols[8])
                except (ValueError, IndexError):
                    continue
                if f > 0 and (best is None or f < best[0]):
                    best = (f, cols[7])
        if best:
            freq, wns = best
    return {"area": area, "seq": seq, "freq": freq, "wns": wns}


def line(label):
    b = sim_info("base")
    o = sim_info("opt")
    sb = synth_info("base")
    so = synth_info("opt")
    rows = [("baseline", b, sb), ("optimized", o, so)]
    print(f"\n{label}\n" + "=" * 78)
    print(f"{'':12s} {'IPC':>8s} {'inst':>12s} {'cycles':>12s} "
          f"{'MHz':>8s} {'area':>10s} {'score':>10s} {'ok':>5s}")
    for name, sim, syn in rows:
        ipc = sim["ipc"] if sim else 0.0
        freq = syn["freq"] if syn and syn["freq"] else 0.0
        area = syn["area"] if syn and syn["area"] else 0.0
        score = ipc * freq
        inst = sim["inst"] if sim else 0
        cyc = sim["cycles"] if sim else 0
        ok = "PASS" if (sim and sim["ok"]) else "--"
        print(f"{name:12s} {ipc:8.4f} {inst:12d} {cyc:12d} "
              f"{freq:8.1f} {area:10.1f} {score:10.1f} {ok:>5s}")
    if b and o and sb and so and sb["freq"]:
        dscore = (o["ipc"] * so["freq"]) / (b["ipc"] * sb["freq"])
        print(f"\nIPC x freq speedup: {dscore:.2f}x   "
              f"(area {so['area']:.1f}, limit 25000)")
    print()


def main():
    line("NPC optimisation summary")
    smoke = os.path.join(RESULT, "smoke-opt.stdout")
    if os.path.exists(smoke):
        txt = open(smoke, errors="ignore").read()
        print("smoke-opt:", "HIT GOOD TRAP" if "HIT GOOD TRAP" in txt else
              ("BAD TRAP" if "BAD TRAP" in txt else "no result"))


if __name__ == "__main__":
    main()
