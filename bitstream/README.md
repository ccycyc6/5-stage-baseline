# 位流（Pangu 200Pro+ / PG2L200H-6IFBB676）

| 文件 | 固件 | 用途 | 大小 | SHA256 |
|---|---|---|---:|---|
| `ares_p4_vision.sbit` | 图像识别 demo | **上板首选**：串口自检 + 上传 32×32 帧识别 | 9,188,552 B | `FF9649E2…3B201BEF` |
| `ares_p4_coremark.sbit` | CoreMark v1.0 | 先验通路：串口输出 4 个 CRC + CoreMark/MHz | 9,188,552 B | `51BB853C…875C5D24` |

两个位流的**网表完全相同**，只有片内 128 KiB BRAM 里的固件镜像不同，因此时序/资源一致：

| 项目 | 数值 |
|---|---|
| 器件 / 封装 / 速度等级 | PG2L200H / FBB676 / -6 |
| 约束时钟 | 27 MHz（period 37.037 ns） |
| 估计最高频率 | 38.36 MHz，setup slack **+10.971 ns**，0 failing |
| Hold（slow） | **+0.068 ns**，0 failing |
| Hold（fast） | −0.073 ns / 60 端点（边角，27 MHz 下余量 11 ns） |
| 资源 | CLMA 45%、LUT 25%、FF 12%、DRM 219.5/415（53%）、APM 8% |
| 生成工具 | PDS 2022.2-SP6.4（compile/synthesize -ads/dev_map/pnr/gen_bit_stream 全通过，0 error） |

## 下载

```powershell
# 1) JTAG 服务（常驻窗口）
D:\PDS_2022.2-SP6.4\bin\cdt_js.exe -port 65420

# 2) 下载（在仓库根目录执行）
D:\PDS_2022.2-SP6.4\bin\cdt_cfg.exe -file fpga\pango\program.tcl `
  -args {E:\qs\self_pro\bitstream\ares_p4_vision.sbit}
```

DONE 灯亮即成功；串口 115200 8N1。详细步骤、命令与排错见
[上板指南](../docs/board_guide.md)。

## 重新生成

```powershell
# 识别版（默认）
powershell -File tools\build_board.ps1 -Target vision
# CoreMark 版
powershell -File tools\build_board.ps1 -Target coremark -Iterations 1000 -UartDiv 234 -CpuHz 27000000
```

产物在 `build/pango/syn/generate_bitstream/ares_p4_board.sbit`，
需自行复制/改名为本目录的文件；一次完整流程约 1 小时（PnR 占绝大部分）。
