import CoreGraphics
import Foundation

/// 重叠量模型：每张图裁掉顶部 `cropTop`、底部 `cropBottom`（占高度比例），
/// 中间那段贴到上一张下方。这是「固定重叠硬拼」的唯一参数来源，不含任何对齐算法。
public struct CropParams: Sendable, Equatable {
    /// 顶部裁切比例，范围 [0, 0.40]
    public var topCropRatio: CGFloat
    /// 底部裁切比例，范围 [0, 0.40]
    public var bottomCropRatio: CGFloat

    /// 默认 15% / 15%（任务书硬约束，不准改默认值）
    public static let `default` = CropParams(topCropRatio: 0.15, bottomCropRatio: 0.15)

    /// 可调范围边界（硬约束 0~0.40）
    public static let minRatio: CGFloat = 0.0
    public static let maxRatio: CGFloat = 0.40

    /// 剩图高度低于该值视为「重叠太多」，UI 应禁用滑块并 toast（任务书第 3 节①）
    public static let minRemainingHeight: CGFloat = 100

    public init(topCropRatio: CGFloat, bottomCropRatio: CGFloat) {
        self.topCropRatio = CropParams.clamp(ratio: topCropRatio)
        self.bottomCropRatio = CropParams.clamp(ratio: bottomCropRatio)
    }

    /// 把任意比例夹到 [minRatio, maxRatio]
    public static func clamp(ratio: CGFloat) -> CGFloat {
        if ratio.isNaN || ratio.isInfinite { return 0 }
        return min(max(ratio, minRatio), maxRatio)
    }

    /// 裁切规格：对第 `index`（0-based）张，共 `count` 张。
    /// 第 1 张只裁底部（留住状态栏/标题）；最后 1 张只裁顶部（留住页脚）；中间张上下都裁。
    public func spec(forIndex index: Int, count: Int) -> CropSpec {
        precondition(count > 0, "count 必须 > 0")
        precondition(index >= 0 && index < count, "index 越界")
        let isFirst = index == 0
        let isLast = index == count - 1
        return CropSpec(
            cropTop: isFirst ? 0 : topCropRatio,
            cropBottom: isLast ? 0 : bottomCropRatio
        )
    }

    /// 校验单张图裁完后剩余高度是否 >= minRemaining。
    /// 若不足，按等比例收缩 top/bottom 使剩余恰为 minRemaining，并返回 adjusted=true。
    public func validated(forImageHeight height: CGFloat,
                          minRemaining: CGFloat = CropParams.minRemainingHeight) -> (params: CropParams, adjusted: Bool) {
        guard height > 0 else { return (self, false) }
        let remaining = height * (1 - topCropRatio - bottomCropRatio)
        if remaining >= minRemaining { return (self, false) }

        // 收缩到刚好剩 minRemaining：removed = 1 - minRemaining/height
        let targetRemoved = 1 - min(minRemaining / height, 1)
        let total = topCropRatio + bottomCropRatio
        if total <= 0 {
            // 极端：原图本身就比 minRemaining 还矮，无法裁出内容，返回不改
            return (self, false)
        }
        let scale = targetRemoved / total
        let newTop = CropParams.clamp(ratio: topCropRatio * scale)
        let newBottom = CropParams.clamp(ratio: bottomCropRatio * scale)
        return (CropParams(topCropRatio: newTop, bottomCropRatio: newBottom), true)
    }
}

/// 单张图的具体裁切规格（比例已转为「该裁多少」）
public struct CropSpec: Sendable, Equatable {
    /// 顶部裁掉的比例 0..1
    public let cropTop: CGFloat
    /// 底部裁掉的比例 0..1
    public let cropBottom: CGFloat

    public init(cropTop: CGFloat, cropBottom: CGFloat) {
        self.cropTop = CropSpec.clamp(cropTop)
        self.cropBottom = CropSpec.clamp(cropBottom)
    }

    private static func clamp(_ v: CGFloat) -> CGFloat {
        if v.isNaN || v.isInfinite || v < 0 { return 0 }
        return min(v, 1)
    }

    /// 在给定尺寸下，返回「保留区域」的 CGRect（坐标系同 CGImage：原点左上，y 向下）
    public func retainedRect(forSize size: CGSize) -> CGRect {
        let topPx = floor(size.height * cropTop)
        let bottomPx = floor(size.height * cropBottom)
        let kept = size.height - topPx - bottomPx
        return CGRect(x: 0, y: topPx, width: size.width, height: max(kept, 0))
    }

    /// 保留后的高度（点）
    public func retainedHeight(forHeight height: CGFloat) -> CGFloat {
        max(height * (1 - cropTop - cropBottom), 0)
    }
}
