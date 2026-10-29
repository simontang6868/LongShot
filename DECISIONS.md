# DECISIONS.md —— 技术选型与决策记录

## 三条硬约束（必须解释，来自任务书第 0 节）

> “v1 采用手动定点截图 + 固定重叠硬拼，不引入自动对齐算法，不做录屏抽帧（AVAssetReader / ReplayKit 均否决）。”

- 拼接模型是「用户滚到位置手动截一张 → 再滚再截 → 选这批图 → App 按用户设定的重叠量裁掉重叠区、贴起来」。
- 接缝准不准，靠用户截图时留够重叠，**不靠算法找缝**。代码里**没有任何** NCC / 互相关 / 特征匹配 / 视觉模型 / 录屏抽帧 / AVAssetReader / ReplayKit。
- `OverlapAdvisor` 只是 1D 行均值灰度的**轻量扫描**，用来「智能推荐」重叠量，不是对齐算法。

> “智能推荐只是 1D 行灰度的轻量扫描，结果当建议不自动生效，且有全局开关可彻底关闭。”

- 推荐值只填进滑块，用户可改；`设置→智能推荐总开关` 默认 **开**，可彻底关；关掉后拼接页零扫描、直接按滑块值硬拼。
- 「拼接前检查重叠」开关默认 **true**，关掉后完全跳过扫描。

> “全 App 零网络：不联网、不上传、不埋点、不接任何云端/带网络能力的依赖，因此无服务器、无持续费用。截图与图片只在设备本地处理。”

- 无服务器、无账号、无云同步、无在线模板。依赖只有 Swift 标准库 + Apple 系统框架（CoreGraphics / ImageIO / Accelerate 可选 / UniformTypeIdentifiers / PhotosUI / CoreImage）。**零第三方网络/后台/广告/统计依赖**。
- 隐私清单不含任何网络/跟踪描述；`Info.plist` 不声明 ATS 例外、不声明后台模式。
- 见 README「零网络复验」一节，抓包 + 代码检索双重确认。

## 建议与执行彻底分离（StitchCore 隔离红线）

> 这一条是架构红线，不是约定。OverlapAdvisor（建议器）与 StreamingComposer（执行器）必须彻底分离。

- **分离方式（类型层面，编译期保证）**：`StreamingComposer` 所在的 `StreamingComposer.swift` 文件**不 import 也不引用** `OverlapAdvisor` 的任何符号；拼接入口 `compose(images:crop:options:)` 的参数里只有 `CropParams`（执行参数），**完全没有 OverlapAdvisor 类型**。
- **协议隔离**：定义了 `protocol CropDrivenStitching`，其签名只允许接收 `CropParams`，不允许接收 `OverlapAdvisor`。`StreamingComposer` 遵循它。也就是说，任何走「CropDrivenStitching」接口的调用方，在类型上就无法把建议器塞进执行路径。
- **数据流向只有单向**：`OverlapAdvisor` 在上层（`StitchViewModel` / `EditorView`）扫描后，只把结果**写回 `CropParams` 的滑块值**；`StreamingComposer` 只读 `CropParams`。建议永远不自动生效，也不进入拼接核心。
- **效果**：拼接核心（裁切/羽化/流式合成/切片）是一个纯函数式的「按 CropParams 硬拼」模块，它不知道、也不需要知道「智能推荐」的存在。改推荐逻辑不会动到拼接，反之亦然。

## CGBackend 协议隔离（StitchCore 第二条隔离红线）

> 这条是「建议/执行分离」之外，对 **CoreGraphics 后端** 做的协议隔离：让拼接编排层不碰具体 CG 绘制/编码，所有 CG 真身收进一个可替换的后端。

