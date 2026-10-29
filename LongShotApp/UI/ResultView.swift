import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UIKit

/// 结果页：导出格式（PNG/JPEG/HEIC/PDF）、切片开关、打码（矩形模糊）、保存相册、系统分享。
struct ResultView: View {
    let bundle: ExportBundle
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss

    @State private var annotateMode = false
    @State private var blurRects: [CGRect] = []
    @State private var slices: [UIImage] = []
    @State private var isSaving = false
    @State private var status: String?
    /// 本地镜像导出格式。
    /// 不能直接写 `.onChange(of: settings.exportFormat)`：OutputFormat 带关联值且未声明 Equatable，
    /// 不满足 onChange 要求的 Equatable 约束，会编译失败。改为监听这个 Hashable 的桥接类型。
    @State private var formatSel: ExportFormatRepresentable = .png

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if slices.isEmpty {
                    ProgressView("准备预览…")
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: slices[0])
                            .resizable().scaledToFit()
                            .overlay(annotationOverlay)
                            .contentShape(Rectangle())
                            .gesture(annotateTap)
                    }
                    if bundle.sliced && slices.count > 1 {
                        Text("已分片：共 \(slices.count) 张（超高自动切片）")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Form {
                    Picker("导出格式", selection: $formatSel) {
                        Text("PNG（文字锐利）").tag(ExportFormatRepresentable.png)
                        Text("JPEG").tag(ExportFormatRepresentable.jpeg)
                        Text("HEIC").tag(ExportFormatRepresentable.heic)
                        Text("PDF").tag(ExportFormatRepresentable.pdf)
                    }
                    Toggle("超高自动切片", isOn: $settings.sliceEnabled)
                    Toggle("打码模式（点图加模糊）", isOn: $annotateMode)
                    if !blurRects.isEmpty {
                        Button("清除打码") { blurRects.removeAll() }
                    }
                }
                .frame(height: 230)

                HStack {
                    Button { saveToPhotos() } label: { Label("存相册", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered)
                        .disabled(isSaving)
                    ShareLink(items: shareItems) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } }
            }
            .task { @MainActor in
                formatSel = ExportFormatRepresentable(settings.exportFormat)
                rebuildSlices()
            }
            .onChange(of: formatSel) { new in
                settings.exportFormat = new.format
            }
            .onChange(of: blurRects) { _ in rebuildSlices() }
        }
    }

    // MARK: 预览重建（应用打码）
    private func rebuildSlices() {
        let ciCtx = CIContext()
        slices = bundle.slicesData.compactMap { data -> UIImage? in
            guard let cg = CGImageSourceCreateWithData(data as CFData, nil)
                    .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { return nil }
            let blurred = blurRects.isEmpty ? cg : blurRegions(in: cg, normalized: blurRects, ciCtx: ciCtx)
            return UIImage(cgImage: blurred)
        }
    }

    // MARK: 打码
    private var annotationOverlay: some View {
        GeometryReader { geo in
            ForEach(Array(blurRects.enumerated()), id: \.offset) { _, r in
                Rectangle().fill(.black.opacity(0.001))
                    .frame(width: r.width * geo.size.width, height: r.height * geo.size.height)
                    .position(x: (r.minX + r.width / 2) * geo.size.width,
                              y: (r.minY + r.height / 2) * geo.size.height)
            }
        }
    }
    private var annotateTap: some Gesture {
        TapGesture().onEnded { _ in
            guard annotateMode else { return }
            // 在点击中心放一个固定尺寸模糊块（归一化坐标）
            blurRects.append(CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.1))
        }
    }

    // MARK: 保存/分享
    private func saveToPhotos() {
        isSaving = true
        let imgs = slices
        var i = 0
        for img in imgs {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            i += 1
        }
        isSaving = false
        status = "已保存到相册（\(imgs.count) 张）"
    }

    private var shareItems: [URL] {
        bundle.slicesData.compactMap { data -> URL? in
            // OutputFormat 未声明 Equatable，不能用 == .pdf，改用模式匹配
            let ext: String
            if case .pdf = settings.exportFormat { ext = "pdf" } else { ext = "png" }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try? data.write(to: url)
            return url
        }
    }

    // 打码：在归一化矩形区域做高斯模糊后贴回
    private func blurRegions(in cg: CGImage, normalized rects: [CGRect], ciCtx: CIContext) -> CGImage {
        // CIImage(cgImage:) 是非可选构造器，不能写 guard let
        let baseCI = CIImage(cgImage: cg)
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        for r in rects {
            let px = CGRect(x: r.minX * CGFloat(cg.width),
                            y: (1 - r.maxY) * CGFloat(cg.height),
                            width: r.width * CGFloat(cg.width),
                            height: r.height * CGFloat(cg.height))
            let region = baseCI.cropped(to: px)
            let f = CIFilter.gaussianBlur()
            f.inputImage = region
            f.radius = 14
            guard let out = f.outputImage,
                  let blurredCG = ciCtx.createCGImage(out, from: px) else { continue }
            ctx.draw(blurredCG, in: px)
        }
        return ctx.makeImage() ?? cg
    }
}

/// ExportFormat 的 Hashable 桥接，供 Picker 使用。
enum ExportFormatRepresentable: Hashable {
    case png, jpeg, heic, pdf
    init(_ f: ExportFormat) {
        switch f {
        case .png: self = .png
        case .jpeg: self = .jpeg
        case .heic: self = .heic
        case .pdf: self = .pdf
        }
    }
    var format: ExportFormat {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg(quality: 0.9)
        case .heic: return .heic(quality: 0.9)
        case .pdf: return .pdf
        }
    }
}
