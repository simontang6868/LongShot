import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// ===========================================================================
// CGBackend —— CoreGraphics 后端（本模块中【唯一】允许出现 CG 绘制/编码的地方）
//
// ⛔ 隔离红线（与 StreamingComposer 头部的红线互为补充）：
//   所有 CoreGraphics 的「建上下文 / 绘制 / 取图 / 缩放 / 编码」只允许出现在
//   本文件。StreamingComposer（执行编排层）只通过 `StitchBackend` 协议拿画布、
//   画、取图、缩放、编码，永远不直接调用 CGContext / CGImageDestination。
//   这样 CG 后端可被整体替换（如未来 Metal 后端），也便于注入 Mock/Spy 后端做
//   纯逻辑测试 —— 这正是「CGBackend 协议隔离」的硬保证。
// ===========================================================================

/// 一张可绘制的画布抽象（包裹 CGContext，向编排层隐藏 CG 细节）。
public protocol BackendCanvas {
    var width: Int { get }
    var height: Int { get }
    /// 在 (x, y) 处绘制整张图（尺寸以图自身为准）。
    func draw(_ image: CGImage, at x: Int, y: Int)
    /// 取合成结果图（等价于 CGContext.makeImage()）。
    func finalize() -> CGImage?
}

/// 拼接后端协议：把「建画布 / 缩放 / 编码」三类 CG 能力抽象出来。
/// StreamingComposer 只认这个协议，不认任何 CoreGraphics 具体类型。
public protocol StitchBackend {
    /// 创建一块填充了底色的可绘制画布。
    func makeCanvas(width: Int, height: Int, fill: CGColor) -> BackendCanvas?
    /// 等比缩放到指定宽高（混宽归一用）。
    func scaled(_ image: CGImage, toWidth width: Int, height: Int) -> CGImage
    /// 把合成结果编码为给定格式（PNG/JPEG/HEIC/PDF），失败返回 nil。
    func encode(_ image: CGImage, format: StreamingComposer.OutputFormat) -> Data?
}

/// CoreGraphics 实现：所有 CG 绘制/编码的真身都在这里。
public struct CGBackend: StitchBackend {
    public init() {}

    public func makeCanvas(width: Int, height: Int, fill: CGColor) -> BackendCanvas? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(fill)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return CGCanvas(ctx: ctx, width: width, height: height)
    }

    public func scaled(_ image: CGImage, toWidth width: Int, height: Int) -> CGImage {
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    public func encode(_ image: CGImage, format: StreamingComposer.OutputFormat) -> Data? {
        let ut = format.utType
        var options: CFDictionary = [:] as CFDictionary
        switch format {
        case .png: break
        case .jpeg(let q):
            options = [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary
        case .heic(let q):
            options = [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary
        case .pdf: break
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, ut.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, options)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

/// CG 画布的具体实现（私有，仅本文件可见）。
private struct CGCanvas: BackendCanvas {
    let ctx: CGContext
    let width: Int
    let height: Int
    func draw(_ image: CGImage, at x: Int, y: Int) {
        ctx.draw(image, in: CGRect(x: x, y: y, width: image.width, height: image.height))
    }
    func finalize() -> CGImage? { ctx.makeImage() }
}
