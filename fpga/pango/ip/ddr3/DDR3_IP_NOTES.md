# Pango Logos2 HMIC_S DDR3 IP for PG2L200H-6IFBB676 (Pangu 200Pro+)

Status: **working**. The IP instance in `ddr3_test/` is regenerated for
PG2L200H / FBB676 / -6, a PDS project adds it with `add_design ...\ddr3_test.idf`,
and the validation project in `_test/` passes `compile` -> `synthesize -ads` -> `dev_map`
with **0 errors** on the real device. `pnr` also places and routes; there is one
open timing item on a PG2L200H-specific clock crossing (see 7.3).

Everything here was produced with PDS 2022.2-SP6.4 (build 146967) and its
bundled IP Compiler. The F: reference material was only read, never modified.

---

## 1. What worked - route A (regenerate the 100H demo IP for the 200H device)

`ip_compiler.exe` is GUI-only for customisation (`-c`), but `ip_generate.exe` is
a **headless regenerator**: it re-runs the IP's `createFiles.tcl` against the
device/package in the `.idf` header and rewrites the RTL wrappers, the
instantiation templates and the constraint file. No GUI needed.

### 1.1 Exact commands

```bat
REM one-off: copy the reference IP instance
xcopy /E /I /Y "F:\BaiduNetdiskDownload\qs\_scan2\2_9_ddr3_test\2_9_ddr3_test\2_9_ddr3_test\ddr3_test\ipcore\ddr3_test" "E:\qs\self_pro\fpga\pango\ip\ddr3\ddr3_test"

REM edit ddr3_test.idf header:
REM   <device>PG2L100H</device>   ->  <device>PG2L200H</device>
REM   <package>FBG676</package>   ->  <package>FBB676</package>
REM   (speedgrade -6 unchanged)

REM regenerate - this is THE command (-ads = the synthesis back-end PDS uses)
D:\PDS_2022.2-SP6.4\bin\ip_generate.exe -i E:\qs\self_pro\fpga\pango\ip\ddr3\ddr3_test\ddr3_test.idf -ads
```

Other switches (`ip_generate.exe -help`):

* `-device STR` `-pack STR` `-speed STR` `-family STR`  - override the `.idf` header
* `-tmp-dir DIR`     - scratch dir, default `rev_1`
* `-log FILE`        - default `generate.log`
* `-disable-syn`     - do not pre-synthesise the IP
* `-copy_name NAME -copy_dir DIR` - clone the instance under a new name

Successful run:

```
IP Generator (Version 2022.2-SP6.4 build 146967)
Instance: ddr3_test (...\ddr3_test.idf)
IP: Pango DDR3 Interface (1.10)
Part: Logos2-PG2L200H-FBB676--6      <-- device override accepted
...
Run file 'createFiles.tcl' ...
Done: 0 error(s), 0 warning(s)
```

### 1.2 The one real trap: the `PAD_*` pins in the demo `.idf` were wrong

The `.idf` carries 329 parameters, 44 of which are `PAD_DQ*` / `PAD_DQS*` /
`PAD_DQSN*` / `PAD_DM*` pin coordinates, plus `PAD_A*` / `PAD_BA*` / `PAD_CK` ...
for the command/address side. `createFiles.tcl` turns those parameters into the
DDR3 pin table of the generated `pnr/ddr_test.fdc`, so they decide the real
pinout.

In the demo `.idf` the **CA pins were correct but the DQ/DQS/DM pins were not**
the pins the demo board actually used, and four of them collided:

| duplicated ball | used twice for |
|---|---|
| `G9` | `mem_dq[12]` and `mem_dq[14]` |
| `H6` | `mem_dq[13]` and `mem_dq[15]` |
| `B5` | `mem_dq[17]` and `mem_dqs_n[2]` |
| `C1` | `mem_dq[26]` and `mem_dqs_n[3]` |

