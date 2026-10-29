import SwiftUI

/// iOS 16 兼容的空状态占位（ContentUnavailableView 仅 iOS 17+，故自建）。
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var description: String?

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
