import CoreGraphics
import Foundation
import ImageIO
import StitchCore
import UIKit
import UniformTypeIdentifiers

/// 导入来源：Tab A 连续截图 / Tab B 相册选图
public enum ImportMode: String, Codable, Sendable {
    case screenshot
    case album
}

/// 单张切片（系统截图或相册图），缓存到 Library/Caches/Slices，用 UUID 命名。
public struct SliceItem: Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public var order: Int

    public init(id: UUID = UUID(), url: URL, order: Int) {
        self.id = id
        self.url = url
        self.order = order
    }

    /// 懒加载解码（仅在使用时驻留内存，符合内存红线）
    public func loadCGImage() -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    public func loadUIImage() -> UIImage? {
        guard let cg = loadCGImage() else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 历史记录：缩略图 + 拼接参数快照，点开可「按原参数重新拼」。
public struct HistoryRecord: Identifiable, Codable {
    public var id: UUID
    public var createdAt: Date
    public var thumbnailPNG: Data
    public var mode: ImportMode
    public var topCropRatio: Double
    public var bottomCropRatio: Double
    public var advisorEnabled: Bool
    public var sliced: Bool
    public var sliceCount: Int

    public init(id: UUID = UUID(), createdAt: Date = Date(), thumbnailPNG: Data,
                mode: ImportMode, topCropRatio: Double, bottomCropRatio: Double,
                advisorEnabled: Bool, sliced: Bool, sliceCount: Int) {
        self.id = id
        self.createdAt = createdAt
        self.thumbnailPNG = thumbnailPNG
        self.mode = mode
        self.topCropRatio = topCropRatio
        self.bottomCropRatio = bottomCropRatio
        self.advisorEnabled = advisorEnabled
        self.sliced = sliced
        self.sliceCount = sliceCount
    }
}

public typealias ExportFormat = StreamingComposer.OutputFormat