A regenerated IP with those values cannot be placed. The authoritative pinout
is the **active** (uncommented) IO table of the demo project's
`pnr/ddr_test.fdc`, which is hardware-proven, and which also matches the board
file already in this repo (`fpga/pango/ares_p4_board.fdc`: clk50 = D18,
rst_n = C22, uart_tx = C24, uart_rx = B24, led0..3 = A20 / C18 / C19 / E18 - all
identical to the demo's free_clk / rst_board / uart_txd / uart_rxd /
ddr_init_done / ddrphy_cpd_lock / err_flag_led / heart_beat_led). So the 44
DQ-family `PAD_*` parameters were rewritten from that file and the IP was
regenerated again; the result has **no duplicate balls** and 71/71 DDR3 pins
identical to the working demo board.

> If you ever re-run the GUI IP compiler on this `.idf`, re-check the pin table:
> the GUI's auto-assignment is what produced the bad values in the first place.

**Naming note**: the instance is `ddr3_test` and the IP top module is
`ddr3_test`. Renaming is possible with
`ip_generate -i ... -copy_name ddr3 -copy_dir ...`, but then every generated
file/module name changes; it was left at the generator default to stay close to
the reference.

---

## 2. Files in this directory

```
fpga/pango/ip/ddr3/
  ddr3_test/                     IP instance (regenerated for PG2L200H-FBB676)
    ddr3_test.idf                the IP configuration XML  <-- add_design this
    ddr3_test.v                  IP top (module ddr3_test)        generated
    ddr3_test_ddrphy_top.v       PHY top                          generated
    ddr3_test_tmpl.v             instantiation template
    ddr3_test_tmpl.vhdl
    generate.log                 generator log of the last run
    rtl/                         ~70 encrypted *.vp sources + ddr3_test_slice_top_v1_10.v
    sim/  sim_lib/               simulation
    example_design/              BIST example design (test_ddr.v + AXI BIST master)
    pnr/
      ddr_test.fdc               RAW generator output (see the warning below)
      ddr3_test.pds / .rcf       demo example-design project
  ddr3_ip.fdc                    **the constraint file to use** (IP-only part)
  ddr3_ports.csv                 machine-readable port list
  DDR3_IP_NOTES.md               this file
  _test/                         validation project (see 7)
```

`ddr3_test/pnr/ddr_test.fdc` is what the generator emits. It is correct for the
71 DDR3 pins but it also contains the demo board's *other* pins (free_clk,
rst_board, uart, LEDs, and a `uart_rxd = L8` that collides with `mem_dq[3]`).
Do not add it wholesale to an SoC. Use `ddr3_ip.fdc`, which is the same file
reduced to the IP-only part:

* `create_clock ref_clk` (8 ns / 125 MHz) + all PHY generated clocks
* the `set_clock_uncertainty` / `set_clock_groups` block
* the `define_attribute {i:...}` PHY placement entries
* the 71-entry DDR3 IO table
* the `ref_clk_p` / `ref_clk_n` input pair (N3/N2, see 4)

---

## 3. IP parameters

```verilog
module ddr3_test #(
    parameter MEM_ROW_WIDTH    = 15,
    parameter MEM_COLUMN_WIDTH = 10,
    parameter MEM_BANK_WIDTH   = 3,
    parameter MEM_DQ_WIDTH     = 32,   // 4 byte lanes -> AXI data = 8*32 = 256 bit
    parameter MEM_DM_WIDTH     = 4,
    parameter MEM_DQS_WIDTH    = 4,
    parameter CTRL_ADDR_WIDTH  = 28    // = ROW+COLUMN+BANK, also the AXI byte address width
);
```

Key `.idf` settings behind them (parameters of the IP instance, not of the
Verilog module):

