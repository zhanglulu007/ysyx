# Minimal standalone NPC test program.
#
# Build:  make -C npc test/mem.bin   (or just: make -C npc run)
# Memory: linked at 0x80000000, the standalone NPC reset vector.
# Output: writes "OK\n" to the NPC serial port, then triggers a good trap.

    .section .text
    .globl _start

_start:
    li      t0, 0x10000000          # NPC serial port
    li      t1, 'O'
    sb      t1, 0(t0)
    li      t1, 'K'
    sb      t1, 0(t0)
    li      t1, '\n'
    sb      t1, 0(t0)

    li      a0, 0                   # a0 = 0 => HIT GOOD TRAP
    ebreak

1:
    j       1b
