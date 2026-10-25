# ARES-P4 上板指南（盘古 200Pro+ / PG2L200H）

> 唯一的上板说明：板卡事实 → 位流 → 烧写 → 串口验证 → 图像识别 → 构建 → 排错。
> 位流文件说明见 [../bitstream/README.md](../bitstream/README.md)。

---

## 1. 一页速查

| 项目 | 值 |
|---|---|
| 开发板 | 盘古 200Pro+（MES2L676-200HP，核心板 + MES2L676-BASE-V1.2 底板） |
| FPGA | **PG2L200H-6IFBB676**（注意是 **FBB**676，PDS 里 200H 没有 FBG676） |
| 系统时钟 | **27 MHz**，引脚 **D18**（核心板 U11，单端有源晶振） |
| 复位按键 | **C22**（低有效） |
| 串口 | TX=**C24**，RX=**B24**，**115200 8N1** |
| LED | led[3:0] = E18 / C19 / C18 / A20 |
| 复位向量 | `0x8000_0000`（片内 BRAM 预装固件，无需 flash 引导） |
| 位流 | [`bitstream/ares_p4_vision.sbit`](../bitstream/ares_p4_vision.sbit)（识别）/ [`ares_p4_coremark.sbit`](../bitstream/ares_p4_coremark.sbit)（CoreMark） |
| 工具链 | PDS 2022.2-SP6.4（`D:\PDS_2022.2-SP6.4`）+ RISC-V GCC 15.2.0（`E:\qs\toolchain\riscv`） |

### 最短路径

```powershell
D:\PDS_2022.2-SP6.4\bin\cdt_js.exe -port 65420                 # ① JTAG 服务，常驻
cd E:\qs\self_pro
D:\PDS_2022.2-SP6.4\bin\cdt_cfg.exe -file fpga\pango\program.tcl `
  -args {E:\qs\self_pro\bitstream\ares_p4_vision.sbit}        # ② 烧位流
# ③ 串口 115200 8N1：应看到 self test: 20/20
powershell -File tools\send_image.ps1 -Port COM3 -Raw build\demo_circle.raw   # ④ 识别
```

---

## 2. 硬件与连接

1. **JTAG 下载器** → 板子 JTAG 口（USB），另一端插电脑；
2. **USB 串口** → 电脑，设备管理器记下 COM 号；
3. 上电 → 按一下复位键 **C22**。

### 关键引脚（均已对照官方例程约束文件核实）

| 信号 | 引脚 | 说明 |
|---|---|---|
| clk | D18 | 27 MHz，BANKL3 `DIFFIO_L3_G1_11P_GMCLK` |
| rst_n | C22 | 复位按键，低有效 |
| uart_tx / uart_rx | C24 / B24 | LVCMOS33 |
| led[0..3] | A20 / C18 / C19 / E18 | led0=复位释放，led1=hart0 退休指令，led2=串口活动，led3=心跳 |
| DDR3 参考时钟 | N3(P) / N2(N) | 125 MHz 差分（接 DDR3 IP 时用） |
| QSPI 配置 Flash | CS=P18，DQ0=R14，DQ1=R15 | 专用配置脚，本设计未使用 |

> 完整 400 球 BANK/专用功能对照表与 DDR3 71 根引脚表见 git 历史
> （commit `9086853` 的 `fpga/pango/board_pinmap.md`、`fpga/pango/ip/ddr3/DDR3_IP_NOTES.md`）。

---

## 3. 位流与烧写

| 位流 | 固件 | 何时用 |
|---|---|---|
| `bitstream/ares_p4_vision.sbit` | 图像识别 demo | **默认**，串口自检 + 上传图片识别 |
| `bitstream/ares_p4_coremark.sbit` | CoreMark v1.0 | 首次上板验通路，跑分 |

两者网表相同（只差片内 BRAM 里的固件），时序/资源一致：
setup **+10.971 ns** @27 MHz（Fmax 38.4 MHz）、hold slow +0.068 ns、
fast 角 hold −0.073 ns/60 端点、DRM 53%、LUT 25%。

### 烧写

```powershell
# 终端 A（常驻）
D:\PDS_2022.2-SP6.4\bin\cdt_js.exe -port 65420

# 终端 B
cd E:\qs\self_pro
D:\PDS_2022.2-SP6.4\bin\cdt_cfg.exe -file fpga\pango\program.tcl `
  -args {E:\qs\self_pro\bitstream\ares_p4_vision.sbit}
```

`program.tcl` 内容 = `cfg_connect → cfg_scan_chain → cfg_assign_file → cfg_program → cfg_disconnect`。
DONE 灯亮即成功；若 DONE 不亮，检查 JTAG 扫链与位流选项里的 **SCBV**（配置 bank 电压）。

---

## 4. 先验通路：CoreMark 位流

烧 `ares_p4_coremark.sbit`，串口 115200 应输出：

