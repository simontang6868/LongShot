import SwiftUI

/// Tab B：相册选图拼。多选（顺序即拼接顺序），选中后进入同一个编辑页。
/// 与 Tab A 共用 PHPickerWrapper：不申请完整相册权限，只拿副本。
struct AlbumPickerView: View {
    @State private var showPicker = false
    @State private var picked: [UIImage] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("从相册多选图片，按顺序拼接成长图。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()

                if picked.isEmpty {
                    EmptyStateView("还没选图", systemImage: "photo.stack",
                                   description: "从相册选几张，顺序就是拼接顺序")
                } else {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(picked.enumerated()), id: \.offset) { i, img in
                                Image(uiImage: img)
                                    .resizable().scaledToFit().frame(height: 140)
                                    .overlay(alignment: .bottomLeading) {
                                        Text("\(i + 1)").foregroundStyle(.white)
                                            .padding(4).background(.black.opacity(0.6))
                                    }
                            }
                        }
                    }
                    NavigationLink("进入编辑页（\(picked.count) 张）", destination: EditorView(mode: .album, images: picked))
                        .buttonStyle(.borderedProminent)
                }

                Button { showPicker = true } label: {
                    Label(picked.isEmpty ? "从相册选图" : "再选几张", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            .navigationTitle("相册选图拼")
            .sheet(isPresented: $showPicker) {
                PHPickerWrapper(selectionLimit: 0) { imgs in
                    picked.append(contentsOf: imgs)
                    showPicker = false
                }
            }
        }
    }
}
