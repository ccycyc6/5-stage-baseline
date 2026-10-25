# 盘古 200Pro+（Pangu 200Pro+）FPGA 引脚映射表

> **目标硬件**：FPGA `PG2L200H-6IFBB676`（Pango Logos2，676 球 FBB 封装），核心板 **MES2L676**，底板 **MES2L676-BASE-V1.2**。
> **证据基座**：`F:\BaiduNetdiskDownload\qs` 下的 Pango 约束文件（`*.fdc`）、IP 配置（`*.idf`）、布局布线报告（`*_prr.prt` / `*.pcf`）与 RTL。
> **口径**：①“来源文件”均为相对 `F:\BaiduNetdiskDownload\qs` 的路径；②同一信号多工程出现只列一组并注明来源；
> ③工程间不一致用 ⚠ 标出并在第 10 章汇总；④文件里没有的一律写 **未找到**，绝不推测引脚号。

---

## 0. 结论摘要与封装争议

### 0.1 器件 / 封装：FBB676 vs FBG676（重要）

源文件里存在**两套器件声明**，二者球位图一致但不是同一个封装名：

| 证据 | 文件 | 器件 / 封装 | 说明 |
| :-- | :-- | :-- | :-- |
| PDS 工程（本板） | `test/1_LED/led_test.pds` 第 14–16 行 | `PG2L200H` / `FBB676` / `-6` | 与本任务描述的 PG2L200H-6IFBB676 完全一致 |
| PDS 工程（本板） | `test/3_UART/uart_test.pds` 第 14–16 行 | `PG2L200H` / `FBB676` / `-6` | 同上 |
| 综合脚本（本板） | `test/3_UART/impl.tcl` 第 3、10 行 | `set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676` | 两次运行都是 200H/FBB676 |
| 综合脚本（历史） | `test/1_LED/impl.tcl` 第 27 行 → 第 30 行 | 先 `PG2L200H -package FBB484`，后改为 `PG2L200H -package FBB676` | 该工程被移植过，最终落在 FBB676 |
| PDS 工程（绝大多数 demo） | 175 个 `*.pds`（如 `_scan2/2_9_ddr3_test/.../ddr3_test.pds`） | `PG2L100H` / `FBG676` / `-6` | 厂商例程原始器件是 100H/FBG676 |
| DDR3 IP 配置 | `_scan2/.../ipcore/ddr3_test/ddr3_test.idf` header | `PG2L100H` / `FBG676` / `-6` | IP 按 100H 生成，引脚表沿用 |
| PDS 安装目录 | `D:/PDS_2022.2-SP6.4/arch/vendor/pango/logos2/pg2l200h/package/` | 只有 `fbb484 / fbb676 / fbg256 / ffbg1156 / mbg324` | 200H **没有** FBG676；FBG676 是 100H 的封装 |

**结论（有证据）**

1. 本板 FPGA 是 **PG2L200H-6IFBB676**（`test/` 下已移植工程 + `impl.tcl` 双重确认）。
2. 大量出现的 `FBG676` 是 **PG2L100H** 的封装名，属厂商 demo 原始器件，不是本板；PG2L200H 在 PDS 里只有 `FBB484/FBB676/FBG256/FFBG1156/MBG324`。
3. 两种封装**球位功能图完全相同**：`test/1_LED/place_route/led_test_prr.prt`（200H/FBB676 实跑）与 `_scan2/.../test_ddr_prr.prt`（100H/FBG676 实跑）逐球比对，300 个共有球的 BANK / `DIFFIO_*` 专用功能名**差异为 0**。所以 100H/FBG676 例程的引脚号可直接用于 200H/FBB676 —— 这也解释了 `test/1_LED/source/led_test.fdc` 与 `_fdcscan/4_1_led_test/.../led_test.fdc` **MD5 完全相同**。
4. 本表以 **200H/FBB676 的 PnR 报告** 作为 BANK 与“专用功能名”依据，以各工程 `.fdc` 作为引脚号依据。

### 0.2 一页速查（最常用信号）

| 功能 | 引脚 | BANK / 专用功能名 | 备注 |
| :-- | :-- | :-- | :-- |
| **系统时钟（单端晶振）** | `D18` | BANKL3 / DIFFIO_L3_G1_11P_GMCLK | clk / sys_clk / free_clk / pin_clk_in / clk_27M / clk_in |
| **复位按键** | `C22` | BANKL3 / DIFFIO_L3_G3_18P | rstn / sys_rst_n / rst_board / rst_in / key_rstn |
| **用户按键** | `C23` | BANKL3 / DIFFIO_L3_G3_18N_VREF | key / dbg_key_oper / rx_rstn |
| **LED[7:0]** | `B17 C17 A18 A17 E18 C19 C18 A20` | BANKL3 | led[7] … led[0] |
| **UART TX** | `C24` | BANKL3 / DIFFIO_L3_G3_22P | uart_tx / uart_txd / txd |
| **UART RX** | `B24` | BANKL3 / DIFFIO_L3_G3_22N | uart_rx / uart_rxd / rxd |
| **DDR3 参考时钟 P/N** | `N3 / N2` | BANKR5 / DIFFIO_R5_G1_11P/N_GMCLK | 125 MHz 差分，clk_p/n 或 ref_clk_p/n |
| **DDR3 时钟 P/N** | `U6 / U5` | BANKR5 | mem_ck / mem_ck_n |
| **配置 Flash 片选** | `P18` | BANKL5 / DIFFIO_L5_G0_05P_FCS_N | 专用名 FCS_N，例程里叫 spi_cs |
| **配置 Flash D0 (MOSI)** | `R14` | BANKL5 / DIFFIO_L5_G0_00P_MOSI_D0 | 专用名 MOSI_D0，例程里叫 spi_dq0 |
| **配置 Flash D1 (MISO)** | `R15` | BANKL5 / DIFFIO_L5_G0_00N_MISO_D1_DI | 专用名 MISO_D1_DI，例程里叫 spi_dq1 |
| **HDMI TX 像素时钟** | `T24` | BANKL5 / DIFFIO_L5_G3_20P_DQS | pix_clk / pixclk_out / vout_clk |
| **HDMI TX 数据 [23:0]** | `P16 K25 K26 L24 L25 L22 L23 N21 N22 N23 N24 P23 P24 R25 P25 T25 T22 R22 N18 M21 M22 P20 P21 P19` | BANKL5 | r_out / g_out / b_out 或 hdmi_data_out |
| **HDMI TX DE / HS / VS** | `N19 / R20 / R21` | BANKL5 | de_out / hs_out / vs_out |
| **HDMI I2C（MS7200+MS7210 共用）** | `K22 (SCL) / K23 (SDA)` | BANKL4 | iic_scl / iic_sda / hd_scl / hd_sda |
| **HDMI IN 像素时钟** | `K21` | BANKL4 / DIFFIO_L4_G1_11P_GMCLK | pixclk_in / pix_clk_in |
| **HDMI IN DE / HS / VS** | `H23 / J23 / H24` | BANKL4 | de_in / hs_in / vs_in |
| **以太网 RGMII TXC / RXC** | `G16 / D19` | BANKL3 | rgmii_txc / rgmii_rxc |
| **以太网 MDC / MDIO** | `A25 / E21` | BANKL3 | mdc / mdio |
| **SFP 关断控制** | `F17 / F15` | BANKL3 | sfp_disable[0] / sfp_disable[1] |
| **PCIe 参考时钟 P/N** | `F11 / E11` | 见 8.3 | 100 MHz 差分 |

---

## 1. 系统时钟

### 1.1 单端系统时钟：D18

整个工程集合里只有 **一根**单端有源晶振输入，落在 **D18**（BANKL3，`DIFFIO_L3_G1_11P_GMCLK`，GCLK 专用时钟输入）。不同工程命名不同、引脚一致：

| 端口名 | 出现工程 | create_clock 写法 | 折算频率 | 来源文件 |
| :-- | :-- | :-- | :-- | :-- |
| `clk` | led / key_led / uart / clm / dram / DSP / encryption | `.fdc` 内无 create_clock，工具自动生成 `-period 1000.000` | 1 MHz（占位） | `test/1_LED/source/led_test.fdc`、`test/3_UART/uart_test.fdc`、`test/1_LED/run.log` |
| `clk_in` | adc_test、encryption | — | — | `_fdcscan/4_7_adc_top/.../adc_test.fdc` |
| `sys_clk` | 4_12 / 4_10 / 3_x HDMI_IN_DDR3_*（共 11 个工程） | `create_clock -name {sys_clk} ... -period {37.000}` | 27.03 MHz | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc |
| `free_clk` | 2_9 ddr3_test | `create_clock -name {free_clk} ... -period {20.000}` | 50 MHz | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc |
| `pin_clk_in` | 9_远程升级 pg2l100h_remote_update | `create_clock -name {pin_clk} [get_nets pin_clk_in] -period {37.000}` | 27.03 MHz | 9_远程升级/FPGA_remote_update/pg2l100h_remote_update/remote_update_golden/prj/pg2l100h_remote_updata.fdc |
| `ref_clk` | 4_11 lvds_test | `create_clock -name {ref_clk} ... -period {20}` | 50 MHz | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |
| `clk_27M` | ADDA_HDMI（ad9280_ad9708_HDMI） | —（端口名即写了 27M） | 27 MHz | 7_FMC扩展子卡及Demo/2_Demo/ADDA_HDMI Demo/ad9280_ad9708_HDMI/ad9280_ad9708_HDMI.fdc |
| `clk_in1` | 4_14 hdmi_in_sfp_hdmi_out | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc |

配套 PLL 的输入频率同样指向 27 MHz：`test/4_PLL/ipcore/PLL/PLL.idf`、`7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/ipcore/pll/pll.idf`、`.../ADDA_HDMI Demo/ad9280_ad9708_HDMI/ipcore/pll/pll.idf`、`.../ipcore/pll_adda/pll_adda.idf` 里 `CLKIN_FREQ = 27.00000000`（同文件里 `CLKIN_FREQ_advancedPage` 还留着 50，属历史残留）。

### 1.2 DDR3 参考时钟（差分对）：N3 / N2，125 MHz

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `ref_clk_p` | N3 | SSTL15D_I / 1.5 V | INPUT | BANKR5 | DIFFIO_R5_G1_11P_GMCLK | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc | DDR3 例程命名；`create_clock -period {8.0}` → 125 MHz |
| `ref_clk_n` | N2 | SSTL15D_I / 1.5 V | INPUT | BANKR5 | DIFFIO_R5_G1_11N_GMCLK | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc | 同上 |
| `clk_p` | N3 | HSTL15D_I / 1.5 V | INPUT | BANKR5 | DIFFIO_R5_G1_11P_GMCLK | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc | 11 个 HDMI 工程命名；`create_clock -name {ref_clk} [get_ports {clk_p}] -period {8.0}` |
| `clk_n` | N2 | HSTL15D_I / 1.5 V | INPUT | BANKR5 | DIFFIO_R5_G1_11N_GMCLK | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc | 同上 |

⚠ **同一对引脚、IO 标准写法不一致**：`2_9_ddr3_test` 写 `SSTL15D_I`，11 个 `HDMI_IN_DDR3_*` 工程写 `HSTL15D_I`。需实机核对按哪种标准布板。

DDR3 IP 侧参数（`_scan2/.../ipcore/ddr3_test/ddr3_test.idf`）：`CLKIN_FREQ = 125.000`、`DFI_CLK_PERIOD = 8000` ps、`DESIRED_DDR3_RATE = 1000.000`、`DDR3_CL = 7`、`DDR3_CWL = 6`。

### 1.3 其它时钟 / 差分参考

| 信号 | 引脚 | IO 标准 | 方向 | BANK | 专用功能名 | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `ref_clk_p` / `ref_clk_n` | F11 / E11 | LVCMOS33（约束里就是普通单端标准） | Input | — | — | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | PCIe 100 MHz 参考，`create_clock -period {10.000}` |
| `i_p_refckp_0` / `i_p_refckn_0` | AA11 / AB11 | （未写） | Input | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/ipcore/hsst_test/pnr/example_design/pango_hsstlp_top.fdc | HSST 参考时钟 0（SFP 用） |
| `i_p_refckp_1` / `i_p_refckn_1` | AA13 / AB13 | （未写） | Input | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/ipcore/hsst_test/pnr/example_design/pango_hsstlp_top.fdc | HSST 参考时钟 1 |
| `i_p_refckp_1` / `i_p_refckn_1` | AA11 / AB11 | （未写） | Input | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | ⚠ 同一族工程里 refck_1 落到 AA11/AB11，与上一行冲突 |
| `rx_clk_p` / `rx_clk_n` | W21 / Y21 | LVDS25 | Input | BANKL6 | DIFFIO_L6_G2_13P_GSCLK | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc | LVDS 接收时钟；主文件 `-period {40}` → 25 MHz，备份 `-period {20}` → 50 MHz（⚠ 不一致） |
| `tx_clk_p` / `tx_clk_n` | T20 / U20 | LVDS25 | Output | BANKL6 | DIFFIO_L6_G2_14P_DQS | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc | LVDS 发送时钟 |
| `rgmii_rxc` | D19 | LVCMOS33 | Input | BANKL3 | DIFFIO_L3_G2_12P_GMCLK | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc | RGMII 接收时钟，`-period {8.000}` → 125 MHz |
| `rgmii_txc` | G16 | LVCMOS33 | Output | BANKL3 | DIFFIO_L3_G0_05N_VREF | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc | RGMII 发送时钟，`-period {8.000}` → 125 MHz |

### 1.4 频率矛盾（27 MHz vs 50 MHz）—— 必须实机核对

- 指向 **27 MHz**：ADDA demo 把 D18 端口直接命名为 `clk_27M`（`7_FMC扩展子卡及Demo/2_Demo/ADDA_HDMI Demo/ad9280_ad9708_HDMI/ad9280_ad9708_HDMI.fdc`）；所有 28 nm PLL IP 的 `CLKIN_FREQ = 27.00000000`；11 个 HDMI 工程与远程升级工程对 D18 用 `-period 37.000`。
- 指向 **50 MHz**：`2_9 ddr3_test` 对 D18 用 `-period 20.000`；`4_11 lvds_test` 用 `-period 20`；`7_FMC.../HDMI_DDR3_OV5640_100H/source/rtl/hdmi_ddr_ov5640_top.v` 第 33 行注释 `//50Mhz`；`ipcore/ddr3_test/example_design/rtl/test_ddr.v` 里 `//115200bps for 50MHz clk.`。
- **判定建议**：以 **27 MHz** 为准（命名 + PLL 参数 + 多数工程一致）。若板上另有一颗 50 MHz 晶振，其引脚**未找到**；旧备份 `_fdcscan/4_13_tri_eth_test/.../constraint_backup/ethernet_test_2023_09_05_11_11_54.fdc` 里出现过 `clk_50m = P20`，但同批工程把 P20 当 `b_out[2]` 用，故 P20 归属存疑。

---

## 2. 复位、按键、LED 与其它简单 IO

### 2.1 复位按键

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `rstn` | C22 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/4_1_led_test/4_1_led_test/4_1_led_test/5_1_led_test/source/led_test.fdc | LED 实验 |
| `rstn` | C22 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/2_7_key_led_test/2_7_key_led_test/2_7_key_led_test/source/key_led_test.fdc | 按键实验 |
| `rst_board` | C22 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc | DDR3 实验 |
| `rst_in` | C22 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc | HDMI 工程 |
| `rstn_in` | C22 | LVCMOS33 / 3.3 V | Input | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc | LVDS 实验 |
| `sys_rst_n` | C22 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/ethernet_test.fdc | 以太网实验 |
| `rstn_key` | C22 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc | 动态 PPLL 实验 |

