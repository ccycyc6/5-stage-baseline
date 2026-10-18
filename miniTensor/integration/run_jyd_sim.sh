#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build the RT-Thread Nano firmware with the miniTensor driver and run it on
# the Verilator model of the real Mundus/NPC core.
#
#   ./integration/run_jyd_sim.sh                      # boots, runs mt_gemm, quits
#   JYD_CONSOLE_CMDS='help;quit' ./integration/run_jyd_sim.sh
#
# Environment prerequisites (see integration/README.md section 6):
#   * npc/mill present and Java 21 selected
#   * npc/configs/build generated, with CONFIG_RVE=n and CONFIG_BP_TAGE=y
#   * npc/vsrc/build/Mundus.sv elaborated
#   * (nvboard is NOT needed here; only the rtthread-nano submodule is)
# ---------------------------------------------------------------------------
set -euo pipefail

# miniTensor is local; the legacy Mundus CPU/BSP must be supplied separately.
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MT_HOME=${MT_HOME:-$(cd "$SELF_DIR/.." && pwd)}
if [[ -z "${MUNDUS_HOME:-}" ]]; then
    echo "Set MUNDUS_HOME to the external Mundus project containing npc/ and rtthread-nano/." >&2
    echo "This script runs the legacy Mundus integration, not the ARES Core." >&2
    exit 1
fi
MUNDUS_HOME=$(cd "$MUNDUS_HOME" && pwd)
NPC_HOME=$MUNDUS_HOME/npc
BSP=$MUNDUS_HOME/rtthread-nano/rt-thread/bsp/MundusJyd
for required in "$NPC_HOME/Makefile" "$BSP/Makefile"; do
    if [[ ! -f "$required" ]]; then
        echo "Missing legacy integration dependency: $required" >&2
        exit 1
    fi
done

export MUNDUS_HOME NPC_HOME MT_HOME
# nvboard is optional.  Point NVBOARD_HOME at the (possibly empty) in-repo
# path so a stale NVBOARD_HOME in the environment cannot pull nvboard.mk back in.
export NVBOARD_HOME=$MUNDUS_HOME/nvboard
# mill needs Java 11+.  JAVA_HOME often points at Java 8, so prefer JAVA_HOME_21,
# then a JDK 21 installed in the usual place.
if [[ -n "${JAVA_HOME_21:-}" ]]; then
    export JAVA_HOME=$JAVA_HOME_21
elif [[ -x /usr/lib/jvm/java-21-openjdk-amd64/bin/java ]]; then
    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
elif [[ -x /usr/lib/jvm/openjdk-21/bin/java ]]; then
    export JAVA_HOME=/usr/lib/jvm/openjdk-21
fi
# npc/Makefile invokes a bare 'mill', not $(MILL).
export PATH=$NPC_HOME:$PATH

CROSS_COMPILE=${CROSS_COMPILE:-riscv64-unknown-elf-}
JYD_CONSOLE_CMDS=${JYD_CONSOLE_CMDS:-mt_gemm;quit}
export JYD_CONSOLE_CMDS

# The full miniTensor test set plus CoreMark does not fit in the 32 KiB IROM
# with this (GCC 13.2, no -mtune=mundus) toolchain, so accelerator builds skip
# CoreMark by default.  A CoreMark build must also drop the test set, e.g.
#   MT_WITH_COREMARK=1 MT_TESTS="" COREMARK_OPT_FLAGS=-Os \
#     JYD_CONSOLE_CMDS='coremark;quit' ./integration/run_jyd_sim.sh
# (plain -O3, or the full MT_TESTS set, overflows the IROM.)
MT_WITH_COREMARK=${MT_WITH_COREMARK:-0}
export MT_WITH_COREMARK

COREMARK_FLAGS=(
    COREMARK_HW_CRC=${COREMARK_HW_CRC:-0}
    COREMARK_HW_MATRIX=${COREMARK_HW_MATRIX:-0}
    COREMARK_OPT_FLAGS=${COREMARK_OPT_FLAGS:--Os}
)

# Forward MT_TESTS only when explicitly set, so MT_TESTS="" means "no test
# modules" while leaving it unset keeps the Makefile default.
MT_TESTS_ARG=()
if [[ -v MT_TESTS ]]; then MT_TESTS_ARG=(MT_TESTS="$MT_TESTS"); fi

echo "== building firmware =="
make -C "$BSP" CROSS_COMPILE="$CROSS_COMPILE" \
    MUNDUS_HOME="$MUNDUS_HOME" NPC_HOME="$NPC_HOME" MT_HOME="$MT_HOME" \
    "${COREMARK_FLAGS[@]}" ${MT_TESTS_ARG[@]+"${MT_TESTS_ARG[@]}"} image

echo "== building and running the Mundus + miniTensor simulation =="
make -C "$BSP" CROSS_COMPILE="$CROSS_COMPILE" \
    MUNDUS_HOME="$MUNDUS_HOME" NPC_HOME="$NPC_HOME" MT_HOME="$MT_HOME" \
    "${COREMARK_FLAGS[@]}" ${MT_TESTS_ARG[@]+"${MT_TESTS_ARG[@]}"} \
    VERILATOR_RESET=0 run