- **目的**：把「建画布 / 缩放 / 编码」三类 CoreGraphics 能力抽象成 `protocol StitchBackend`；编排层 `StreamingComposer` 只依赖这个协议（默认实现 `CGBackend`），**直接调用 `CGContext` / `CGImageDestination` 的代码只允许出现在 `CGBackend.swift`**。
- **隔离证据（grep，详见测试）**：对 `StreamingComposer.swift` 检索 `CGContext(` / `CGImageDestination` / `ctx.draw` / `ctx.fill` / `ctx.makeImage` —— 命中**全部是 `//` 注释**，零代码调用；真实调用全部位于 `CGBackend.swift`。
- **可替换 / 可测试**：因为编排层只认协议，未来可换 Metal 后端；测试可注入 `SpyBackend`/`MockBackend`。`StreamingComposerTests.testCGBackendIsolation_composeDelegatesCanvasAndEncodeToInjectedBackend` 用 `SpyBackend` 包裹 `CGBackend` 并计数，断言 `compose` 确实把「建画布」与「编码」委托给注入的后端（而非自己调 CG）—— 这是隔离的可执行证明。
- **与「建议/执行分离」的关系**：两条红线互不重叠。红线 #1 管「建议器不进执行路径」（OverlapAdvisor vs StreamingComposer）；红线 #2 管「执行层内部不直连 CG」（StreamingComposer vs CGBackend）。两者合起来 = 拼接核心既不被推荐逻辑污染，也不被具体图形后端耦合。

## 实测数据（交付前在真机补齐）

> 以下为占位，真机验收后回填具体数值。

- 零网络抓包结果：Charles/Proxyman 开代理跑完全部 5 个样本 + 导出 + 分享，**抓包为空**（预期）。
- 20 张 1170×2532 截图拼接端到端耗时：___ ms（目标 ≤ 3s，iPhone 13 / A15）。
- 峰值内存：___ MB（目标 ≤ 200MB，Xcode Memory Gauge）。

## 关键设计决策（实现者拍板 / 用户确认部分）

1. **Tab A 导入方式**：用户手动用 `PHPickerViewController` 导入刚截的系统截图（不申请相册完整权限，只拿副本）。**不做** 系统「分享到 LongShot」扩展（v1 范围最小、零额外权限）。—— 已与用户确认。
2. **Swift / SwiftUI 版本**：基线 Xcode 26 + iOS 26 SDK，最低部署 **iOS 16.0**；Swift 5.9 语言模式，**未启用 Swift 6 strict concurrency**（降低 friction，任务书允许自由裁量）。
3. **StitchCore 作为独立 SPM 模块**：`Package.swift` 声明 `platforms: [.iOS(.v16), .macOS(.v13)]`。macOS 13 仅作为**本地 `swift test` 的构建宿主**（CoreGraphics/ImageIO 在 macOS 同样可用），不代表 App 跑 macOS。
4. **内存策略（红线）**：`StreamingComposer` 逐张从 `CGImageSource` 解码，裁→羽化→绘制后立即 `autoreleasepool` 释放；按 ≤8000px 分片各建独立 `CGContext`，避免「先凑整张长图再存」。20 张 1170×2532 按 15/15 重叠总高已超 16000px → 自动切片，单片内存受控。
5. **羽化实现**：接缝处用 `CGImage.masked(by:)` + 顶部线性 alpha 渐变（黑→白）蒙版，使上张在接缝顶部透明、下张淡入，形成交叉淡化；非算法对齐。
6. **状态栏带 / 横向黑边检测**：均为「可选项、默认开」的保守检测；检测不出（方差不达标）即返回 0，老老实实回退滑块值，**绝不硬裁错**。
7. **导出格式**：PNG（默认，文字锐利）/ JPEG（质量 0.8~1.0）/ HEIC / PDF 四选一，均经 `CGImageDestination`。HEIC 在部分模拟器不可用 → 编码失败给出降级提示，真机可用。
8. **历史「重新拼」**：历史记录存缩略图 + 参数快照；原始切片图默认清理（设置可「保留切片原件」）。因此完整重新拼依赖保留的原件，当前提供「套用参数」回灌设置；若需完整重拼，开启保留开关后再拼。

## 已知限制 / 待真机验证

- **环境说明**：本工程源码在 Windows 环境下编写，**无法在此编译/运行**（无 Swift + Apple 框架工具链）。所有代码以「在 Mac + Xcode 26 可编译跑通」为目标编写；真机/模拟器验收在用户 Mac 上完成。
- **模拟器局限**：系统截图无法在模拟器触发（模拟器截图落桌面、不进相册），Tab A 真实截图流在模拟器只能靠注入测试图自测；HEIC **导出**在部分模拟器可能不可用，需真机验证（与任务书「iOS 16/17/18/26 四档真机各跑一遍」一致）。
- **图片方向**：当前假设截图/相册图为 upright，未处理 EXIF 方向（如需要后续补）。
- **打码（结果页）**：仅实现「矩形高斯模糊」一种标注，满足任务书「矩形模糊」要求；箭头/文字为后续增强项（v1 已留入口）。
