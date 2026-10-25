# 盘古 200Pro+（PG2L200H-6IFBB676）上板手册

本文档记录把 ARES-P4 SoC 真正跑在盘古 200Pro+ 开发板上所需的全部内容：
器件与板卡事实、工具链、FPGA 工程与约束、固件镜像、位流生成、JTAG 下载、
串口验证，以及尚未完成的部分（DDR3 / HDMI / miniTensor-YOLO）的明确接口和步骤。

---

## 1. 板卡与器件（已核实）

| 项目 | 事实 | 依据 |
|---|---|---|
| 开发板 | 盘古 200Pro+，产品型号 MES2L676-200HP | 教程1《硬件实验指导手册》1.4.2 节 |
| FPGA | **PG2L200H-6IFBB676**（注意不是 FBG676） | 同上；PDS 器件库 `logos2/pg2l200h/package/fbb676.eval` |
| 结构 | MES2L676 核心板 + MES2L676-BASE-V1.2 底板，板对板连接器 LB3524-G120 | 教程1 2.1.1 节 |
| 核心板 | PG2L200H + 2 片 512MB DDR3（共 32bit）+ 2 片 128Mb QSPI FLASH | 教程1 2.1.1 节 |
| 底板外设 | HDMI 输出/输入、千兆网口(RTL8211F)、串口、SD 卡、SFP、SMA_HSST、PCIe x4、按键、LED、EEPROM | 教程1 2.1.1 节 |
| 系统时钟 | **27 MHz** 单端晶振（核心板 U11），引脚 **D18** | 教程1 2.1.2.2.3.2 节明确写“单端 27MHz 用于 FPGA 系统时钟”；各 demo 的 `.fdc` |
| DDR3 参考时钟 | **N3(P)/N2(N)**，125 MHz 差分（核心板 U7） | 教程1 2.1.2.2.3.1 节；ddr3 demo `create_clock -period 8.0` |
| 复位按键 | **C22**（低有效），用户按键 **C23** | 同上 |
| 串口 | TX **C24**、RX **B24**（LVCMOS33，USB-UART 桥） | `2_8_uart_test.fdc` |
| LED | led[3:0] = E18 / C19 / C18 / A20 | `4_1_led_test/.../led_test.fdc` |

> 说明：F:\BaiduNetdiskDownload\qs 中的例程面向盘古 100Pro+（PG2L100H-6IFBG676），
> 但 100Pro+ 与 200Pro+ 使用同一块 MES2L676 核心板/底板，时钟、按键、UART、LED、
> DDR3、HDMI、FLASH 的引脚完全一致，因此例程里的 `.fdc` 引脚可以直接复用。
> 唯一要改的是 PDS 里的器件：**PG2L200H + FBB676**（PDS 中 200H 没有 FBG676 这个封装）。

---

## 2. 工具链（本机已装好）

| 工具 | 位置 | 说明 |
|---|---|---|
| PDS 2022.2-SP6.4 | `D:\PDS_2022.2-SP6.4` | 已含 license（`F:\BaiduNetdiskDownload\license\MAC\license\new_pds_00e04cf107df.lic`），支持 fabric_ads/compiler/configuration |
| RISC-V GCC 15.2.0 | `E:\qs\toolchain\riscv\bin\riscv-none-elf-gcc.exe` | xPack 版，支持 `rv32im_zicsr_zifencei/ilp32` |
| Python 3 | 系统自带 | 生成 hex 镜像、跑构建脚本 |
| 串口助手 | `F:\BaiduNetdiskDownload\qs\5_Software\串口调试助手\sscom5.13.1.exe` | 115200 8N1 |

**重要限制（实测）**：PDS 2022.2 自带的 Synplify Pro 没有 license，
只能使用 ADS 综合器；ADS **不支持** SystemVerilog 的 `interface`、`enum`、
`N'(x)` 强制位宽、结构体成员位选等语法。因此仓库里
`tools/pango_prep.py` 会先把 `rtl/**/*.sv` 复制到 `build/pango/syn/rtl/**/*.v`
并做等价的语法转换（enum → localparam + typedef 等），再交给 PDS 编译。
Verilator 仿真仍然使用原始 `rtl/`，两者互不影响。

转换清单与每一类错误的实测记录在 `build/pango/syn/PORT_NOTES.md`（由脚本自动生成），要点：

| ADS 限制 | 机械改法 | 本项目命中次数 |
|---|---|---:|
| `typedef enum` 不支持 | 每个枚举项 → `localparam`，再加 `typedef logic [W-1:0] name_t;` | 12 个枚举 |
| `N'(expr)` 位宽强转 | 改成 `(expr)` | 37 处 |
| 隐式端口连接 `.clk` | 展开成 `.clk(clk)` | 152 处 |
| `for (int i = ...)` | 循环变量提升为模块级 `integer` | 38 处 |
| 多维 packed 数组变量下标 | 展平成 1-D + `:+` 部分选择 | 60 处 |
| `string` 类型 | 改成 `reg [8*256-1:0]` | 1 处 |

> 另外：`add_design` 一次只能加一个文件（多文件会报 Flow-0072），
> 所以 flow 脚本里是循环逐个添加。

---

## 3. 上板配置（ARES-P4 Board，v1）

`rtl/board/ares_p4_board.sv` 是板上顶层，端口只有 clk / rst_n / uart_rx / uart_tx / led[3:0]：

| 特性 | v1 配置 |
|---|---|
| 主频 | **27 MHz**（D18 直连，暂不经过 PLL） |
| 复位 | 按键 C22 + 上电计数器，异步复位同步释放 |
| 串口 | 115200 8N1，`UART_DIV=234`（27 MHz / 115200，误差 0.16%） |
| 存储 | **片内 256 KiB BRAM 顶替 DDR3**（`rtl/soc/ddr/onchip_ddr.sv`，128-bit/拍） |
| 启动 | 复位向量直接设为 `0x8000_0000`；BRAM 由固件 hex 初始化，CPU 取指即运行 |
| LED | led0=复位释放，led1=hart0 退休指令，led2=UART 活动，led3=1.5 Hz 心跳 |
| miniTensor | `ARES_NO_MT`：用 `mt_cluster_stub` 占位（ADS 不支持 CV-X-IF 的 SV interface） |
| 视频 | 板上构建用 `ares_video_stub`（寄存器窗口+空闲输出）：ADS rtl-infer 对彩条/OSD 的常量 mux 会误报
  `_$_VCC_$_` 多驱动；HDMI 尚未接线，仿真仍用完整 `ares_video` |
| 缓存复位 | `ARES_FPGA` 下不逐行复位 cache 阵列（BRAM 上电即 0），否则 1 Mbit 缓存会被综合成触发器 |

为什么用片内 BRAM 顶替 DDR3：DDR3 需要 Pango HMIC_S IP + AXI 桥 + 1000+ 行引脚约束，
是上板风险最高的一环。先用 256 KiB BRAM 把「CPU → 缓存 → 内存 → UART」整条链路跑通，
CoreMark 的 CoreMark/MHz 指标与内存介质无关（只影响可测的绝对主频上限），
拿到确定的分数后再接 DDR3。DDR3 的替换点已经隔离在
`rtl/soc/ddr/pango_ddr3_axi.sv`（`PANGO_DDR3_IP` 分支），接口是 128-bit 的
req/rsp 四拍握手，见第 7 节。

---

## 4. 生成位流（一条命令链）

```powershell
# 4.1 生成固件镜像（CoreMark，1000 次迭代 ≈ 20 s @27 MHz，满足赛题 ≥10 s 要求）
powershell -ExecutionPolicy Bypass -File tools\build_win.ps1 -Target coremark -Iterations 1000 -UartDiv 234 -CpuHz 27000000

# 4.2 生成 ADS 兼容 RTL 副本
python tools\pango_prep.py

# 4.3 跑 PDS：综合 → 布局布线 → 位流（在 fpga/pango/syn 目录下执行）
cd fpga\pango\syn
D:\PDS_2022.2-SP6.4\bin\pds_shell.exe -file flow_board.tcl -project_name ares_p4
```