### 2.2 用户按键

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `key` | C23 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18N_VREF | _fdcscan/2_7_key_led_test/2_7_key_led_test/2_7_key_led_test/source/key_led_test.fdc | 按键/LED 实验 |
| `key` | C23 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18N_VREF | _fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc | 动态 PPLL 实验 |
| `rx_rstn` | C23 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18N_VREF | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | HDMI IN/SFP 实验里同一引脚当第二复位用 |

### 2.3 8 位用户 LED（4 个独立工程完全一致）

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |

同一组焊盘在别的工程里被改名成状态灯（引脚完全一致，可交叉验证）：

| 工程里的灯名 | 引脚 | = led[n] | 来源文件 |
| :-- | :-- | :-- | :-- |
| `heart_beat_led` | A20 | led[0] | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc |
| `ddr_init_done` | A20 | led[0] | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc |
| `ddrphy_cpd_lock` | C18 | led[1] | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc |
| `err_flag_led` / `init_over_rx` / `led_test` / `smlh_link_up` | C19 | led[2] | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc ; _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc ; _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc |
| `hdmi_int_led` / `ref_led` / `cmos_init_done[1]` | E18 | led[3] | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc ; _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc |
| `pll_lock` | A17 | led[4] | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc |
| `bist_run_led` | A18 | led[5] | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc |
| `status_led[1]` / `rdlh_link_up` / `rgmii_txd[2]`(旧) | C18 | led[1] | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/ethernet_test.fdc ; _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc |

`E18` 的语义有 RTL 注释：`7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/source/rtl/hdmi_ddr_ov5640_top.v` 第 76 行 `output hdmi_int_led, //HDMI_OUT初始化完成`。

### 2.4 其它简单 IO

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `rstn_out` | G25 | LVCMOS33 / 3.3 V | OUTPUT | BANKL4 | DIFFIO_L4_G3_22P_BFOE_N | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc | **上电延时复位输出**：`7_FMC.../hdmi_ddr_ov5640_top.v` 第 180 行 `assign rstn_out = (rstn_1ms == 16'h2710);`，同时驱动 `ms72xx_ctl` 等模块 resetn |
| `phy_rstn` | G25 | LVCMOS33 / 3.3 V | OUTPUT | BANKL4 | DIFFIO_L4_G3_22P_BFOE_N | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc | 以太网 PHY 复位（与上一行同脚，说明该脚是底板“复位输出”网络） |
| `rstn` | B20 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G2_14P_DQS | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | ⚠ 同一工程里 rstn 落在 B20，与 `2_11` 以太网工程 `rgmii_txd[1] = B20` 冲突 |
| `lock_led` | D19 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_12P_GMCLK | _fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc | ⚠ D19 在以太网工程里是 `rgmii_rxc` 输入，此处当输出 LED，二者不能同时成立 |
| `led_int` | A20 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_14N_DQS | _fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc | = led[0] A20 |
| `led` | A20 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_14N_DQS | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | = led[0] A20 |
| `led_int` | A20 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_14N_DQS | 7_FMC扩展子卡及Demo/2_Demo/ADDA_HDMI Demo/ad9280_ad9708_HDMI/ad9280_ad9708_HDMI.fdc | = led[0] A20 |

---

## 3. UART

UART 只有一对固定引脚，被 5 个工程使用（命名不同、引脚相同）：

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `uart_tx` | C24 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G3_22P | _fdcscan/2_8_uart_test/2_8_uart_test/2_8_uart_test/uart_test.fdc | DRIVE=8 / SLOW |
| `uart_rx` | B24 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_22N | _fdcscan/2_8_uart_test/2_8_uart_test/2_8_uart_test/uart_test.fdc | 同上 |
| `uart_txd` | C24 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G3_22P | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc | DDR3 例程 |
| `uart_rxd` | B24 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_22N | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc | DDR3 例程 |
| `txd` | C24 | LVCMOS33 / 3.3 V | Output | BANKL3 | DIFFIO_L3_G3_22P | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | PCIe DMA 例程 |
| `rxd` | B24 | LVCMOS33 / 3.3 V | Input | BANKL3 | DIFFIO_L3_G3_22N | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | PCIe DMA 例程 |
| `uart_tx` | C24 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G3_22P | 9_远程升级/FPGA_remote_update/pg2l100h_remote_update/remote_update_golden/prj/pg2l100h_remote_updata.fdc | 远程升级例程 |
| `uart_rx` | B24 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_22N | 9_远程升级/FPGA_remote_update/pg2l100h_remote_update/remote_update_golden/prj/pg2l100h_remote_updata.fdc | 远程升级例程 |

ADC 例程里同一对引脚叫 `cfg_uart_txd / cfg_uart_rxd`（来源 `_fdcscan/4_7_adc_top/4_7_adc_top/4_7_adc_top/adc_top/pnr/adc_test.fdc`）：C24 / B24。

---

## 4. QSPI 配置 Flash（核心板 2 颗 128 Mb）

### 4.1 结论表

全部 103 个 `.fdc` 里**没有任何一个**给“板级 QSPI 配置 Flash”起 `qspi_* / flash_*` 之类的信号名 —— 唯一有证据的是远程升级工程里的 `spi_*` 一组：

| 信号 | FPGA 引脚 | BANK / 引脚专用功能名 | 方向 | 约束状态 | 说明 |
| :-- | :-- | :-- | :-- | :-- | :-- |
| `spi_cs` | **P18** | BANKL5 / `DIFFIO_L5_G0_05P_FCS_N` | Output | 未注释，实际生效 | 专用名 **FCS_N** = Flash Chip Select |
| `spi_dq0` | **R14**（另有被覆盖的 P22） | BANKL5 / `DIFFIO_L5_G0_00P_MOSI_D0` | Output | 未注释；文件第 73 行先写 P22，第 207 行重定义为 R14，PnR 最终采用 **R14** | 专用名 **MOSI_D0** = 配置 Flash 数据 0 |
| `spi_dq1` | **R15** | BANKL5 / `DIFFIO_L5_G0_00N_MISO_D1_DI` | Input | 未注释 | 专用名 **MISO_D1_DI** = 配置 Flash 数据 1 |
| `spi_dq2` | P14 | BANKL5 / `DIFFIO_L5_G0_01P_D2` | Inout | ⚠ **被注释掉**（该文件第 44–49 行以 `#` 开头） | 专用名 D2 |
| `spi_dq3` | N14 | BANKL5 / `DIFFIO_L5_G0_01N_D3` | Inout | ⚠ **被注释掉** | 专用名 D3 |
| `spi_clk` | U6（不可用） | BANKR5 / `DIFFIO_R5_G3_20P_DQS` | Output | ⚠ **被注释掉**；且 U6 在 DDR3 例程里是 `mem_ck`，两者互斥 | **QSPI CLK 引脚未找到** |
| （第二片 Flash 片选） | **F25** | BANKL4 / `DIFFIO_L4_G3_22N_BFWE_FCS2_N` | — | 无 .fdc 使用；来自 PnR 球位表 | 专用名 **FCS2_N** = 第二片配置 Flash 片选，与“核心板 2 颗 QSPI Flash”吻合 |
| （配置接口辅助脚） | P15 | BANKL5 / `DIFFIO_L5_G0_02P_DQS_IO_STATUS_C` | — | 无 .fdc 使用 | `IO_STATUS_C`：配置状态输出 |
| （配置接口辅助脚） | P16 | BANKL5 / `DIFFIO_L5_G0_02N_DQS_ECCLKIN` | — | 无 .fdc 使用 | `ECCLKIN`：配置时钟输入 |
| （配置接口 D8） | N18 | BANKL5 / `DIFFIO_L5_G0_05N_VREF_D8` | — | 无 .fdc 使用 | x8 模式数据 8 |
| （配置接口 CSO） | N24 | BANKL5 / `DIFFIO_L5_G2_14N_DQS_CSO_DOUT` | — | 无 .fdc 使用 | `CSO_DOUT`：级联数据输出（多片菊花链） |

### 4.2 证据链与判定

1. **引脚号来源**：`9_远程升级/FPGA_remote_update/pg2l100h_remote_update/remote_update_golden/prj/pg2l100h_remote_updata.fdc`（Io Table 第 44–161 行），以及同工程最终结果 `9_远程升级/.../prj/device_map/remote_updata_top.pcf`（`def_port {spi_cs} LOC=P18 ...`、`def_port {spi_dq0} LOC=R14 ...`、`def_port {spi_dq1} LOC=R15 ...`）与 `.../place_route/remote_updata_golden_top_prr.prt`。
2. **是否专用配置引脚：是。** 上述 `.prt` 给出的球位专用名是 `DIFFIO_L5_G0_00P_MOSI_D0`、`DIFFIO_L5_G0_05P_FCS_N`、`DIFFIO_L5_G0_00N_MISO_D1_DI` —— `MOSI / MISO / FCS_N / FCS2_N / CSO_DOUT` 就是 Pango 配置（SPI/MSPI）专用功能命名；`test/1_LED/place_route/led_test_prr.prt`（PG2L200H/FBB676 实跑）对同样的球给出一模一样的名字。
3. **为什么例程能把它们当普通 IO 用**：PDS 器件配置里有 `(persist_pin "Release For USER")`（`D:/PDS_2022.2-SP6.4/arch/vendor/pango/logos2/pg2l200h/data/config/ini_data/Logos2-PG2L200H.ini` 第 86 行；同文件第 89 行还有 `(persist_slave_spi_pin "No")`、第 68–69 行 `spi_address_width` / `spi_data_width X1/X2/X4/X8`），即配置完成后这些专用脚会**释放给用户逻辑**——这正是远程升级例程能直接改写配置 Flash 的原因。
4. **Flash 型号 / 容量 / 位宽：未找到。** 源目录里没有任何 Flash 器件手册或丝印文本（`4_IC_datasheet` 只有 EEPROM / 以太网 PHY / HDMI PHY / OV5640 / 电源）。“2 颗 128 Mb QSPI”来自任务描述，文件内**无器件型号**。
5. **QSPI CLK 引脚：未找到。** 所有文件里 `spi_clk` 唯一一次赋值是 `U6` 且被注释，而 U6 是 DDR3 的 `mem_ck`；PnR 球位表里 BANKL5 也没有名为 `CCLK` 的专用脚。

---

## 5. HDMI TX 输出（MS7210）

### 5.1 关键结论：FPGA 里没有 TMDS 序列化器

- 底板 HDMI 输出**不是**由 FPGA 直接产生 TMDS，而是 **24 位并行 RGB + DE/HS/VS/PIXCLK 送给 MS7210**（HDMI 发送 PHY），TMDS 在片外完成。
- RTL 证据：`7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/source/rtl/ms72xx_ctl.v` 第 76–104 行实例化 `ms7200_ctl U1_ms7200_ctl`（RX）与 `ms7210_ctl U2_ms7210_ctl`（TX），两者共用一条 I2C 总线（第 106 行 `device_id` 选 `8'hB2`(TX) / `8'h56`(RX)）。
- 因此 **HDMI 通路上的 OSERDES / SERDES / HSST 参数（640×480@60 的 25 MHz 像素时钟、720p、1080p）在本板上不存在**：全库 `grep OSERDES` 只命中 DDR3 PHY 内部（`GTP_OSERDES_E2`，参数 `OSERDES_MODE = "HMSDR8TO1"`，见 `_scan2/.../sim_lib/ddrphy/ddr3_test_slice_top_v1_10.v`）与 LVDS 例程；HDMI 的串行器是片外 MS7210。

### 5.2 并行 RGB 输出引脚（以 `2_10_hdmi_loop` 为准，11 个 HDMI 工程一致）

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `pixclk_out` | T24 | LVCMOS33 / 3.3 V | OUTPUT | BANKL5 | DIFFIO_L5_G3_20P_DQS | _fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc | 像素时钟输出；该 fdc 第 370 行另有 `define_attribute {n:pixclk_out} {PAP_CLOCK_DEDICATED_ROUTE} {FALSE}` |

**R 通道 r_out[7:0]**

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |

**G 通道 g_out[7:0]**

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |

**B 通道 b_out[7:0]**

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |

**同步 / 使能**

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `de_out` | N19 | LVCMOS33 / 3.3 V | OUTPUT | BANKL5 | DIFFIO_L5_G2_15N_D31_A15 | _fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc | 数据使能 |
| `hs_out` | R20 | LVCMOS33 / 3.3 V | OUTPUT | BANKL5 | DIFFIO_L5_G2_17P_D28_A12 | _fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc | 行同步 |
| `vs_out` | R21 | LVCMOS33 / 3.3 V | OUTPUT | BANKL5 | DIFFIO_L5_G2_17N_D27_A11 | _fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc | 场同步 |

其它工程对同一 24 位总线的命名（引脚一致，仅打包顺序不同）：

| 工程 | 命名 | 说明 | 来源文件 |
| :-- | :-- | :-- | :-- |
| 4_12 HDMI_IN_DDR3_HDMI_OUT | `r_out / g_out / b_out` | 与 hdmi_loop 完全一致 | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc |
| 4_6 hdmi_dyn_ppll | `r_out / g_out / b_out` | ⚠ **位序整体取反**（该工程 `r_out[7] = N21`，hdmi_loop 是 `r_out[0] = N21`），引脚集合相同 | _fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc |
| 4_14 hdmi_in_sfp_hdmi_out | `hdmi_data_out[23:0]` | [23:16]=R、[15:8]=G、[7:0]=B，位序与 hdmi_loop 相同 | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc |
| ADDA_HDMI | `vout_data[23:0]` + `vout_clk/de/hs/vs` | [23:16]=R、[15:8]=G、[7:0]=B | 7_FMC扩展子卡及Demo/2_Demo/ADDA_HDMI Demo/ad9280_ad9708_HDMI/ad9280_ad9708_HDMI.fdc |

### 5.3 HDMI 使能 / 热插拔 (HPD)

- **HPD（热插拔检测）输入：未找到。** 103 个 `.fdc` 中没有任何 `hpd / hotplug` 端口。
- **HDMI 芯片复位/使能**：由 G25 `rstn_out` 输出提供（见 2.4，RTL 是 10 ms 延时释放的复位）；`hdmi_int_led`(E18) 指示 TX 初始化完成，`init_over_rx`(C19) 指示 RX 初始化完成 —— 而 `ms72xx_ctl.v` 第 48 行 `assign init_over_rx = 1'b1;` 把它硬接为 1，所以 C19 实际是常高电平的灯。

### 5.4 像素时钟的生成（PLL 点频，无引脚）

