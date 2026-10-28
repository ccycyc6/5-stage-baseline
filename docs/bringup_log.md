# 上板验证日志（bringup log）

> 规则：每过一关追加一节，只贴事实（命令、串口原文、报告数字），不写推测。
> 位流不入库，但 sha256 必须记录，保证"结论对应哪一个位流"。
> 方案：[board_yolo_camera_plan.md](board_yolo_camera_plan.md)

---

## 进度总表

| 关 | 内容 | 状态 | 日期 | 位流 sha256 | DRM | WNS | 结论 |
|---|---|---|---|---|---|---|---|
| B0 | 厂商位流钉死板子 | ☐ | | — | — | — | |
| B1 | 最小位流（时钟/UART 活着） | ☐ | | | | | |
| B2 | CPU + ROM 打印 | ☐ | | | | | |
| B3 | BRAM 读写自检 | ☐ | | | | | |
| B4 | 串口 loader | ☐ | | | | | |
| B5 | 张量上板 | ☐ | | | | | |
| B6 | 并入视频 | ☐ | | | | | |
| B7 | 摄像头 + OSD | ☐ | | | | | |

---

## B0 — 厂商位流（无代码）

- **日期**：
- **烧写 1**：`led_test.sbit` → 现象：
- **烧写 2**：`uart_top.sbit` → 串口原文：

```text
<逐字粘贴>
```

- **结论**：板子/下载/串口 正常 / 异常（写明）
- **备注**：DONE 灯状态、COM 口、波特率

---

## B1 — 最小位流（时钟 / UART）

- **日期**：2026-10-28（构建）   **提交**：`board(b1)`   **tag**：待上板通过后打 `board-b1`
- **位流**：`build/pango/smoke/generate_bitstream/board_smoke.sbit`（9,188,552 B）
- **sha256**：`284C6E38E931859BF7D198E3E947B56C792E267AB0FDFBFD0683EA9EBB952A14`
- **上板前仿真门**：`sim/rtl/tb_board_smoke.sv`（Verilator 5.020，WSL）→ `TB PASS: two full messages decoded at 115200`
  - 该仿真在第一次构建后抓到一个真实 bug：`MSG[idx*8 +: 8]` 把字节顺序取反了（收到 `0A 0D 4B 4F … 41`），已改为从高位往下取；若不做这一步，板上会看到一堆乱码而不是 "ARES-S1 smoke OK"
- **资源**：CLMA 47/30075，LUT 128/159800，寄存器 103/319600，**DRM 0/415**
- **时序**：setup slack **+32.4 ns**（27 MHz 约束），0 failing；hold 无违例
- **完整流程耗时**：1m48s（compile 4s / synth 11s / dev_map ~15s / pnr ~60s / bitgen 21s）
- **警告**：`Public-4008`（`free_cnt[25]`、`gap_cnt[24]` 悬空，故意不接，无害）；
  `Timing-4086/4087`（led/uart_tx 未加 output delay，本阶段不需要）
- **上板现象**：⏳ 待烧写

```text
（待填：串口应每 0.5 s 出现一行 "ARES-S1 smoke OK"）
```

- **LED**：待观察 led[0] 闪（约 1.6 s 周期）、led[1] 常亮（复位已释放）
- **结论**：构建通过；上板待验证

---

## B2 — CPU + ROM

- **日期**：   **提交**：   **tag**：`board-b2`
- **位流 sha256**：
- **资源 / 时序**：DRM __/415，WNS __ ns
- **现象**：

```text
B2 OK
B2 OK mcycle=00001234
```

- **结论**：

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
