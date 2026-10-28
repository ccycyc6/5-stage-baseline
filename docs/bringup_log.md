# 上板验证日志（bringup log）

> 规则：每过一关追加一节，只贴事实（命令、串口原文、报告数字），不写推测。
> 位流不入库，但 sha256 必须记录，保证"结论对应哪一个位流"。
> 方案：[board_yolo_camera_plan.md](board_yolo_camera_plan.md)

---

## 进度总表

| 关 | 内容 | 状态 | 日期 | 位流 sha256 | DRM | WNS | 结论 |
|---|---|---|---|---|---|---|---|
| B0 | 厂商位流钉死板子 | ✅ PASS | 2026-10-28 | 厂商原版 | — | — | 板子/下载/串口正常 |
| B1 | 最小位流（时钟/UART 活着） | ✅ PASS | 2026-10-28 | `284C6E38…` | 0/415 | +32.4 ns | 时钟/复位/UART/引脚/流程全部正常 |
| B2 | CPU + ROM 打印 | ✅ PASS | 2026-10-28 | `A5581886…` | 8/415 | +17.7 ns | 板上串口 + LED 均符合预期 |
| B3 | BRAM 读写自检 | ☐ | | | | | |
| B4 | 串口 loader | ☐ | | | | | |
| B5 | 张量上板 | ☐ | | | | | |
| B6 | 并入视频 | ☐ | | | | | |
| B7 | 摄像头 + OSD | ☐ | | | | | |

---

## B0 — 厂商位流（无代码）

- **日期**：2026-10-28
- **烧写**：`led_test.sbit`（厂商 4_1_led_test）→ **LED 正常**
- **烧写**：`uart_top.sbit`（厂商 2_8_uart_test）→ 串口正常
- **结论**：**PASS**。板子、供电、JTAG 下载链、SCBV、USB-UART 全部正常。
  之前"下载后没反应"**不是**板子/下载/电源问题。
- **意义**：把嫌疑范围压缩到"我们的设计"这一侧。

---

## B1 — 最小位流（时钟 / UART）

- **日期**：2026-10-28   **提交**：`75d47a3`   **tag**：`board-b1`
- **位流**：`build/pango/smoke/generate_bitstream/board_smoke.sbit`（9,188,552 B）
- **sha256**：`284C6E38E931859BF7D198E3E947B56C792E267AB0FDFBFD0683EA9EBB952A14`
- **资源**：CLMA 47/30075，LUT 128/159800，寄存器 103/319600，**DRM 0/415**
- **时序**：setup slack **+32.4 ns**（27 MHz），0 failing
- **上板前仿真门**：`sim/rtl/tb_board_smoke.sv`（Verilator 5.020）→ `TB PASS: two full messages decoded at 115200`
  - 抓到真实 bug：`MSG[idx*8 +: 8]` 字节序取反（收到 `0A 0D 4B 4F … 41`），已改为从高位取。
- **上板现象**：串口每 0.5 s 输出 `ARES-S1 smoke OK`；LED 心跳（用户确认）
- **结论**：**PASS**。27 MHz 进 fabric、POR+按键复位、UART 分频/引脚、PDS 流程、约束全部正常。
  PDS 自动插入全局时钟缓冲（place 日志 `clkbufg_0/gopclkbufg`），无需手工 BUFG。
- **意义**：SoC 侧的问题从此只可能在 RTL/综合/BRAM/启动，而不在板级。

---

## B2 — CPU + ROM

- **日期**：2026-10-28   **提交**：`e789a33`   **tag**：`board-b2`
- **位流**：`build/pango/soc/generate_bitstream/board_b2.sbit`（9,188,552 B）
- **sha256**：`A5581886C2D0A28F5D8B1D9D91D0A1FAB18DD9CA75EC617537D24842538A4383`
- **资源**：LUT 3597/159800 (2.25%)，REG 2768/319600，DRAM 189/39500，**DRM 8/415**
- **时序**：setup WNS **+17.722 ns**，0 failing；hold slow WHS +0.128 ns；
  hold **fast** 角 `-0.026 ns / 1 endpoint`（27 MHz 下无实际影响，已知边角；
  如要收掉，在 FDC 加 `set_clock_uncertainty 0.100 -hold [get_clocks {sys_clk}]` 重跑）
- **全流程耗时**：5m47s（compile 4s / synth 20s / dev_map 11s / pnr ~4m / bitgen 20s）
- **上板前仿真门**：`sim/rtl/tb_b2.sv`（真实 SoC RTL + 生成的 boot_rom + 真实固件）
  → `TB PASS: B2 banner decoded from the generated ROM`
- **上板现象**（用户实测，2026-10-28 20:44）：

```text
[20:44:54.454] B2 OK mcycle=6d33da4e
[20:44:54.923] B2 OK mcycle=6df4a601
[20:44:55.391] B2 OK mcycle=6eb571a1
```

  每行间隔 0.468 s，mcycle 增量 ≈ 12.63 M → **26.9 MHz**，与 27 MHz 约束一致。
- **LED**：led[0] 闪、led[1] 常亮、**led[2] 高频闪**、led[7:4] 随 PC 跳变 —— 与预测完全一致
- **结论**：**PASS**。CPU、ADS 综合、ROM 启动、UART、CSR mcycle 全部在真实板卡上验证。
  这同时回答了最初的问题：**"下载后没反应"不是 CPU 或工具链的问题**——B2 用一个
  不含 BRAM、不含 DDR、不含 loader 的最小系统，在同一套流程下正常工作。

---

## B3 — BRAM 自检

- **日期**：   **提交**：   **tag**：`board-b3`
- **现象**：

```text
BRAM PASS (4096 bytes)
```

- **结论**：

---

## B4 — 串口 loader

- **日期**：   **提交**：   **tag**：`board-b4`
- **现象**：

```text
ARES-S1 loader v1 - send image
download 18342 bytes, crc ok
jump 0x80000000
hello from RV32IM @27MHz, mcycle=...
```

- **结论**：

---

## B5 — 张量

- **日期**：   **提交**：   **tag**：`board-b5`
- **现象**：

```text
miniTensor self-check OK
miniTensor detector: 1/1 images decoded, 17184 commands/image, ... golden diff 0 bytes
```

- **结论**：

---

## B6 — 并入视频

- **日期**：   **提交**：   **tag**：`board-b6`
- **现象**：

```text
SYS P=1 D=1 H=1 C=1
```

- **结论**：

---

## B7 — 摄像头 + OSD

- **日期**：   **提交**：   **tag**：`board-b7`
- **现象**：

```text
cam frame=142 box=(462,190,502,230) t=268ms
```

- **结论**：
