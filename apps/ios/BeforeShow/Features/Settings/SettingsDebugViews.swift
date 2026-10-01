import SwiftData
import SwiftUI
import UIKit
import UserNotifications

#if DEBUG
enum DebugProEntitlementOption: String, CaseIterable {
    case free
    case active
    case expired

    var state: ProEntitlementState {
        switch self {
        case .free:
            return .free
        case .active:
            return .active(productID: "debug.local.pro", expirationDate: nil)
        case .expired:
            return .expired(productID: "debug.local.pro", expirationDate: Date(timeIntervalSince1970: 0))
        }
    }

    init(state: ProEntitlementState) {
        switch state {
        case .free:
            self = .free
        case .active:
            self = .active
        case .expired:
            self = .expired
        }
    }
}

struct ProEntitlementDebugPicker: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""

    private var selectedOption: DebugProEntitlementOption {
        get {
            DebugProEntitlementOption(state: ProEntitlementStorage.decode(entitlementRawValue))
        }
        nonmutating set {
            entitlementRawValue = ProEntitlementStorage.encode(newValue.state)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            Text(BSLocalization.text("Pro 状态测试"))
                .font(BSFont.V3.body.weight(.semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("切换后立即生效，仅调试构建可见。"))
                .font(BSFont.V3.small)
                .foregroundColor(BSColor.Stage.muted)

            Picker(BSLocalization.text("Pro 状态"), selection: Binding(get: { selectedOption }, set: { selectedOption = $0 })) {
                ForEach(DebugProEntitlementOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, BSSpacing.xs)
        }
        .padding(.vertical, BSSpacing.xs)
    }
}

extension DebugProEntitlementOption {
    var displayName: String {
        switch self {
        case .free: return BSLocalization.text("免费版")
        case .active: return BSLocalization.text("Pro 已启用")
        case .expired: return BSLocalization.text("Pro 已过期")
        }
    }
}

struct DebugPrintPendingNotificationsRow: View {
    @State private var isPrinting = false

    var body: some View {
        Button {
            isPrinting = true
            Task { @MainActor in
                await LocalNotificationCenter.shared.printPendingRequests()
                isPrinting = false
            }
        } label: {
            HStack(spacing: BSSpacing.compact) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(BSLocalization.text("打印待发通知"))
                        .font(BSFont.V3.body)
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(BSLocalization.text("输出当前现场已排程的本地通知到控制台"))
                        .font(BSFont.V3.small)
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer()

                if isPrinting {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
