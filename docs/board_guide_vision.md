# 盘古 200Pro+ 上板指南（图像识别版）

> 目标：把 ARES-P4 跑在真实板子上，并通过串口完成一次**照片识别**。
> 器件：PG2L200H-6IFBB676 ｜ 主频 27 MHz ｜ 串口 115200 8N1

---

## 1. 你会拿到什么

| 文件 | 用途 | 状态 |
|---|---|---|
| `build/pango/syn/generate_bitstream/coremark_ares_p4_board.sbit` | CoreMark 版（先验通路） | 已生成 2026‑10‑18 |
| `build/pango/syn/generate_bitstream/ares_p4_board.sbit` | **图像识别版（vision 固件）** | 已生成 2026‑10‑26 05:47 |

两个位流**网表完全相同**（只差片内 BRAM 的初值），所以时序/资源也一致：

| 项目 | 结果 |
|---|---|
| 约束时钟 | 27 MHz（period 37.037 ns） |
| 估计最高频率 | 38.36 MHz，setup slack **+10.971 ns**，0 failing |
| Hold（slow） | +0.068 ns，0 failing |
| Hold（fast） | −0.073 ns / 60 端点（边角，27 MHz 下余量 11 ns，可接受） |
| 资源 | CLMA 45%、LUT 25%、FF 12%、DRM 53%、APM 8% |

> 已核对：`build/pango/syn/fw.hex` 与 `build_win/vision/vision.bin` 的 128 位镜像
> **哈希一致**，与 coremark 镜像不一致 → 识别固件确实被烧进了位流。
> 本次全流程耗时 1h7m（compile 1m → synth 2.5m → dev_map 1m → pnr 1h1m → bitgen 10s）。
| `tools/send_image.ps1` | 串口上传图片 + 读回识别结果 |
| `tools/img2raw.py` | 把 BMP/PGM/PPM 照片转成板子要的 32×32 原始帧 |
| `firmware/vision/` | 板上识别固件的源码与协议说明 |

---

## 2. 硬件连接

1. **JTAG 下载器**插到板子的 JTAG 口（USB），另一端插电脑；
2. **USB 串口**（板载 USB-UART）插电脑，设备管理器里记下 COM 号（如 COM3）；
3. 板上电，电源灯亮；按下复位键 **C22** 后松开。

> 板子 = MES2L676 核心板 + MES2L676-BASE-V1.2 底板；
> 27 MHz 系统时钟在核心板 U11，串口 TX=C24 / RX=B24。

---

## 3. 下载位流

先起 JTAG 服务（只起一次，窗口保持打开）：

```powershell
D:\PDS_2022.2-SP6.4\bin\cdt_js.exe -port 65420
```

另开一个终端下载位流：

```powershell
cd E:\qs\self_pro

# CoreMark 版（先验证板子通路）
D:\PDS_2022.2-SP6.4\bin\cdt_cfg.exe -file fpga\pango\program.tcl `
  -args {E:\qs\self_pro\build\pango\syn\generate_bitstream\coremark_ares_p4_board.sbit}

# 图像识别版
D:\PDS_2022.2-SP6.4\bin\cdt_cfg.exe -file fpga\pango\program.tcl `
  -args {E:\qs\self_pro\build\pango\syn\generate_bitstream\ares_p4_board.sbit}
```

下载成功的标志：DONE 灯亮；串口开始有输出。
若 DONE 不亮：先确认 JTAG 链能扫到器件，再检查位流选项里的 **SCBV**（配置 bank 电压）是否与底板一致。

---

## 4. 打开串口（115200 8N1）

任选其一：

- **sscom**（资料里自带）：`F:\BaiduNetdiskDownload\qs\5_Software\串口调试助手\sscom5.13.1.exe`
- **PowerShell**：
  ```powershell
  $p = New-Object System.IO.Ports.SerialPort COM3,115200,"None",8,"One"
  $p.Open(); $p.ReadExisting(); $p.Close()
  ```

接 CoreMark 位流时应看到：

```
==================================================
ARES-P4 CoreMark 1.0 / RV32IM
Pangu 200Pro+ / PG2L200H / 27 MHz
...
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xfcaf
ARES-P4 CoreMark/MHz : 0.9xx
```

四个 CRC 对得上，说明 CPU/缓存/内存/串口在真实板子上全部正常，再往下做识别。

---

## 5. 识别版固件的交互

下载图像识别位流后，串口会打印：

```
==================================================
ARES-P4 vision demo / RV32IM / CPU only
Pangu 200Pro+ / PG2L200H / 27 MHz
32x32 frame -> 16x16 features -> 5 shape classes
==================================================

--- built-in self test (5 classes x 4 variants) ---
circle     ok   ok   ok   ok
square     ok   ok   ok   ok
triangle   ok   ok   ok   ok
cross      ok   ok   ok   ok
ring       ok   ok   ok   ok
self test: 20/20 correct, last classify xxxxx cycles

commands: d=self test  u=upload 32x32 frame  a=preview  m=menu
```

