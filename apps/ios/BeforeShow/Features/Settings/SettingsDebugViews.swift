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
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(BSLocalization.text("Pro 状态测试"))
                .font(BSFont.V3.body.weight(.semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("切换后立即生效，仅调试构建可见。"))
                .font(BSFont.V3.body)
                .foregroundColor(BSColor.Stage.muted)

            Picker(BSLocalization.text("Pro 状态"), selection: Binding(get: { selectedOption }, set: { selectedOption = $0 })) {
                ForEach(DebugProEntitlementOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(BSSpacing.md)
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
            HStack(spacing: BSSpacing.md) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(width: 34, height: 34)
                    .background(BSColor.Stage.muted.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text("打印待发通知")
                        .font(BSFont.V3.body.weight(.semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                    Text("输出当前现场已排程的本地通知到控制台")
                        .font(BSFont.V3.body)
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer()

                if isPrinting {
                    ProgressView()
                }
            }
            .padding(BSSpacing.md)
        }
        .buttonStyle(SettingsPressButtonStyle())
    }
}
#endif