| IP 文件 | CLKIN | 输出点频 | 用途 | 来源 |
| :-- | :-- | :-- | :-- | :-- |
| `ipcore/pll/pll.idf`（HDMI_DDR3_OV5640_100H） | 27 MHz | `CLKOUT0 = 37.125 MHz`、`CLKOUT1 = 10.000 MHz`、`CLKOUT2 = 25.000 MHz` | 25 MHz 可作 640×480@60 像素时钟 | `7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/ipcore/pll/pll.idf` |
| `ipcore/pll/pll.idf`（ADDA_HDMI） | 27 MHz | `CLKOUT0 = 148.5 MHz`、`CLKOUT1 = 10.390 MHz` | 148.5 MHz = 1080p60 像素时钟 | `7_FMC扩展子卡及Demo/2_Demo/ADDA_HDMI Demo/ad9280_ad9708_HDMI/ipcore/pll/pll.idf` |
| `ipcore/pll_adda/pll_adda.idf` | 27 MHz | `CLKOUT0 = 118.000 MHz`、`CLKOUT1 = 29.700 MHz` | AD/DA 采样时钟 | 同目录 `pll_adda.idf` |
| `test/4_PLL/ipcore/PLL/PLL.idf` | 27 MHz | `CLKOUT0 = 54 MHz`、`CLKOUT1 = 81 MHz`、`CLKOUT2 = 81 MHz(180°)` | PLL 实验 | `test/4_PLL/ipcore/PLL/PLL.idf` |

720p / 1080p 的**显式**像素时钟约束（如 74.25 / 148.5 MHz 的 create_clock）在 `.fdc` 中**未找到**；只有上表 PLL 点频与 `6_doc/VESA/Vesa  Monitor Timing_v1r12.pdf` 可参考。

---

## 6. HDMI IN（MS7200）

MS7200 把 HDMI 解成 24 位并行 RGB + DE/HS/VS/PIXCLK 送进 FPGA（与 TX 完全对称）。引脚（`2_10_hdmi_loop` 与 11 个 `HDMI_IN_DDR3_*` 工程一致）：

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `pixclk_in` | K21 | LVCMOS33 / 3.3 V | INPUT | BANKL4 | DIFFIO_L4_G1_11P_GMCLK | _fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc | RX 像素时钟输入 |
| `de_in` | H23 | LVCMOS33 / 3.3 V | INPUT | BANKL4 | DIFFIO_L4_G2_13N_GSCLK | _fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc | 数据使能 |
| `hs_in` | J23 | LVCMOS33 / 3.3 V | INPUT | BANKL4 | DIFFIO_L4_G2_13P_GSCLK | _fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc | 行同步 |
| `vs_in` | H24 | LVCMOS33 / 3.3 V | INPUT | BANKL4 | DIFFIO_L4_G2_15N_A27 | _fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc | 场同步 |

**R 通道 r_in[7:0]**

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |

**G 通道 g_in[7:0]**

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |

**B 通道 b_in[7:0]**

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |

4_14 工程用 `hdmi_data_in[23:0]` 表示同一组（[23:16]=R、[15:8]=G、[7:0]=B），逐位一致，可直接对照 `_fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc`。

**配置总线（TX/RX 共用一条 I2C）**

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `hd_scl` | K22 | LVCMOS33 / 3.3 V | OUTPUT | BANKL4 | DIFFIO_L4_G2_17P_A24 | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc | I2C SCL（4_12 工程名） |
| `hd_sda` | K23 | LVCMOS33 / 3.3 V | INOUT | BANKL4 | DIFFIO_L4_G2_17N_A23 | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc | I2C SDA（4_12 工程名） |
| `iic_scl` | K22 | LVCMOS33 / 3.3 V | OUTPUT | BANKL4 | DIFFIO_L4_G2_17P_A24 | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | I2C SCL（4_14 工程名） |
| `iic_sda` | K23 | LVCMOS33 / 3.3 V | INOUT | BANKL4 | DIFFIO_L4_G2_17N_A23 | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | I2C SDA（4_14 工程名） |
| `iic_tx_scl` | K22 | LVCMOS33 / 3.3 V | OUTPUT | BANKL4 | DIFFIO_L4_G2_17P_A24 | _fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc | I2C SCL（4_6 工程名） |
| `iic_tx_sda` | K23 | LVCMOS33 / 3.3 V | INOUT | BANKL4 | DIFFIO_L4_G2_17N_A23 | _fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc | I2C SDA（4_6 工程名） |

⚠ `7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/constraint_backup/*.fdc` 里 `iic_tx_scl / iic_tx_sda` 落在 **M21 / L21**，那是 OV5640 摄像头的 I2C（FMC 子卡），与本板 K22/K23 不是同一路。

---

## 7. DDR3

### 7.1 `.idf` 基本信息（器件 / 容量 / 位宽 / 生成目标）

| 项目 | 值 |
| :-- | :-- |
| IP 名 / 版本 | `DDR3 Interface` / `Logos2 HMIC_S` v1.10（id 042003） |
| 实例 | `ddr3_test` |
| family / device / package / speedgrade | `Logos2` / `PG2L100H` / `FBG676` / `-6` |
| 生成工具 | 未找到 |
| 器件型号 | `MT41K256M16XX`（另：`DDR3_DFT_MEM_PART` = `MT41K256M16XX`，`DDR3_BASE_MEM_PART` = `MT41K128M16XX`） |
| 存储类型 / 位宽 | `DDR3`，MEM_DQ_WIDTH = **32**，MEM_DQS_WIDTH = 4，MEM_DM_WIDTH = 4 |
| 地址 | ROW = 15，COLUMN = 10，BANK = 3，ADDR = 15 |
| 速率 | DESIRED / ACTUAL DDR3 RATE = 1000.000 / 1000.000 Mb/s，CL = 7，CWL = 6，CLKIN_FREQ = 125.000 MHz |
| BANK 分组 | BANK0/1/2 = R5 / R4 / L6，BANK_CA = R5，BANK_PLL_REF = R5 |
| 容量推算 | 15 行 × 10 列 × 8 bank = 256 M 地址 × 32 bit = **8 Gbit = 1 GB**（= 2 颗 4 Gb 器件拼 x32） |

### 7.2 权威引脚表（`.fdc`，12 个工程一致）

来源：`_fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc`（`_scan2` 下有 MD5 完全相同的副本）。第 3 列是另一套 `HDMI_DDR3_OV5640_100H` 变体的值，⚠ 表示与该表不同（见 7.3）。

| 信号 | 引脚（2_9_ddr3_test + 11 个 HDMI 工程） | 引脚（HDMI_DDR3_OV5640 变体） | IO 标准 | 方向 | BANK | 引脚专用功能名 (PnR) |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `mem_ck` | U6 | U6 | HSTL15D_I | OUTPUT | BANKR5 | DIFFIO_R5_G3_20P_DQS |
| `mem_ck_n` | U5 | U5 | HSTL15D_I | OUTPUT | BANKR5 | DIFFIO_R5_G3_20N_DQS |
| `mem_cke` | R1 | R1 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_14P_DQS |
| `mem_cs_n` | N4 | N4 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_13N_GSCLK |
| `mem_ras_n` | P6 | P6 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G3_18P |
| `mem_cas_n` | T7 | T7 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G3_23N |
| `mem_we_n` | T8 | T8 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G3_23P |
| `mem_odt` | H2 | H2 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_09P |
| `mem_rst_n` | H1 | H1 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_09N |
| `mem_ba[0]` | P4 | P4 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_13P_GSCLK |
| `mem_ba[1]` | R2 | R2 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_16N |
| `mem_ba[2]` | T5 | T5 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G3_19P |
| `mem_a[0]` | J1 | J1 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_06N |
| `mem_a[1]` | L3 | L3 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_07P |
| `mem_a[2]` | L2 | L2 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_10N_GSCLK |
| `mem_a[3]` | P3 | P3 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_12N_GMCLK |
| `mem_a[4]` | T2 | T2 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_16P |
| `mem_a[5]` | M1 | M1 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_08N_DQS |
| `mem_a[6]` | U1 | U1 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_17N |
| `mem_a[7]` | K1 | K1 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_06P |
| `mem_a[8]` | U2 | U2 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_17P |
| `mem_a[9]` | K2 | K2 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_07N |
| `mem_a[10]` | T3 | T3 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_15N |
| `mem_a[11]` | P1 | P1 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_14N_DQS |
| `mem_a[12]` | T4 | T4 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G2_15P |
| `mem_a[13]` | M2 | M2 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_10P_GSCLK |
| `mem_a[14]` | N1 | N1 | HSTL15_I | OUTPUT | BANKR5 | DIFFIO_R5_G1_08P_DQS |
| `mem_dq[0]` | G5 | F4 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G1_11P_GMCLK |
| `mem_dq[1]` | J6 | F5 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G1_06P_VAA13P |
| `mem_dq[2]` | F5 | G4 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G1_11N_GMCLK |
| `mem_dq[3]` | L8 | G5 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G1_07P_VAA14P |
| `mem_dq[4]` | G4 | J5 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G1_10P_GSCLK |
| `mem_dq[5]` | K7 | J6 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G1_09P_VAA0P |
| `mem_dq[6]` | F4 | K6 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G1_10N_GSCLK |
| `mem_dq[7]` | J5 | K7 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G1_06N_VAA13N |
| `mem_dq[8]` | H6 | E6 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G0_04P_VAA12P |
| `mem_dq[9]` | F8 | F7 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G0_03P |
| `mem_dq[10]` | H8 | F8 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G0_01P_VAA6P |
| `mem_dq[11]` | D6 | G6 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G0_00N_VAA4N |
| `mem_dq[12]` | G8 | G9 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G0_01N_VAA6N |
| `mem_dq[13]` | E6 | H6 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G0_00P_VAA4P |
| `mem_dq[14]` | H9 | G9 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G0_05P |
| `mem_dq[15]` | G6 | H6 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G0_04N_VAA12N |
| `mem_dq[16]` | C4 | A4 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G2_13N_GSCLK |
| `mem_dq[17]` | D4 | B5 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G2_13P_GSCLK |
| `mem_dq[18]` | A4 | B4 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G2_15N |
| `mem_dq[19]` | E3 | C4 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G2_17N |
| `mem_dq[20]` | C3 | D3 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G2_16N |
| `mem_dq[21]` | F3 | D4 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G2_17P |
| `mem_dq[22]` | B4 | D5 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G2_15P |
| `mem_dq[23]` | D3 | E3 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G2_16P |
| `mem_dq[24]` | F2 | A2 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G3_21P |
| `mem_dq[25]` | D1 | A3 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G3_22N |
| `mem_dq[26]` | G1 | C1 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G3_23N |
| `mem_dq[27]` | A2 | B2 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G3_19N |
| `mem_dq[28]` | E1 | D1 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G3_22P |
| `mem_dq[29]` | A3 | E1 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G3_19P |
| `mem_dq[30]` | G2 | E2 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G3_23P |
| `mem_dq[31]` | C2 | F2 ⚠ | HSTL15_I | INOUT | BANKR4 | DIFFIO_R4_G3_18P |
| `mem_dqs[0]` | J4 | H4 ⚠ | HSTL15D_I | INOUT | BANKR4 | DIFFIO_R4_G1_08P_DQS_VAA15P |
| `mem_dqs_n[0]` | H4 | J4 ⚠ | HSTL15D_I | INOUT | BANKR4 | DIFFIO_R4_G1_08N_DQS_VAA15N |
| `mem_dqs[1]` | H7 | G7 ⚠ | HSTL15D_I | INOUT | BANKR4 | DIFFIO_R4_G0_02P_DQS_VAA11P |
| `mem_dqs_n[1]` | G7 | H7 ⚠ | HSTL15D_I | INOUT | BANKR4 | DIFFIO_R4_G0_02N_DQS_VAA11N |
| `mem_dqs[2]` | B5 | A5 ⚠ | HSTL15D_I | INOUT | BANKR4 | DIFFIO_R4_G2_14P_DQS |
| `mem_dqs_n[2]` | A5 | B5 ⚠ | HSTL15D_I | INOUT | BANKR4 | DIFFIO_R4_G2_14N_DQS |
| `mem_dqs[3]` | C1 | B1 ⚠ | HSTL15D_I | INOUT | BANKR4 | DIFFIO_R4_G3_20P_DQS |
| `mem_dqs_n[3]` | B1 | C1 ⚠ | HSTL15D_I | INOUT | BANKR4 | DIFFIO_R4_G3_20N_DQS |
| `mem_dm[0]` | K6 | K8 ⚠ | HSTL15_I | OUTPUT | BANKR4 | DIFFIO_R4_G1_09N_VAA0N |
| `mem_dm[1]` | F7 | H9 ⚠ | HSTL15_I | OUTPUT | BANKR4 | DIFFIO_R4_G0_03N |
| `mem_dm[2]` | D5 | E5 ⚠ | HSTL15_I | OUTPUT | BANKR4 | DIFFIO_R4_G2_12N_GMCLK |
| `mem_dm[3]` | E2 | G1 ⚠ | HSTL15_I | OUTPUT | BANKR4 | DIFFIO_R4_G3_21N |

### 7.3 变体差异（同一块板的两套 bit 映射）

`7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/ipcore/ddr3_test/pnr/ddr_test.fdc` 与主表的**控制/地址/BA/CS/CK/RAS/CAS/WE/ODT/RST 完全一致**，只有 44 个 DQ/DQS/DM 落位不同（同一 byte lane 内的位序互换 + DM 归位差别）：

| 信号 | 主表（2_9_ddr3_test + 11 个 HDMI 工程） | 变体（HDMI_DDR3_OV5640_100H） |
| :-- | :-- | :-- |
| `mem_dq[0]` | G5 | F4 |
| `mem_dq[1]` | J6 | F5 |
| `mem_dq[2]` | F5 | G4 |
| `mem_dq[3]` | L8 | G5 |
| `mem_dq[4]` | G4 | J5 |
| `mem_dq[5]` | K7 | J6 |
| `mem_dq[6]` | F4 | K6 |
| `mem_dq[7]` | J5 | K7 |
| `mem_dq[8]` | H6 | E6 |
| `mem_dq[9]` | F8 | F7 |
| `mem_dq[10]` | H8 | F8 |
| `mem_dq[11]` | D6 | G6 |
| `mem_dq[12]` | G8 | G9 |
| `mem_dq[13]` | E6 | H6 |
| `mem_dq[14]` | H9 | G9 |
| `mem_dq[15]` | G6 | H6 |
| `mem_dq[16]` | C4 | A4 |
| `mem_dq[17]` | D4 | B5 |
| `mem_dq[18]` | A4 | B4 |
| `mem_dq[19]` | E3 | C4 |
| `mem_dq[20]` | C3 | D3 |
| `mem_dq[21]` | F3 | D4 |
| `mem_dq[22]` | B4 | D5 |
| `mem_dq[23]` | D3 | E3 |
| `mem_dq[24]` | F2 | A2 |
| `mem_dq[25]` | D1 | A3 |
| `mem_dq[26]` | G1 | C1 |
| `mem_dq[27]` | A2 | B2 |
| `mem_dq[28]` | E1 | D1 |
| `mem_dq[29]` | A3 | E1 |
| `mem_dq[30]` | G2 | E2 |
| `mem_dq[31]` | C2 | F2 |
| `mem_dqs[0]` | J4 | H4 |
| `mem_dqs_n[0]` | H4 | J4 |
| `mem_dqs[1]` | H7 | G7 |
| `mem_dqs_n[1]` | G7 | H7 |
| `mem_dqs[2]` | B5 | A5 |
| `mem_dqs_n[2]` | A5 | B5 |
| `mem_dqs[3]` | C1 | B1 |
| `mem_dqs_n[3]` | B1 | C1 |
| `mem_dm[0]` | K6 | K8 |
| `mem_dm[1]` | F7 | H9 |
| `mem_dm[2]` | D5 | E5 |
| `mem_dm[3]` | E2 | G1 |

