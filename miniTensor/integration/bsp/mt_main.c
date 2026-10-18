/*
 * mt_main.c -- RT-Thread entry point for the accelerator-only image.
 *
 * Used instead of competition_app.c when MT_WITH_COREMARK=0.  CoreMark and the
 * miniTensor drivers no longer fit together in the 32 KiB IROM with the
 * riscv64-unknown-elf 13.2 toolchain available here (the BSP was tuned for a
 * GCC 16.1 build with -mtune=mundus), so the benchmark is dropped when the
 * image only needs to exercise the accelerator.
 */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"

int finsh_system_init(void);

static int quit_command(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    rt_kprintf("Exit simulation.\n");
    halt(0);
}
MSH_CMD_EXPORT_ALIAS(quit_command, quit, exit Verilator simulation.);

int main(void)
{
    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    rt_kprintf("MundusJyd miniTensor shell ready.\n");
    rt_kprintf("Commands: help, mt_gemm, mt_memtest, mt_conv, quit.\n");

    return finsh_system_init();
}
