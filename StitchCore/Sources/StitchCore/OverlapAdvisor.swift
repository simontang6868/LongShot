import CoreGraphics
import Foundation

/// 智能推荐重叠量：轻量校验的本体，**不是**对齐算法。
/// 只在 1D 行均值灰度信号上算，搜索窗口 ±8%，O(n) 很轻；
/// 结果只是「推荐值」，填进滑块让用户确认，不自动替用户决定（任务书第 3 节②）。
public struct OverlapAdvisor: Sendable {

    /// 是否启用（设置里全局开关，默认 true；拼接页右上角可本次覆盖）。关掉时直接跳过，零扫描开销。
    public var enabled: Bool
    /// 搜索窗口相对滑块值的浮动（默认 ±0.08）。实际扫描上界 = maxRatio + searchMargin。
    public var searchMargin: CGFloat
    /// 重叠量上限（硬约束 0.40）
    public var maxRatio: CGFloat

    public init(enabled: Bool = true,
                searchMargin: CGFloat = 0.08,
                maxRatio: CGFloat = CropParams.maxRatio) {
        self.enabled = enabled
        self.searchMargin = searchMargin
        self.maxRatio = maxRatio
    }

    // MARK: - 推荐

    /// 扫描相邻两张，反推应留多少重叠。
    /// - 返回 nil 表示「没扫出明确信号」（如纯色页脚导致差异处处都很小），调用方应回退滑块值。
    public func recommend(previous: CGImage, next: CGImage) -> OverlapRecommendation? {
        guard enabled else { return nil }
        let prevMeans = rowMeans(previous)
        let nextMeans = rowMeans(next)
        guard prevMeans.count > 4, nextMeans.count > 4 else { return nil }

        let hp = prevMeans.count
        let hn = nextMeans.count
        let h = min(hp, hn)
        let band = Int(CGFloat(h) * min(maxRatio + searchMargin, 0.6))
        guard band >= 2 else { return nil }

        var bestD = 1
        var bestDiff = Double.greatestFiniteMagnitude
        var worstDiff = 0.0

        // d = 假定的重叠行数。prev 尾部 d 行 vs next 头部 d 行逐行比对。
        for d in 1...min(band, h) {
            var sum = 0.0
            for t in 0..<d {
                let pv = prevMeans[hp - d + t]
                let nv = nextMeans[t]
                sum += abs(pv - nv)
            }
            let avg = sum / Double(d)
            worstDiff = max(worstDiff, avg)
            if avg < bestDiff {
                bestDiff = avg
                bestD = d
            }
        }

        // 置信度：最优与最差差异越大，信号越清晰
        let confidence = CGFloat(worstDiff > 1e-6 ? (worstDiff - bestDiff) / worstDiff : 0)
        guard confidence > 0.15 else { return nil }

        let inferred = min(CGFloat(bestD) / CGFloat(hp), maxRatio)
        return OverlapRecommendation(
            recommendedTopCrop: inferred,
            recommendedBottomCrop: inferred,
            confidence: confidence,
            inferredOverlap: inferred
        )
    }

    /// 相邻两张的相似度 0~1（1 表示几乎一模一样）。用于「好像重复了」提示（样本 5b）。
    public func similarity(_ a: CGImage, _ b: CGImage) -> CGFloat {
        let sa = resample(rowMeans(a), to: 64)
        let sb = resample(rowMeans(b), to: 64)
        guard sa.count == sb.count, !sa.isEmpty else { return 0 }
        var diff = 0.0
        for i in 0..<sa.count {
            diff += abs(sa[i] - sb[i])
        }
        let avg = diff / Double(sa.count)
        return CGFloat(max(0, min(1, 1 - avg)))
    }

    /// 两张宽度差异比例 0~1（|wa-wb|/max）。> 0.10 触发「宽度不一致」提示（样本 5c）。
    public func widthRatio(_ a: CGImage, _ b: CGImage) -> CGFloat {
        let wa = CGFloat(a.width), wb = CGFloat(b.width)
        let m = max(wa, wb)
        guard m > 0 else { return 0 }
        return abs(wa - wb) / m
    }

    // MARK: - 内部像素工具（与 SeamRenderer 解耦，独立 1D 行均值）

    private func rowMeans(_ image: CGImage) -> [CGFloat] {
        let w = image.width, h = image.height
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let stride = ctx.bytesPerRow
        return withExtendedLifetime(ctx) {
            guard let data = ctx.data else { return [] }
            let bytes = data.bindMemory(to: UInt8.self, capacity: stride * h)
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

    private func resample(_ arr: [CGFloat], to n: Int) -> [CGFloat] {
        guard arr.count > 0, n > 0 else { return [] }
        guard arr.count != n else { return arr }
        var out = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            let idx = Int((CGFloat(i) / CGFloat(n)) * CGFloat(arr.count))
            out[i] = arr[min(idx, arr.count - 1)]
        }
        return out
    }
}

/// 推荐结果。recommendedTopCrop / recommendedBottomCrop 直接喂给滑块初值（用户可改）。
public struct OverlapRecommendation: Sendable {
    public let recommendedTopCrop: CGFloat
    public let recommendedBottomCrop: CGFloat
    /// 信号置信度 0~1
    public let confidence: CGFloat
    /// 推断出的重叠比例
    public let inferredOverlap: CGFloat
}
