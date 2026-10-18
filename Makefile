# ARES-P4 SoC build / regression entry points.
#
#   make lint        - Verilator lint of the synthesizable SoC
#   make sim         - build the Verilator SoC simulator
#   make core-test   - 5-stage core directed ISA test
#   make coremark    - CoreMark v1.0 on hart0
#   make smp         - 4-hart mailbox/barrier/scratchpad test
#   make mt-gemm     - miniTensor DMA + GEMM + epilogue test
#   make yolo        - packed INT8 YOLO detector on miniTensor
#   make board       - rebuild CoreMark with board baud divisor

RISCV_PREFIX ?= riscv64-unknown-elf-
CC           := $(RISCV_PREFIX)gcc
OBJCOPY      := $(RISCV_PREFIX)objcopy
SIZE         := $(RISCV_PREFIX)size
VERILATOR    ?= verilator

ITERATIONS     ?= 10
DET_IMG_COUNT  ?= 1
UART_DIV       ?= 8
BOARD_UART_DIV ?= 868

ARCH   := -march=rv32im_zicsr_zifencei -mabi=ilp32
CFLAGS := $(ARCH) -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles \
          -mno-relax -msmall-data-limit=0 -Ifirmware -Ifirmware/common \
          -DUART_DIV=$(UART_DIV)
LDFLAGS := $(ARCH) -nostdlib -nostartfiles -mno-relax -T firmware/common/linker.ld

RTL_COMMON := rtl/common/ares_pkg.sv
MT_RTL := \
  rtl/minitensor/interface/core_v_xif.sv \
  rtl/minitensor/common/minitensor_pkg.sv \
  rtl/minitensor/tensor/tensor_pkg.sv \
  rtl/minitensor/vector/vpu_pkg.sv \
  rtl/minitensor/vector/vpu_vector_regfile.sv \
  rtl/minitensor/vector/vpu_vector_alu.sv \
  rtl/minitensor/control/vpu_vector_controller.sv \
  rtl/minitensor/tensor/MXU/Systolic_Array/tensor_pe.sv \
  rtl/minitensor/tensor/MXU/Systolic_Array/tensor_systolic_array.sv \
  rtl/minitensor/tensor/MXU/INT8_GEMM/tensor_gemm_core.sv \
  rtl/minitensor/tensor/tensor_controller.sv \
  rtl/minitensor/tensor/Epilogue/tensor_epilogue_core.sv \
  rtl/minitensor/tensor/Epilogue/tensor_epilogue_controller.sv \
  rtl/minitensor/memory/unified_buffer.sv \
  rtl/minitensor/memory/vpu_dma.sv \
  rtl/minitensor/top/mini_tensor_top.sv
CORE_RTL := \
  rtl/core/ares_regfile.sv rtl/core/ares_csr.sv rtl/core/ares_bpu.sv \
  rtl/core/ares_muldiv.sv rtl/cache/ares_l1i.sv rtl/cache/ares_l1d.sv \
  rtl/core/ares_l_core.sv
SOC_RTL := \
  rtl/soc/mt/mt_cvxif_shim.sv rtl/soc/mt/mt_dma_l2_bridge.sv rtl/soc/mt/mt_cluster.sv \
  rtl/soc/ares_cluster.sv rtl/soc/ares_clint.sv rtl/soc/ares_plic.sv \
  rtl/soc/ares_mailbox.sv rtl/soc/ares_uart.sv rtl/soc/ares_gpio.sv \
  rtl/soc/ares_spi.sv rtl/soc/ares_periph_stub.sv rtl/soc/ares_mmio_bus.sv \
  rtl/soc/video/ares_video.sv rtl/soc/ares_l2.sv \
  rtl/soc/ddr/ddr3_model.sv rtl/soc/ddr/pango_ddr3_axi.sv rtl/soc/ares_p4_soc.sv
RTL_ALL := $(RTL_COMMON) $(MT_RTL) $(CORE_RTL) $(SOC_RTL)
TB_SOC  := sim/rtl/tb_soc.sv
TB_CORE := sim/rtl/tb_core.sv sim/rtl/tb_l2_mem.sv

.PHONY: all lint sim core-test coremark smp mt-gemm yolo video board clean

all: lint sim

lint:
	$(VERILATOR) --lint-only -Wall -Wno-fatal -Irtl/common -Irtl/minitensor \
	  $(RTL_ALL) --top-module ares_p4_soc

sim:
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Irtl/common -Irtl/minitensor \
	  $(RTL_ALL) $(TB_SOC) --top-module tb_soc --Mdir build/obj_soc -o Vtb_soc

# ---------------------------------------------------------------- core test
core-test:
	mkdir -p build
	$(CC) $(ARCH) -nostdlib -nostartfiles -T firmware/tests/core_test.ld \
	  -o build/core_test.elf firmware/tests/core_test.S
	$(OBJCOPY) -O binary build/core_test.elf build/core_test.bin
	python3 sim/tools/bin2hex.py build/core_test.bin build/core_test.hex
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Irtl/common \
	  rtl/common/ares_pkg.sv rtl/core/ares_regfile.sv rtl/core/ares_csr.sv \
	  rtl/core/ares_bpu.sv rtl/core/ares_muldiv.sv rtl/cache/ares_l1i.sv \
	  rtl/cache/ares_l1d.sv rtl/core/ares_l_core.sv $(TB_CORE) \
	  --top-module tb_core --Mdir build/obj_core -o Vtb_core
	./build/obj_core/Vtb_core

