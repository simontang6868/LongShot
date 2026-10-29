import CoreGraphics
import Foundation

/// 测试图生成：全部用 CoreGraphics 程序化绘制，不依赖任何外部图片文件。
enum TestImages {
    static func make(width: Int, height: Int, draw: (CGContext, Int, Int) -> Void) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, width, height)
        return ctx.makeImage()!
    }

    static func solid(width: Int, height: Int, _ c: (UInt8, UInt8, UInt8)) -> CGImage {
        make(width: width, height: height) { ctx, w, h in
            let col = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                              components: [CGFloat(c.0)/255, CGFloat(c.1)/255, CGFloat(c.2)/255, 1])!
            ctx.setFillColor(col)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    /// 每行亮度按正弦变化的内容图，rowMean 随行平滑变化，供重叠检测使用。
    static func content(width: Int, height: Int, phase: Double = 0, freq: Double = 0.2) -> CGImage {
        make(width: width, height: height) { ctx, w, h in
            for y in 0..<h {
                let v = 0.5 + 0.5 * sin((Double(y) + phase) * freq)
                let c = UInt8(clamp01(v) * 255)
                ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                         components: [CGFloat(c)/255, CGFloat(c)/255, CGFloat(c)/255, 1])!)
                ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
            }
        }
    }

    /// 用同一段内容构造 prev/next，next 相对 prev 下移 (1-overlap)*H 行，模拟用户留 overlap 重叠。
    static func overlapPair(width: Int, height: Int, overlap: CGFloat, freq: Double = 0.2) -> (prev: CGImage, next: CGImage) {
        let prev = content(width: width, height: height, freq: freq)
        let offset = Int((1 - overlap) * Double(height))
        let next = content(width: width, height: height, phase: Double(offset), freq: freq)
        return (prev, next)
    }
}

private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }
