import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

extension MemoryCreateSourceOption {
    /// At the show the camera is the first thing reached for; without one, the album.
    static var quick: Self { UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .library }
}

/// Camera, album or a line of text, each saved straight into the show with no editor in between.
/// The result comes back once so the caller can give one light piece of feedback.
struct MemoryCaptureModifier: ViewModifier {
    @Binding var source: MemoryCreateSourceOption?
    let show: Show
    let onFinished: (Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isCameraPresented = false
    @State private var isLibraryPresented = false
    @State private var isTextPresented = false
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var cameraError: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: source) { _, next in
                guard let next else { return }
                source = nil
                begin(next)
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                SystemMemoryCameraPicker { result in
                    isCameraPresented = false
                    guard case .photo(let data) = result else { return }
                    Task { @MainActor in
                        do {
                            try await MemoryCaptureCoordinator.saveCameraPhoto(data, to: show, in: modelContext)
                            onFinished(true)
                        } catch {
                            onFinished(false)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $isLibraryPresented, selection: $pickedItems, selectionBehavior: .ordered, matching: .any(of: [.images, .videos]))
            .onChange(of: pickedItems) { _, items in
                guard !items.isEmpty else { return }
                pickedItems = []
                Task { @MainActor in
                    let saved = await MemoryCaptureCoordinator.saveLibraryItems(items, to: show, in: modelContext)
                    onFinished(saved == items.count)
                }
            }
            .sheet(isPresented: $isTextPresented) {
                MemoryLineSheet(title: BSLocalization.text("写一句"), initialText: "", allowsEmpty: false) { text in
                    try await MemoryCaptureCoordinator.saveText(text, to: show, in: modelContext)
                    onFinished(true)
                }
            }
            .alert(BSLocalization.text("无法继续"), isPresented: Binding(get: { cameraError != nil }, set: { if !$0 { cameraError = nil } })) {
                if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                    Button(BSLocalization.text("前往设置")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Button(BSLocalization.text("知道了"), role: .cancel) {}
            } message: {
                Text(cameraError ?? "")
            }
    }

    private func begin(_ option: MemoryCreateSourceOption) {
        switch option {
        case .library: isLibraryPresented = true
        case .text: isTextPresented = true
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                isLibraryPresented = true
                return
            }
            Task { @MainActor in
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized:
                    isCameraPresented = true
                case .notDetermined:
                    if await AVCaptureDevice.requestAccess(for: .video) {
                        isCameraPresented = true
                    } else {
                        cameraError = BSLocalization.text("没有相机权限。你可以在系统设置中允许访问。")
                    }
                default:
                    cameraError = BSLocalization.text("没有相机权限。你可以在系统设置中允许访问。")
                }
            }
        }
    }
}

extension View {
    func memoryCapture(_ source: Binding<MemoryCreateSourceOption?>, show: Show, onFinished: @escaping (Bool) -> Void = { _ in }) -> some View {
        modifier(MemoryCaptureModifier(source: source, show: show, onFinished: onFinished))
    }
}

/// 拍 / 相册 / 写一句, side by side so each is one tap away.
struct MemoryCaptureBar: View {
    var compact = false
    let onSelect: (MemoryCreateSourceOption) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MemoryCreateSourceOption.allCases, id: \.self) { option in
                Button { onSelect(option) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.iconName).font(.system(size: compact ? 13 : 15, weight: .semibold))
                        if !compact { Text(option.captureTitle).font(.system(size: 14, weight: .semibold)) }
                    }
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, minHeight: compact ? 36 : 46)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.captureTitle)
            }
        }
    }
}

extension MemoryCreateSourceOption {
    var captureTitle: String {
        switch self {
        case .camera: BSLocalization.text("拍一张")
        case .library: BSLocalization.text("相册")
        case .text: BSLocalization.text("写一句")
        }
    }
}

/// One line for a memory: new text, or the caption under a photo. Saving closes it; errors stay here.
struct MemoryLineSheet: View {
    let title: String
    let initialText: String
    let allowsEmpty: Bool
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextField(BSLocalization.text("此刻想记下的一句"), text: $text, axis: .vertical)
                    .font(.system(size: 17))
                    .lineLimit(3...8)
                    .focused($isFocused)
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 12)).foregroundStyle(BSColor.Stage.live)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: "取消") { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                        .disabled(isSaving || (!allowsEmpty && trimmed.isEmpty) || trimmed.count > 500)
                        .accessibilityLabel(BSLocalization.text("完成"))
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .onAppear {
            text = initialText
            isFocused = true
        }
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            do {
                try await onSave(trimmed)
                dismiss()
            } catch {
                errorMessage = BSLocalization.text("没有保存，请重试")
                isSaving = false
            }
        }
    }
}