同时 `.idf` 的 `PAD_*` 清单与**变体**更吻合（例如 `.idf` 里 `PAD_DM0 = K8`、`PAD_DQ12 = PAD_DQ14 = G9` 都是变体在用；而主表用 `mem_dm[0] = K6`、`mem_dq[3] = L8`，`L8` 在 `.idf` 的 `PAD_*` 里根本不存在）。

**判定**：物理布线以**主表**为准（12 个工程 + 独立 DDR3 测试工程一致）。`.idf` 的 `PAD_*` 是 IP GUI 槽位名而非真实信号名（它自身就有重复值，如 `PAD_DQ13` 与 `PAD_DQ15` 都是 H6），不能当接线表用。若必须二选一，请以主表 + 实机核对上表差异位。

### 7.4 `.idf` 的 `PAD_*` 原始参数清单（127 条，逐字照录）

> 说明：这是 IP 配置里保存的槽位→引脚映射，**不是**可直接照抄的信号名（存在重复值）。可直接使用的信号表见 7.2。来源：`_scan2/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/ddr3_test.idf`。

| .idf 参数名 | PAD_* 值 | BANK |
| :-- | :-- | :-- |
| `PAD_A0` | J1 | BANKR5 |
| `PAD_A1` | L3 | BANKR5 |
| `PAD_A2` | L2 | BANKR5 |
| `PAD_A3` | P3 | BANKR5 |
| `PAD_A4` | T2 | BANKR5 |
| `PAD_A5` | M1 | BANKR5 |
| `PAD_A6` | U1 | BANKR5 |
| `PAD_A7` | K1 | BANKR5 |
| `PAD_A8` | U2 | BANKR5 |
| `PAD_A9` | K2 | BANKR5 |
| `PAD_A10` | T3 | BANKR5 |
| `PAD_A11` | P1 | BANKR5 |
| `PAD_A12` | T4 | BANKR5 |
| `PAD_A13` | M2 | BANKR5 |
| `PAD_A14` | N1 | BANKR5 |
| `PAD_A15` | P5 | BANKR5 |
| `PAD_BA0` | P4 | BANKR5 |
| `PAD_BA1` | R2 | BANKR5 |
| `PAD_BA2` | T5 | BANKR5 |
| `PAD_CK` | U6 | BANKR5 |
| `PAD_CKN` | U5 | BANKR5 |
| `PAD_CKE` | R1 | BANKR5 |
| `PAD_CS` | N4 | BANKR5 |
| `PAD_RAS` | P6 | BANKR5 |
| `PAD_CAS` | T7 | BANKR5 |
| `PAD_WE` | T8 | BANKR5 |
| `PAD_ODT` | H2 | BANKR5 |
| `PAD_RESET` | H1 | BANKR5 |
| `PAD_DM0` | K8 | BANKR4 |
| `PAD_DM1` | H9 | BANKR4 |
| `PAD_DM2` | E5 | BANKR4 |
| `PAD_DM3` | G1 | BANKR4 |
| `PAD_DM4` | L14 | BANKL4 |
| `PAD_DM5` | J19 | BANKL4 |
| `PAD_DM6` | H21 | BANKL4 |
| `PAD_DM7` | F25 | BANKL4 |
| `PAD_DM8` | P18 | BANKL5 |
| `PAD_DQS0` | H4 | BANKR4 |
| `PAD_DQS1` | G7 | BANKR4 |
| `PAD_DQS2` | A5 | BANKR4 |
| `PAD_DQS3` | B1 | BANKR4 |
| `PAD_DQS4` | K16 | BANKL4 |
| `PAD_DQS5` | K20 | BANKL4 |
| `PAD_DQS6` | G22 | BANKL4 |
| `PAD_DQS7` | E26 | BANKL4 |
| `PAD_DQS8` | P15 | BANKL5 |
| `PAD_DQSN0` | J4 | BANKR4 |
| `PAD_DQSN1` | H7 | BANKR4 |
| `PAD_DQSN2` | B5 | BANKR4 |
| `PAD_DQSN3` | C1 | BANKR4 |
| `PAD_DQSN4` | K17 | BANKL4 |
| `PAD_DQSN5` | J20 | BANKL4 |
| `PAD_DQSN6` | F22 | BANKL4 |
| `PAD_DQSN7` | D26 | BANKL4 |
| `PAD_DQSN8` | P16 | BANKL5 |
| `PAD_DQ0` | F4 | BANKR4 |
| `PAD_DQ1` | F5 | BANKR4 |
| `PAD_DQ2` | G4 | BANKR4 |
| `PAD_DQ3` | G5 | BANKR4 |
| `PAD_DQ4` | J5 | BANKR4 |
| `PAD_DQ5` | J6 | BANKR4 |
| `PAD_DQ6` | K6 | BANKR4 |
| `PAD_DQ7` | K7 | BANKR4 |
| `PAD_DQ8` | E6 | BANKR4 |
| `PAD_DQ9` | F7 | BANKR4 |
| `PAD_DQ10` | F8 | BANKR4 |
| `PAD_DQ11` | G6 | BANKR4 |
| `PAD_DQ12` | G9 | BANKR4 |
| `PAD_DQ13` | H6 | BANKR4 |
| `PAD_DQ14` | G9 | BANKR4 |
| `PAD_DQ15` | H6 | BANKR4 |
| `PAD_DQ16` | A4 | BANKR4 |
| `PAD_DQ17` | B5 | BANKR4 |
| `PAD_DQ18` | B4 | BANKR4 |
| `PAD_DQ19` | C4 | BANKR4 |
| `PAD_DQ20` | D3 | BANKR4 |
| `PAD_DQ21` | D4 | BANKR4 |
| `PAD_DQ22` | D5 | BANKR4 |
| `PAD_DQ23` | E3 | BANKR4 |
| `PAD_DQ24` | A2 | BANKR4 |
| `PAD_DQ25` | A3 | BANKR4 |
| `PAD_DQ26` | C1 | BANKR4 |
| `PAD_DQ27` | B2 | BANKR4 |
| `PAD_DQ28` | D1 | BANKR4 |
| `PAD_DQ29` | E1 | BANKR4 |
| `PAD_DQ30` | E2 | BANKR4 |
| `PAD_DQ31` | F2 | BANKR4 |
| `PAD_DQ32` | L15 | BANKL4 |
| `PAD_DQ33` | J15 | BANKL4 |
| `PAD_DQ34` | M15 | BANKL4 |
| `PAD_DQ35` | J14 | BANKL4 |
| `PAD_DQ36` | M16 | BANKL4 |
| `PAD_DQ37` | J16 | BANKL4 |
| `PAD_DQ38` | M14 | BANKL4 |
| `PAD_DQ39` | K15 | BANKL4 |
| `PAD_DQ40` | H18 | BANKL4 |
| `PAD_DQ41` | K21 | BANKL4 |
| `PAD_DQ42` | G20 | BANKL4 |
| `PAD_DQ43` | L18 | BANKL4 |
| `PAD_DQ44` | H19 | BANKL4 |
| `PAD_DQ45` | L17 | BANKL4 |
| `PAD_DQ46` | G21 | BANKL4 |
| `PAD_DQ47` | J18 | BANKL4 |
| `PAD_DQ48` | H23 | BANKL4 |
| `PAD_DQ49` | H22 | BANKL4 |
| `PAD_DQ50` | J23 | BANKL4 |
| `PAD_DQ51` | E23 | BANKL4 |
| `PAD_DQ52` | K23 | BANKL4 |
| `PAD_DQ53` | F23 | BANKL4 |
| `PAD_DQ54` | J24 | BANKL4 |
| `PAD_DQ55` | H24 | BANKL4 |
| `PAD_DQ56` | E25 | BANKL4 |
| `PAD_DQ57` | G26 | BANKL4 |
| `PAD_DQ58` | G25 | BANKL4 |
| `PAD_DQ59` | J25 | BANKL4 |
| `PAD_DQ60` | D25 | BANKL4 |
| `PAD_DQ61` | J26 | BANKL4 |
| `PAD_DQ62` | G24 | BANKL4 |
| `PAD_DQ63` | H26 | BANKL4 |
| `PAD_DQ64` | R14 | BANKL5 |
| `PAD_DQ65` | R15 | BANKL5 |
| `PAD_DQ66` | P14 | BANKL5 |
| `PAD_DQ67` | N14 | BANKL5 |
| `PAD_DQ68` | N16 | BANKL5 |
| `PAD_DQ69` | N17 | BANKL5 |
| `PAD_DQ70` | R16 | BANKL5 |
| `PAD_DQ71` | R17 | BANKL5 |

---

## 8. 其它板级接口

### 8.1 以太网 RGMII（RTL8211F）

主表来自 `_fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc`（2025-02-18 备份，18 个信号），与主文件 `ethernet_test.fdc` 的 mdio/mdc/led 一致：

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `rgmii_txd[3]` | D21 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_17N | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_txd[2]` | C21 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_15P | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_txd[1]` | B21 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_15N | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_txd[0]` | E20 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_13P_GSCLK | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_tx_ctl` | D20 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G2_13N_GSCLK | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_txc` | G16 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G0_05N_VREF | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_rxd[3]` | B19 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G1_09P | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_rxd[2]` | A19 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G1_09N | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_rxd[1]` | E16 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G1_07P | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_rxd[0]` | D16 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G1_07N | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_rx_ctl` | H16 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G0_05P | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `rgmii_rxc` | D19 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G2_12P_GMCLK | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |  |
| `mdio` | E21 | LVCMOS33 / 3.3 V | INOUT | BANKL3 | DIFFIO_L3_G2_17P | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc | MDIO（INOUT） |
| `mdc` | A25 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G3_19N | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc | MDC |
| `phy_rstn` | G25 | LVCMOS33 / 3.3 V | OUTPUT | BANKL4 | DIFFIO_L4_G3_22P_BFOE_N | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc | PHY 复位，与 HDMI 工程的 rstn_out 同脚 |
| `sys_clk` | D18 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G1_11P_GMCLK | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc | = D18 |
| `sys_rst_n` | C22 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc | = C22 |

`2_11_ethernet_test` 是另一套 RGMII：`rgmii_txd[3:0] = D21 / C21 / B21 / E20`、`rgmii_rxd[3:0] = B19 / A19 / E16 / D16`、`rgmii_tx_ctl = D20`、`rgmii_txc = G16`、`rgmii_rx_ctl = H16`、`rgmii_rxc = D19`、`phy_rstn = G25`。其中 **txd[1]=B21、txd[0]=E20、rx_ctl=H16、rxc=D19** 与上表不一致，两套不能混用。来源：`_fdcscan/2_11_ethernet_test/2_11_ethernet_test/2_11_ethernet_test/ethernet_test.fdc`。

`4_13` 的旧备份 `.../constraint_backup/ethernet_test_2023_09_05_11_11_54.fdc` 里还有**三组** RGMII（端口 1/2/3，如 `rgmii_txd_1[3:0] = A18 / C18 / D17 / F17`、`rgmii_txd_2[3:0] = C22 / E20 / E22 / F21`、`rgmii_rxc_2 = M19`），属多网口实验遗留，与单口底板不符，仅作参考。

### 8.2 SFP / HSST 高速收发

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `sfp_disable[0]` | F17 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G0_01N | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | SFP0 关断控制 |
| `sfp_disable[1]` | F15 | LVCMOS33 / 3.3 V | OUTPUT | BANKL3 | DIFFIO_L3_G0_03N | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | SFP1 关断控制 |
| `i_p_refckp_1` | AA11 | 未找到 | INPUT | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | HSST 参考时钟（该工程把 refck_1 放到 AA11） |
| `i_p_refckn_1` | AB11 | 未找到 | INPUT | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc | 同上（AB11） |
| `i_p_refckp_0` | AA11 | 未找到 | INPUT | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/ipcore/hsst_test/pnr/example_design/pango_hsstlp_top.fdc | HSST PLL0 参考时钟 P |
| `i_p_refckn_0` | AB11 | 未找到 | INPUT | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/ipcore/hsst_test/pnr/example_design/pango_hsstlp_top.fdc | HSST PLL0 参考时钟 N |
| `i_p_refckp_1` | AA13 | 未找到 | INPUT | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/ipcore/hsst_test/pnr/example_design/pango_hsstlp_top.fdc | HSST PLL1 参考时钟 P |
| `i_p_refckn_1` | AB13 | 未找到 | INPUT | — | — | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/ipcore/hsst_test/pnr/example_design/pango_hsstlp_top.fdc | HSST PLL1 参考时钟 N |

HSST 的 **TX/RX 差分数据引脚没有出现在任何 `.fdc`**（IP 用 `i:U_INST.U_GTP_HSSTLP_WRAPPER.CHANNEL0..3_ENABLE.U_GTP_HSSTLP_LANE0..3` 这种实例级约束自动分配，见 `_fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/ipcore/hsst_test/pnr/example_design/pango_hsstlp_top.fdc`），故 **SFP 的 TX/RX 差分对引脚号：未找到**。

### 8.3 PCIe（x4）

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `ref_clk_p` | F11 | LVCMOS33 / 3.3 V | Input | — | — | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | 100 MHz 差分参考 P |
| `ref_clk_n` | E11 | LVCMOS33 / 3.3 V | Input | — | — | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | 100 MHz 差分参考 N |
| `perst_n` | G24 | LVCMOS33 / 3.3 V | Input | BANKL4 | DIFFIO_L4_G3_18P_A22 | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | PERST# 输入 |
| `button_rst_n` | C22 | LVCMOS33 / 3.3 V | Input | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | = C22 |
| `txd` | C24 | LVCMOS33 / 3.3 V | Output | BANKL3 | DIFFIO_L3_G3_22P | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | = C24（UART） |
| `rxd` | B24 | LVCMOS33 / 3.3 V | Input | BANKL3 | DIFFIO_L3_G3_22N | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | = B24（UART） |
| `pclk_led` | A20 | LVCMOS33 / 3.3 V | Output | BANKL3 | DIFFIO_L3_G2_14N_DQS | _fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc | = A20 |

PCIe 的 4 条 lane 差分对同样只有实例级约束（`i:u_ips2l_pcie_wrap...GTP_HSST_4LANE_TOP...`），**lane 引脚号：未找到**。

### 8.4 LVDS / FMC 扩展口

来自 `_fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc`（LVDS25 差分）：