| parameter | value | meaning |
|---|---|---|
| `MEM_TYPE` | `DDR3` | DDR3 mode |
| `DESIRED_DDR3_RATE` / `ACTUAL_RATE` | `1000.000` / `1000.000` | 1000 Mbps/pin (500 MHz CK) |
| `CLKIN_FREQ` | `125.000` | ref_clk / PLL input, MHz |
| `DFI_CLK_PERIOD` | `8000` | DFI (controller) clock period in ps = 125 MHz |
| `DDR3_BASE_MEM_PART` | `MT41K128M16XX` | see risk 9.1 |
| `DDR3_DFT_MEM_PART` / `DDR_MEM_PART` | `MT41K256M16XX` | see risk 9.1 |
| `DDR3_MEM_ROW_WIDTH` / `_COLUMN` / `_BANK` | `15 / 10 / 3` | geometry |
| `DDR3_CL_VALUE` / `DDR3_CWL` / `DDR3_CL` | `6 / 6 / 7` | CAS latency |
| `DDR3_ODT_VALUE` / `DDR3_OUTPUT_DRIVER` | `001` / `00` | DDR3 MR1 / MR0 fields |
| `DDRC_TREFI / TRFC / T_FAW / T_RAS / T_RC / T_RCD / T_RP / T_RRD / T_RTP / T_WR / T_WTR / T_XP` | `3900 /150 /22 /19 /25 /7 /7 /5 /4 /8 /4 /4` | controller timing (ck cycles) |
| `GPLL_BANDWIDTH` / `PPLL_BANDWIDTH` | `HIGH` / `HIGH` | PLL loop bandwidth |
| `CA_GROUP_NUM` | `3` | DDR_PHY command/address groups |
| `DQ0_EN..DQ3_EN` | `true` (`DQ4_EN..DQ8_EN` = false) | 4 byte lanes used |
| `CUSTOMIZE_CA` / `CUSTOMIZE_MEM` | `true` / `false` | CA pins chosen manually, memory type fixed |
| `USER_PINS_CON_EN` / `USER_FDC_PATH` | `false` / `Please select a fdc file` | unused |

---

## 4. Clocks and reset

| signal | requirement |
|---|---|
| `ref_clk` (IP port, **single ended**) | **125 MHz**. Fed from the board 125 MHz DDR3 reference oscillator through a differential input buffer: `GTP_INBUFDS` driven by `ref_clk_p` / `ref_clk_n` (SSTL15D_I, balls **N3 / N2** - see the note in `ddr3_ip.fdc`). Constraint: `create_clock -name ref_clk [get_ports ref_clk_p] -period 8.0` |
| `resetn` (IP port) | **active LOW** asynchronous reset. Must be low while the reference clock starts, then released; the IP contains its own reset synchroniser (`ips2l_rst_sync_v1_3`). The example design uses `resetn = rst_board & dbg_ddr_rst_n`. |
| `core_clk` (IP output) | controller / AXI clock, 125 MHz = `ref_clk`. The user side of the AXI port must run on this clock. |
| `apb_clk` / `apb_rst_n` | APB configuration port for the PHY; unused = tie `apb_clk = 0`, `apb_rst_n = 0`, `apb_sel = 0` exactly as the reference design does. No APB clock constraint then. |
| `mem_ck` (output) | 500 MHz DDR clock generated by the PHY (DDR3-1000). |

Derived clock tree (from `ddr3_ip.fdc`, useful when reading a timing report):

```
ref_clk         8.000 ns  declared on ref_clk_p
rst_clk         8.000 ns  ddrphy_top/rst_clk_gpll/gpll_inst/CLKOUT0
ddrphy_sysclk   8.000 ns  ddrphy_top/ddrphy_gpll/gpll_inst/CLKOUT0   (controller clock)
phy_dq_clk_0    1.000 ns  i_dqs_bank[0]/ddrphy_ppll/u_ppll/CLKOUTPHY (500 MHz DDR)
phy_dq_sysclk_0 8.000 ns  i_dqs_bank[0]/u_ddrphy_ioclkdiv/CLKOUT
phy_dq_clk_1    1.000 ns  i_dqs_bank[1]/...   (ditto)
```

---

## 5. IP port list (module `ddr3_test`, widths resolved for the parameters above)

86 ports. Also available as `ddr3_ports.csv`.

### 5.1 Clock / reset / status

