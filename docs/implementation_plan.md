# ARES-P4 SoC 实现计划（PG2L200H / 盘古 200Pro+）

> 目标：在紫光同创 PG2L200H-6IFBG676 上实现 4×ARES-L 五级流水 RISC-V 核、
> 共享 L2、DDR3、CLINT/PLIC、Mailbox、UART/GPIO/SPI/I2C/SD、视频链路，
> 每核挂 1 个工作区 miniTensor 作为 CV-X-IF 外挂 INT8 加速器；
> 跑通 CoreMark v1.0 与 YOLO 图像识别。

## 1. 设计范围

| 类别 | 实现 |
|---|---|
| 内核 | ARES-L：RV32IM + Zicsr + Zifencei，5 级单发射，2-bit BHT + BTB，完整 M-mode trap/中断 |
| 特权 | M-mode；mtvec Direct；MSIP/MTIP/MEIP；mcycle/minstret |
| 存储 | 每核 L1I 8 KiB 2-way、L1D 8 KiB 2-way、write-back/write-allocate；共享 L2 128 KiB 4-way + 128 KiB scratchpad；DDR3 1 GiB |
| 加速 | 4× miniTensor（CV-X-IF，4×4 INT8 GEMM + VPU + epilogue），每核命令行 FIFO，128-bit DMA |
| 系统 | CLINT 4 hart、PLIC 32 source/4 context、Mailbox/Barrier、Boot ROM、QSPI |
| 外设 | UART、GPIO、SPI、I2C、SD(SPI)、GbE 寄存器壳、DMA |
| 视频 | OV5640/DVP 捕获 → DDR 帧缓存 → 缩放/量化 → YOLO → OSD → HDMI TX |
| 软件 | 裸机 runtime、CoreMark 移植、INT8 YOLO 检测器、4 核 AMP worker |
| 验证 | Verilator SoC TB、ISA 定向测试、CoreMark CRC、YOLO golden、多核 mailbox/barrier、视频帧检查 |

## 2. 地址映射

| 起始 | 大小 | 区域 | 缓存 |
|---|---:|---|---|
| 0x0000_0000 | 64 KiB | Boot ROM | 否 |
| 0x0001_0000 | 64 KiB | CLINT | 否 |
| 0x0002_0000 | 64 KiB | PLIC | 否 |
| 0x0003_0000 | 64 KiB | Mailbox / Barrier | 否 |
| 0x1000_0000 | 128 KiB | L2 scratchpad（共享） | 否 |
| 0x1002_0000 | 64 KiB | per-core scratch（4×16 KiB） | 否 |
| 0x4000_0000 | 1 GiB | DDR3 uncached alias | 否 |
| 0x8000_0000 | 1 GiB | DDR3 cached | 是 |
| 0xC000_0000 | 16 MiB | QSPI flash 窗口 | 否 |
| 0xD000_0000 | 64 KiB | UART/GPIO/SPI/I2C/SD/GbE/Video/DMA | 否 |
| 0xE000_0000 | 16 KiB | miniTensor 0–3（每核 4 KiB） | 否 |
| 0xF000_0000 | 64 KiB | Debug / perf | 否 |

## 3. 微架构

### 3.1 ARES-L 五级流水

- IF：PC、BTB/BHT 预测、L1I 取指。
- ID：译码、GPR 2R、立即数、冒险检测、CSR 地址译码。
- EX：ALU、分支解析、地址生成、MUL/DIV 启动、转发。
- MEM：L1D 访问、非对齐检查、uncached/MMIO 访问。
- WB：寄存器写回、CSR 写、trap/中断提交、FENCE。

冒险：EX/MEM、MEM/WB 全转发；load-use 1 拍 stall；MUL 2 拍、DIV 33 拍；
分支 EX 解析，mispredict 2 拍 flush。异常在 WB 精确提交。

### 3.2 存储层次

- L1I/L1D：2-way、32 B line、LRU 近似；L1D write-back + write-allocate；
  fence 全 cache 回写并失效，fence.i 失效 L1I。
- L2：4-way、128 KiB、32 B line；4 core port + 1 video port，
  轮询仲裁，video 优先；miss 时 blocking refill/evict。
- scratchpad：128 KiB，16 B 字，uncached，供核间共享/YOLO tile/MT DMA。
- DDR3：AXI4 128-bit master；仿真用行为模型，FPGA 接 Pango DDR3 IP。

### 3.3 miniTensor 集成

