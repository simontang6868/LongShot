import CoreGraphics
import SwiftUI
import StitchCore
import UIKit

/// 拼接编辑页：缩略条拖拽调序/删除、顶部/底部重叠量滑块、智能推荐、实时预览、导出。
struct EditorView: View {
    let mode: ImportMode
    let images: [UIImage]

    @EnvironmentObject var settings: SettingsStore
    @StateObject private var vm: StitchViewModel

    @State private var showToast = false
    @State private var toastMsg = ""
    @State private var editMode: EditMode = .inactive
    @State private var showResult = false
    @State private var exportResult: ExportBundle?

    /// 必须标 @MainActor：init 里要构造 StitchViewModel 并读写 SettingsStore，
    /// 两者都是 @MainActor 隔离的；View 的合成 init 默认是 nonisolated，会直接编译报错。
    @MainActor
    init(mode: ImportMode, images: [UIImage]) {
        self.mode = mode
        self.images = images
        let v = StitchViewModel()
        v.mode = mode
        v.advisorEnabled = SettingsStore.shared.advisorEnabled
        v.checkOverlap = SettingsStore.shared.checkOverlapBeforeStitch
        v.enableStatusBarCrop = SettingsStore.shared.enableStatusBarCrop
        v.enableEdgeCrop = SettingsStore.shared.enableEdgeCrop
        v.crop = SettingsStore.shared.cropParams
        v.addUIImages(images)
        _vm = StateObject(wrappedValue: v)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 缩略条（可编辑调序/删除）
            thumbnailStrip

            // 控制区
            controls
                .padding(.horizontal)

            Divider()

            // 实时预览
            previewArea

            Spacer(minLength: 0)

            exportButton
        }
        .navigationTitle("编辑拼接")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
        }
        .environment(\.editMode, $editMode)
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMsg).padding(10).background(.black.opacity(0.8))
                    .foregroundStyle(.white).cornerRadius(8).padding(.bottom, 80)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showResult) {
            if let bundle = exportResult {
                ResultView(bundle: bundle)
            }
        }
        .task { @MainActor in
            vm.runAdvisorChecks()
        }
    }

    // MARK: 缩略条
    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(vm.items.enumerated()), id: \.element.id) { i, item in
                    Group {
                        if let img = item.loadUIImage() {
                            Image(uiImage: img).resizable().scaledToFit().frame(height: 80)
                                .overlay(alignment: .bottomLeading) {
                                    Text("\(i + 1)").foregroundStyle(.white).padding(3)
                                        .background(.black.opacity(0.6))
                                }
                                .contextMenu {
                                    Button(role: .destructive) { vm.removeItem(item.id) } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(height: 96)
        .background(.quaternary)
    }

    // MARK: 控制区
    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("顶部裁切：\(Int(vm.crop.topCropRatio * 100))%")
                Slider(value: topBinding, in: 0...0.40, step: 0.01)
            }
            HStack {
                Text("底部裁切：\(Int(vm.crop.bottomCropRatio * 100))%")
                Slider(value: bottomBinding, in: 0...0.40, step: 0.01)
            }
            HStack {
                Button { vm.applyRecommended() } label: {
                    Label("智能推荐", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled(vm.items.count < 2)

                Toggle("推荐开关", isOn: $vm.advisorEnabled)
                    .labelsHidden()
                Spacer()
            }

            if !vm.advisorMessages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(vm.advisorMessages, id: \.self) { msg in
                        Text("⚠️ \(msg)").font(.caption).foregroundStyle(.orange)
                    }
                    Button("就这样拼") { vm.advisorMessages = [] }
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: 预览
    @State private var magnify: CGFloat = 1.0
    private var previewArea: some View {
        Group {
            if vm.isProcessing {
                ProgressView("合成中…")
            } else if let img = vm.previewImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .scaleEffect(magnify)
                        .gesture(MagnificationGesture().onChanged { magnify = $0 })
                }
            } else if vm.items.isEmpty {
                EmptyStateView("没有图片", systemImage: "photo", description: "先导入几张截图或相册图")
            } else {
                Text("预览将自动生成").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 导出
    private var exportButton: some View {
        Button {
            if let r = vm.exportSlices(format: settings.exportFormat,
                                       sliceEnabled: settings.sliceEnabled,
                                       sliceHeight: settings.sliceHeight) {
                exportResult = ExportBundle(slicesData: r.data, sliced: r.sliced,
                                            width: r.width, height: r.height,
                                            thumb: vm.thumbnailPNG() ?? Data())
                if let thumb = vm.thumbnailPNG() {
                    HistoryStore.shared.append(HistoryRecord(
                        thumbnailPNG: thumb, mode: vm.mode,
                        topCropRatio: Double(vm.crop.topCropRatio),
                        bottomCropRatio: Double(vm.crop.bottomCropRatio),
                        advisorEnabled: vm.advisorEnabled,
                        sliced: r.sliced, sliceCount: r.data.count))
                }
                showResult = true
            }
        } label: {
            if vm.isProcessing { ProgressView() } else { Text("预览拼接并导出") }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .padding()
        .disabled(vm.items.isEmpty)
    }

    // MARK: 滑块绑定（含边界保护）
    private var topBinding: Binding<Double> {
        Binding(get: { Double(vm.crop.topCropRatio) },
                set: { v in
                    let c = CropParams(topCropRatio: CGFloat(v), bottomCropRatio: vm.crop.bottomCropRatio)
                    applyCropWithGuard(c)
                })
    }
    private var bottomBinding: Binding<Double> {
        Binding(get: { Double(vm.crop.bottomCropRatio) },
                set: { v in
                    let c = CropParams(topCropRatio: vm.crop.topCropRatio, bottomCropRatio: CGFloat(v))
                    applyCropWithGuard(c)
                })
    }
    private func applyCropWithGuard(_ c: CropParams) {
        if let first = vm.items.first?.loadCGImage() {
            let (adj, changed) = c.validated(forImageHeight: CGFloat(first.height))
            vm.crop = adj
            if changed { flash("重叠太多了，留点内容吧") }
        } else {
            vm.crop = c
        }
        vm.schedulePreview()
        vm.runAdvisorChecks()
    }
    private func flash(_ msg: String) {
        toastMsg = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showToast = false }
        }
    }
}

/// 一次导出的结果包（喂给 ResultView）
struct ExportBundle: Identifiable {
    let id = UUID()
    let slicesData: [Data]
    let sliced: Bool
    let width: Int
    let height: Int
    let thumb: Data
}