| port | dir | width |
|---|---|---|
| `ref_clk` | in | 1 |
| `resetn` | in | 1 |
| `core_clk` | out | 1 |
| `pll_lock` | out | 1 |
| `phy_pll_lock` | out | 1 |
| `gpll_lock` | out | 1 |
| `rst_gpll_lock` | out | 1 |
| `ddrphy_cpd_lock` | out | 1 |
| `ddr_init_done` | out | 1 |

### 5.2 AXI4-style slave (exact contract in 8)

| port | dir | width |
|---|---|---|
| `axi_awaddr` | in | 28 |
| `axi_awuser_ap` | in | 1 |
| `axi_awuser_id` | in | 4 |
| `axi_awlen` | in | 4 |
| `axi_awvalid` | in | 1 |
| `axi_awready` | out | 1 |
| `axi_wdata` | in | **256** (8 x DQ width) |
| `axi_wstrb` | in | **32** (1 per byte lane) |
| `axi_wready` | out | 1 |
| `axi_wusero_id` | out | 4 |
| `axi_wusero_last` | out | 1 |
| `axi_araddr` | in | 28 |
| `axi_aruser_ap` | in | 1 |
| `axi_aruser_id` | in | 4 |
| `axi_arlen` | in | 4 |
| `axi_arvalid` | in | 1 |
| `axi_arready` | out | 1 |
| `axi_rdata` | out | **256** |
| `axi_rid` | out | 4 |
| `axi_rlast` | out | 1 |
| `axi_rvalid` | out | 1 |

There is **no** `wlast`, **no** `rready`, **no** `bresp` / `rresp`, **no** `bid`:
it is one write channel plus one read channel, not a full AXI4 slave.

### 5.3 APB (PHY configuration, optional)

| port | dir | width |
|---|---|---|
| `apb_clk` / `apb_rst_n` / `apb_sel` / `apb_enable` / `apb_write` | in | 1 each |
| `apb_addr` | in | 8 |
| `apb_wdata` | in | 16 |
| `apb_ready` | out | 1 |
| `apb_rdata` | out | 16 |

### 5.4 DDR3 device pins (71)

| port | dir | width |
|---|---|---|
| `mem_a` | out | 15 (`mem_a[14:0]`) |
| `mem_ba` | out | 3 |
| `mem_ck` / `mem_ck_n` / `mem_cke` / `mem_cs_n` / `mem_ras_n` / `mem_cas_n` / `mem_we_n` / `mem_odt` / `mem_rst_n` | out | 1 each |
| `mem_dq` | inout | 32 |
| `mem_dqs` | inout | 4 |
| `mem_dqs_n` | inout | 4 |
| `mem_dm` | out | 4 |

(no per-rank `mem_cs_n[1:0]`, no per-rank CKE: single rank. `mem_a[10]` is the
DDR3 precharge / auto-precharge pin, as usual.)

### 5.5 Calibration / debug (all inert when tied as in 7.1)

| port | dir | width | tie-off |
|---|---|---|---|
| `dbg_gate_start`, `dbg_cpd_start` | in | 1 | 0 |
| `dbg_ddrphy_rst_n` | in | 1 | **1** (0 holds the PHY in reset) |
| `dbg_gpll_scan_rst` | in | 1 | 0 |
| `samp_position_dyn_adj`, `wrcal_position_dyn_adj` | in | 1 | 0 |
| `force_read_clk_ctrl` | in | 1 | 0 |
| `ck_dly_en` | in | 1 | 0 |
| `init_samp_position_even` / `_odd` | in | 32 each | 0 |
| `init_wrcal_position` | in | 32 | 0 |
| `init_slip_step` | in | 16 | 0 |
| `init_read_clk_ctrl` | in | 12 | 0 |
| `init_ck_dly_step` | in | 8 | 0 |
| `debug_cpd_offset` | in | 10 | 0 |
| `debug_cpd_offset_adj`, `debug_cpd_offset_dir` | in | 1 | 0 |
| `debug_calib_ctrl` | out | 34 | - |
| `dbg_slice_status` / `dbg_slice_state` / `debug_data` | out | 68 / 88 / 276 | - |
| `dbg_dll_upd_state` / `debug_gpll_dps_phase` / `dbg_rst_dps_state` / `dbg_tran_err_rst_cnt` | out | 2 / 9 / 3 / 6 | - |
| `dbg_ddrphy_init_fail` / `align_error` | out | 1 | - |
| `debug_dps_cnt_dir0` / `_dir1` | out | 10 each | - |
| `ck_dly_set_bin` | out | 8 | - |
| `debug_rst_state` / `debug_cpd_state` | out | 4 / 4 | - |

