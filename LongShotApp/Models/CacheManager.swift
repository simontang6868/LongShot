import Foundation
import StitchCore

/// 切片缓存管理：存到 Library/Caches/Slices（不在 tmp，避免被系统随时清掉），UUID 命名。
/// 拼完导出后可一键清理；设置里「保留切片原件」默认关。绝不删除用户相册原图。
enum CacheManager {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Slices", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 把一张解码后的图以 PNG 写入缓存，返回 URL。返回 nil 表示写入失败。
    static func save(_ cg: CGImage, id: UUID = UUID()) -> URL? {
        let url = directory.appendingPathComponent("\(id.uuidString).png")
        guard let data = StreamingComposer.encode(cg, format: .png) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// 把外部（PHPicker 拿到）的图片文件复制进缓存，返回新 URL。
    static func importExternal(_ source: URL, id: UUID = UUID()) -> URL? {
        let dest = directory.appendingPathComponent("\(id.uuidString).\(source.pathExtension.lowercased())")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    /// 一键清理切片缓存（保留开关为关时的默认行为）
    static func clearAll() {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: directory,
                                                    includingPropertiesForKeys: nil)) ?? []
        for f in contents {
            try? fm.removeItem(at: f)
        }
    }

    static func clear(_ urls: [URL]) {
        let fm = FileManager.default
        for u in urls where u.path.hasPrefix(directory.path) {
            try? fm.removeItem(at: u)
        }
    }
}
