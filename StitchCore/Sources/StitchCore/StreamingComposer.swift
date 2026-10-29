import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// ===========================================================================
// StreamingComposer —— 拼接「执行」层（编排器，不碰具体 CG 绘制/编码）
//
// ⛔ 隔离红线 #1（建议与执行分离，编译期契约，见文件末尾协议 `CropDrivenStitching`）：
//   本文件【不得】import OverlapAdvisor，也【不得】调用 OverlapAdvisor 的任何
//   符号。拼接只消费 `CropParams` 的滑块值（topCropRatio / bottomCropRatio）。
//   “建议”（智能推荐）与“执行”（硬拼）彻底分离：OverlapAdvisor 只在上层
//   （StitchViewModel / EditorView）产生建议值并写回 CropParams；
//   StreamingComposer 永远不知道 OverlapAdvisor 的存在。
//
// ⛔ 隔离红线 #2（CGBackend 协议隔离）：
//   本文件【不得】直接调用任何 CoreGraphics 绘制/编码 API
//   （CGContext / CGContext.makeImage / CGImageDestination* / ctx.draw / ctx.fill 等）。
//   所有 CG 绘制与编码只允许出现在 CGBackend.swift（遵循 `StitchBackend` 协议）。
//   本编排器只通过 `backend: StitchBackend` 拿画布、画、取图、缩放、编码，
//   因此可以整体替换后端（如未来 Metal 后端），也可注入 Spy/Mock 后端做纯逻辑测试。
//   若有人在本文件里写 CGContext(...) 或 CGImageDestinationCreateWithData(...) ——
//   删掉，那是 CGBackend 的地盘，架构不允许。
// ===========================================================================

/// 流式合成器：逐张解码 → 裁 → 羽化 → 绘制，画完立即释放该张；
/// 输出长图，超长（> maxSingleHeight）按 ≤ sliceHeight 自动分片，内存峰值受控。
/// 分片写出：边画边开新的 CGImageDestination 编码，写完立即释放该片的
/// CGContext 与 CGImage，绝不把分片 CGImage 攒进数组（见 `Slice.data`）。
public struct StreamingComposer: CropDrivenStitching {

    public struct Options: Sendable {
        /// 相册混宽时缩放对齐到第一张宽度（系统截图路径应为 false，保持原分辨率）
        public var normalizeWidthToFirst: Bool
        /// 接缝羽化带高（px）
        public var featherHeight: Int
        /// 状态栏/导航栏带检测裁切（默认开）
        public var enableStatusBarCrop: Bool
        /// 横向黑/白边检测裁切（默认开）
        public var enableEdgeCrop: Bool
        /// 超过该高度触发切片（任务书默认 16000px）
        public var maxSingleHeight: Int
        /// 每片高度（任务书默认 8000px）
        public var sliceHeight: Int
        /// 分片写出时使用的编码格式（拼接执行层只管「按这个值编码」，不关心建议）
        public var outputFormat: OutputFormat
        /// 接缝底色（默认白，避免羽化透明处露黑）
        public var backgroundColor: CGColor