---

## 6. Pin list (PG2L200H / FBB676)

All 71 DDR3 balls, taken from the hardware-proven demo board and accepted by
`dev_map` on the 200H. IO standard `SSTL15_I` (DQS pins `SSTL15D_I`), VCCIO 1.5 V,
`PAP_IO_DDR_TERM_MODE {ON}` / `PAP_IO_DDR_RES {60}` on the DQ/DQS pins.

| Signal | Ball | Signal | Ball | Signal | Ball |
|---|---|---|---|---|---|
| `mem_a[0]` | J1 | `mem_a[1]` | L3 | `mem_a[2]` | L2 |
| `mem_a[3]` | P3 | `mem_a[4]` | T2 | `mem_a[5]` | M1 |
| `mem_a[6]` | U1 | `mem_a[7]` | K1 | `mem_a[8]` | U2 |
| `mem_a[9]` | K2 | `mem_a[10]` | T3 | `mem_a[11]` | P1 |
| `mem_a[12]` | T4 | `mem_a[13]` | M2 | `mem_a[14]` | N1 |
| `mem_ba[0]` | P4 | `mem_ba[1]` | R2 | `mem_ba[2]` | T5 |
| `mem_ck` | U6 | `mem_ck_n` | U5 | `mem_cke` | R1 |
| `mem_cs_n` | N4 | `mem_ras_n` | P6 | `mem_cas_n` | T7 |
| `mem_we_n` | T8 | `mem_odt` | H2 | `mem_rst_n` | H1 |
| `mem_dq[0]` | G5 | `mem_dq[1]` | J6 | `mem_dq[2]` | F5 |
| `mem_dq[3]` | L8 | `mem_dq[4]` | G4 | `mem_dq[5]` | K7 |
| `mem_dq[6]` | F4 | `mem_dq[7]` | J5 | `mem_dq[8]` | H6 |
| `mem_dq[9]` | F8 | `mem_dq[10]` | H8 | `mem_dq[11]` | D6 |
| `mem_dq[12]` | G8 | `mem_dq[13]` | E6 | `mem_dq[14]` | H9 |
| `mem_dq[15]` | G6 | `mem_dq[16]` | C4 | `mem_dq[17]` | D4 |
| `mem_dq[18]` | A4 | `mem_dq[19]` | E3 | `mem_dq[20]` | C3 |
| `mem_dq[21]` | F3 | `mem_dq[22]` | B4 | `mem_dq[23]` | D3 |
| `mem_dq[24]` | F2 | `mem_dq[25]` | D1 | `mem_dq[26]` | G1 |
| `mem_dq[27]` | A2 | `mem_dq[28]` | E1 | `mem_dq[29]` | A3 |
| `mem_dq[30]` | G2 | `mem_dq[31]` | C2 | `mem_dqs[0]` | J4 |
| `mem_dqs[1]` | H7 | `mem_dqs[2]` | B5 | `mem_dqs[3]` | C1 |
| `mem_dqs_n[0]` | H4 | `mem_dqs_n[1]` | G7 | `mem_dqs_n[2]` | A5 |
| `mem_dqs_n[3]` | B1 | `mem_dm[0]` | K6 | `mem_dm[1]` | F7 |
| `mem_dm[2]` | D5 | `mem_dm[3]` | E2 | `ref_clk_p` | N3 |
| `ref_clk_n` | N2 |  |  |  |  |

---

## 7. Validation project (`_test/`)

`_test/ddr3_top.v` is a small wrapper: `GTP_INBUFDS` on the reference clock, a
3-FF reset synchroniser on the 50 MHz board clock, all AXI / APB / debug inputs
tied idle, all DDR3 pins exported, IP instance named **`I_ips_ddr_top`**
(required, see 8.5).