产物：

| 文件 | 内容 |
|---|---|
| `fpga/pango/syn/compile/…` | 编译日志 |
| `fpga/pango/syn/impl/…` | 综合/布局布线报告（资源、时序） |
| `fpga/pango/syn/generate_bitstream/ares_p4.sbit` | JTAG 下载用位流 |
| `fpga/pango/syn/fw.hex` | 被打进 BRAM 的固件镜像 |

---

## 4.4 板上构建的实测资源（PDS device_map，PG2L200H-6IFBB676）

| 资源 | 用量 | 总量 | 占比 |
|---|---:|---:|---:|
| LUT | 42,867 | 159,800 | 27% |
| FF | 35,427 | 319,600 | 12% |
| DRM（块 RAM） | 219.5 | 415 | 53% |
| 分布式 RAM | 8,696 | 39,500 | 23% |
| APM | 56 | 740 | 8% |
| IO | 8 | 400 | 2% |

注意：

- ADS 会把 256-bit 的 cache line / 128-bit 的 on-chip 存储按字节和 64K 深度拆分，
  块 RAM 用量比理论值放大约 4 倍：一开始用完整容量（L1 8K/L2 128K/scratch 192K/onchip 256K）
  时 DRM 直接顶到 415/415、分布式 RAM 超限（DRC-0018），dev_map 失败。
  把 `L1_BYTES=4096`、`CACHE_SETS=512`、`SCRATCH_WORDS=4096`、
  `ONCHIP_WORDS=8192`（128 KiB）后降到 53%，才留出布线余量。
  再想加东西（DDR3 控制器、视频帧缓存）需要先腾块 RAM，或把 cache line 拆成两个 128-bit 阵列。
- 板上 v1 用的是**缩小版缓存**（L1 4 KiB、L2 64 KiB、scratchpad 64 KiB、
  片内存储 128 KiB），所以板上 CoreMark/MHz 会比仿真的 0.903 低一些；
  仿真配置仍是完整大小。固件栈顶相应改到 `0x8002_0000`（`linker.ld`）。
- LUT 只用了 32%，逻辑还很宽裕，瓶颈完全在块 RAM。

## 4.5 实测结果（本机已跑通，2026‑10‑18）

```
build/pango/syn/generate_bitstream/ares_p4_board.sbit   9,188,552 B
```

完整流程耗时：compile 1m19s + synthesize 3m53s + dev_map 0m40s + pnr 2h26m + gen_bit_stream 1m。

时序（`report_timing/ares_p4_board.rtr`，slow/fast 双角）：

| 项目 | 结果 |
|---|---|
| 约束时钟 | sys_clk 27 MHz（period 37.037 ns），36971 个时钟负载 |
| 估计最高频率 | **38.36 MHz**（slack +10.971 ns） |
| Setup（slow） | WNS **+10.971 ns**，0 failing |
| Hold（slow） | WHS **+0.068 ns**，0 failing |
| Setup（fast） | WNS **+21.287 ns**，0 failing |
| Hold（fast） | WHS **−0.073 ns**，60 个端点，THS −1.509 ns ← **唯一未收敛项** |

> Fast 角的 hold 差 73 ps，属于布线最后一档的边角问题，正常出货前要收掉。三种收法（任选）：
> 1. 在 `ares_p4_board.fdc` 加 `set_clock_uncertainty 0.100 -hold [get_clocks sys_clk]` 后重跑 pnr；
> 2. pnr 打开 hold fix / 换 seed（`pnr -optimize` / `-slack_router`）；
> 3. 把 clk 输入加一级 BUFG 后再看（当前 8 根 IO 里 clk 直接进时钟网络）。
> 27 MHz 下这些路径余量本来是 11 ns，实际风险很低，但报告要如实标注。

资源（PnR 报告）：

| 资源 | 用量 | 总量 | 占比 |
|---|---:|---:|---:|
| CLMA（逻辑阵列） | 13,396 | 30,075 | 45% |
| LUT | 29,741 | 120,300 | 25% |
| FF | 28,142 | 240,600 | 12% |
| LUT‑FF pairs | 7,048 | 120,300 | 6% |
| APM | 56 | 740 | 8% |
| DRM | 219.5 | 415 | 53% |
| CCS | 1 | 1 | 100% |

