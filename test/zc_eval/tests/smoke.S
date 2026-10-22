# ============================================================================
# RV32E 冒烟测试: ALU/依赖旁路/load-store/分支/BTB/jal-jalr/CSR/fence.i
# 失败时 a0 = 用例编号, ebreak; 成功时 a0 = 0。
# 只使用 RV32E 的 x0-x15。
# ============================================================================
.option norvc
.section .text
.globl _start

.macro CHK_EQ ra_, rb_, code
    beq \ra_, \rb_, 1f
    li  a0, \code
    j   fail
1:
.endm

.macro CHK_NE ra_, rb_, code
    bne \ra_, \rb_, 1f
    li  a0, \code
    j   fail
1:
.endm

_start:
    j   t_alu

fail:
    ebreak

t_alu:
    # x0 恒零
    addi x0, x0, 5
    CHK_EQ x0, x0, 1

    # ALU + 连续 RAW 依赖 (EX->EX 旁路)
    li   t0, 5
    addi t0, t0, 7          # 12
    add  t1, t0, t0         # 24
    sub  t2, t1, t0         # 12
    xori t2, t2, 0xff       # 243
    li   t0, 243
    CHK_EQ t2, t0, 2

    li   t0, -1
    srai t1, t0, 4
    li   t0, -1
    CHK_EQ t1, t0, 3
    srli t2, t1, 28         # 0xF
    li   t0, 15
    CHK_EQ t2, t0, 4

    li   t0, 1
    slli t1, t0, 31
    srli t2, t1, 31
    li   t0, 1
    CHK_EQ t2, t0, 5

    li   t0, -5
    li   t1, 3
    slt  t2, t0, t1
    li   t0, 1
    CHK_EQ t2, t0, 6
    sltu t2, t1, t0
    CHK_EQ t2, x0, 7

    # lui / auipc
    lui  t0, 0x12345
    li   t1, 0x12345000
    CHK_EQ t0, t1, 8
    auipc t0, 0
    auipc t1, 0
    addi t0, t0, 4
    CHK_EQ t0, t1, 9

    # load/store: word
    la   t0, data
    li   t1, 0x12345678
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    CHK_EQ t1, t2, 10
    addi t2, t2, 1
    li   t1, 0x12345679
    CHK_EQ t1, t2, 11

    # byte sign/zero extend
    li   t1, 0x80
    sb   t1, 4(t0)
    lb   t2, 4(t0)
    li   t1, -128
    CHK_EQ t1, t2, 12
    lbu  t2, 4(t0)
    li   t1, 128
    CHK_EQ t1, t2, 13

    # half word
    li   t1, 0x5678
    sh   t1, 6(t0)
    lhu  t2, 6(t0)
    CHK_EQ t1, t2, 14

    li   t1, 0xabcd
    sh   t1, 8(t0)
    lh   t2, 8(t0)
    li   t1, -0x5433
    CHK_EQ t1, t2, 15

    # load-use 进分支
    li   t1, 7
    sw   t1, 12(t0)
    lw   t2, 12(t0)
    li   t1, 7
    CHK_EQ t2, t1, 16

    # 循环: 1..10 求和 = 55 (后向 taken 分支)
    li   t0, 0
    li   t1, 1
    li   t2, 11
loop1:
    add  t0, t0, t1
    addi t1, t1, 1
    blt  t1, t2, loop1
    li   t1, 55
    CHK_EQ t0, t1, 17

    # 嵌套循环 (两个后向分支争用 BTB)
    li   s0, 0
    li   s1, 0
outer:
    li   t0, 0
inner:
    addi s0, s0, 1
    addi t0, t0, 1
    li   t1, 4
    blt  t0, t1, inner
    addi s1, s1, 1
    li   t1, 3
    li   t2, 3
    CHK_EQ t1, t2, 26
    blt  s1, t1, outer
    li   t1, 12
    CHK_EQ s0, t1, 18

    # 前向分支: not-taken / taken
    li   t0, 2
    beq  t0, x0, fail
    bne  t0, x0, 1f
    j    fail
1:

    # 前向 taken 分支 (BTB 不应分配, 走重定向)
    li   t0, 1
    beq  t0, x0, 2f
    addi t1, x0, 7
2:
    li   t0, 7
    CHK_EQ t1, t0, 19

    # jal / jalr 函数调用 (BTB taken cache)
    li   s0, 0
    li   s1, 5
call_loop:
    jal  ra, func
    addi s0, s0, 1
    bne  s0, s1, call_loop
    li   t0, 5
    CHK_EQ s0, t0, 20
    CHK_EQ a1, t0, 21

    # CSR: csrw / csrs / csrr
    li   t0, 0x1800
    csrw mstatus, t0
    csrr t1, mstatus
    CHK_EQ t0, t1, 22
    li   t0, 8
    csrs mstatus, t0
    csrr t1, mstatus
    li   t0, 0x1808
    CHK_EQ t0, t1, 23
    csrw mstatus, zero
    csrr t1, mstatus
    CHK_EQ t1, zero, 24

    # fence.i: 冲刷 ICache/BTB 后从下一条继续
    .word 0x0000100F
    li   t0, 42
    li   t1, 42
    CHK_EQ t0, t1, 25

    # 成功
    li   a0, 0
    ebreak

# 被调用函数: 返回 a1=5
func:
    li   a1, 5
    jalr x0, 0(ra)

.section .data
.align 4
data:
    .space 64
