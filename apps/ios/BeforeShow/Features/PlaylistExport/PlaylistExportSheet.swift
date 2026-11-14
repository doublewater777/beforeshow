import SwiftUI
import UIKit

/// 导出到音乐 App: a playlist as screenshots and as text, ready for a music app's import.
struct PlaylistExportSheet: View {
    static let guideURL = URL(string: "https://beforeshow.doublewaterapps.com/playlist-guide/")!

    let songs: [PlaylistExport.Song]

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var isShowingPaywall = false
    @State private var isSaving = false
    @State private var toast: BSToastPayload?
    @State private var guidePage: BSInAppBrowserPage?

    private var isProActive: Bool { ProEntitlementStorage.decode(entitlementRawValue).isProActive }
    private var pages: [[PlaylistExport.Song]] { PlaylistExport.pages(songs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button { guidePage = BSInAppBrowserPage(url: Self.guideURL) } label: {
                        HStack(spacing: 6) {
                            Text(BSLocalization.text("QQ 音乐用文字或截图，网易云音乐用截图，汽水音乐用歌单链接导入。"))
                                .foregroundStyle(BSColor.Stage.muted)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Text(BSLocalization.text("图文教程"))
                                .fontWeight(.semibold)
                                .foregroundStyle(BSColor.Stage.foreground)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                        PlaylistExportPage(songs: page)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) { actions }
            .background(BSColor.Stage.background.ignoresSafeArea())
            .navigationTitle(BSLocalization.text("导出到音乐 App"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BSChromeToolbarCloseButton { dismiss() } }
            .bsToastOverlay(toast, bottomPadding: 96)
        }
        .tint(BSColor.Stage.foreground)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $isShowingPaywall) { ProPaywallView() }
        .sheet(item: $guidePage) { BSInAppBrowser(page: $0).ignoresSafeArea() }
    }

    private var actions: some View {
        HStack(spacing: 9) {
            Button(action: copy) {
                label(BSLocalization.text("复制文字"), isLoading: false)
            }
            .buttonStyle(BSSecondaryButtonStyle())
            Button { Task { await save() } } label: {
                label(
                    pages.count > 1 ? BSLocalization.format("保存 %lld 张图片", pages.count) : BSLocalization.text("保存图片"),
                    isLoading: isSaving
                )
            }
            .buttonStyle(BSPrimaryButtonStyle())
        }
        .disabled(isSaving)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(BSColor.Stage.background)
    }

    private func label(_ title: String, isLoading: Bool) -> some View {
        HStack(spacing: BSSpacing.sm) {
            if !isProActive {
                Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
            }
            if isLoading {
                ProgressView().controlSize(.small).tint(BSColor.Stage.background)
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func copy() {
        guard isProActive else { return isShowingPaywall = true }
        UIPasteboard.general.string = PlaylistExport.text(songs)
        toast = BSToastPayload(tone: .success, message: BSLocalization.format("已复制 %lld 首", songs.count))
    }

    @MainActor
    private func save() async {
        guard isProActive else { return isShowingPaywall = true }
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard let images = PlaylistExport.images(songs) else {
            toast = BSToastPayload(tone: .failure, message: BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        do {
            for image in images { try await FootprintPhotoLibrary.save(image) }
            toast = BSToastPayload(tone: .success, message: BSLocalization.text("已保存到相册"))
        } catch {
            toast = BSToastPayload(tone: .failure, message: BSLocalization.text("保存失败，请检查相册权限"))
        }
    }
}

extension View {
    /// Presents the export sheet for whatever songs the caller has at the moment it opens.
    func playlistExport(isPresented: Binding<Bool>, songs: @escaping () -> [PlaylistExport.Song]) -> some View {
        sheet(isPresented: isPresented) { PlaylistExportSheet(songs: PlaylistExport.songs(songs())) }
    }
}