每核一个 mt_cluster：
- mt_cvxif_shim：MMIO 寄存器 + 8 项命令 FIFO + CV-X-IF 时序。
- mini_tensor_top：工作区 RTL 原样例化。
- mt_dma_l2_bridge：把 miniTensor 128-bit 读写端口接到本核 L2 端口。
- 本核地址 0xE000_0000 + hart*0x1000 在 cluster 内解码，不占 SoC 总线。

寄存器：INSTR 0x00、RS1 0x04、RS2 0x08、KICK 0x0C、STATUS 0x10、RESULT 0x14。

### 3.4 多核启动

复位 PC = 0x0000_0000。Boot ROM 两条指令跳转到 0x8000_0000。
启动代码读 mhartid：hart0 初始化 UART/PLIC/CLINT/DDR，释放 hart1–3；
hart1–3 在 per-core scratch 等待 entry PC 与栈，进入 worker 循环。
核间同步使用 mailbox + barrier + fence；共享数据只放 scratchpad/uncached 区。

## 4. 目录

    rtl/common/        共享包
    rtl/core/          ARES-L 五级核
    rtl/cache/         L1I/L1D
    rtl/soc/           L2、总线、CLINT/PLIC/Mailbox、外设
    rtl/soc/mt/        miniTensor 包装
    rtl/soc/video/     捕获/缩放/OSD/HDMI
    rtl/soc/ddr/       DDR3 行为模型与 AXI 桥
    sim/               Verilator TB、DPI 内存、UART/视频模型
    firmware/          启动、runtime、CoreMark、YOLO
    fpga/pango/        PDS 工程、PDC/SDC、IP 说明
    docs/              架构、验证、性能报告

## 5. 验证门禁

1. make lint：Verilator 0 warning（允许既定 waive）。
2. make isa：RV32IM 定向测试通过。
3. make coremark：CoreMark CRC 校验通过，输出 Iterations/Sec、CoreMark/MHz。
4. make yolo：32×32 合成图/摄像头帧检测，bounding box 与 golden 一致。
5. make smp：4 核 mailbox/barrier、共享 scratchpad 读写一致。
6. make video：捕获→缩放→OSD→HDMI 时序/像素检查。
7. PDS：综合、布局布线、时序报告与资源报告归档。

## 6. 里程碑

| 阶段 | 内容 | 交付 |
|---|---|---|
| M1 | 包、ARES-L、L1、简单 TB | ISA 测试通过 |
| M2 | L2/scratchpad/CLINT/PLIC/UART | CoreMark 在单核 SoC 通过 |
| M3 | 4 核、mailbox/barrier、启动 | SMP 测试通过 |
| M4 | miniTensor 接入 | YOLO golden 通过 |
| M5 | 视频链路 | 摄像头/彩条→检测→OSD |
| M6 | Pango 工程、约束、报告 | 可上板 bitstream 流程 |

## 7. 当前实现状态（2026-10）

| 项目 | 状态 |
|---|---|
| ARES-L 五级核、CSR/trap、BHT+BTB、RV32IM | 已实现，定向 ISA 测试通过 |
| 2-way L1I/L1D、共享 L2、scratchpad | 已实现，CoreMark/SMP/scratchpad 测试通过 |
| 4 核启动、CLINT/PLIC、Mailbox/Barrier | 已实现，SMP 测试通过 |
| miniTensor CV-X-IF、DMA、4x4 GEMM/累加/epilogue | 已实现，定向测试通过 |
| CoreMark v1.0 | PASS，CRC 0xe714/0x1fd7/0x8e3a/0xfcaf，0.903 CoreMark/MHz |
| YOLO 检测器 | 全图执行完成（17,184 命令/图），阶段 golden 仍有偏差，见 docs/yolo_status.md |
| 视频 640x480/OSD/TMDS | 已实现，时序/OSD/TMDS 测试通过 |
| Pango PDS 工程/约束 | 模板已提供，未在本环境运行综合/布局布线 |

### 下一步

1. 修复 net_conv 在 L1 的 tile/行地址偏差（见 docs/yolo_status.md）。
2. 用 PDS 完成 PG2L200H 综合、时序和资源报告，补全 PDC 引脚与 DDR3/HDMI IP。
3. 增加 L2 MSHR/store buffer，提高 CoreMark/MHz。
4. 接入 OV5640/HDMI-IN 捕获与 scaler，把视频帧送入 YOLO。