        public static let `default` = Options(
            normalizeWidthToFirst: false,
            featherHeight: SeamRenderer.defaultFeatherHeight,
            enableStatusBarCrop: true,
            enableEdgeCrop: true,
            maxSingleHeight: 16000,
            sliceHeight: 8000,
            outputFormat: .png,
            backgroundColor: CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                     components: [1, 1, 1, 1])!
        )
    }

    public enum OutputFormat: Sendable {
        case png
        case jpeg(quality: Double)
        case heic(quality: Double)
        case pdf

        /// 对应的 UTI（供 CGImageDestination 使用）
        public var utType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .heic: return .heic
            case .pdf: return .pdf
            }
        }
    }

    public enum ComposeError: Error, Sendable {
        case emptyInput
        case failedToDecode(index: Int)
        case failedToRender
        case encodingFailed(UTType)
    }

    /// 单个分片的编码结果。composer 边画边把该片编码成 `data`，
    /// 随即释放其 CGContext 与 CGImage —— 永不把分片 CGImage 攒进数组。
    public struct Slice: Sendable {
        /// 该片已编码的字节（默认 PNG，由 options.outputFormat 决定）
        public let data: Data
        public let width: Int
        public let height: Int
        public init(data: Data, width: Int, height: Int) {
            self.data = data; self.width = width; self.height = height
        }
    }

    public struct Output: Sendable {
        /// 各分片的编码结果（顺序即拼接顺序）。注意：这里存的是「编码后的 Data」，
        /// 不是 CGImage —— 分片 CGImage 在写出后立即释放，绝不累积。
        public let slices: [Slice]
        public let totalWidth: Int
        public let totalHeight: Int
        public let sliced: Bool
    }

    private let renderer: SeamRenderer
    /// CG 后端（默认 CGBackend）。编排层只通过此协议拿画布/编码，不碰具体 CG。
    private let backend: StitchBackend

    public init(renderer: SeamRenderer = SeamRenderer(), backend: StitchBackend = CGBackend()) {
        self.renderer = renderer
        self.backend = backend
    }

    // MARK: - 公开入口

    /// 便捷入口：调用方已持有全部 CGImage（小批量/测试用）。大批量请用 `compose(sources:)` 省内存。
    public func compose(images: [CGImage], crop: CropParams, options: Options = .default) throws -> Output {
        try compose(inputs: images.map { .cg($0) }, crop: crop, options: options)
    }

    /// 内存安全入口：逐张从 CGImageSource 解码，全程只驻留当前张 + 目标上下文。
    public func compose(sources: [CGImageSource], crop: CropParams, options: Options = .default) throws -> Output {
        try compose(inputs: sources.map { .source($0) }, crop: crop, options: options)
    }

    // MARK: - 核心

    private enum StitchInput {
        case cg(CGImage)
        case source(CGImageSource)
        func cgImage() -> CGImage? {
            switch self {
            case .cg(let i): return i
            case .source(let s): return CGImageSourceCreateImageAtIndex(s, 0, nil)
            }
        }
    }

    private func compose(inputs: [StitchInput], crop: CropParams, options: Options) throws -> Output {
        guard !inputs.isEmpty else { throw ComposeError.emptyInput }
        let count = inputs.count

        // 1) 规划：逐张解码算最终尺寸（算完立即释放），确定目标宽度与切片分组。
        var heights = [Int](repeating: 0, count: count)
        var widths = [Int](repeating: 0, count: count)
        for i in 0..<count {
            guard let img = inputs[i].cgImage() else { throw ComposeError.failedToDecode(index: i) }
            let processed = process(img, index: i, count: count, options: options)
            widths[i] = processed.width
            heights[i] = processed.height
        }
        let targetWidth = widths[0]

        // 2) 切片分组：连续图片累加到不超过 sliceHeight；单张超长则独占一片。
        var groups: [[Int]] = []
        var cur: [Int] = []
        var curH = 0
        for i in 0..<count {
            let h = heights[i]
            if cur.isEmpty {
                cur = [i]; curH = h
            } else if curH + h <= options.sliceHeight {
                cur.append(i); curH += h
            } else {
                groups.append(cur)
                cur = [i]; curH = h
            }
        }
        if !cur.isEmpty { groups.append(cur) }

        let totalHeight = heights.reduce(0, +)
        let sliced = groups.count > 1 || totalHeight > options.maxSingleHeight

        // 3) 绘制 + 分片写出：逐片向后端拿画布，逐张解码/裁/羽化/画；
        //    画完立即把该片编码（后端内部开新的 CGImageDestination），写完释放该片
        //    CGImage 与上下文，绝不把分片 CGImage 攒进数组。
        //   注意：本循环不直接调用任何 CG 绘制/编码 API —— 全部经 backend 协议。
        var slices: [Slice] = []
        slices.reserveCapacity(groups.count)
        var carry: CGImage? = nil  // 跨切片边界时，携带上片最后一张用于羽化（单张瞬态，非累积）

        for (gIdx, group) in groups.enumerated() {
            let sliceH = group.map { heights[$0] }.reduce(0, +)
            // 每个分片独立在 autoreleasepool 内完成：
            // 后端建画布 → 画 → finalize → 后端编码 → 该片图与画布随 pool 释放
            var sliceData: Data?
            var sliceError: Error?
            autoreleasepool {
                do {
                    guard let canvas = backend.makeCanvas(width: targetWidth, height: sliceH,
                                                         fill: options.backgroundColor) else {
                        throw ComposeError.failedToRender
                    }

                    var y = 0
                    for (localIdx, imgIndex) in group.enumerated() {
                        guard let img = inputs[imgIndex].cgImage() else { throw ComposeError.failedToDecode(index: imgIndex) }
                        let processed = process(img, index: imgIndex, count: count, options: options)
                        let piece = normalize(processed, toWidth: targetWidth, backend: backend)

                        if imgIndex == 0 {
                            canvas.draw(piece, at: 0, y: y)
                        } else {
                            // 跨切片边界：先画上片最后一张的底部羽化带（plain），再用本张羽化覆盖，形成交叉淡化
                            if localIdx == 0, let carried = carry {
                                let fh = min(options.featherHeight, carried.height, piece.height)
                                if fh > 0 {
                                    let carryBottom = crop(carried, rect: CGRect(x: 0, y: carried.height - fh, width: carried.width, height: fh))
                                    canvas.draw(carryBottom, at: 0, y: y)
                                }
                            }
                            let feathered = renderer.featheredTop(piece, featherHeight: options.featherHeight)
                            canvas.draw(feathered, at: 0, y: y)
                        }
                        y += piece.height
                        carry = processed
                    }

                    guard let sliceImg = canvas.finalize() else { throw ComposeError.failedToRender }
                    // 边画边写出：后端编码完成后该片 CGImage 与画布随 pool 释放
                    sliceData = backend.encode(sliceImg, format: options.outputFormat)
                } catch {
                    sliceError = error
                }
            }
            if let e = sliceError { throw e }
            guard let d = sliceData else { throw ComposeError.encodingFailed(options.outputFormat.utType) }
            slices.append(Slice(data: d, width: targetWidth, height: sliceH))
            // 非最后一片：carry 已在上循环末尾设为本片最后一张，供下一片边界羽化
            if gIdx == groups.count - 1 { carry = nil }
        }

        return Output(slices: slices, totalWidth: targetWidth, totalHeight: totalHeight, sliced: sliced)
    }

    // MARK: - 逐张处理

    /// 解码后的一张：依次做 黑边裁切 → 状态栏带裁切 → 重叠量裁切（首/末张单边）。
    private func process(_ img: CGImage, index: Int, count: Int, options: Options) -> CGImage {
        var cur = img
        if options.enableEdgeCrop {
            let ins = renderer.horizontalEdgeInsets(for: cur)
            if ins.left > 0 || ins.right > 0 {
                cur = crop(cur, rect: CGRect(x: ins.left, y: 0,
                                             width: cur.width - Int(ins.left) - Int(ins.right),
                                             height: cur.height))
            }
        }
        if options.enableStatusBarCrop {
            let ins = renderer.statusBarCropInsets(for: cur)
            if ins.top > 0 || ins.bottom > 0 {
                cur = crop(cur, rect: CGRect(x: 0, y: ins.top,
                                             width: cur.width,
                                             height: cur.height - Int(ins.top) - Int(ins.bottom)))
            }
        }
        let spec = crop.spec(forIndex: index, count: count)
        let r = spec.retainedRect(forSize: CGSize(width: cur.width, height: cur.height))
        return crop(cur, rect: r)
    }

    /// 宽度归一化：与 targetWidth 不一致时等比缩放（仅在混宽/相册路径发生）。
    /// 缩放交由后端（CGBackend）完成，编排层不直接调 CG。
    private func normalize(_ img: CGImage, toWidth targetWidth: Int, backend: StitchBackend) -> CGImage {
        if img.width == targetWidth { return img }
        let h = max(1, Int(round(CGFloat(img.height) * CGFloat(targetWidth) / CGFloat(img.width))))
        return backend.scaled(img, toWidth: targetWidth, height: h)
    }

    private func crop(_ img: CGImage, rect: CGRect) -> CGImage {
        let x = max(0, Int(rect.origin.x))
        let y = max(0, Int(rect.origin.y))
        let w = min(Int(rect.width), img.width - x)
        let h = min(Int(rect.height), img.height - y)
        guard w > 0, h > 0 else { return img }
        return img.cropping(to: CGRect(x: x, y: y, width: w, height: h)) ?? img
    }

    // MARK: - 编码输出

    /// 公开编码工具：委托给 CGBackend（CG 编码的真身在 CGBackend，不在本文件）。
    /// HEIC 在部分环境（模拟器）可能不可用 → 返回 nil（调用方降级提示）。
    public static func encode(_ image: CGImage, format: OutputFormat) -> Data? {
        CGBackend().encode(image, format: format)
    }
}

// ===========================================================================
// 协议隔离（编译期契约）：凡是遵循 `CropDrivenStitching` 的执行器，其公开接口
// 只允许接收 `CropParams`（执行参数），绝不允许接收 `OverlapAdvisor`（建议器）
// 类型。StreamingComposer 的 compose 签名里没有 OverlapAdvisor 的身影，
// 因此拼接路径在类型层面就无法调用任何推荐逻辑 —— 这才是「建议与执行彻底分离」
// 的硬保证，而非靠注释或约定。
// ===========================================================================
public protocol CropDrivenStitching {
    func compose(images: [CGImage], crop: CropParams, options: StreamingComposer.Options) throws -> StreamingComposer.Output
    func compose(sources: [CGImageSource], crop: CropParams, options: StreamingComposer.Options) throws -> StreamingComposer.Output
}

extension StreamingComposer: CropDrivenStitching {}