```
==================================================
ARES-P4 CoreMark 1.0 / RV32IM
Pangu 200Pro+ / PG2L200H / 27 MHz
4x ARES-L 5-stage + 2-way L1 + shared L2
==================================================
CoreMark Size    : 666
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xfcaf
ARES-P4 timed cycles : ...
ARES-P4 CoreMark/MHz : 0.9xx
```

**四个 CRC 与参考值一致**，说明 CPU 五级流水、2 路 L1、共享 L2、片内存储、
UART 在真实板子上全部正常。跑分满足赛题"迭代次数使运行时间 ≥10 s"（1000 次迭代）。

---

## 5. 图像识别 demo（vision 位流）

### 5.1 它做什么

```
32×32 灰度帧 ──► 阈值/包围盒归一化 ──► 16×16 特征(L1 归一化) ──► 与 5 个原型算 L1 距离
   （串口上传 1024 B）                                                  │
                                            circle / square / triangle / cross / ring
```

- 全部定点、无浮点、无大权重表（原型在启动时由同一套渲染函数生成）
- 类别 5 个几何形状；距离 > 150 判为 `UNKNOWN`
- 离线验证：5 类 × 4 变体（干净/加噪/平移/缩放）= **20/20**，同类最差距离 40、
  异类最小 ~90；`tools/vision_sim.py` 可复跑

### 5.2 上电后串口输出

```
==================================================
ARES-P4 vision demo / RV32IM / CPU only
Pangu 200Pro+ / PG2L200H / 27 MHz
32x32 frame -> 16x16 features -> 5 shape classes
==================================================

--- built-in self test (5 classes x 4 variants) ---
circle     ok   ok   ok   ok
...
self test: 20/20 correct, last classify xxxxx cycles

commands: d=self test  u=upload 32x32 frame  a=preview  m=menu
```

> `self test: 20/20` 是关键：它同时验证了 CPU、内存、分类算法和串口。

### 5.3 串口命令

| 键 | 作用 |
|---|---|
| `d` | 重跑自检 |
| `u` | 上传一帧 32×32 图像并识别 |
| `a` | 重显上一帧的 16×16 ASCII 预览 |
| `m` | 菜单 |

### 5.4 用自己的照片识别

```powershell
# ① 照片转 32×32 帧（支持 BMP 24bit / PGM / PPM）；工具会打印 ASCII 预览
python tools\img2raw.py C:\photos\circle.bmp build\circle.raw
python tools\img2raw.py C:\photos\circle.bmp build\circle.raw --invert     # 亮背景+暗图形
python tools\img2raw.py C:\photos\circle.bmp build\circle.raw --threshold 128

# ② 上传并识别
powershell -File tools\send_image.ps1 -Port COM3 -Raw build\circle.raw
```

拍照建议：深色背景 + 亮色图形（或反过来用 `--invert`）、图形占画面 1/3 以上、
尽量正对拍摄。板上返回示例：

```
got 1024 bytes
................
.....########...
..##############
result: circle  distance 34  confidence 86%
classify took 58432 cycles (2163 us at 27 MHz)
```

没有照片也能先试：`python tools\img2raw.py --demo triangle build\t.raw`
（5 张演示帧已放在 `build/demo_{circle,square,triangle,cross,ring}.raw`）。

### 5.5 串口协议（自己写上位机时用）

| 方向 | 内容 |
|---|---|
| PC → 板 | `u`（0x75） |
| 板 → PC | `ready for 1024 bytes (32x32 raw)` |
| PC → 板 | 1024 字节，行优先，0=背景，255=形状 |
| 板 → PC | 16 行 ASCII 预览 + `result: …` + `classify took … cycles` |

---

## 6. 构建（改固件 / 改 RTL 后）

### 6.1 一条命令

```powershell
cd E:\qs\self_pro
powershell -File tools\build_board.ps1 -Target vision        # 识别版
powershell -File tools\build_board.ps1 -Target coremark -Iterations 1000   # CoreMark 版
```

它做四件事：编固件 → 转 128 位 `$readmemh` 镜像 → 生成 ADS 兼容 RTL →
PDS compile / synthesize -ads / dev_map / pnr / report_timing / gen_bit_stream。
产物：`build/pango/syn/generate_bitstream/ares_p4_board.sbit`（约 1 小时，PnR 占绝大部分）。

### 6.2 工具链与两个必须知道的限制

- **PDS 自带的 Synplify Pro 没有 license**（`Flow-0028`），只能用 ADS；
- **ADS 只支持 SV 子集**：不支持 `interface`、`enum`、隐式端口 `.clk`、
  `N'(x)`、多维 packed 变量下标等。`tools/pango_prep.py` 会把这些机械改写成
  ADS 能吃的形式（enum→localparam、`.p`→`.p(p)`、cast→括号、2-D 展平），
  生成 `build/pango/syn/rtl/**/*.v`，转换清单写在 `build/pango/syn/PORT_NOTES.md`。
