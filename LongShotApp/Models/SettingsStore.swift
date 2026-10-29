import Foundation
import SwiftUI
import StitchCore

/// 全局设置 + 持久化（UserDefaults）。三条硬约束的默认值/开关都落在这里。
/// - 重叠量默认 15%/15%（不准改默认值，仅允许用户调整 0~0.40）
/// - 智能推荐默认开、可关
/// - 输出格式、切片开关等
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("topCropRatio") var topCropRatio: Double = 0.15
    @AppStorage("bottomCropRatio") var bottomCropRatio: Double = 0.15
    @AppStorage("advisorEnabled") var advisorEnabled: Bool = true
    @AppStorage("checkOverlapBeforeStitch") var checkOverlapBeforeStitch: Bool = true
    @AppStorage("enableStatusBarCrop") var enableStatusBarCrop: Bool = true
    @AppStorage("enableEdgeCrop") var enableEdgeCrop: Bool = true
    @AppStorage("keepOriginals") var keepOriginals: Bool = false
    @AppStorage("exportFormatRaw") var exportFormatRaw: String = "png"
    @AppStorage("sliceEnabled") var sliceEnabled: Bool = true
    @AppStorage("sliceHeight") var sliceHeight: Int = 8000

    var cropParams: CropParams {
        get { CropParams(topCropRatio: CGFloat(topCropRatio), bottomCropRatio: CGFloat(bottomCropRatio)) }
        set {
            topCropRatio = Double(CropParams.clamp(ratio: newValue.topCropRatio))
            bottomCropRatio = Double(CropParams.clamp(ratio: newValue.bottomCropRatio))
        }
    }

    var exportFormat: ExportFormat {
        get {
            switch exportFormatRaw {
            case "jpeg": return .jpeg(quality: 0.9)
            case "heic": return .heic(quality: 0.9)
            case "pdf": return .pdf
            default: return .png
            }
        }
        set {
            switch newValue {
            case .png: exportFormatRaw = "png"
            case .jpeg: exportFormatRaw = "jpeg"
            case .heic: exportFormatRaw = "heic"
            case .pdf: exportFormatRaw = "pdf"
            }
        }
    }

    /// 把当前 UI 滑块值（已 clamp）同步进持久化
    func syncCrop(_ p: CropParams) { cropParams = p }
}