命令：

| 键 | 作用 |
|---|---|
| `d` | 重跑自检（5 类 × 4 变体，应 20/20） |
| `u` | 上传一帧 32×32 图像并识别 |
| `a` | 重显上一帧的 16×16 ASCII 预览 |
| `m` | 打印菜单 |

---

## 6. 用一张真实照片做识别（重点）

### 6.1 准备照片

拍/画一个**形状**（圆、方、三角、十字、环），尽量：
- 深色背景 + 亮色图形（或反过来，用 `--invert`）；
- 图形占画面 1/3 以上；
- 拍完转成 **BMP（24 位）** 或 **PGM/PPM**（PowerPoint 截图另存 BMP、Photoshop 导出 BMP 都行）。

### 6.2 转成板子要的 32×32 帧

```powershell
cd E:\qs\self_pro
python tools\img2raw.py C:\photos\circle.bmp build\circle.raw
# 背景亮、图形暗时：
python tools\img2raw.py C:\photos\circle.bmp build\circle.raw --invert
# 想强制二值化：
python tools\img2raw.py C:\photos\circle.bmp build\circle.raw --threshold 128
```

工具会打印一张 16×16 的 ASCII 预览，先肉眼确认图形没截断、没整体偏移。

### 6.3 上传并识别

```powershell
powershell -ExecutionPolicy Bypass -File tools\send_image.ps1 -Port COM3 -Raw build\circle.raw
```

板上返回：

```
................
.....########...
...############.
..##############
..##############
................
result: circle  distance 34  confidence 86%
classify took 58432 cycles (2163 us at 27 MHz)
```

> 没有照片也能先试：`python tools\img2raw.py --demo triangle build\t.raw`
> 生成的是固件同一套渲染器的合成图。

---

## 7. 排错

| 现象 | 检查 |
|---|---|
| 串口完全无输出 | 位流是否下载成功（DONE）、COM 口是否选对、波特率是否 115200 |
| 全是乱码 | 固件 UART_DIV 与主频不匹配。27 MHz 用 234；若你的板子晶振是 50 MHz，用 `-UartDiv 434 -CpuHz 50000000` 重编固件 |
| 自检不是 20/20 | 说明固件被改坏了；重跑 `tools/build_win.ps1 -Target vision` 并重下位流 |
| 上传超时 | `send_image.ps1` 是否先收到 `ready for 1024 bytes`；串口助手会抢串口，二选一 |
| 识别成 UNKNOWN | 距离 > 150：形状不在这 5 类里，或对比度太低/图形太小。重新拍，或调 `--threshold` |
| 每次都识别成同一类 | 图像几乎全黑或全白（min/max 差 < 24 被判空帧）；调整曝光/阈值 |

---

## 8. 再往前一步（按难度排序）

1. **换固件不换位流**（最省事）：当前固件是编译进片内 BRAM 的，
   改固件要重跑 PDS（约 2.5 h）。如果想快速迭代，下一步应加一个
   UART bootloader（把固件下载到内存），之后只烧一次位流。
2. **摄像头**：板上有 OV5640 接口与 HDMI IN（MS7200）。需要
   DVP 采集 + 帧缓存（占 DRAM/BRAM），再把 32×32 缩放结果喂给现在的分类器——
   接口不变，只是把 `frame[]` 换成采集结果。
3. **DDR3**：`fpga/pango/ip/ddr3/` 的 IP 已为 200H 验证，还差一个
   128-bit ↔ 256-bit AXI 桥；接上后可以用 512 MB 帧缓存。
4. **miniTensor 加速**：需要把 CV-X-IF interface 展平（2 个文件 81 处），
   然后把 16×16 的 L1 距离/卷积搬到加速器上，对比 cycles。

---

## 9. 常用命令速查

```powershell
# 编固件（vision / coremark / yolo / smp）
powershell -File tools\build_win.ps1 -Target vision -UartDiv 234 -CpuHz 27000000

# 一键：固件 -> 128bit 镜像 -> RTL 转换 -> 综合/布局布线/位流
powershell -File tools\build_board.ps1 -Target vision

# 只重跑 PDS（固件已就绪）
cd build\pango\syn
D:\PDS_2022.2-SP6.4\bin\pds_shell.exe -file flow_board.tcl -project_name ares_p4

# 图片转换 / 上传
python tools\img2raw.py --demo ring build\ring.raw
powershell -File tools\send_image.ps1 -Port COM3 -Raw build\ring.raw
```