| 信号 (port) | FPGA 引脚 | IO 标准 / VCCIO | 方向 | BANK | 引脚专用功能名 (PnR) | 来源文件 | 备注 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `tx_data_p[3]` | V19 | LVDS25 / 2.5 V | OUTPUT | BANKL6 | DIFFIO_L6_G2_17P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_data_n[3]` | W19 | LVDS25 / 2.5 V | OUTPUT | BANKL6 | DIFFIO_L6_G2_17N | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_data_p[2]` | V18 | LVDS25 / 2.5 V | OUTPUT | BANKL6 | DIFFIO_L6_G3_18P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_data_n[2]` | W18 | LVDS25 / 2.5 V | OUTPUT | BANKL6 | DIFFIO_L6_G3_18N_VREF | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_data_p[1]` | V16 | LVDS25 / 2.5 V | OUTPUT | BANKL6 | DIFFIO_L6_G3_23P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_data_n[1]` | V17 | LVDS25 / 2.5 V | OUTPUT | BANKL6 | DIFFIO_L6_G3_23N | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_data_p[0]` | T14 | LVDS25 / 2.5 V | Output | BANKL6 | DIFFIO_L6_G3_19P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_data_n[0]` | T15 | LVDS25 / 2.5 V | Output | BANKL6 | DIFFIO_L6_G3_19N | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_data_p[3]` | AB24 | LVDS25 / 2.5 V | INPUT | BANKL6 | DIFFIO_L6_G1_08P_DQS | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_data_n[3]` | AC24 | LVDS25 / 2.5 V | INPUT | BANKL6 | DIFFIO_L6_G1_08N_DQS | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_data_p[2]` | V23 | LVDS25 / 2.5 V | INPUT | BANKL6 | DIFFIO_L6_G1_09P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_data_n[2]` | W23 | LVDS25 / 2.5 V | INPUT | BANKL6 | DIFFIO_L6_G1_09N | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_data_p[1]` | W20 | LVDS25 / 2.5 V | INPUT | BANKL6 | DIFFIO_L6_G2_15P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_data_n[1]` | Y20 | LVDS25 / 2.5 V | INPUT | BANKL6 | DIFFIO_L6_G2_15N | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_data_p[0]` | AA24 | LVDS25 / 2.5 V | Input | BANKL6 | DIFFIO_L6_G1_06P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_data_n[0]` | AB25 | LVDS25 / 2.5 V | Input | BANKL6 | DIFFIO_L6_G1_06N | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_clk_p` | T20 | LVDS25 / 2.5 V | Output | BANKL6 | DIFFIO_L6_G2_14P_DQS | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `tx_clk_n` | U20 | LVDS25 / 2.5 V | Output | BANKL6 | DIFFIO_L6_G2_14N_DQS | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_clk_p` | W21 | LVDS25 / 2.5 V | Input | BANKL6 | DIFFIO_L6_G2_13P_GSCLK | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `rx_clk_n` | Y21 | LVDS25 / 2.5 V | Input | BANKL6 | DIFFIO_L6_G2_13N_GSCLK | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc |  |
| `ref_clk` | D18 | LVCMOS33 / 3.3 V | Input | BANKL3 | DIFFIO_L3_G1_11P_GMCLK | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc | = D18 |
| `rstn_in` | C22 | LVCMOS33 / 3.3 V | Input | BANKL3 | DIFFIO_L3_G3_18P | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc | = C22 |
| `dbg_key_oper` | C23 | LVCMOS33 / 3.3 V | INPUT | BANKL3 | DIFFIO_L3_G3_18N_VREF | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc | = C23 |
| `err_flag` | A20 | LVCMOS33 / 3.3 V | Output | BANKL3 | DIFFIO_L3_G2_14N_DQS | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc | = A20 |

⚠ **`rx_data_p[0] / rx_data_n[0]` 两版不一致**：主文件 `lvds_rx_tx.fdc` 是 `AB25 / AB24`，备份 `lvds_rx_tx_2025_02_05_11_37_18.fdc` 是 `T19 / U19`。TX 侧两版相同。

### 8.5 ADC

- `4_7_adc_top` 用 Pango 片内 ADC（`ipcore/adc_test`）。顶层约束 `_fdcscan/4_7_adc_top/4_7_adc_top/4_7_adc_top/adc_top/pnr/adc_test.fdc` 只有 `led=A20 / clk_in=D18 / rst_n=C22 / cfg_uart_txd=C24 / cfg_uart_rxd=B24`，**没有 ADC 模拟或外部引脚**（模拟通道在片内）。
- IP 自带 example design `.../ipcore/adc_test/pnr/example_design/ipmxe_adc_top.fdc` 里有 `apb_clk=D19 / rst_n=D24 / cfg_uart_txd=D3 / cfg_uart_rxd=C3 / adc_loadsc_n=D23 / adc_clk_out=E20`，但都是 IP 自动布局的**模板引脚**（D19/E20 在其它工程里分别是 `rgmii_rxc` / `rgmii_txd[0]`），**未采信**。

### 8.6 EEPROM / I2C / SD 卡

- **EEPROM**：板上有 EEPROM（`4_IC_datasheet/EEPROM/` 下有 `AT24C01C-AT24C02C-…pdf`、`iic_timing.pdf`、`IIC状态机.pdf`、`24xx02_Verilog_Model/*.v`），但**没有任何 `.fdc` 约束过 EEPROM 的 I2C 引脚** → 引脚 **未找到**。
- **SD / TF 卡**：全库 `.fdc` 无任何 `sd_* / tf_* / sdcard` 信号 → **未找到**。
- **I2C**：唯一有约束的 I2C 是 HDMI 的 K22/K23（见第 6 章）。

---

## 9. 约束文件语法示例（可直接使用的 `.fdc` 片段）

Pango PDS 的引脚约束由 `define_attribute` 三元组构成：`{p:端口名} {属性} {值}`。下面片段使用的引脚全部来自本表实测证据。

```tcl
# ===== board_pinmap_min.fdc — 盘古200Pro+ / PG2L200H-6IFBB676 =====
# 端口名请与自己的 top 模块一致（示例用 clk / rstn / key / uart_tx / uart_rx / led[7:0]）

# ---------- 系统时钟（默认按 27 MHz；若确认是 50 MHz 见文末 clock 约束） ----------
define_attribute {p:clk} {PAP_IO_DIRECTION} {INPUT}
define_attribute {p:clk} {PAP_IO_LOC}       {D18}
define_attribute {p:clk} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:clk} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:clk} {PAP_IO_NONE}      {TRUE}

# ---------- 复位按键（低有效） ----------
define_attribute {p:rstn} {PAP_IO_DIRECTION} {INPUT}
define_attribute {p:rstn} {PAP_IO_LOC}       {C22}
define_attribute {p:rstn} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:rstn} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:rstn} {PAP_IO_NONE}      {TRUE}

# ---------- 用户按键 ----------
define_attribute {p:key}  {PAP_IO_DIRECTION} {INPUT}
define_attribute {p:key}  {PAP_IO_LOC}       {C23}
define_attribute {p:key}  {PAP_IO_VCCIO}     {3.3}
define_attribute {p:key}  {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:key}  {PAP_IO_NONE}      {TRUE}

# ---------- UART ----------
define_attribute {p:uart_tx} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:uart_tx} {PAP_IO_LOC}       {C24}
define_attribute {p:uart_tx} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:uart_tx} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:uart_tx} {PAP_IO_DRIVE}     {8}
define_attribute {p:uart_tx} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:uart_tx} {PAP_IO_NONE}      {TRUE}

define_attribute {p:uart_rx} {PAP_IO_DIRECTION} {INPUT}
define_attribute {p:uart_rx} {PAP_IO_LOC}       {B24}
define_attribute {p:uart_rx} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:uart_rx} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:uart_rx} {PAP_IO_NONE}      {TRUE}

# ---------- 8 位 LED（led[0]=A20 … led[7]=B17） ----------
define_attribute {p:led[0]} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:led[0]} {PAP_IO_LOC}       {A20}
define_attribute {p:led[0]} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:led[0]} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:led[0]} {PAP_IO_DRIVE}     {8}
define_attribute {p:led[0]} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:led[0]} {PAP_IO_NONE}      {TRUE}

define_attribute {p:led[1]} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:led[1]} {PAP_IO_LOC}       {C18}
define_attribute {p:led[1]} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:led[1]} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:led[1]} {PAP_IO_DRIVE}     {8}
define_attribute {p:led[1]} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:led[1]} {PAP_IO_NONE}      {TRUE}

define_attribute {p:led[2]} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:led[2]} {PAP_IO_LOC}       {C19}
define_attribute {p:led[2]} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:led[2]} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:led[2]} {PAP_IO_DRIVE}     {8}
define_attribute {p:led[2]} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:led[2]} {PAP_IO_NONE}      {TRUE}

define_attribute {p:led[3]} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:led[3]} {PAP_IO_LOC}       {E18}
define_attribute {p:led[3]} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:led[3]} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:led[3]} {PAP_IO_DRIVE}     {8}
define_attribute {p:led[3]} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:led[3]} {PAP_IO_NONE}      {TRUE}

define_attribute {p:led[4]} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:led[4]} {PAP_IO_LOC}       {A17}
define_attribute {p:led[4]} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:led[4]} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:led[4]} {PAP_IO_DRIVE}     {8}
define_attribute {p:led[4]} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:led[4]} {PAP_IO_NONE}      {TRUE}

define_attribute {p:led[5]} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:led[5]} {PAP_IO_LOC}       {A18}
define_attribute {p:led[5]} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:led[5]} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:led[5]} {PAP_IO_DRIVE}     {8}
define_attribute {p:led[5]} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:led[5]} {PAP_IO_NONE}      {TRUE}

define_attribute {p:led[6]} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:led[6]} {PAP_IO_LOC}       {C17}
define_attribute {p:led[6]} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:led[6]} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:led[6]} {PAP_IO_DRIVE}     {8}
define_attribute {p:led[6]} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:led[6]} {PAP_IO_NONE}      {TRUE}

define_attribute {p:led[7]} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:led[7]} {PAP_IO_LOC}       {B17}
define_attribute {p:led[7]} {PAP_IO_VCCIO}     {3.3}
define_attribute {p:led[7]} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:led[7]} {PAP_IO_DRIVE}     {8}
define_attribute {p:led[7]} {PAP_IO_SLEW}      {SLOW}
define_attribute {p:led[7]} {PAP_IO_NONE}      {TRUE}

# ---------- 时钟约束（.fdc 里可直接写 SDC） ----------
create_clock -name {clk} [get_ports {clk}] -period {37.000} -waveform {0.000 18.500}   # 27 MHz
# 若确认板上是 50 MHz，改成：create_clock -name {clk} [get_ports {clk}] -period {20.000} -waveform {0.000 10.000}
```

**DDR3 参考时钟（125 MHz 差分）写法**（IO 标准二选一，见 1.2 的 ⚠）：

```tcl
define_attribute {p:ref_clk_p} {PAP_IO_DIRECTION} {INPUT}
define_attribute {p:ref_clk_p} {PAP_IO_LOC}       {N3}
define_attribute {p:ref_clk_p} {PAP_IO_VCCIO}     {1.5}
define_attribute {p:ref_clk_p} {PAP_IO_STANDARD}  {HSTL15D_I}   # 2_9_ddr3_test 用的是 SSTL15D_I
define_attribute {p:ref_clk_n} {PAP_IO_DIRECTION} {INPUT}
define_attribute {p:ref_clk_n} {PAP_IO_LOC}       {N2}
define_attribute {p:ref_clk_n} {PAP_IO_VCCIO}     {1.5}
define_attribute {p:ref_clk_n} {PAP_IO_STANDARD}  {HSTL15D_I}
create_clock -name {ref_clk} [get_ports {ref_clk_p}] -period {8.0} -waveform {0 4.0}
```

**QSPI 配置 Flash（仅在用户态访问 Flash 时写；属专用配置脚，配置完成后被释放给用户）**

```tcl
# 依据 9_远程升级 例程 + PnR 球位名（P18=FCS_N、R14=MOSI_D0、R15=MISO_D1_DI）
define_attribute {p:spi_cs}  {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:spi_cs}  {PAP_IO_LOC}       {P18}
define_attribute {p:spi_cs}  {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:spi_cs}  {PAP_IO_VCCIO}     {3.3}

define_attribute {p:spi_dq0} {PAP_IO_DIRECTION} {OUTPUT}
define_attribute {p:spi_dq0} {PAP_IO_LOC}       {R14}
define_attribute {p:spi_dq0} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:spi_dq0} {PAP_IO_VCCIO}     {3.3}

define_attribute {p:spi_dq1} {PAP_IO_DIRECTION} {INPUT}
define_attribute {p:spi_dq1} {PAP_IO_LOC}       {R15}
define_attribute {p:spi_dq1} {PAP_IO_STANDARD}  {LVCMOS33}
define_attribute {p:spi_dq1} {PAP_IO_VCCIO}     {3.3}

# spi_clk 引脚：未找到 —— 若你的板子把 CCLK 接到了普通 IO，请自行补一条 PAP_IO_LOC
```

---

## 10. 冲突与“未找到”清单

### 10.1 工程之间互相矛盾的引脚

| 引脚 | 矛盾内容 | 来源文件 |
| :-- | :-- | :-- |
| D18 | 时钟频率：27 MHz（`-period 37` / `CLKIN_FREQ 27` / `clk_27M`） vs 50 MHz（`-period 20` / 注释 `50Mhz`） | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc ; _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc ; 7_FMC扩展子卡及Demo/2_Demo/ADDA_HDMI Demo/ad9280_ad9708_HDMI/ad9280_ad9708_HDMI.fdc |
| N3 / N2 | IO 标准：`HSTL15D_I`（11 个 HDMI 工程） vs `SSTL15D_I`（2_9_ddr3_test） | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc ; _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc |
| D19 | 以太网 `rgmii_rxc`（输入，PHY 驱动） vs `lock_led`（输出 LED） | _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc ; _fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc |
| B20 | `rgmii_txd[1]`（输出） vs `rstn`（输入） | _fdcscan/2_11_ethernet_test/2_11_ethernet_test/2_11_ethernet_test/ethernet_test.fdc ; _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc |
| P20 | `b_out[2]`（HDMI 数据） vs `clk_50m`（旧备份里的 50 MHz 时钟输入） | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc ; _fdcscan/4_13_tri_eth_test/.../constraint_backup/ethernet_test_2023_09_05_11_11_54.fdc |
| G25 | `rstn_out`（HDMI 复位输出） vs `phy_rstn`（以太网 PHY 复位）—— 同一网络两种叫法 | _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc ; _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |
| B21 / E20 / H16 / D19 | `2_11_ethernet_test` 与 `4_13_tri_eth_test` 两套 RGMII 不一致 | _fdcscan/2_11_ethernet_test/2_11_ethernet_test/2_11_ethernet_test/ethernet_test.fdc ; _fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc |
| AB25 / AB24 vs T19 / U19 | `rx_data_p[0] / rx_data_n[0]` LVDS 接收对两版不一致 | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc ; _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/constraint_backup/lvds_rx_tx_2025_02_05_11_37_18.fdc |
| R14 vs P22 | `spi_dq0` 在同一文件里被定义两次（第 73 行 P22、第 207 行 R14），PnR 最终取 R14 | 9_远程升级/FPGA_remote_update/pg2l100h_remote_update/remote_update_golden/prj/pg2l100h_remote_updata.fdc |
| M21 / L21 vs K22 / K23 | `iic_*`：OV5640 摄像头 I2C（FMC 子卡） vs 板载 HDMI I2C | 7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/constraint_backup/HDMI_DDR3_OV5640_test_2024_05_16_21_30_53.fdc ; _fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc |
| AA11 / AB11 vs AA13 / AB13 | HSST 参考时钟对：`4_14` 把 refck_1 放 AA11/AB11，另有工程用 AA13/AB13 | _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc ; _fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/ipcore/hsst_test/pnr/example_design/pango_hsstlp_top.fdc |
| rx_data_p/n 全部 | `rx_clk` 频率 25 MHz（`-period 40`）vs 50 MHz（`-period 20`，备份） | _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc ; _fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/constraint_backup/lvds_rx_tx_2025_02_05_11_37_18.fdc |
| 整张 DDR3 表 | 8 个 DQ 位 + 全部 DQS/DM 落位有两套（见 7.3） | _fdcscan/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc ; 7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/ipcore/ddr3_test/pnr/ddr_test.fdc |
| 整张 DDR3 表（第三、四套） | `DDR3_50H`（PGL50H/FBG484）、`ddr3_100h`（PG2L100H/FBG484）是完全不同的球位，不属本板 | 7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/source/rtl/DDR3_50H/pnr/ddr_test.fdc ; 7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/ipcore/ddr3_100h/pnr/ddr_test.fdc |

### 10.2 未找到

| 项目 | 说明 |
| :-- | :-- |
| ****QSPI 配置 Flash 的 CLK（CCLK）**** | 唯一一次赋值 U6 被注释且与 DDR3 `mem_ck` 冲突；PnR 球位表 BANKL5 无 CCLK 命名脚 |
| ****QSPI Flash 型号 / 容量 / 位宽**** | 无 Flash 数据手册、无丝印文本；“2 颗 128 Mb”仅来自任务描述 |
| ****HDMI TX 的 TMDS 时钟/数据差分对**** | 由片外 MS7210 产生，FPGA 侧不存在 |
| ****HDMI TX 的 HPD（热插拔）输入**** | 全部 `.fdc` 无 hpd / hotplug 端口 |
| ****HDMI 用 OSERDES 的参数（25 MHz / 720p / 1080p）**** | HDMI 通路无 OSERDES；只有 DDR3 PHY 的 `GTP_OSERDES_E2`（`HMSDR8TO1`） |
| ****720p / 1080p 显式像素时钟约束**** | 仅 PLL 点频 148.5 MHz / 37.125 MHz 可参考，无 create_clock |
| ****SFP 的 TX/RX 高速差分对引脚**** | HSST IP 用实例级约束（`CHANNELx_ENABLE.U_GTP_HSSTLP_LANEx`），无 `PAP_IO_LOC` |
| ****PCIe x4 的 lane 差分对引脚**** | 同上，仅实例级约束 |
| ****EEPROM（AT24C02）的 I2C 引脚**** | 有器件手册，无引脚约束 |
| ****SD / TF 卡引脚**** | 全库无 `sd_*` / `tf_*` 信号 |
| ****除 DDR3 参考外的 100 MHz / 125 MHz 独立单端晶振**** | 未找到 |
| ****DDR3 两套映射的物理确认**** | 两套 `.fdc` 冲突，需实机核对 7.3 的差异位 |

---

## 11. 证据文件索引

| 文件（相对 qs 根目录） | 用途 |
| :-- | :-- |
| `test/1_LED/led_test.pds`、`test/3_UART/uart_test.pds` | PG2L200H / FBB676 器件确认 |
| `test/3_UART/impl.tcl`、`test/1_LED/impl.tcl` | `set_arch -device PG2L200H -package FBB676`；FBB484→FBB676 移植轨迹 |
| `test/1_LED/place_route/led_test_prr.prt` | **200H/FBB676 全球位专用功能名（本表 BANK / 功能名列来源）** |
| `test/1_LED/device_map/led_test.pcf` | 最终引脚属性（LOC / VCCIO / IOSTANDARD） |
| `test/1_LED/source/led_test.fdc` | D18 / C22 / LED[7:0] |
| `_fdcscan/2_7_key_led_test/.../source/key_led_test.fdc` | C23 用户按键 |
| `_fdcscan/2_8_uart_test/2_8_uart_test/2_8_uart_test/uart_test.fdc` | C24 / B24 |
| `_fdcscan/2_9_ddr3_test/.../ipcore/ddr3_test/pnr/ddr_test.fdc` | **DDR3 权威引脚表 + ref_clk_p/n + 125 MHz** |
| `_scan2/2_9_ddr3_test/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/ddr3_test.idf` | **DDR3 器件 / 位宽 / `PAD_*` 清单** |
| `_scan2/2_9_ddr3_test/.../place_route/test_ddr_prr.prt` | DDR3 球位交叉验证（与 200H 报告一致） |
| `_fdcscan/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/5_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT_top.fdc` | HDMI IN/OUT + DDR3 + LED 综合约束（11 个工程 MD5 相同） |
| `_fdcscan/2_10_hdmi_loop/2_10_hdmi_loop/2_10_hdmi_loop/hdmi_loop.fdc` | HDMI 24 位 RGB + 同步 + I2C |
| `_fdcscan/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/4_6_hdmi_dyn_ppll/hdmi_dyn_ppll.fdc` | 另一套 HDMI 位序 + 动态 PPLL |
| `_fdcscan/4_14_hdmi_in_sfp_hdmi_out/4_14_hdmi_in_sfp_hdmi_out/hdmi_in_sfp_hdmi_out.fdc` | SFP 控制 + HSST 参考时钟 + HDMI 24 位打包 |
| `_fdcscan/4_13_tri_eth_test/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/constraint_backup/ethernet_test_2025_02_18_16_02_20.fdc` | RGMII 主表 |
| `_fdcscan/4_11_lvds_test/4_11_lvds_test/4_11_lvds_test/lvds_test/lvds_test/pnr/lvds_rx_tx.fdc` | LVDS / FMC 扩展口 |
| `_fdcscan/4_15_PCIE_DMA/4_15_PCIE_DMA/pnr/pango_pcie_top.fdc` | PCIe 参考时钟 / PERST# |
| `9_远程升级/FPGA_remote_update/pg2l100h_remote_update/remote_update_golden/prj/pg2l100h_remote_updata.fdc` | 配置 Flash 引脚（唯一证据） |
| `9_远程升级/.../prj/device_map/remote_updata_top.pcf` | SPI 引脚最终值 |
| `9_远程升级/.../place_route/remote_updata_golden_top_prr.prt` | `MOSI_D0` / `FCS_N` / `MISO_D1_DI` 专用名 |
| `7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/source/rtl/ms72xx_ctl.v` | MS7200/MS7210 共用 I2C、`init_over_rx` 语义、设备地址 |
| `7_FMC扩展子卡及Demo/2_Demo/HDMI_DDR3_OV5640_100H/source/rtl/hdmi_ddr_ov5640_top.v` | `rstn_out` 10 ms 复位、`hdmi_int_led` 注释 |
| `7_FMC扩展子卡及Demo/2_Demo/ADDA_HDMI Demo/ad9280_ad9708_HDMI/ad9280_ad9708_HDMI.fdc` | `clk_27M = D18` 直接命名证据 |
| `7_FMC扩展子卡及Demo/2_Demo/ADDA_HDMI Demo/.../ipcore/pll/pll.idf` | 148.5 MHz 像素时钟点频 |
| `D:/PDS_2022.2-SP6.4/arch/vendor/pango/logos2/pg2l200h/data/config/ini_data/Logos2-PG2L200H.ini` | `persist_pin` / `spi_data_width`（PDS 安装目录，非 qs 内） |
| `D:/PDS_2022.2-SP6.4/arch/vendor/pango/logos2/pg2l200h/script/base.tcl` | `package/FBB676/FBB676.eval`，确认 200H 无 FBG676 |

---

## 附录 A：PG2L200H-FBB676 全 400 球 BANK / 专用功能名对照

来源：`test/1_LED/place_route/led_test_prr.prt`（PG2L200H-6FBB676 实际布局布线报告）。该表与 `_scan2/2_9_ddr3_test/.../test_ddr_prr.prt`（PG2L100H-6FBG676）共有的 300 个球功能名**完全一致**，可互为佐证。

### BANKL3（50 球）

| 球位 | IOBD / IOBS 索引 | 专用功能名 |
| :-- | :-- | :-- |
| `A17` | IOBD_0_1422 | `DIFFIO_L3_G1_08P_DQS` |
| `A18` | IOBS_0_1416 | `DIFFIO_L3_G1_08N_DQS` |
| `A19` | IOBS_0_1404 | `DIFFIO_L3_G1_09N` |
| `A20` | IOBS_0_1338 | `DIFFIO_L3_G2_14N_DQS` |
| `A22` | IOBS_0_1314 | `DIFFIO_L3_G2_16N` |
| `A23` | IOBD_0_1272 | `DIFFIO_L3_G3_20P_DQS` |
| `A24` | IOBS_0_1266 | `DIFFIO_L3_G3_20N_DQS` |
| `A25` | IOBS_0_1278 | `DIFFIO_L3_G3_19N` |
| `B17` | IOBS_0_1440 | `DIFFIO_L3_G1_06N` |
| `B19` | IOBD_0_1410 | `DIFFIO_L3_G1_09P` |
| `B20` | IOBD_0_1344 | `DIFFIO_L3_G2_14P_DQS` |
| `B21` | IOBS_0_1326 | `DIFFIO_L3_G2_15N` |
| `B22` | IOBD_0_1320 | `DIFFIO_L3_G2_16P` |
| `B24` | IOBS_0_1242 | `DIFFIO_L3_G3_22N` |
| `B25` | IOBD_0_1284 | `DIFFIO_L3_G3_19P` |
| `B26` | IOBS_0_1254 | `DIFFIO_L3_G3_21N` |
| `C17` | IOBD_0_1446 | `DIFFIO_L3_G1_06P` |
| `C18` | IOBS_0_1380 | `DIFFIO_L3_G1_11N_GMCLK` |
| `C19` | IOBS_0_1362 | `DIFFIO_L3_G2_12N_GMCLK` |
| `C21` | IOBD_0_1332 | `DIFFIO_L3_G2_15P` |
| `C22` | IOBD_0_1296 | `DIFFIO_L3_G3_18P` |
| `C23` | IOBS_0_1290 | `DIFFIO_L3_G3_18N_VREF` |
| `C24` | IOBD_0_1248 | `DIFFIO_L3_G3_22P` |
| `C26` | IOBD_0_1260 | `DIFFIO_L3_G3_21P` |
| `D16` | IOBS_0_1428 | `DIFFIO_L3_G1_07N` |
| `D18` | IOBD_0_1386 | `DIFFIO_L3_G1_11P_GMCLK` |
| `D19` | IOBD_0_1368 | `DIFFIO_L3_G2_12P_GMCLK` |
| `D20` | IOBS_0_1350 | `DIFFIO_L3_G2_13N_GSCLK` |
| `D21` | IOBS_0_1302 | `DIFFIO_L3_G2_17N` |
| `D23` | IOBD_0_1236 | `DIFFIO_L3_G3_23P` |
| `D24` | IOBS_0_1230 | `DIFFIO_L3_G3_23N` |
| `E16` | IOBD_0_1434 | `DIFFIO_L3_G1_07P` |
| `E17` | IOBD_0_1398 | `DIFFIO_L3_G1_10P_GSCLK` |
| `E18` | IOBS_0_1392 | `DIFFIO_L3_G1_10N_GSCLK` |
| `E20` | IOBD_0_1356 | `DIFFIO_L3_G2_13P_GSCLK` |
| `E21` | IOBD_0_1308 | `DIFFIO_L3_G2_17P` |
| `E22` | IOBS_0_1224 | `SIO_L3_01` |
| `F15` | IOBS_0_1476 | `DIFFIO_L3_G0_03N` |
| `F17` | IOBS_0_1500 | `DIFFIO_L3_G0_01N` |
| `F18` | IOBD_0_1494 | `DIFFIO_L3_G0_02P_DQS` |
| `F19` | IOBS_0_1488 | `DIFFIO_L3_G0_02N_DQS` |
| `F20` | IOBS_0_1464 | `DIFFIO_L3_G0_04N` |
| `G15` | IOBD_0_1482 | `DIFFIO_L3_G0_03P` |
| `G16` | IOBS_0_1452 | `DIFFIO_L3_G0_05N_VREF` |
| `G17` | IOBD_0_1506 | `DIFFIO_L3_G0_01P` |
| `G19` | IOBD_0_1470 | `DIFFIO_L3_G0_04P` |
| `H14` | IOBD_0_1518 | `DIFFIO_L3_G0_00P` |
| `H15` | IOBS_0_1512 | `DIFFIO_L3_G0_00N` |
| `H16` | IOBD_0_1458 | `DIFFIO_L3_G0_05P` |
| `H17` | IOBS_0_1524 | `SIO_L3_00` |

### BANKL4（50 球）

| 球位 | IOBD / IOBS 索引 | 专用功能名 |
| :-- | :-- | :-- |
| `D25` | IOBS_0_972 | `DIFFIO_L4_G3_19N_A19` |
| `D26` | IOBS_0_960 | `DIFFIO_L4_G3_20N_DQS_A18` |
| `E23` | IOBS_0_1008 | `DIFFIO_L4_G2_16N_A25` |
| `E25` | IOBD_0_978 | `DIFFIO_L4_G3_19P_A20` |
| `E26` | IOBD_0_966 | `DIFFIO_L4_G3_20P_DQS` |
| `F22` | IOBS_0_1032 | `DIFFIO_L4_G2_14N_DQS_BADRVO_N` |
| `F23` | IOBD_0_1014 | `DIFFIO_L4_G2_16P_A26` |
| `F24` | IOBS_0_984 | `DIFFIO_L4_G3_18N_VREF_A21` |
| `F25` | IOBS_0_936 | `DIFFIO_L4_G3_22N_BFWE_FCS2_N` |
| `G20` | IOBD_0_1092 | `DIFFIO_L4_G1_10P_GSCLK` |
| `G21` | IOBS_0_1086 | `DIFFIO_L4_G1_10N_GSCLK` |
| `G22` | IOBD_0_1038 | `DIFFIO_L4_G2_14P_DQS` |
| `G24` | IOBD_0_990 | `DIFFIO_L4_G3_18P_A22` |
| `G25` | IOBD_0_942 | `DIFFIO_L4_G3_22P_BFOE_N` |
| `G26` | IOBS_0_948 | `DIFFIO_L4_G3_21N_A16` |
| `H18` | IOBS_0_1098 | `DIFFIO_L4_G1_09N_VAA10N` |
| `H19` | IOBS_0_1134 | `DIFFIO_L4_G1_06N_VAA7N` |
| `H21` | IOBD_0_1062 | `DIFFIO_L4_G2_12P_GMCLK` |
| `H22` | IOBS_0_1056 | `DIFFIO_L4_G2_12N_GMCLK` |
| `H23` | IOBS_0_1044 | `DIFFIO_L4_G2_13N_GSCLK` |
| `H24` | IOBS_0_1020 | `DIFFIO_L4_G2_15N_A27` |
| `H26` | IOBD_0_954 | `DIFFIO_L4_G3_21P_A17` |
| `J14` | IOBD_0_1200 | `DIFFIO_L4_G0_01P_VAA2P` |
| `J15` | IOBS_0_1194 | `DIFFIO_L4_G0_01N_VAA2N` |
| `J16` | IOBS_0_1206 | `DIFFIO_L4_G0_00N_VAA1N` |
| `J18` | IOBD_0_1104 | `DIFFIO_L4_G1_09P_VAA10P` |
| `J19` | IOBD_0_1140 | `DIFFIO_L4_G1_06P_VAA7P` |
| `J20` | IOBS_0_1110 | `DIFFIO_L4_G1_08N_DQS_VAA9N` |
| `J21` | IOBS_0_1074 | `DIFFIO_L4_G1_11N_GMCLK` |
| `J23` | IOBD_0_1050 | `DIFFIO_L4_G2_13P_GSCLK` |
| `J24` | IOBD_0_1026 | `DIFFIO_L4_G2_15P_A28` |
| `J25` | IOBD_0_930 | `DIFFIO_L4_G3_23P_VS1` |
| `J26` | IOBS_0_924 | `DIFFIO_L4_G3_23N_VS0` |
| `K15` | IOBD_0_1212 | `DIFFIO_L4_G0_00P_VAA1P` |
| `K16` | IOBD_0_1188 | `DIFFIO_L4_G0_02P_DQS_VAA3P` |
| `K17` | IOBS_0_1182 | `DIFFIO_L4_G0_02N_DQS_VAA3N` |
| `K18` | IOBS_0_1218 | `SIO_L4_00` |
| `K20` | IOBD_0_1116 | `DIFFIO_L4_G1_08P_DQS_VAA9P` |
| `K21` | IOBD_0_1080 | `DIFFIO_L4_G1_11P_GMCLK` |
| `K22` | IOBD_0_1002 | `DIFFIO_L4_G2_17P_A24` |
| `K23` | IOBS_0_996 | `DIFFIO_L4_G2_17N_A23` |
| `L14` | IOBS_0_1170 | `DIFFIO_L4_G0_03N` |
| `L15` | IOBS_0_1158 | `DIFFIO_L4_G0_04N_VAA5N` |
| `L17` | IOBD_0_1128 | `DIFFIO_L4_G1_07P_VAA8P` |
| `L18` | IOBS_0_1122 | `DIFFIO_L4_G1_07N_VAA8N` |
| `L19` | IOBS_0_918 | `SIO_L4_01` |
| `M14` | IOBD_0_1176 | `DIFFIO_L4_G0_03P` |
| `M15` | IOBD_0_1164 | `DIFFIO_L4_G0_04P_VAA5P` |
| `M16` | IOBD_0_1152 | `DIFFIO_L4_G0_05P` |
| `M17` | IOBS_0_1146 | `DIFFIO_L4_G0_05N_VREF` |

### BANKL5（50 球）

| 球位 | IOBD / IOBS 索引 | 专用功能名 |
| :-- | :-- | :-- |
| `K25` | IOBD_0_834 | `DIFFIO_L5_G1_06P_D9` |
| `K26` | IOBS_0_828 | `DIFFIO_L5_G1_06N_D10` |
| `L20` | IOBS_0_816 | `DIFFIO_L5_G1_07N_D12` |
| `L22` | IOBD_0_786 | `DIFFIO_L5_G1_10P_GSCLK` |
| `L23` | IOBS_0_780 | `DIFFIO_L5_G1_10N_GSCLK` |
| `L24` | IOBD_0_810 | `DIFFIO_L5_G1_08P_DQS_N` |
| `L25` | IOBS_0_804 | `DIFFIO_L5_G1_08N_DQS_D13` |
| `M19` | IOBS_0_912 | `SIO_L5_00` |
| `M20` | IOBD_0_822 | `DIFFIO_L5_G1_07P_D11` |
| `M21` | IOBD_0_774 | `DIFFIO_L5_G1_11P_GMCLK` |
| `M22` | IOBS_0_768 | `DIFFIO_L5_G1_11N_GMCLK` |
| `M24` | IOBD_0_798 | `DIFFIO_L5_G1_09P_D14` |
| `M25` | IOBS_0_792 | `DIFFIO_L5_G1_09N_D15` |
| `M26` | IOBS_0_666 | `DIFFIO_L5_G3_19N_D23_A7` |
| `N14` | IOBS_0_888 | `DIFFIO_L5_G0_01N_D3` |
| `N16` | IOBD_0_870 | `DIFFIO_L5_G0_03P_D4` |
| `N17` | IOBS_0_864 | `DIFFIO_L5_G0_03N_D5` |
| `N18` | IOBS_0_840 | `DIFFIO_L5_G0_05N_VREF_D8` |
| `N19` | IOBS_0_714 | `DIFFIO_L5_G2_15N_D31_A15` |
| `N21` | IOBD_0_756 | `DIFFIO_L5_G2_12P_GMCLK` |
| `N22` | IOBS_0_750 | `DIFFIO_L5_G2_12N_GMCLK` |
| `N23` | IOBD_0_732 | `DIFFIO_L5_G2_14P_DQS_RWSEL` |
| `N24` | IOBS_0_726 | `DIFFIO_L5_G2_14N_DQS_CSO_DOUT` |
| `N26` | IOBD_0_672 | `DIFFIO_L5_G3_19P_D24_A8` |
| `P14` | IOBD_0_894 | `DIFFIO_L5_G0_01P_D2` |
| `P15` | IOBD_0_882 | `DIFFIO_L5_G0_02P_DQS_IO_STATUS_C` |
| `P16` | IOBS_0_876 | `DIFFIO_L5_G0_02N_DQS_ECCLKIN` |
| `P18` | IOBD_0_846 | `DIFFIO_L5_G0_05P_FCS_N` |
| `P19` | IOBD_0_720 | `DIFFIO_L5_G2_15P_CS_N` |
| `P20` | IOBD_0_744 | `DIFFIO_L5_G2_13P_GSCLK` |
| `P21` | IOBS_0_738 | `DIFFIO_L5_G2_13N_GSCLK` |
| `P23` | IOBD_0_708 | `DIFFIO_L5_G2_16P_D30_A14` |
| `P24` | IOBS_0_702 | `DIFFIO_L5_G2_16N_D29_A13` |
| `P25` | IOBS_0_678 | `DIFFIO_L5_G3_18N_VREF_D25_A9` |
| `P26` | IOBS_0_642 | `DIFFIO_L5_G3_21N_D20_A4` |
| `R14` | IOBD_0_906 | `DIFFIO_L5_G0_00P_MOSI_D0` |
| `R15` | IOBS_0_900 | `DIFFIO_L5_G0_00N_MISO_D1_DI` |
| `R16` | IOBD_0_858 | `DIFFIO_L5_G0_04P_D6` |
| `R17` | IOBS_0_852 | `DIFFIO_L5_G0_04N_D7` |
| `R18` | IOBS_0_612 | `SIO_L5_01` |
| `R20` | IOBD_0_696 | `DIFFIO_L5_G2_17P_D28_A12` |
| `R21` | IOBS_0_690 | `DIFFIO_L5_G2_17N_D27_A11` |
| `R22` | IOBS_0_630 | `DIFFIO_L5_G3_22N_D18_A2` |
| `R23` | IOBS_0_618 | `DIFFIO_L5_G3_23N_D16_A0` |
| `R25` | IOBD_0_684 | `DIFFIO_L5_G3_18P_D26_A10` |
| `R26` | IOBD_0_648 | `DIFFIO_L5_G3_21P_D21_A5` |
| `T22` | IOBD_0_636 | `DIFFIO_L5_G3_22P_D19_A3` |
| `T23` | IOBD_0_624 | `DIFFIO_L5_G3_23P_D17_A1` |
| `T24` | IOBD_0_660 | `DIFFIO_L5_G3_20P_DQS` |
| `T25` | IOBS_0_654 | `DIFFIO_L5_G3_20N_DQS_D22_A6` |

### BANKL6（50 球）

| 球位 | IOBD / IOBS 索引 | 专用功能名 |
| :-- | :-- | :-- |
| `AA22` | IOBD_0_516 | `DIFFIO_L6_G1_07P` |
| `AA23` | IOBS_0_510 | `DIFFIO_L6_G1_07N` |
| `AA24` | IOBD_0_528 | `DIFFIO_L6_G1_06P` |
| `AA25` | IOBS_0_546 | `DIFFIO_L6_G0_04N` |
| `AB24` | IOBD_0_504 | `DIFFIO_L6_G1_08P_DQS` |
| `AB25` | IOBS_0_522 | `DIFFIO_L6_G1_06N` |
| `AB26` | IOBD_0_576 | `DIFFIO_L6_G0_02P_DQS` |
| `AC24` | IOBS_0_498 | `DIFFIO_L6_G1_08N_DQS` |
| `AC26` | IOBS_0_570 | `DIFFIO_L6_G0_02N_DQS` |
| `T14` | IOBD_0_366 | `DIFFIO_L6_G3_19P` |
| `T15` | IOBS_0_360 | `DIFFIO_L6_G3_19N` |
| `T17` | IOBD_0_354 | `DIFFIO_L6_G3_20P_DQS` |
| `T18` | IOBS_0_348 | `DIFFIO_L6_G3_20N_DQS` |
| `T19` | IOBD_0_402 | `DIFFIO_L6_G2_16P` |
| `T20` | IOBD_0_426 | `DIFFIO_L6_G2_14P_DQS` |
| `U14` | IOBD_0_330 | `DIFFIO_L6_G3_22P` |
| `U15` | IOBD_0_342 | `DIFFIO_L6_G3_21P` |
| `U16` | IOBS_0_336 | `DIFFIO_L6_G3_21N` |
| `U17` | IOBS_0_306 | `SIO_L6_01` |
| `U19` | IOBS_0_396 | `DIFFIO_L6_G2_16N` |
| `U20` | IOBS_0_420 | `DIFFIO_L6_G2_14N_DQS` |
| `U21` | IOBD_0_450 | `DIFFIO_L6_G2_12P_GMCLK` |
| `U22` | IOBD_0_468 | `DIFFIO_L6_G1_11P_GMCLK` |
| `U24` | IOBS_0_606 | `SIO_L6_00` |
| `U25` | IOBD_0_600 | `DIFFIO_L6_G0_00P` |
| `U26` | IOBS_0_594 | `DIFFIO_L6_G0_00N` |
| `V14` | IOBS_0_324 | `DIFFIO_L6_G3_22N` |
| `V16` | IOBD_0_318 | `DIFFIO_L6_G3_23P` |
| `V17` | IOBS_0_312 | `DIFFIO_L6_G3_23N` |
| `V18` | IOBD_0_378 | `DIFFIO_L6_G3_18P` |
| `V19` | IOBD_0_390 | `DIFFIO_L6_G2_17P` |
| `V21` | IOBS_0_444 | `DIFFIO_L6_G2_12N_GMCLK` |
| `V22` | IOBS_0_462 | `DIFFIO_L6_G1_11N_GMCLK` |
| `V23` | IOBD_0_492 | `DIFFIO_L6_G1_09P` |
| `V24` | IOBD_0_540 | `DIFFIO_L6_G0_05P` |
| `V26` | IOBD_0_588 | `DIFFIO_L6_G0_01P` |
| `W18` | IOBS_0_372 | `DIFFIO_L6_G3_18N_VREF` |
| `W19` | IOBS_0_384 | `DIFFIO_L6_G2_17N` |
| `W20` | IOBD_0_414 | `DIFFIO_L6_G2_15P` |
| `W21` | IOBD_0_438 | `DIFFIO_L6_G2_13P_GSCLK` |
| `W23` | IOBS_0_486 | `DIFFIO_L6_G1_09N` |
| `W24` | IOBS_0_534 | `DIFFIO_L6_G0_05N_VREF` |
| `W25` | IOBD_0_564 | `DIFFIO_L6_G0_03P` |
| `W26` | IOBS_0_582 | `DIFFIO_L6_G0_01N` |
| `Y20` | IOBS_0_408 | `DIFFIO_L6_G2_15N` |
| `Y21` | IOBS_0_432 | `DIFFIO_L6_G2_13N_GSCLK` |
| `Y22` | IOBD_0_480 | `DIFFIO_L6_G1_10P_GSCLK` |
| `Y23` | IOBS_0_474 | `DIFFIO_L6_G1_10N_GSCLK` |
| `Y25` | IOBD_0_552 | `DIFFIO_L6_G0_04P` |
| `Y26` | IOBS_0_558 | `DIFFIO_L6_G0_03N` |

### BANKL7（50 球）

| 球位 | IOBD / IOBS 索引 | 专用功能名 |
| :-- | :-- | :-- |
| `AA15` | IOBS_0_18 | `DIFFIO_L7_G3_22N` |
| `AA17` | IOBD_0_72 | `DIFFIO_L7_G3_18P` |
| `AA18` | IOBS_0_90 | `DIFFIO_L7_G2_16N` |
| `AA19` | IOBD_0_144 | `DIFFIO_L7_G2_12P_GMCLK` |
| `AA20` | IOBD_0_162 | `DIFFIO_L7_G1_11P_GMCLK` |
| `AB16` | IOBD_0_36 | `DIFFIO_L7_G3_21P` |
| `AB17` | IOBS_0_66 | `DIFFIO_L7_G3_18N_VREF` |
| `AB19` | IOBS_0_138 | `DIFFIO_L7_G2_12N_GMCLK` |
| `AB20` | IOBS_0_156 | `DIFFIO_L7_G1_11N_GMCLK` |
| `AB21` | IOBD_0_174 | `DIFFIO_L7_G1_10P_GSCLK` |
| `AB22` | IOBS_0_300 | `SIO_L7_00` |
| `AC16` | IOBS_0_30 | `DIFFIO_L7_G3_21N` |
| `AC17` | IOBD_0_60 | `DIFFIO_L7_G3_19P` |
| `AC18` | IOBD_0_120 | `DIFFIO_L7_G2_14P_DQS` |
| `AC19` | IOBD_0_132 | `DIFFIO_L7_G2_13P_GSCLK` |
| `AC21` | IOBS_0_168 | `DIFFIO_L7_G1_10N_GSCLK` |
| `AC22` | IOBD_0_282 | `DIFFIO_L7_G0_01P` |
| `AC23` | IOBS_0_276 | `DIFFIO_L7_G0_01N` |
| `AD17` | IOBS_0_54 | `DIFFIO_L7_G3_19N` |
| `AD18` | IOBS_0_114 | `DIFFIO_L7_G2_14N_DQS` |
| `AD19` | IOBS_0_126 | `DIFFIO_L7_G2_13N_GSCLK` |
| `AD20` | IOBD_0_186 | `DIFFIO_L7_G1_09P` |
| `AD21` | IOBD_0_222 | `DIFFIO_L7_G1_06P` |
| `AD23` | IOBD_0_234 | `DIFFIO_L7_G0_05P` |
| `AD24` | IOBS_0_228 | `DIFFIO_L7_G0_05N_VREF` |
| `AD25` | IOBD_0_258 | `DIFFIO_L7_G0_03P` |
| `AD26` | IOBS_0_252 | `DIFFIO_L7_G0_03N` |
| `AE17` | IOBD_0_84 | `DIFFIO_L7_G2_17P` |
| `AE18` | IOBD_0_108 | `DIFFIO_L7_G2_15P` |
| `AE20` | IOBS_0_180 | `DIFFIO_L7_G1_09N` |
| `AE21` | IOBS_0_216 | `DIFFIO_L7_G1_06N` |
| `AE22` | IOBD_0_198 | `DIFFIO_L7_G1_08P_DQS` |
| `AE23` | IOBD_0_246 | `DIFFIO_L7_G0_04P` |
| `AE25` | IOBD_0_294 | `DIFFIO_L7_G0_00P` |
| `AE26` | IOBS_0_288 | `DIFFIO_L7_G0_00N` |
| `AF17` | IOBS_0_78 | `DIFFIO_L7_G2_17N` |
| `AF18` | IOBS_0_102 | `DIFFIO_L7_G2_15N` |
| `AF19` | IOBD_0_210 | `DIFFIO_L7_G1_07P` |
| `AF20` | IOBS_0_204 | `DIFFIO_L7_G1_07N` |
| `AF22` | IOBS_0_192 | `DIFFIO_L7_G1_08N_DQS` |
| `AF23` | IOBS_0_240 | `DIFFIO_L7_G0_04N` |
| `AF24` | IOBD_0_270 | `DIFFIO_L7_G0_02P_DQS` |
| `AF25` | IOBS_0_264 | `DIFFIO_L7_G0_02N_DQS` |
| `W14` | IOBD_0_12 | `DIFFIO_L7_G3_23P` |
| `W15` | IOBS_0_6 | `DIFFIO_L7_G3_23N` |
| `W16` | IOBS_0_0 | `SIO_L7_01` |
| `Y15` | IOBD_0_24 | `DIFFIO_L7_G3_22P` |
| `Y16` | IOBD_0_48 | `DIFFIO_L7_G3_20P_DQS` |
| `Y17` | IOBS_0_42 | `DIFFIO_L7_G3_20N_DQS` |
| `Y18` | IOBD_0_96 | `DIFFIO_L7_G2_16P` |

### BANKR4（50 球）

| 球位 | IOBD / IOBS 索引 | 专用功能名 |
| :-- | :-- | :-- |
| `A2` | IOBS_732_972 | `DIFFIO_R4_G3_19N` |
| `A3` | IOBD_732_978 | `DIFFIO_R4_G3_19P` |
| `A4` | IOBS_732_1020 | `DIFFIO_R4_G2_15N` |
| `A5` | IOBS_732_1032 | `DIFFIO_R4_G2_14N_DQS` |
| `B1` | IOBS_732_960 | `DIFFIO_R4_G3_20N_DQS` |
| `B2` | IOBS_732_984 | `DIFFIO_R4_G3_18N_VREF` |
| `B4` | IOBD_732_1026 | `DIFFIO_R4_G2_15P` |
| `B5` | IOBD_732_1038 | `DIFFIO_R4_G2_14P_DQS` |
| `C1` | IOBD_732_966 | `DIFFIO_R4_G3_20P_DQS` |
| `C2` | IOBD_732_990 | `DIFFIO_R4_G3_18P` |
| `C3` | IOBS_732_1008 | `DIFFIO_R4_G2_16N` |
| `C4` | IOBS_732_1044 | `DIFFIO_R4_G2_13N_GSCLK` |
| `D1` | IOBS_732_936 | `DIFFIO_R4_G3_22N` |
| `D3` | IOBD_732_1014 | `DIFFIO_R4_G2_16P` |
| `D4` | IOBD_732_1050 | `DIFFIO_R4_G2_13P_GSCLK` |
| `D5` | IOBS_732_1056 | `DIFFIO_R4_G2_12N_GMCLK` |
| `D6` | IOBS_732_1206 | `DIFFIO_R4_G0_00N_VAA4N` |
| `E1` | IOBD_732_942 | `DIFFIO_R4_G3_22P` |
| `E2` | IOBS_732_948 | `DIFFIO_R4_G3_21N` |
| `E3` | IOBS_732_996 | `DIFFIO_R4_G2_17N` |
| `E5` | IOBD_732_1062 | `DIFFIO_R4_G2_12P_GMCLK` |
| `E6` | IOBD_732_1212 | `DIFFIO_R4_G0_00P_VAA4P` |
| `F2` | IOBD_732_954 | `DIFFIO_R4_G3_21P` |
| `F3` | IOBD_732_1002 | `DIFFIO_R4_G2_17P` |
| `F4` | IOBS_732_1086 | `DIFFIO_R4_G1_10N_GSCLK` |
| `F5` | IOBS_732_1074 | `DIFFIO_R4_G1_11N_GMCLK` |
| `F7` | IOBS_732_1170 | `DIFFIO_R4_G0_03N` |
| `F8` | IOBD_732_1176 | `DIFFIO_R4_G0_03P` |
| `G1` | IOBS_732_924 | `DIFFIO_R4_G3_23N` |
| `G2` | IOBD_732_930 | `DIFFIO_R4_G3_23P` |
| `G4` | IOBD_732_1092 | `DIFFIO_R4_G1_10P_GSCLK` |
| `G5` | IOBD_732_1080 | `DIFFIO_R4_G1_11P_GMCLK` |
| `G6` | IOBS_732_1158 | `DIFFIO_R4_G0_04N_VAA12N` |
| `G7` | IOBS_732_1182 | `DIFFIO_R4_G0_02N_DQS_VAA11N` |
| `G8` | IOBS_732_1194 | `DIFFIO_R4_G0_01N_VAA6N` |
| `G9` | IOBS_732_1146 | `DIFFIO_R4_G0_05N_VREF` |
| `H3` | IOBS_732_918 | `SIO_R4_01` |
| `H4` | IOBS_732_1110 | `DIFFIO_R4_G1_08N_DQS_VAA15N` |
| `H6` | IOBD_732_1164 | `DIFFIO_R4_G0_04P_VAA12P` |
| `H7` | IOBD_732_1188 | `DIFFIO_R4_G0_02P_DQS_VAA11P` |
| `H8` | IOBD_732_1200 | `DIFFIO_R4_G0_01P_VAA6P` |
| `H9` | IOBD_732_1152 | `DIFFIO_R4_G0_05P` |
| `J4` | IOBD_732_1116 | `DIFFIO_R4_G1_08P_DQS_VAA15P` |
| `J5` | IOBS_732_1134 | `DIFFIO_R4_G1_06N_VAA13N` |
| `J6` | IOBD_732_1140 | `DIFFIO_R4_G1_06P_VAA13P` |
| `J8` | IOBS_732_1218 | `SIO_R4_00` |
| `K6` | IOBS_732_1098 | `DIFFIO_R4_G1_09N_VAA0N` |
| `K7` | IOBD_732_1104 | `DIFFIO_R4_G1_09P_VAA0P` |
| `K8` | IOBS_732_1122 | `DIFFIO_R4_G1_07N_VAA14N` |
| `L8` | IOBD_732_1128 | `DIFFIO_R4_G1_07P_VAA14P` |

### BANKR5（50 球）

| 球位 | IOBD / IOBS 索引 | 专用功能名 |
| :-- | :-- | :-- |
| `H1` | IOBS_732_792 | `DIFFIO_R5_G1_09N` |
| `H2` | IOBD_732_798 | `DIFFIO_R5_G1_09P` |
| `J1` | IOBS_732_828 | `DIFFIO_R5_G1_06N` |
| `J3` | IOBS_732_900 | `DIFFIO_R5_G0_00N` |
| `K1` | IOBD_732_834 | `DIFFIO_R5_G1_06P` |
| `K2` | IOBS_732_816 | `DIFFIO_R5_G1_07N` |
| `K3` | IOBD_732_906 | `DIFFIO_R5_G0_00P` |
| `K5` | IOBS_732_864 | `DIFFIO_R5_G0_03N` |
| `L2` | IOBS_732_780 | `DIFFIO_R5_G1_10N_GSCLK` |
| `L3` | IOBD_732_822 | `DIFFIO_R5_G1_07P` |
| `L4` | IOBS_732_876 | `DIFFIO_R5_G0_02N_DQS` |
| `L5` | IOBD_732_870 | `DIFFIO_R5_G0_03P` |
| `L7` | IOBS_732_888 | `DIFFIO_R5_G0_01N` |
| `M1` | IOBS_732_804 | `DIFFIO_R5_G1_08N_DQS` |
| `M2` | IOBD_732_786 | `DIFFIO_R5_G1_10P_GSCLK` |
| `M4` | IOBD_732_882 | `DIFFIO_R5_G0_02P_DQS` |
| `M5` | IOBS_732_840 | `DIFFIO_R5_G0_05N_VREF` |
| `M6` | IOBD_732_846 | `DIFFIO_R5_G0_05P` |
| `M7` | IOBD_732_894 | `DIFFIO_R5_G0_01P` |
| `N1` | IOBD_732_810 | `DIFFIO_R5_G1_08P_DQS` |
| `N2` | IOBS_732_768 | `DIFFIO_R5_G1_11N_GMCLK` |
| `N3` | IOBD_732_774 | `DIFFIO_R5_G1_11P_GMCLK` |
| `N4` | IOBS_732_738 | `DIFFIO_R5_G2_13N_GSCLK` |
| `N6` | IOBS_732_852 | `DIFFIO_R5_G0_04N` |
| `N7` | IOBD_732_858 | `DIFFIO_R5_G0_04P` |
| `N8` | IOBS_732_912 | `SIO_R5_00` |
| `P1` | IOBS_732_726 | `DIFFIO_R5_G2_14N_DQS` |
| `P3` | IOBS_732_750 | `DIFFIO_R5_G2_12N_GMCLK` |
| `P4` | IOBD_732_744 | `DIFFIO_R5_G2_13P_GSCLK` |
| `P5` | IOBS_732_678 | `DIFFIO_R5_G3_18N_VREF` |
| `P6` | IOBD_732_684 | `DIFFIO_R5_G3_18P` |
| `P8` | IOBS_732_642 | `DIFFIO_R5_G3_21N` |
| `R1` | IOBD_732_732 | `DIFFIO_R5_G2_14P_DQS` |
| `R2` | IOBS_732_702 | `DIFFIO_R5_G2_16N` |
| `R3` | IOBD_732_756 | `DIFFIO_R5_G2_12P_GMCLK` |
| `R5` | IOBS_732_666 | `DIFFIO_R5_G3_19N` |
| `R6` | IOBS_732_630 | `DIFFIO_R5_G3_22N` |
| `R7` | IOBD_732_636 | `DIFFIO_R5_G3_22P` |
| `R8` | IOBD_732_648 | `DIFFIO_R5_G3_21P` |
| `T2` | IOBD_732_708 | `DIFFIO_R5_G2_16P` |
| `T3` | IOBS_732_714 | `DIFFIO_R5_G2_15N` |
| `T4` | IOBD_732_720 | `DIFFIO_R5_G2_15P` |
| `T5` | IOBD_732_672 | `DIFFIO_R5_G3_19P` |
| `T7` | IOBS_732_618 | `DIFFIO_R5_G3_23N` |
| `T8` | IOBD_732_624 | `DIFFIO_R5_G3_23P` |
| `U1` | IOBS_732_690 | `DIFFIO_R5_G2_17N` |
| `U2` | IOBD_732_696 | `DIFFIO_R5_G2_17P` |
| `U4` | IOBS_732_612 | `SIO_R5_01` |
| `U5` | IOBS_732_654 | `DIFFIO_R5_G3_20N_DQS` |
| `U6` | IOBD_732_660 | `DIFFIO_R5_G3_20P_DQS` |

### BANKR6（50 球）

| 球位 | IOBD / IOBS 索引 | 专用功能名 |
| :-- | :-- | :-- |
| `AA2` | IOBS_732_462 | `DIFFIO_R6_G1_11N_GMCLK` |
| `AA3` | IOBD_732_468 | `DIFFIO_R6_G1_11P_GMCLK` |
| `AA4` | IOBD_732_450 | `DIFFIO_R6_G2_12P_GMCLK` |
| `AA5` | IOBD_732_342 | `DIFFIO_R6_G3_21P` |
| `AA7` | IOBS_732_372 | `DIFFIO_R6_G3_18N_VREF` |
| `AA8` | IOBS_732_324 | `DIFFIO_R6_G3_22N` |
| `AB1` | IOBD_732_528 | `DIFFIO_R6_G1_06P` |
| `AB2` | IOBD_732_480 | `DIFFIO_R6_G1_10P_GSCLK` |
| `AB4` | IOBS_732_444 | `DIFFIO_R6_G2_12N_GMCLK` |
| `AB5` | IOBS_732_336 | `DIFFIO_R6_G3_21N` |
| `AB6` | IOBD_732_318 | `DIFFIO_R6_G3_23P` |
| `AC1` | IOBS_732_522 | `DIFFIO_R6_G1_06N` |
| `AC2` | IOBS_732_474 | `DIFFIO_R6_G1_10N_GSCLK` |
| `AC3` | IOBD_732_438 | `DIFFIO_R6_G2_13P_GSCLK` |
| `AC4` | IOBD_732_390 | `DIFFIO_R6_G2_17P` |
| `AC6` | IOBS_732_312 | `DIFFIO_R6_G3_23N` |
| `AD1` | IOBD_732_504 | `DIFFIO_R6_G1_08P_DQS` |
| `AD3` | IOBS_732_432 | `DIFFIO_R6_G2_13N_GSCLK` |
| `AD4` | IOBS_732_384 | `DIFFIO_R6_G2_17N` |
| `AD5` | IOBD_732_426 | `DIFFIO_R6_G2_14P_DQS` |
| `AE1` | IOBS_732_498 | `DIFFIO_R6_G1_08N_DQS` |
| `AE2` | IOBD_732_492 | `DIFFIO_R6_G1_09P` |
| `AE3` | IOBD_732_414 | `DIFFIO_R6_G2_15P` |
| `AE5` | IOBS_732_420 | `DIFFIO_R6_G2_14N_DQS` |
| `AF2` | IOBS_732_486 | `DIFFIO_R6_G1_09N` |
| `AF3` | IOBS_732_408 | `DIFFIO_R6_G2_15N` |
| `AF4` | IOBS_732_396 | `DIFFIO_R6_G2_16N` |
| `AF5` | IOBD_732_402 | `DIFFIO_R6_G2_16P` |
| `U7` | IOBD_732_540 | `DIFFIO_R6_G0_05P` |
| `V1` | IOBD_732_600 | `DIFFIO_R6_G0_00P` |
| `V2` | IOBS_732_570 | `DIFFIO_R6_G0_02N_DQS` |
| `V3` | IOBD_732_576 | `DIFFIO_R6_G0_02P_DQS` |
| `V4` | IOBS_732_606 | `SIO_R6_00` |
| `V6` | IOBD_732_564 | `DIFFIO_R6_G0_03P` |
| `V7` | IOBS_732_534 | `DIFFIO_R6_G0_05N_VREF` |
| `V8` | IOBD_732_354 | `DIFFIO_R6_G3_20P_DQS` |
| `V9` | IOBS_732_306 | `SIO_R6_01` |
| `W1` | IOBS_732_594 | `DIFFIO_R6_G0_00N` |
| `W3` | IOBD_732_552 | `DIFFIO_R6_G0_04P` |
| `W4` | IOBS_732_582 | `DIFFIO_R6_G0_01N` |
| `W5` | IOBD_732_588 | `DIFFIO_R6_G0_01P` |
| `W6` | IOBS_732_558 | `DIFFIO_R6_G0_03N` |
| `W8` | IOBS_732_348 | `DIFFIO_R6_G3_20N_DQS` |
| `Y1` | IOBS_732_510 | `DIFFIO_R6_G1_07N` |
| `Y2` | IOBD_732_516 | `DIFFIO_R6_G1_07P` |
| `Y3` | IOBS_732_546 | `DIFFIO_R6_G0_04N` |
| `Y5` | IOBS_732_360 | `DIFFIO_R6_G3_19N` |
| `Y6` | IOBD_732_366 | `DIFFIO_R6_G3_19P` |
| `Y7` | IOBD_732_378 | `DIFFIO_R6_G3_18P` |
| `Y8` | IOBD_732_330 | `DIFFIO_R6_G3_22P` |

---

*本文件由脚本从 `F:\BaiduNetdiskDownload\qs` 的 `.fdc` / `.idf` / `.prt` / `.pcf` 原文解析生成；所有引脚号均可在第 11 章列出的文件中逐字核对，未能取得的项目已明确标注“未找到”。*