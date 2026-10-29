# LongShot —— 本地离线长截图拼接工具

手动定点截图 + **固定重叠硬拼**，没有自动对齐算法；全程离线、零网络、无水印、0 服务费。
iOS 16+，Swift / SwiftUI。

## 功能

- **Tab A 连续截图拼（主打）**：用户自己用系统截图（侧边+音量上）→ 在 App 内用 PHPicker 导入刚截的几张 → 按重叠量拼。
- **Tab B 相册选图拼**：PHPicker 多选，顺序即拼接顺序，进入同一编辑页。
- 顶部/底部重叠量滑块（默认 15%/15%，可调 0~40%），实时预览（防抖 200ms、后台串行队列）。
- 「智能推荐」：1D 行灰度轻扫，反推应留多少重叠，只作建议、可关。
- 接缝羽化、状态栏带/黑边检测裁切（均可关）。
- 超长图（>16000px）自动切片（默认每片 8000px，可关），系统分享 / 存相册 / 存文件。
- 导出 PNG / JPEG / HEIC / PDF 四选一。
- 历史记录、设置（重叠量、推荐开关、接缝处理、导出、切片）。

## 构建步骤（在 Mac 上）

1. 用 **Xcode 26** 新建一个 **iOS App**（Interface: SwiftUI，Language: Swift），最低部署 **iOS 16.0**，包名随意（如 `LongShot`）。
2. 把 `StitchCore/` 作为**本地 Swift Package** 加入工程：
   - Xcode → File → Add Packages → 选 `LongShot/StitchCore/` 目录 → Add。
   - 在 App target 的 **Frameworks, Libraries…** 里勾选 `StitchCore`。
3. 把 `LongShotApp/` 下的所有 `.swift`（Models / ViewModels / Pickers / UI / LongShotApp.swift）拖进 App target（保持文件夹分组）。
4. Signing 用你的**免费开发者账号**即可（无月费、无后端）。
5. 选一台 **iOS 16+ 真机**（或模拟器）运行。

> 不需要写任何 `.xcodeproj` 手工配置；以上为标准 Xcode 工作流。

## 跑 StitchCore 单测

在 `StitchCore/` 目录：

```bash
cd StitchCore
swift test          # 需要 macOS 13+ 宿主；用例用 CoreGraphics 程序化生成测试图，无外部依赖
```

覆盖：裁切参数边界、羽化、流式写出、超高自动切片、以及任务书第 7 节 5 个样本的「智能推荐」推荐值快照。

## 零网络复验（交付硬指标）

1. **静态检索**：全仓 `grep` 确认无 `URLSession / NSURL / URLRequest / URL(string` 及任何网络框架 import。
   ```bash
   grep -rnE "URLSession|NSURL|URLRequest" LongShotApp StitchCore || echo "NO NETWORK API"
   ```
2. **隐私清单**：`PrivacyInfo.xcprivacy` 不写任何网络/跟踪描述。
3. **Info.plist**：不声明 `NSAppTransportSecurity` 例外、不声明后台模式。
4. **动态抓包**：Charles / Proxyman 开代理，把「导入 → 拼接 → 5 个样本 → 导出 → 分享」全部跑一遍，**抓包为空**才算过。

## 明确不做（别让 AI 编功能）

- 不录屏、不抽帧、不帮用户自动滚动别的 App 界面（滚动永远靠用户手指 + 系统截图）。
- 不做自动对齐算法、不接 NCC / 特征匹配 / 视觉模型（v2 候选，v1 不做）。
- 不上服务器、不联网、不埋点、不接任何云端 SDK → 无账号、无云同步、无协作、无在线模板。
- 不偷偷删用户相册里的任何东西：只写入，不删除用户原图。
- 超长内容（>16000px）默认切片是平台分享限制，不是能力缺陷。

详见 `PRD.md`（任务书精简）与 `DECISIONS.md`（技术选型与实测数据）。
