#!/usr/bin/env python3
# Parse objdump text and emit addr,class,word CSV for the trace analyzer.
import re, sys

if len(sys.argv) != 3:
    print("usage: parse_disasm.py <objdump.txt> <out.csv>")
    sys.exit(1)

src, dst = sys.argv[1], sys.argv[2]
rx = re.compile(r'^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]+)\s+([a-zA-Z0-9_.]+)')

branch = {'beq','bne','blt','bge','bltu','bgeu',
          'beqz','bnez','blez','bgez','bltz','bgtz','bgt','ble','bgtu','bleu'}
jump = {'jal','jalr','j','jr','ret','call','tail'}
load = {'lb','lh','lw','lbu','lhu'}
store = {'sb','sh','sw'}
upper = {'lui','auipc'}
csr = {'csrrw','csrrs','csrrc','csrrwi','csrrsi','csrrci','ecall','ebreak','mret','fence.i','fence'}

rows = []
with open(src) as f:
    for line in f:
        m = rx.match(line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        word = int(m.group(2), 16)
        mn = m.group(3)
        if mn in branch: c = 'branch'
        elif mn in jump: c = 'jump'
        elif mn in load: c = 'load'
        elif mn in store: c = 'store'
        elif mn in upper: c = 'upper'
        elif mn in csr: c = 'csr'
        else: c = 'alu'
        rows.append((addr, c, word))

rows.sort()
with open(dst, 'w') as f:
    f.write('addr,class,word\n')
    for a, c, w in rows:
        f.write(f'{a:x},{c},{w:x}\n')
print(f'{len(rows)} instructions -> {dst}')
