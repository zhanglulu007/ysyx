.section .text
.globl _start
_start:
    la t0, patch_site
    li t1, 0x12300513        # addi a0, zero, 0x123
    sw t1, 0(t0)
    fence.i
    li a0, 0
    jalr ra, 0(t0)
check:
    li t2, 0x123
    bne a0, t2, fail
    li a0, 0
    j done
fail:
    li a0, 1
done:
    ebreak
patch_site:
    nop
    j check
