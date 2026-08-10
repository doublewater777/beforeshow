import PhotosUI
import SwiftData
import SwiftUI

struct DynamicCoverQuickPicker: View {
    let show: Show
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: BSSpacing.lg) {
            Text("添加动态封面")
                .font(BSFont.headline)
                .foregroundColor(BSColor.Stage.foreground)
            Text("选择一段不超过 15 秒的视频，作为这场现场的动态一面。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
            Button {
                isPickerPresented = true
            } label: {
                Label("从照片图库选择", systemImage: "video.badge.plus")
                    .font(BSFont.caption.weight(.semibold))
                    .foregroundColor(BSColor.Stage.background)
                    .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
                    .background(BSColor.Stage.accent, in: RoundedRectangle(cornerRadius: BSRadius.md))
            }
            .buttonStyle(.plain)
            .photosPicker(isPresented: $isPickerPresented, selection: $selectedItem, matching: .videos)
            .disabled(isImporting)
            if isImporting { ProgressView().tint(BSColor.Stage.accent) }
        }
        .padding(BSSpacing.roomy)
        .background(BSColor.Stage.surfaceRaised)
        .onChange(of: selectedItem) { _, item in
            guard let item, !isImporting else { return }
            isImporting = true
            importTask = Task { @MainActor in
                defer { isImporting = false; selectedItem = nil }
                do {
                    try await DynamicCoverImportCoordinator.importVideo(item, for: show, in: modelContext)
                    dismiss()
                } catch {
                    errorMessage = "视频没有载入，请重试。"
                }
            }
        }
        .interactiveDismissDisabled(isImporting)
        .onDisappear {
            importTask?.cancel()
            importTask = nil
        }
        .alert("动态封面没有更新", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