- 由此带来两个板上构建的取舍（都在 `ares_p4_board.sv` 里参数化）：
  - `ARES_NO_MT`：miniTensor 用 `mt_cluster_stub` 占位（ADS 编不了 CV‑X‑IF interface）；
  - 视频用 `ares_video_stub`（ADS rtl-infer 对彩条/OSD 常量 mux 误报多驱动）；
  - 缓存/存储缩小到 L1 4 KiB、L2 64 KiB、scratch 64 KiB、片内 128 KiB——
    否则 ADS 的 DRAM 推断会把 DRM 顶到 415/415、LUTRAM 超限。

### 6.3 实测资源与时序

| 资源 | 用量 | 总量 | 占比 |
|---|---:|---:|---:|
| CLMA | 13,396 | 30,075 | 45% |
| LUT | 29,741 | 120,300 | 25% |
| FF | 28,142 | 240,600 | 12% |
| DRM | 219.5 | 415 | 53% |
| APM | 56 | 740 | 8% |

| 时序 | 结果 |
|---|---|
| setup（27 MHz） | WNS **+10.971 ns**，0 failing；估计 Fmax 38.36 MHz |
| hold slow | +0.068 ns，0 failing |
| hold fast | −0.073 ns / 60 端点（唯一未收敛项，27 MHz 下余量 11 ns） |

---

## 7. 排错

| 现象 | 检查 |
|---|---|
| 串口完全无输出 | 位流是否下载成功（DONE）、COM 口、波特率 115200 |
| 全是乱码 | UART_DIV 与主频不匹配：27 MHz 用 **234**；若晶振是 50 MHz 用 434 并重编固件 |
| 自检不是 20/20 | 固件被改坏，重跑 `tools/build_win.ps1 -Target vision` 并重下位流 |
| 上传超时 | 是否先收到 `ready for 1024 bytes`；串口助手会抢占串口，二选一 |
| 识别成 UNKNOWN | 距离 >150：形状不在 5 类内，或反差太低/图形太小；重拍或调 `--threshold` |
| 每次都同一类 | 图像几乎全黑/全白（min/max 差 <24 被判空帧）；调曝光/阈值 |
| PDS 报 `DRC-0018 LUTM` | 缓存/存储参数被调大了；参见 6.2 的尺寸 |

---

## 8. 边界与下一步

当前能力：
- **静态图片识别**（照片/截图/手绘形状拍平后上传），不是视频流；
- 5 类几何形状是可解释的最小闭环，用来验证"图像进 → 特征 → 判决 → 串口出"整条链。

按难度排序的后续：

1. **UART bootloader**（最划算）：现在固件烧在 BRAM 里，改固件要重跑 PDS（≈1 h）；
   加个串口引导后只需烧一次位流，迭代从 1 小时降到几秒。
2. **摄像头**：OV5640 / HDMI IN（片外 MS7210/MS7200，FPGA 只出并行 RGB），
   需要 DVP 采集 + 帧缓存，再把 32×32 缩放结果喂给现有分类器（接口不变）。
3. **DDR3**：`fpga/pango/ip/ddr3/` 的 HMIC_S IP 已为 200H 生成并通过
   compile/synth/dev_map/pnr；还差一个 128-bit ↔ 256-bit AXI 桥
   （IP 的 AXI 从口无 rready/bresp，读数据要加缓冲），以及 Pango 的 200H PHY
   摆放集来收掉 DFI↔PHY 约 −4.1 ns 的 setup 违例。
4. **miniTensor 加速**：把 `core_v_xif` interface 展平（2 个文件 81 处引用），
   然后把距离计算/卷积搬到加速器，对比 cycles 与核心占用。

---

## 9. 文件清单

| 路径 | 内容 |
|---|---|
| `bitstream/*.sbit` | 两个可烧写的位流 + 说明 |
| `docs/board_guide.md` | 本文 |
| `rtl/board/ares_p4_board.sv` | 板上顶层（引脚、复位、LED） |
| `rtl/soc/ddr/onchip_ddr.sv` | 128-bit 片内存储（$readmemh 预装固件） |
| `fpga/pango/ares_p4_board.fdc` | 引脚 + 27 MHz 时钟约束 |
| `fpga/pango/flow_board.tcl` | PDS 全流程脚本 |
| `fpga/pango/program.tcl` | JTAG 烧写脚本 |
| `firmware/vision/` | 识别固件（算法/协议/主程序） |
| `tools/build_board.ps1` | 固件→镜像→RTL 转换→综合布线 一条命令 |
| `tools/build_win.ps1` | 免 make 的 RV32IM 固件构建 |
| `tools/img2raw.py` / `send_image.ps1` | 照片转帧 / 串口上传 |
| `tools/pango_prep.py` | ADS 兼容 RTL 生成器 |