### 7.1 Flow

```tcl
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
add_constraint E:/qs/self_pro/fpga/pango/ip/ddr3/_test/ddr3_test.fdc
add_design     E:/qs/self_pro/fpga/pango/ip/ddr3/_test/ddr3_top.v
add_design     E:/qs/self_pro/fpga/pango/ip/ddr3/ddr3_test/ddr3_test.idf
compile -top_module ddr3_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
```

run from `_test/` with
`pds_shell.exe -file flow.tcl -project_name ddr3_ip_test`.

### 7.2 Result: **PASS** (0 errors, 0 constraint errors)

`add_design` of the `.idf` is accepted by a PG2L200H project - no
device-mismatch complaint - and the generated `rtl/*.vp` are compiled as-is.
The only messages are the usual IP-internal Verilog style warnings plus three
`ConstraintEditor-4019` warnings for the deliberately unconstrained board pins.

Device utilisation (after `dev_map`, PG2L200H-6IFBB676):

| resource | used | available | % |
|---|---|---|---|
| FF | 2572 | 319600 | 1 |
| LUT | 2897 | 159800 | 2 |
| Distributed RAM | 8 | 39500 | 1 |
| IO | 78 | 400 | 20 |
| **DDR_PHY** | **7** | 40 | 18 |
| DDRPHY_CPD | 1 | 20 | 5 |
| DDRPHY_IOCLK_DIV | 2 | 10 | 20 |
| MRCKB | 1 | 20 | 5 |
| GPLL | 2 | 10 | 20 |
| PPLL | 2 | 10 | 20 |
| RCKB | 2 | 40 | 5 |
| USCM | 3 | 32 | 10 |
| TSERDES | 14 | 80 | 18 |
| **CCS** | **1** | **1** | **100** |
| DRM / APM | 0 | 415 / 740 | 0 |

`DDR_PHY 7` = 4 data-lane sites + 3 command/address sites; `PPLL 2` = one per
DQS bank; `GPLL 2` = `ddrphy_gpll` + `rst_clk_gpll`. The design consumes the
device's **only** CCS (column clock switch, inserted by the tool) - if the SoC
needs a CCS elsewhere there is none left.

Final placement of the PHY fabric (from `place_route/run.log`):

```
ddrphy_gpll/u_gpll          -> GPLL_727_769
i_dqs_bank[0] ppll/ioclkdiv -> PPLL_727_613 / DDRPHY_IOCLK_DIV_728_616
i_dqs_bank[1] ppll/ioclkdiv -> PPLL_727_919 / DDRPHY_IOCLK_DIV_728_922
i_ca_group[0..2]            -> DDR_PHY_729_769 / _615 / _613
i_dqs_group[0..3]           -> DDR_PHY_729_1075 / _1077 / _921 / _919
u_clkbufm                   -> MRCKB_721_762
u_ddrphy_cpd                -> DDRPHY_CPD_729_772
```

### 7.3 `pnr` - places and routes, one timing item open

`pnr -optimize_multi_corner_timing -fix_hold_violation` completes (exit 0, no
errors) and `report_timing` runs. Hold is clean and most clocks are fine:

| crossing | WNS (ns) | failing endpoints |
|---|---|---|
| ddrphy_sysclk -> ddrphy_sysclk | +0.341 | 0 / 7162 |
| rst_clk -> rst_clk | +4.590 | 0 / 420 |
| phy_dq_sysclk_1 -> ddrphy_sysclk | +2.795 | 0 / 260 |
| **ddrphy_sysclk -> phy_dq_sysclk_0** | **-4.095** | **164 / 164** |
| **ddrphy_sysclk -> phy_dq_sysclk_1** | **-4.161** | **420 / 420** |

