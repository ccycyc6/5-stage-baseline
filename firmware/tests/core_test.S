    .section .text
    .globl _start
_start:
    li   x1, 0
    li   x2, 10
    li   x3, 0
1:
    add  x3, x3, x2
    addi x2, x2, -1
    bnez x2, 1b

    li   x4, 0x80001000
    sw   x3, 0(x4)          # 55

    li   x5, 7
    li   x6, 6
    mul  x7, x5, x6         # 42
    sw   x7, 4(x4)

    li   x8, 100
    li   x9, 7
    div  x10, x8, x9        # 14
    sw   x10, 8(x4)
    rem  x11, x8, x9        # 2
    sw   x11, 12(x4)

    li   x12, 0x12345678
    sw   x12, 16(x4)
    lb   x13, 16(x4)        # 0x78
    sw   x13, 20(x4)
    lbu  x14, 19(x4)        # 0x12
    sw   x14, 24(x4)

    li   x15, 1
    li   x16, 2
    blt  x15, x16, 2f
    li   x17, 0xdead
    j    3f
2:
    li   x17, 0xbeef
3:
    sw   x17, 28(x4)

    fence
    fence.i
    ebreak
    j    .
