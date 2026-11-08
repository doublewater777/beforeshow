import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum MerchCaptureSource: String, Identifiable {
    case camera
    case library
    var id: String { rawValue }

    static var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
}

/// 拍下 / 选一张周边照片就直接存进这场；种类和名字之后在周边柜里长按改。
@MainActor
enum MerchCaptureCoordinator {
    static func save(photo data: Data, to show: Show, in context: ModelContext) async throws {
        let showID = show.id
        let itemID = UUID()
        let cutout = await Task.detached(priority: .userInitiated) { MerchCutout.pngCutout(from: data) }.value
        await LocalMediaCommitGate.shared.acquire()
        defer { Task { await LocalMediaCommitGate.shared.release() } }
        let paths = try await ShowAssetMediaStore.shared.saveMerchPhoto(data: data, cutoutPNG: cutout, showID: showID, itemID: itemID)
        let item = MerchItem(id: itemID, showID: showID, relativePath: paths.photo, cutoutRelativePath: paths.cutout)
        item.show = show
        context.insert(item)
        do {
            try context.save()
        } catch {
            context.rollback()
            for path in [paths.photo] + (paths.cutout.map { [$0] } ?? []) {
                try? await ShowAssetMediaStore.shared.deleteMerch(relativePath: path, showID: showID)
            }
            throw error
        }
    }

    static func delete(_ item: MerchItem, in context: ModelContext) async throws {
        let showID = item.showID
        let paths = item.storedRelativePaths
        context.delete(item)
        try context.save()
        for path in paths {
            try? await ShowAssetMediaStore.shared.deleteMerch(relativePath: path, showID: showID)
        }
    }
}

/// 相机全屏 / 系统相册二选一，选完直接保存，结果用一次轻反馈回给调用方。
struct MerchCaptureModifier: ViewModifier {
    @Binding var source: MerchCaptureSource?
    let show: Show
    let onFinished: (Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var pickerItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(get: { source == .camera }, set: { if !$0 { source = nil } })) {
                SystemMemoryCameraPicker { result in
                    source = nil
                    if case .photo(let data) = result { persist(data) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: Binding(get: { source == .library }, set: { if !$0 { source = nil } }),
                selection: $pickerItem,
                matching: .images
            )
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                Task { @MainActor in
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return onFinished(false) }
                    persist(data)
                }
            }
    }

    private func persist(_ data: Data) {
        Task { @MainActor in
            do {
                try await MerchCaptureCoordinator.save(photo: data, to: show, in: modelContext)
                onFinished(true)
            } catch {
                onFinished(false)
            }
        }
    }
}

extension View {
    func merchCapture(_ source: Binding<MerchCaptureSource?>, show: Show, onFinished: @escaping (Bool) -> Void) -> some View {
        modifier(MerchCaptureModifier(source: source, show: show, onFinished: onFinished))
    }
}

/// 「拍一张」入口：有相机时给相机 / 相册两项，模拟器等无相机环境直接打开相册。
struct MerchCaptureMenu<Label: View>: View {
    @Binding var source: MerchCaptureSource?
    @ViewBuilder let label: () -> Label

    var body: some View {
        if MerchCaptureSource.isCameraAvailable {
            Menu {
                Button { source = .camera } label: { SwiftUI.Label(BSLocalization.text("拍一张"), systemImage: "camera") }
                Button { source = .library } label: { SwiftUI.Label(BSLocalization.text("从相册选"), systemImage: "photo") }
            } label: { label() }
        } else {
            Button { source = .library } label: { label() }
        }
    }
}
