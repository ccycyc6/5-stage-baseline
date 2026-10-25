# 赛题要求对照表（2026 全国大学生嵌入式芯片与系统设计竞赛 · 紫光同创选题）

> 赛题：基于紫光同创 RISCV 指令集 CPU 设计（选题一）
> 平台：盘古 200Pro+ / PG2L200H-6IFBB676

## 一、基础任务

| 赛题要求 | 实现位置 | 状态 |
|---|---|---|
| RV32I 通用处理单元 | `rtl/core/ares_l_core.sv`（+ MUL/DIV → RV32IM） | 已实现，定向 ISA 测试通过 |
| ≥3 级流水线 | ARES-L 五级：IF / ID / EX / MEM / WB | 已实现 |
| 数据冲突处理 | EX/MEM、MEM/WB 全转发 + load-use 1 拍停顿 | 已实现 |
| 分支跳转处理 | EX 级解析，2 拍 flush；BHT + BTB 预测 | 已实现 |
| UART 控制器 | `rtl/soc/ares_uart.sv`（8N1，可配分频） | 已实现，板上 115200 |
| GPIO | `rtl/soc/ares_gpio.sv` | 已实现 |
| CoreMark v1.0 | `firmware/coremark/`，`tools/build_win.ps1 -Target coremark` | 仿真 PASS（4 个 CRC 与参考值一致） |

## 二、高阶任务

| 赛题要求 | 实现位置 | 状态 |
|---|---|---|
| 2 路组相联 I/D Cache | `rtl/cache/ares_l1i.sv`、`ares_l1d.sv`（各 8 KiB，2-way，32 B line，LRU） | 已实现 |
| 总线突发效率 | L2 以 2×16 B 回填 32 B line；L2 128 KiB 4-way | 已实现（阻塞式，可优化 MSHR） |
| 动态分支预测（BTB） | `rtl/core/ares_bpu.sv`（2-bit BHT + BTB） | 已实现 |
| 异常/中断机制 | `rtl/core/ares_csr.sv` + `ares_clint.sv` + `ares_plic.sv`（M-mode、MSIP/MTIP/MEIP、mret） | 已实现 |
| AI 加速单元 | `rtl/minitensor/`（4×4 INT8 脉动阵列 GEMM + VPU + epilogue），`rtl/soc/mt/`（CV-X-IF 适配 + DMA） | RTL 完成，仿真 GEMM 回归通过；**板上需先解决 ADS 不支持 SV interface** |
| 移植 YOLO | `firmware/yolo/`（3 conv + head，INT8，权重打包） | 全图可跑通；`docs/yolo_status.md` 记录的 stage-1 偏差未修复 |
| 板上图像识别（CPU 基线） | `firmware/vision/`：32×32 帧 → 16×16 特征 → 5 类形状，串口输出类别/距离/耗时；见 `docs/board_guide_vision.md` | 已验证算法（离线 20/20、raw 回放 5/5），位流重编中 |
| 传感器/显示融合 | `rtl/soc/video/ares_video.sv`（640×480 时序 + OSD + TMDS 编码） | 时序/OSD/TMDS 仿真通过；板上 HDMI 序列化器待接 |

## 三、测评标准对照

| 评分项 | 我们的证据 | 备注 |
|---|---|---|
| CoreMark 分数（含迭代次数 ≥10 s） | 仿真 0.903 CoreMark/MHz @100 MHz；板上 50 MHz、1000 次迭代 ≈ 22 s | 板上实际分数待填（见 `docs/board_bringup.md` 第 5 节） |
| 执行效率 CoreMark/MHz | 单发射 5 级 + 阻塞 L2；下一步 MSHR/store buffer/2 拍乘法器 | |
| 时钟频率 | 板级 v1 用 50 MHz 直连；PDS 时序报告给出可达上限 | 提升到 100 MHz 需加 PLL |
| 资源效率 CoreMark/LUTs | PDS 综合报告 `fpga/pango/syn/impl/**` | 待填实测 LUT/DRM |
| AI 模型性能与资源 | miniTensor 每核 4×4 INT8 GEMM；YOLO 17,184 命令/图，6.37 M cycles（仿真） | 板上需 MT 端口展平 |
| 延迟/识别率 | 见 `docs/yolo_status.md` | 识别率待修复后测 |
| 代码规范/注释/模块化 | 目录分层：core / cache / soc / minitensor / video / board；每文件头注释 | |
| 时序约束合理性 | `fpga/pango/ares_p4_board.fdc`（create_clock + IO + 异步路径） | |
| 分析报告（ILA 波形） | PDS 内置 Fabric Debugger（`rtl/soc/ares_p4_soc.sv` 已引出 dbg_pc/commit/valid 流水信号，可直接接 ILA） | 上板后抓 CoreMark 关键段 |

## 四、当前差距（按优先级）

1. **板上 CoreMark**：位流流程已打通（见 `docs/board_bringup.md`），待实测填数与截图。
2. **DDR3**：`fpga/pango/ip/ddr3/`（IP 重新生成）+ AXI 桥，接上后可用 1 GiB 内存。
3. **miniTensor 上板**：把 `core_v_xif` interface 展平成端口（只影响 2 个文件 81 处），
   然后 YOLO 才能跑在板上。
4. **YOLO 数值正确性**：`docs/yolo_status.md` 的 tile 地址偏差。
5. **HDMI 输出**：加 OSERDES 发送器 + 像素时钟，把检测框叠在视频上。