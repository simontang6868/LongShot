import Foundation

/// 历史记录本地存储：一个 JSON 文件（App Documents 内），零网络、零云端。
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var records: [HistoryRecord] = []

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("history.json")
    }()

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    func append(_ record: HistoryRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func remove(_ id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
