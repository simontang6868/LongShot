import SwiftUI

/// LongShot —— 本地离线长截图拼接工具（手动定点截图 + 固定重叠硬拼，无自动对齐算法，零网络）。
@main
struct LongShotApp: App {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                ScreenshotImportView()
                    .tabItem { Label("截图拼", systemImage: "camera.viewfinder") }
                AlbumPickerView()
                    .tabItem { Label("相册拼", systemImage: "photo.stack") }
                HistoryView()
                    .tabItem { Label("历史", systemImage: "clock") }
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
            .environmentObject(settings)
            .environmentObject(history)
        }
    }
}