> `C: Bitstream-2001: SCBV has not been set` 是提示按板卡配置 bank 电压；默认值本板可用，
> 若下载后 DONE 不亮，在 PDS 位流选项里按底板 VCCIO 设 SCBV 再重新生成。

## 5. 下载与验证

1. 接好 USB 下载器与 USB 串口，板子上电。
2. 启动 JTAG Server（只需一次）：
   ```
   D:\PDS_2022.2-SP6.4\bin\cdt_js.exe -port 65420
   ```
3. 下载位流：
   ```
   D:\PDS_2022.2-SP6.4\bin\cdt_cfg.exe -file fpga\pango\program.tcl -args {E:\qs\self_pro\fpga\pango\syn\generate_bitstream\ares_p4.sbit}
   ```
   `program.tcl` 的内容就是 `cfg_connect → cfg_scan_chain → cfg_assign_file → cfg_program → cfg_disconnect`。
4. 串口 115200 8N1，应看到：
   ```
   ==================================================
   ARES-P4 CoreMark 1.0 / RV32IM
   Pangu 200Pro+ / PG2L200H / 27 MHz
   ...
   CoreMark Size    : 666
   seedcrc          : 0xe9f5
   [0]crclist       : 0xe714
   [0]crcmatrix     : 0x1fd7
   [0]crcstate      : 0x8e3a
   [0]crcfinal      : 0xfcaf
   ARES-P4 timed cycles : ...
   ARES-P4 CoreMark/MHz : 0.9xx
   ```
   四个 CRC 与 2K 性能跑分参考值一致即说明 RV32IM 全部指令、缓存、中断、
   存储系统在真实板卡上工作正常。
5. 固化（可选，掉电后独立运行）：用 PDS 生成 flash 镜像后执行 `program_flash.tcl`，
   细节见 PDS《Fabric Configuration 用户手册》第 4.3.19 节（eflash/外部 QSPI）。

---

## 6. 与仿真的一致性

同一份 `firmware/`、同一份 `rtl/`，只是顶层不同：

| 场景 | 顶层 | DDR 实现 | 启动 |
|---|---|---|---|
| Verilator 仿真 | `sim/rtl/tb_soc.sv` | `ddr3_model.sv`（+DDR=xxx.hex） | 复位向量 0x0 → Boot ROM 跳 0x8000_0000 |
| 板上 v1 | `rtl/board/ares_p4_board.sv` | `onchip_ddr.sv`（BRAM 预装固件） | 复位向量 0x8000_0000 |
| 板上 v2（待接） | 同上 + `PANGO_DDR3_IP` | Pango HMIC_S DDR3 IP | 同上 |

---

## 7. 尚未完成的部分（明确接口，可按图施工）

### 7.1 DDR3（IP 已就绪，还差一个 AXI 桥）
IP 已经为 PG2L200H-6IFBB676 重新生成并通过 compile / synthesize / dev_map / pnr 验证：

- 位置：`fpga/pango/ip/ddr3/ddr3_test/ddr3_test.idf`（`add_design` 这个 .idf 即可）
- 约束：`fpga/pango/ip/ddr3/ddr3_ip.fdc`（时钟 + 71 根 DDR3 引脚 + PHY 摆放）
- 说明：`fpga/pango/ip/ddr3/DDR3_IP_NOTES.md`，端口表 `ddr3_ports.csv`
- 重新生成：先改 .idf 头部 `<device>PG2L200H</device><package>FBB676</package>`，再执行
  `D:\PDS_2022.2-SP6.4\bin\ip_generate.exe -i ...\ddr3_test.idf -ads`
  （输出应有 `Part: Logos2-PG2L200H-FBB676--6 ... 0 error(s)`）

接进 SoC 必须注意（踩过的坑）：

