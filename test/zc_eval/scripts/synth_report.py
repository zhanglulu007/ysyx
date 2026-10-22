#!/usr/bin/env python3
"""Parse one synthesis run: area + max frequency + critical endpoint."""
import os
import re
import sys

tag = sys.argv[1] if len(sys.argv) > 1 else "opt"
d = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "result", f"synth-{tag}")

area = None
seq = None
freq = None
slack = None
endpoint = None

stat = os.path.join(d, "synth_stat.txt")
if os.path.exists(stat):
    txt = open(stat, errors="ignore").read()
    m = re.search(r"Chip area for module '\\\\?NPCSynth[^']*':\s*([0-9.]+)", txt)
    if m:
        area = float(m.group(1))
    m = re.search(r"sequential elements:\s*([0-9.]+)", txt)
    if m:
        seq = float(m.group(1))

rpt = None
for f in os.listdir(d) if os.path.isdir(d) else []:
    if f.endswith(".rpt"):
        rpt = os.path.join(d, f)
if rpt and os.path.exists(rpt):
    best = None
    for line in open(rpt, errors="ignore"):
        if "core_clock" in line and "| max" in line:
            cols = [c.strip() for c in line.split("|")]
            # | endpoint | clock | type | delay | required | cppr | slack | freq |
            try:
                f = float(cols[8])
            except (ValueError, IndexError):
                continue
            if best is None or f < best[0]:
                best = (f, cols[1], cols[7])
    if best:
        freq = best[0]
        slack = best[2]
        endpoint = best[1]

print(f"[synth-{tag}] dir={d}")
print(f"  area      : {area}")
print(f"  seq_area  : {seq}")
print(f"  max_freq  : {freq} MHz")
print(f"  wns       : {slack} ns")
print(f"  endpoint  : {endpoint}")

# machine-readable line
print(f"RESULT {tag} area={area} seq={seq} freq={freq} wns={slack}")