# ---------------------------------------------------------------- CoreMark
COREMARK_SRC := firmware/common/start.S firmware/common/runtime.c \
  firmware/coremark/core_list_join.c firmware/coremark/core_matrix.c \
  firmware/coremark/core_state.c firmware/coremark/core_util.c \
  firmware/coremark/core_portme.c firmware/coremark/main.c

build/coremark/coremark.elf: $(COREMARK_SRC) firmware/coremark/core_main.c
	mkdir -p build/coremark
	rm -f build/coremark/*.o
	for f in $(COREMARK_SRC); do \
	  $(CC) $(CFLAGS) -Ifirmware/coremark -DITERATIONS=$(ITERATIONS) \
	    -c $$f -o build/coremark/$$(basename $$f).o; \
	done
	$(CC) $(CFLAGS) -Ifirmware/coremark -DITERATIONS=$(ITERATIONS) \
	  -Dmain=coremark_main -c firmware/coremark/core_main.c \
	  -o build/coremark/core_main.c.o
	$(CC) $(LDFLAGS) build/coremark/*.o -lgcc -o $@
	$(OBJCOPY) -O binary $@ build/coremark/coremark.bin
	python3 sim/tools/bin2hex.py build/coremark/coremark.bin build/coremark/coremark.hex
	$(SIZE) $@

coremark: build/coremark/coremark.elf sim
	./build/obj_soc/Vtb_soc +DDR=build/coremark/coremark.hex >/dev/null 2>&1 || true
	@echo "--- CoreMark UART output ---"
	@cat build/uart.log

board:
	rm -f build/coremark/coremark.elf
	$(MAKE) build/coremark/coremark.elf ITERATIONS=1000 UART_DIV=$(BOARD_UART_DIV)

# ---------------------------------------------------------------- SMP
smp: sim
	rm -rf build/smp
	mkdir -p build/smp
	$(CC) $(CFLAGS) -c firmware/common/start.S -o build/smp/start.o
	$(CC) $(CFLAGS) -c firmware/common/runtime.c -o build/smp/runtime.o
	$(CC) $(CFLAGS) -c firmware/tests/smp_test.c -o build/smp/smp_test.o
	$(CC) $(LDFLAGS) build/smp/*.o -lgcc -o build/smp/smp.elf
	$(OBJCOPY) -O binary build/smp/smp.elf build/smp/smp.bin
	python3 sim/tools/bin2hex.py build/smp/smp.bin build/smp/smp.hex
	./build/obj_soc/Vtb_soc +DDR=build/smp/smp.hex >/dev/null 2>&1 || true
	@echo "--- SMP UART output ---"
	@cat build/uart.log

# ---------------------------------------------------------------- miniTensor GEMM
mt-gemm: sim
	rm -rf build/mtgemm
	mkdir -p build/mtgemm
	$(CC) $(CFLAGS) -Ifirmware/yolo -c firmware/common/start.S -o build/mtgemm/start.o
	$(CC) $(CFLAGS) -Ifirmware/yolo -c firmware/common/runtime.c -o build/mtgemm/runtime.o
	$(CC) $(CFLAGS) -Ifirmware/yolo -c firmware/yolo/mt.c -o build/mtgemm/mt.o
	$(CC) $(CFLAGS) -Ifirmware/yolo -c firmware/tests/mt_gemm.c -o build/mtgemm/mt_gemm.o
	$(CC) $(LDFLAGS) build/mtgemm/*.o -lgcc -o build/mtgemm/mt_gemm.elf
	$(OBJCOPY) -O binary build/mtgemm/mt_gemm.elf build/mtgemm/mt_gemm.bin
	python3 sim/tools/bin2hex.py build/mtgemm/mt_gemm.bin build/mtgemm/mt_gemm.hex
	./build/obj_soc/Vtb_soc +DDR=build/mtgemm/mt_gemm.hex >/dev/null 2>&1 || true
	@echo "--- miniTensor UART output ---"
	@cat build/uart.log

# ---------------------------------------------------------------- YOLO
yolo: sim
	rm -rf build/yolo
	mkdir -p build/yolo
	for f in firmware/common/start.S firmware/common/runtime.c \
	         firmware/yolo/mt.c firmware/yolo/mt_net.c \
	         firmware/yolo/mt_detect.c firmware/yolo/main.c; do \
	  $(CC) $(CFLAGS) -Ifirmware/yolo -DDET_IMG_COUNT=$(DET_IMG_COUNT) \
	    -c $$f -o build/yolo/$$(basename $$f).o; \
	done
	$(CC) $(LDFLAGS) build/yolo/*.o -lgcc -o build/yolo/yolo.elf
	$(OBJCOPY) -O binary build/yolo/yolo.elf build/yolo/yolo.bin
	python3 sim/tools/bin2hex.py build/yolo/yolo.bin build/yolo/yolo.hex
	$(SIZE) build/yolo/yolo.elf
	./build/obj_soc/Vtb_soc +DDR=build/yolo/yolo.hex >/dev/null 2>&1 || true
	@echo "--- YOLO UART output ---"
	@cat build/uart.log

video:
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Irtl/common \
	  rtl/common/ares_pkg.sv rtl/soc/video/ares_video.sv sim/rtl/tb_video.sv \
	  --top-module tb_video --Mdir build/obj_video -o Vtb_video
	./build/obj_video/Vtb_video

clean:
	rm -rf build