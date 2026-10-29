import CoreGraphics
import Foundation

/// 接缝与边缘处理：羽化过渡、状态栏带裁切、横向黑/白边裁切。
/// 全部基于 CoreGraphics 像素读取，零依赖；任何检测「拿不准」时返回 0（不裁），
/// 交由上层回退到用户滑块值，绝不硬裁错（任务书第 3 节③）。
public struct SeamRenderer {

    /// 接缝羽化带高度，取 20~30px 中段（任务书要求 20~30px）
    public static let defaultFeatherHeight = 25
    public static let maxFeatherHeight = 30

    /// 状态栏/导航栏带检测：灰度归一化容差（0~1）。越小越严格。
    public static let statusBarTolerance: CGFloat = 0.05
    /// 单条状态栏带最多多裁这么多 pt（保守上限，防误裁）
    public static let maxStatusBarCrop: CGFloat = 60
    /// 顶部/底部探测带高度上限
    public static let statusBarScanBand: CGFloat = 160

    /// 横向黑/白边容差
    public static let edgeTolerance: CGFloat = 0.05
    /// 单条边最多裁这么多 pt
    public static let maxEdgeInset: CGFloat = 24

    public init() {}

    // MARK: - 接缝羽化（线性 alpha 渐变）

    /// 返回「顶部 featherHeight 像素从透明(0)渐变到不透明(1)、其余完全不透明」的蒙版。
    /// 用 CGImage.masking(_:) 作用在源图上：顶部半透明 → 露出底下上一张图，形成交叉淡化。
    private static func makeTopFeatherMask(width: Int, height: Int, featherHeight: Int) -> CGImage? {
        guard width > 0, height > 0, featherHeight > 0 else { return nil }
        let fh = min(featherHeight, height)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // 默认全白 = 完全显示当前图
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // 顶部 fh 像素：黑(0, 透明) → 白(1, 不透明)
        let grad = CGGradient(
            colorsSpace: cs,
            colors: [CGColor(gray: 0, alpha: 1) as CFTypeRef,
                     CGColor(gray: 1, alpha: 1) as CFTypeRef] as CFArray,
            locations: [0, 1]
        )
        ctx.drawLinearGradient(grad!, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: fh), options: [])
        return ctx.makeImage()
    }

    /// 给一张图施加「顶部羽化」，使其在拼接到上一张下方时接缝是交叉淡化而非硬切。
    /// 非顶部（如首图、或当前图不是接在另一张下面时）调用方应直接画原图。
    public func featheredTop(_ image: CGImage, featherHeight: Int = Self.defaultFeatherHeight) -> CGImage {
        let fh = min(max(featherHeight, 0), Self.maxFeatherHeight)
        guard fh > 0,
              let mask = Self.makeTopFeatherMask(width: image.width, height: image.height, featherHeight: fh),
              let masked = image.masking(mask) else {
            return image
        }
        return masked
    }

    // MARK: - 像素统计辅助

    /// 把图绘入 8-bit 灰度上下文，返回 (context, bytes, bytesPerRow)。bytes 只读。
    private func grayContext(_ image: CGImage) -> (ctx: CGContext, bytes: UnsafePointer<UInt8>, stride: Int)? {
        let w = image.width, h = image.height
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let stride = ctx.bytesPerRow
        guard let data = ctx.data else { return nil }
        // capacity 用真实 stride*h；ctx 必须与 bytes 同生命周期（调用方用 withExtendedLifetime 持有）
        let bytes = UnsafePointer<UInt8>(data.bindMemory(to: UInt8.self, capacity: stride * h))
        return (ctx: ctx, bytes: bytes, stride: stride)
    }

    /// 每行均值（0~1，灰度归一化），长度 = 高度
    private func rowMeans(_ image: CGImage) -> [CGFloat] {
        guard let gc = grayContext(image) else { return [] }
        return withExtendedLifetime(gc) {
            let bytes = gc.bytes, stride = gc.stride
            let h = image.height, w = image.width
            var out = [CGFloat](repeating: 0, count: h)
            for y in 0..<h {
                var sum: UInt64 = 0
                let base = y * stride
                for x in 0..<w { sum += UInt64(bytes[base + x]) }
                out[y] = CGFloat(sum) / CGFloat(w) / 255.0
            }
            return out
        }
    }

    /// 每列均值（0~1），长度 = 宽度
    private func colMeans(_ image: CGImage) -> [CGFloat] {
        guard let gc = grayContext(image) else { return [] }
        return withExtendedLifetime(gc) {
            let bytes = gc.bytes, stride = gc.stride
            let h = image.height, w = image.width
            var out = [CGFloat](repeating: 0, count: w)
            for x in 0..<w {
                var sum: UInt64 = 0
                for y in 0..<h { sum += UInt64(bytes[y * stride + x]) }
                out[x] = CGFloat(sum) / CGFloat(h) / 255.0
            }
            return out
        }
    }

    /// 从数组头部起，连续满足「与首值差 <= tol」的长度（封顶 maxLen）
    private func uniformPrefix(_ arr: [CGFloat], tol: CGFloat, maxLen: Int) -> Int {
        guard let first = arr.first else { return 0 }
        var len = 0
        for i in 0..<min(arr.count, maxLen) {
            if abs(arr[i] - first) <= tol { len = i + 1 } else { break }
        }
        return len
    }

    /// 从数组尾部起，连续满足「与尾值差 <= tol」的长度（封顶 maxLen）
    private func uniformSuffix(_ arr: [CGFloat], tol: CGFloat, maxLen: Int) -> Int {
        guard let last = arr.last else { return 0 }
        var len = 0
        for i in (0..<min(arr.count, maxLen)).reversed() {
            if abs(arr[i] - last) <= tol { len = (arr.count - i) } else { break }
        }
        return len
    }

    // MARK: - 状态栏 / 导航栏带检测（可选项，默认开）

    /// 检测顶部/底部是否存在「近乎纯色的固定高度带」（状态栏/导航栏/页脚），
    /// 返回建议额外多裁的顶部/底部 pt；检测不出返回 (0,0)，上层回退滑块值。
    public func statusBarCropInsets(for image: CGImage,
                                    maxCrop: CGFloat = Self.maxStatusBarCrop) -> (top: CGFloat, bottom: CGFloat) {
        let means = rowMeans(image)
        guard means.count > 4 else { return (0, 0) }
        let scan = min(Int(Self.statusBarScanBand), means.count)
        let topLen = min(uniformPrefix(means, tol: Self.statusBarTolerance, maxLen: scan), Int(maxCrop))
        let bottomLen = min(uniformSuffix(means, tol: Self.statusBarTolerance, maxLen: scan), Int(maxCrop))
        return (CGFloat(topLen), CGFloat(bottomLen))
    }

    // MARK: - 横向黑 / 白边检测（刘海遮挡、截图自带边框）

    /// 检测左右是否存在「近乎纯色的窄边带」，返回建议左/右内缩 pt；
    /// 检测不出或带宽超过 maxInset 时返回 (0,0)，避免误裁内容。
    public func horizontalEdgeInsets(for image: CGImage,
                                     maxInset: CGFloat = Self.maxEdgeInset) -> (left: CGFloat, right: CGFloat) {
        let means = colMeans(image)
        guard means.count > 4 else { return (0, 0) }
        let leftLen = min(uniformPrefix(means, tol: Self.edgeTolerance, maxLen: Int(maxInset)), Int(maxInset))
        let rightLen = min(uniformSuffix(means, tol: Self.edgeTolerance, maxLen: Int(maxInset)), Int(maxInset))
        return (CGFloat(leftLen), CGFloat(rightLen))
    }
}