1. **实例名必须是 `I_ips_ddr_top`，且放在顶层**：`ddr3_ip.fdc` 里的 `{i:...}` 路径是绝对的。
2. **参考时钟是 N3/N2 差分对（125 MHz）**，用 `GTP_INBUFDS` 送进 IP 的 `ref_clk`；
   不要用 M21/M22（Pango 676 参考值），会报 `Place-0094`。
3. IP 的 AXI 从口是 **256-bit 数据 / 32-bit wstrb**，而且**没有 rready、没有 bresp/bvalid、没有 wlast**
   （读数据不能反压，必须在桥里加一级 rdata 缓冲）。
4. `resetn` 低有效，`core_clk` 输出 125 MHz，是 AXI 的工作时钟。
5. SoC 侧地址 0x8000_0000 / 0x4000_0000 要映射到 DDR 偏移 0，128-bit 拍要拼成 256-bit。
6. 已知遗留：200H 上 `ddrphy_sysclk → phy_dq_sysclk` 的 setup 有约 −4.1 ns 违例
   （同一 IP 在 100H 上是 +0.9 ns），需要 Pango 的 200H PHY 摆放集（`200h_ddr3_676_x72.fdc` 风格）才能收。
7. DDR PHY 会占满器件唯一的 **CCS** 资源。

桥的接口契约（SoC 侧 pango_ddr3_axi 已经定义好）：
`req_valid/req_ready/req_write/req_addr[31:0]/req_wdata[127:0]/req_wstrb[15:0]` →
`rsp_valid/rsp_ready/rsp_rdata[127:0]`，一拍一个 16 B beat。需要写一个
`pango_ddr3_ip` 模块实现这个契约 + AXI4 主口（单拍 aw/ar 即可，wstrb 16→32 位扩展，
读回 256-bit 拆成两个 128-bit beat）。

### 7.2 HDMI 输出（好消息：不需要 OSERDES）
- 本板 TMDS 由**片外 MS7210** 完成，FPGA 只需要输出**并行 24-bit RGB + pix_clk + de + hs + vs**：
  pix_clk=**T24**、de=**N19**、hs=**R20**、vs=**R21**，R/G/B 各 8 位引脚见 `board_pinmap.md` 第 5.2 节。
- HDMI 芯片要先用 I2C 初始化（SCL=**K22**/SDA=**K23**，TX 地址 0xB2，RX 0x56），
  复位输出 **G25**（demo 里 `rstn_out = (rstn_1ms == 16'h2710)` 即 10 ms 后释放）。
- 因此板上视频链路 = `ares_video` 的时序/OSD 部分（去掉 TMDS 编码器）→ 并行 RGB → MS7210。
  demo 的 `ms72xx_ctl.v` 可直接复用做 I2C 配置。
- 像素时钟 25 MHz 需由 PLL 产生（`ipm2l_flex_pll`），27 MHz 主频下不能用整数分频得到 25 MHz。

### 7.3 miniTensor / YOLO
- 现状：RTL 有 `core_v_xif` 这个 SV interface，ADS 无法编译，所以板上构建用
  `mt_cluster_stub` 占位。
- 解决办法（二选一）：
  1. 把 `core_v_xif` 拆成两个 packed struct（cpu→co / co→cpu）或扁平端口，
     只影响 `mini_tensor_top.sv`、`mt_cvxif_shim.sv`、`ares_cluster.sv` 三处；
  2. 换用支持 SV interface 的综合器（PDS 新版 / Synplify Pro，需要 license）。
- 另外 `docs/yolo_status.md` 记录的 stage-1 卷积 golden 偏差仍未修复，
  YOLO 要在板上出正确框，必须先修 `firmware/yolo/mt_net.c` 的 tile/地址计算。
- 在修好之前，板上可以用 `firmware/tests/mt_gemm.c`（GEMM/累加/epilogue 回归）
  证明加速器数据通路本身是对的。

### 7.4 主频提升
- 27 MHz 现在很保守；ADS 综合后看时序报告，若能过 100 MHz 就把 PLL 加上
  （`ipm2l_flex_pll` 27→100 MHz），CoreMark 绝对分数约 3.7 倍，CoreMark/MHz 不变。