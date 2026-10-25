# ARES-P4 板上图像识别 demo（CPU 版）

不依赖 miniTensor、不依赖摄像头，先在没有加速器的情况下把
**"图像进 → 特征 → 分类 → 串口输出"** 这条链子在板上跑通。

## 输入 / 输出

- 输入：32×32 灰度帧，1024 字节，行优先，0=背景，255=形状
- 输出：类别名、距离、置信度、分类耗时（cycles / µs），以及 16×16 ASCII 预览
- 类别：`circle` / `square` / `triangle` / `cross` / `ring`

## 算法（全部定点，无浮点、无查表大权重）

1. **阈值**：取帧内 min/max 的中点；min/max 差 < 24 视为空帧
2. **归一化**：取前景包围盒，按较长边缩放到 24 px，居中画到 32×32 画布
3. **降采样**：2×2 盒式平均 → 16×16 = 256 维
4. **特征**：减均值 → 按 sum|v| 归一化到 256（等价于 L1 归一化）
5. **分类**：与 5 个原型算 L1 距离，取最小；距离 > 150 判为 UNKNOWN

原型在启动时由同一套渲染函数生成（`vision_init_prototypes`），所以固件里
没有大块权重表，flash/BRAM 占用很小。

离线用 `tools/_sim_vision.py` 对同一算法做了等价验证：
5 类 × 4 种变体（干净 / 加噪 / 平移 / 缩放）**20/20 全对**，同类最差距离 40，
异类最小距离 ~90，阈值 150 有余量。

## 串口协议

| 方向 | 内容 |
|---|---|
| PC → 板 | `u`（0x75）请求上传 |
| 板 → PC | `ready for 1024 bytes (32x32 raw)` |
| PC → 板 | 1024 字节原始帧（无包头、无校验） |
| 板 → PC | 16 行 ASCII 预览 + `result: <class> distance <d> confidence <p>%` + `classify took <n> cycles` |

其它命令：`d` 自检、`a` 重显上一帧、`m` 菜单。

## 构建

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_win.ps1 -Target vision -UartDiv 234 -CpuHz 27000000
```

产物：`build_win\vision\vision.elf/bin/hex`（约 15.6 KB）。

## 已知限制

- 这是**静态图片**识别（照片/截图/手绘形状拍平后上传），不是视频流；
  摄像头链路见 `docs/board_guide_vision.md` 第 8 节。
- 5 类几何形状是"可解释的最小闭环"，用来验证数据通路；
  换成人脸/数字/物体需要换特征或上 miniTensor，接口不变。
