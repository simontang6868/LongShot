import SwiftUI

/// iOS 16 兼容的空状态占位（ContentUnavailableView 仅 iOS 17+，故自建）。
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var description: String?

    /// 首位参数不带标签的便捷构造器。
    /// 合成 memberwise init 会强制 `title:` 标签，四个调用点都是 `EmptyStateView("...", systemImage:)`，
    /// 不补这个 init 会四个地方一起编译失败。
    init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let description {
                Text(description).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