For comparison the same IP and the same flow on the 100H demo board close those
two crossings at +0.932 / +1.602 ns. So it is a **PG2L200H-specific placement**
problem in the DFI <-> PHY clock crossing, not a broken constraint file: the
capture clock comes from PPLLs at y = 613 / 919 while the data slices sit at
y = 919..1077, and about 4 ns of clock-insertion skew is not covered by the
0.4 ns `set_clock_uncertainty`. Next step if hardware bring-up needs it closed:
pin the PHY fabric with explicit `define_attribute {i:...} {PAP_LOC} {...}`
entries (PPLL / DDRPHY_IOCLK_DIV / DDR_PHY / u_clkbufm) the way Pango's own
`ip/system_ip/ips2l_hmic_s/.../pnr/200h_ddr3_676_x72.fdc` does for its reference
pinout, or ask Pango for the 200H placement set that matches this pinout.
The `dev_map` gate of this task is unaffected.

### 7.4 How the reference clock must NOT be constrained

Two hard place-and-route failures were hit on the way, both about the reference
clock pin pair - worth knowing:

* no `ref_clk_p`/`ref_clk_n` constraint at all ->
  `E: Place-0028: Fixed group with base instance u_refclk_inbuf/opit_2 cannot be placed`
* `ref_clk_p = M21` / `ref_clk_n = M22` (Pango's 676 reference value) ->
  `E: Place-0094: MREGION_CLOCK: the placement of ...u_clkbufm/clkbufm_inst and
  ...i_dqs_bank[0].u_clkbufr/goprclk is incompatible`
* `ref_clk_p = N3` / `ref_clk_n = N2` (the demo board) -> **works**, the placer
  then puts `ddrphy_gpll` in the DDR PHY column (GPLL_727_769)

---

## 8. What the SoC must add in front of the IP - AXI4 bridge contract

### 8.1 Shape

* One **write** channel: `awaddr[27:0]`, `awlen[3:0]`, `awvalid/awready`, then
  `wdata[255:0]` with `wstrb[31:0]` and `wready` per beat.
* One **read** channel: `araddr[27:0]`, `arlen[3:0]`, `arvalid/arready`, then
  `rdata[255:0]` with `rvalid` and `rlast` per beat.
* 256-bit data = one 32-byte beat. `CTRL_ADDR_WIDTH = 28` byte address ->
  **256 MiB window** (0x0000_0000 .. 0x0FFF_FFFF).
* `awlen` / `arlen` are AXI4 style: **number of beats minus one** (0..15), i.e.
  up to 16 beats = 512 bytes per burst. (Checked against the IP's own BIST
  master: it drives `awlen = 4'd15` and counts 16 `wready` beats.)
* `wstrb` is one bit per byte of `wdata` (`wstrb[n]` -> `wdata[8n+7:8n]`).
* No `bvalid` / `bresp`: a write is complete at the last `wready` handshake.
* No `rready`: read data **cannot be back-pressured** - the consumer must always
  accept `rvalid` beats. An AXI4 master in front of it must buffer or pace
  requests, never stall.
* No `wlast`: the IP reports the end of a write burst on `axi_wusero_last`
  (asserted with the last accepted beat) and echoes `axi_awuser_id` on
  `axi_wusero_id[3:0]`.
* No `bid`: `axi_rid[3:0]` echoes `axi_aruser_id` and `axi_rlast` ends the burst.
* `axi_awuser_ap` / `axi_aruser_ap`: 1-bit auto-precharge hint, tie 0 unless the
  row should be closed after the burst.
* Everything on this port runs on `core_clk` (125 MHz = `ref_clk`).

### 8.2 Suggested mapping for a 128-bit SoC interconnect

* one 128-bit AXI4 beat = 16 B, one IP beat = 32 B -> pack **two** SoC beats per
  IP beat; a lone 16-bit-wide write is a `wstrb` of `0x0000FFFF` or `0xFFFF0000`,
* split an N-beat 128-bit read burst into ceil(N/2) IP beats,
* `awlen` = (number of 256-bit beats) - 1, addresses 32-byte aligned,
* keep a byte-offset register and use `wstrb` for the first / last partial beat
  instead of realigning the address,
* the read path must sink `rvalid` unconditionally (8.1).

### 8.3 Address map

The IP address is a byte address into the DDR3 rank; the low 5 bits are the byte
lane inside the 256-bit beat, so use `addr[27:5]` for beat addressing.

### 8.4 Connection checklist

```verilog
.ref_clk  (ref_clk)        // 125 MHz, from GTP_INBUFDS on ref_clk_p / ref_clk_n
.resetn   (resetn)         // active LOW
// AXI  -> see 8.1
.apb_clk(1'b0), .apb_rst_n(1'b0), .apb_sel(1'b0), .apb_enable(1'b0),
.apb_addr(8'd0), .apb_write(1'b0), .apb_wdata(16'd0),   // .apb_ready/.apb_rdata open
.dbg_ddrphy_rst_n(1'b1),   // everything else in 5.5 tied 0
```

### 8.5 Mandatory instance name

`ddr3_ip.fdc` addresses the PHY placement with absolute instance paths:

```
define_attribute {i:I_ips_ddr_top.u_ddrphy_top.u_ddrphy_cpd} {PAP_LOC} {DDRPHY_CPD_729_772}
define_attribute {i:I_ips_ddr_top.u_ddrphy_top.ddrphy_reset_ctrl.ddrphy_ioclk_gate[0]} {PAP_LOC} {CLMA_717_672:FF3}
define_attribute {i:I_ips_ddr_top.u_ddrphy_top.ddrphy_reset_ctrl.ddrphy_ioclk_gate[1]} {PAP_LOC} {CLMA_717_978:FF3}
```

and the generated-clock lines use `I_ips_ddr_top.u_ddrphy_top.ddrphy_gpll/...`,
`...ddrphy_slice_top.i_dqs_bank[0]...`. **Instantiate the IP as `I_ips_ddr_top` at
the top level of the SoC** (not inside a hierarchy), or prefix every
`{i:...}` path with the new hierarchy.

---

## 9. Risks / open items

1. **Memory geometry vs part number.** `DDR3_BASE_MEM_PART = MT41K128M16XX`
   (2 Gb, 128M x16) but the configured geometry is 15 row / 10 column / 3 bank,
   which is MT41K256M16-class (4 Gb); `DDR3_DFT_MEM_PART` / `DDR_MEM_PART` say
   `MT41K256M16XX`, and `CTRL_ADDR_WIDTH = 28` exposes 256 MiB. Confirm what is
   fitted on the 200Pro+ and, if it is a 4 Gb part, whether a wider
   `CTRL_ADDR_WIDTH` is needed - that is a re-run of the IP compiler.
2. **DDR3-1000 at CL=6 / CWL=6** is an unusual bin. If the board memory is a
   DDR3-1600 part (typical for MT41K256M16), regenerate at
   `DESIRED_DDR3_RATE = 800` or `1066` with the matching CL - the IP library is
   already set up for those (`GUI_DDR3_CL_800 = 6`, `GUI_DDR3_CL_1066 = 7`).
   Note the DFI clock stays 125 MHz at 1000 Mbps, so a rate change also changes
   `core_clk`.
3. **Reference clock ball N3/N2** comes from the 100H demo board (whose whole IO
   map matches `ares_p4_board.fdc`). Pango's 676 reference files use M21/M22,
   which fails with `Place-0094 MREGION_CLOCK` for this pinout (7.4), so N3/N2
   is the pair to use - but confirm it against the 200Pro+ schematic. A wrong
   pair here is a hard pnr failure, not a warning.
4. **`pnr` timing** on the DFI <-> PHY crossings, 7.3.
5. **CCS 1/1 (100 %)** after `dev_map` - the device has a single CCS and the DDR
   PHY takes it.
6. `mem_dq[3] = L8` collides with the demo's `uart_rxd = L8` in the raw
   generator `ddr_test.fdc`; harmless with `ddr3_ip.fdc` (uart pins removed) but
   do not merge the raw file into the SoC constraints.
7. The `rtl/*.vp` sources are IEEE-1735 encrypted: they cannot be edited, only
   regenerated. Any pin / parameter change must go through the `.idf` and
   `ip_generate.exe`.
