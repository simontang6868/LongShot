import CoreGraphics
import Foundation
import StitchCore
import SwiftUI
import UIKit

/// 拼接编辑的核心状态机：管理切片列表、重叠量、智能推荐检查、实时预览、导出。
/// 预览在后台串行队列重算，主线程只收结果；防抖 200ms 防止滑块狂算（任务书第 4 节）。
@MainActor
final class StitchViewModel: ObservableObject {
    @Published var mode: ImportMode = .screenshot
    @Published var items: [SliceItem] = []
    @Published var crop: CropParams = .default
    @Published var advisorEnabled: Bool = true
    @Published var checkOverlap: Bool = true
    @Published var enableStatusBarCrop: Bool = true
    @Published var enableEdgeCrop: Bool = true

    @Published var previewImage: UIImage?
    @Published var isProcessing: Bool = false
    @Published var advisorMessages: [String] = []
    @Published var previewError: String?

    private var debounceTask: DispatchWorkItem?

    // MARK: - 导入

    /// 从 PHPicker 拿到的图片（我们只有副本，绝不接触用户相册原图）
    func addUIImages(_ imgs: [UIImage]) {
        let cgs = imgs.compactMap { $0.cgImage }
        addCGImages(cgs)
    }

    func addCGImages(_ imgs: [CGImage]) {
        var added: [SliceItem] = []
        for cg in imgs {
            if let url = CacheManager.save(cg) {
                added.append(SliceItem(url: url, order: items.count + added.count))
            }
        }
        items.append(contentsOf: added)
        schedulePreview()
        runAdvisorChecks()
    }

    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        recomputeOrder()
        schedulePreview()
    }

    func move(from: IndexSet, to: Int) {
        items.move(fromOffsets: from, toOffset: to)
        recomputeOrder()
        schedulePreview()
    }

    private func recomputeOrder() {
        for i in items.indices { items[i].order = i }
    }

    // MARK: - 预览（防抖 + 后台）

    func schedulePreview() {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.composePreview()
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    private func gatherCGImages() -> [CGImage] {
        items.compactMap { $0.loadCGImage() }
    }

    /// 重算预览：后台串行队列合成，主线程只收结果，不卡 UI。预览降到 360 宽省内存。
    private func composePreview() {
        guard !items.isEmpty else { previewImage = nil; return }
        guard let cgs = Optional(gatherCGImages()), !cgs.isEmpty else { return }
        isProcessing = true
        previewError = nil
        let crop = self.crop
        let sb = self.enableStatusBarCrop
        let ec = self.enableEdgeCrop
        let scaled = cgs.map { scaleToWidth($0, 360) }
        DispatchQueue.global(qos: .userInitiated).async {
            var opts = StreamingComposer.Options.default
            opts.enableStatusBarCrop = sb
            opts.enableEdgeCrop = ec
            opts.maxSingleHeight = Int.max
            opts.sliceHeight = Int.max
            let result: StreamingComposer.Output
            do {
                result = try StreamingComposer().compose(images: scaled, crop: crop, options: opts)
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.previewError = "预览合成失败"
                }
                return
            }
            if let first = result.slices.first, let img = UIImage(data: first.data) {
                DispatchQueue.main.async {
                    self.previewImage = img
                    self.isProcessing = false
                }
            } else {
                DispatchQueue.main.async { self.isProcessing = false }
            }
        }
    }

    // MARK: - 智能推荐检查（轻量，可关）

    /// 返回软性提示文案（不静默改参数，用户点「就这样拼」即尊重选择）。
    @discardableResult
    func runAdvisorChecks() -> [String] {
        guard advisorEnabled, checkOverlap else {
            advisorMessages = []
            return []
        }
        let cgs = gatherCGImages()
        let advisor = OverlapAdvisor(enabled: true)
        var msgs: [String] = []
        for i in 0..<(cgs.count - 1) {
            let prev = cgs[i], next = cgs[i + 1]
            if let rec = advisor.recommend(previous: prev, next: next) {
                let diff = abs(rec.inferredOverlap - CGFloat(crop.topCropRatio))
                if diff > 0.05 {
                    msgs.append("第 \(i + 1)、\(i + 2) 张看起来留得不太够，会跳段吗？可点智能推荐")
                }
            }
            if advisor.similarity(prev, next) > 0.95 {
                msgs.append("第 \(i + 1)、\(i + 2) 张好像重复了，要不要删一张？")
            }
            if advisor.widthRatio(prev, next) > 0.10 {
                msgs.append("这几张宽度不一致，会按第一张缩放哦")
            }
        }
        advisorMessages = msgs
        return msgs
    }

    /// 智能推荐：扫一遍填进滑块（仅建议，用户可再改）。
    func applyRecommended() {
        let cgs = gatherCGImages()
        guard cgs.count >= 2 else { return }
        let advisor = OverlapAdvisor(enabled: true)
        var sumTop = 0.0, sumBot = 0.0, n = 0
        for i in 0..<(cgs.count - 1) {
            if let rec = advisor.recommend(previous: cgs[i], next: cgs[i + 1]) {
                sumTop += Double(rec.recommendedTopCrop)
                sumBot += Double(rec.recommendedBottomCrop)
                n += 1
            }
        }
        guard n > 0 else { return }
        crop = CropParams(topCropRatio: CGFloat(sumTop / Double(n)),
                          bottomCropRatio: CGFloat(sumBot / Double(n)))
        schedulePreview()
        runAdvisorChecks()
    }

    // MARK: - 导出

    /// 真实导出：原分辨率，按设置切片/格式/裁切。返回各切片编码后的 Data。
    func exportSlices(format: ExportFormat, sliceEnabled: Bool, sliceHeight: Int) -> (data: [Data], sliced: Bool, width: Int, height: Int)? {
        guard let cgs = Optional(gatherCGImages()), !cgs.isEmpty else { return nil }
        var opts = StreamingComposer.Options.default
        opts.enableStatusBarCrop = enableStatusBarCrop
        opts.enableEdgeCrop = enableEdgeCrop
        opts.outputFormat = format
        if !sliceEnabled {
            opts.sliceHeight = Int.max
            opts.maxSingleHeight = Int.max
        } else {
            opts.sliceHeight = max(1000, sliceHeight)
        }
        let result: StreamingComposer.Output
        do {
            result = try StreamingComposer().compose(images: cgs, crop: crop, options: opts)
        } catch {
            previewError = "导出合成失败"
            return nil
        }
        let datas = result.slices.map { $0.data }
        guard !datas.isEmpty else {
            previewError = "编码失败（HEIC 在模拟器可能不可用，请改用 PNG/JPEG）"
            return nil
        }
        return (datas, result.sliced, result.totalWidth, result.totalHeight)
    }

    func thumbnailPNG() -> Data? {
        guard let cg = previewImage?.cgImage else { return nil }
        return StreamingComposer.encode(cg, format: .png)
    }

    // MARK: - 工具

    private func scaleToWidth(_ img: CGImage, _ w: Int) -> CGImage {
        let h = max(1, Int(round(CGFloat(img.height) * CGFloat(w) / CGFloat(img.width))))
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }
}
