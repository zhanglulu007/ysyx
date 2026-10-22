#!/usr/bin/env python3
import re, sys, collections

stat = sys.argv[1]
net = sys.argv[2]

area = {}
chip = 0.0
for line in open(stat):
    m = re.match(r'^\s+(\d+)\s+([0-9.Ee+-]+)\s+([A-Z0-9_]+)\s*$', line)
    if m:
        n = int(m.group(1)); a = float(m.group(2)); typ = m.group(3)
        area[typ] = a / n
    if 'Chip area' in line:
        chip = float(line.split(':')[1])

tot = collections.defaultdict(float)
cnt = collections.defaultdict(int)
rx = re.compile(r'^\s+([A-Z][A-Z0-9_]*)\s+\\?([^\s(]+)\s*\(')
for line in open(net):
    m = rx.match(line)
    if not m:
        continue
    typ, name = m.group(1), m.group(2)
    if typ not in area:
        continue
    p = name
    if p.startswith('u_top.u_icache'): grp = 'icache'
    elif p.startswith('u_top.u_regfile'): grp = 'regfile'
    elif p.startswith('u_top.u_idu'): grp = 'idu'
    elif p.startswith('u_top.u_exu'): grp = 'exu'
    elif p.startswith('u_top.u_lsu'): grp = 'lsu'
    elif p.startswith('u_top.u_csr'): grp = 'csr'
    elif p.startswith('u_top.u_arbiter'): grp = 'arbiter'
    elif p.startswith('u_top.u_ifu'): grp = 'ifu'
    elif p.startswith('u_top.u_wbu'): grp = 'wbu'
    else: grp = 'top/other'
    tot[grp] += area[typ]
    cnt[grp] += 1

print(f'chip area = {chip:.2f}')
s = 0.0
for k, v in sorted(tot.items(), key=lambda x: -x[1]):
    print(f'{k:12s} {v:10.2f}  {100*v/chip:5.1f}%  cells={cnt[k]}')
    s += v
print(f'{"sum":12s} {s:10.2f}  (unaccounted {chip-s:.2f})')
