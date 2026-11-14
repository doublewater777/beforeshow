import SwiftUI
import UIKit

/// The home screen icons: the stage lights in colour for everyone, black-and-white and gold with Pro.
enum AppIconOption: String, CaseIterable, Identifiable {
    case standard
    case mono
    case gold

    var id: String { rawValue }

    /// The name the asset catalog gives the alternate icon; nil is the primary icon.
    var alternateName: String? {
        switch self {
        case .standard: nil
        case .mono: "AppIconMono"
        case .gold: "AppIconGold"
        }
    }

    var previewImage: String {
        switch self {
        case .standard: "AppLogo"
        case .mono: "AppIconMonoPreview"
        case .gold: "AppIconGoldPreview"
        }
    }

    var title: String {
        switch self {
        case .standard: BSLocalization.text("舞台光")
        case .mono: BSLocalization.text("黑白")
        case .gold: BSLocalization.text("鎏金")
        }
    }

    var isPro: Bool { self != .standard }

    static func current(alternateName: String?) -> AppIconOption {
        allCases.first { $0.alternateName == alternateName } ?? .standard
    }
}

struct AppIconSettingsView: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var selection = AppIconOption.current(alternateName: UIApplication.shared.alternateIconName)
    @State private var isShowingPaywall = false
    @State private var toast: BSToastPayload?

    private var isProActive: Bool { ProEntitlementStorage.decode(entitlementRawValue).isProActive }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: BSSpacing.lg) {
                ForEach(AppIconOption.allCases) { option in
                    tile(option)
                }
            }
            .padding(BSSpacing.roomy)
        }
        .background(BSColor.Stage.background.ignoresSafeArea())
        .navigationTitle(BSLocalization.text("App 图标"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingPaywall) { ProPaywallSheetView() }
        .bsToastOverlay(toast, bottomPadding: 28)
    }

    private func tile(_ option: AppIconOption) -> some View {
        let locked = option.isPro && !isProActive
        let isSelected = option == selection
        return Button {
            choose(option, locked: locked)
        } label: {
            VStack(spacing: BSSpacing.sm) {
                Image(option.previewImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? BSColor.Stage.foreground : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(BSColor.Stage.foreground)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.black.opacity(0.55)))
                                .padding(5)
                        }
                    }
                HStack(spacing: 4) {
                    Text(option.title)
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func choose(_ option: AppIconOption, locked: Bool) {
        guard !locked else {
            isShowingPaywall = true
            return
        }
        guard option != selection, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = selection
        selection = option
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(option.alternateName)
            } catch {
                selection = previous
                toast = BSToastPayload(tone: .failure, message: BSLocalization.text("图标更换失败，请重试"))
            }
        }
    }
}
