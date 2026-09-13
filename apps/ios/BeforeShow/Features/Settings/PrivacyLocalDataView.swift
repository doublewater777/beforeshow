import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct PrivacyLocalDataView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(ProductAnalyticsPreferences.appStorageKey) private var productAnalyticsEnabled = true
    @State private var inventory: LocalDataInventory?
    @State private var clearFeedback: ClearDataFeedback?
    @State private var isClearing = false
    @State private var showsClearConfirmation = false

    var body: some View {
        BSStageScaffold(title: "", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
            SettingsGroup(title: BSLocalization.text("产品改进")) {
                Toggle(isOn: productAnalyticsBinding) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(BSLocalization.text("帮助改进产品"))
                            .font(BSFont.V3.body.weight(.semibold))
                            .foregroundColor(BSColor.Stage.foreground)
                        Text(BSLocalization.text("匿名分析与操作回放，用于发现卡点和修复问题。可随时关闭。"))
                            .font(BSFont.V3.body)
                            .foregroundColor(BSColor.Stage.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(BSColor.Stage.accent)
                .padding(.horizontal, BSSpacing.md)
                .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
                .accessibilityHint(BSLocalization.text("关闭后停止发送匿名分析与操作回放"))
            }

            SettingsGroup(title: BSLocalization.text("本地数据")) {
                if let inventory {
                    if inventory.isEmpty {
                        settingsStatusRow(BSLocalization.text("暂无本地数据"))
                    } else {
                        inventoryRow(BSLocalization.text("现场"), value: BSLocalization.format("%lld 场", inventory.showCount))
                        SettingsDivider()
                        inventoryRow(BSLocalization.text("记忆碎片"), value: BSLocalization.format("%lld 条", inventory.memoryFragmentCount))
                        SettingsDivider()
                        inventoryRow(BSLocalization.text("票根与时刻表"), value: BSLocalization.format("%lld 个", inventory.assetCount))
                        SettingsDivider()
                        inventoryRow(BSLocalization.text("动态封面"), value: BSLocalization.format("%lld 个", inventory.dynamicCoverCount))
                        SettingsDivider()
                        inventoryRow(BSLocalization.text("App 内占用"), value: formattedBytes(inventory.appBytes))
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BSSpacing.md)
                        .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
                }
            }

            SettingsGroup(title: "清除本地数据") {
                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    HStack(spacing: BSSpacing.sm) {
                        if isClearing {
                            ProgressView()
                        }
                        Text("清除 BeforeShow 本地数据")
                    }
                }
                .buttonStyle(BSDangerButtonStyle())
                .disabled(isClearing || inventory?.isEmpty != false)
                .opacity(isClearing || inventory?.isEmpty != false ? 0.35 : 1)
                .padding(.horizontal, BSSpacing.md)
                .padding(.vertical, BSSettingsStyle.rowVerticalPadding)

                if let clearFeedback {
                    SettingsDivider()
                    Label(
                        clearFeedback.text,
                        systemImage: clearFeedback.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                    )
                    .font(BSFont.V3.body)
                    .foregroundColor(clearFeedback.isError ? BSColor.Stage.danger : BSColor.Stage.success)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BSSpacing.md)
                    .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .alert(
            DangerConfirmation.clearLocalData.title,
            isPresented: $showsClearConfirmation
        ) {
            Button(DangerConfirmation.clearLocalData.confirmTitle, role: .destructive) {
                clearLocalData()
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(DangerConfirmation.clearLocalData.message)
        }
        .navigationTitle(BSLocalization.text("隐私与本地数据"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshInventory()
        }
    }

    private var productAnalyticsBinding: Binding<Bool> {
        Binding(
            get: { productAnalyticsEnabled },
            set: { newValue in
                productAnalyticsEnabled = newValue
                ProductAnalyticsPreferences.apply(newValue)
            }
        )
    }

    private func inventoryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(BSFont.V3.body)
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Text(value)
                .font(BSFont.V3.body.weight(.medium))
                .foregroundColor(BSColor.Stage.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: BSSettingsStyle.rowMinimumHeight, alignment: .leading)
    }

    private func settingsStatusRow(_ text: String) -> some View {
        Text(text)
            .font(BSFont.V3.body)
            .foregroundColor(BSColor.Stage.muted)
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: BSSettingsStyle.rowMinimumHeight, alignment: .leading)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @MainActor
    private func refreshInventory() async {
        inventory = await LocalDataInventoryService.compute(modelContext: modelContext)
    }

    private func clearLocalData() {
        let before = inventory
        isClearing = true
        clearFeedback = nil
        Task { @MainActor in
            do {
                let context = modelContext
                await ShowAssetMediaStore.shared.acquireCommitGate()
                ShowAssetCleanupRetry.markFullCleanupPrepared()
                do {
                    ListeningRoomCache.discardLocalState()
                    try ListeningLocalDataCleaner.deleteAll(in: context)
                    try context.delete(model: Show.self)
                    try context.delete(model: CurrentShowSelection.self)
                    try context.delete(model: NotificationSchedulingState.self)
                    try context.delete(model: ShowNotificationScheduleRecord.self)
                    try context.delete(model: MemoryMediaItem.self)
                    try context.delete(model: MemoryFragment.self)
                    try context.delete(model: ShowAsset.self)
                    try context.delete(model: DynamicCover.self)
                    try context.save()
                    // 系统通知中心里的 pending 请求不受 SwiftData 删除影响，
                    // 必须显式清掉，否则清空数据后通知仍按时弹出、深链指向已删除的现场。
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                } catch {
                    context.rollback()
                    throw error
                }
                DynamicCoverFaceStore.clearAll()
                ShowAssetCleanupRetry.markFullCleanupPending()
                ShowAssetCleanupRetry.clearFullCleanupPrepared()

                var cleanupFailures: [String] = []
                try await MemoryFragmentMediaStore.shared.deleteAll()
                do {
                    try await ShowAssetMediaStore.shared.deleteAll()
                } catch {
                    cleanupFailures.append(BSLocalization.text("票根和时刻表副本"))
                }
                do {
                    try await DynamicCoverMediaStore.shared.deleteAll()
                } catch {
                    cleanupFailures.append(BSLocalization.text("动态封面视频副本"))
                }
                if cleanupFailures.isEmpty {
                    ShowAssetCleanupRetry.clearFullCleanupPending()
                }

                await ShowAssetMediaStore.shared.releaseCommitGate()

                if cleanupFailures.isEmpty {
                    let freedBytes = before?.mediaBytes ?? 0
                    clearFeedback = .success(freedBytes > 0
                        ? BSLocalization.format("已清除本地数据，释放 %@。", formattedBytes(freedBytes))
                        : BSLocalization.text("已清除本地数据。"))
                } else {
                    clearFeedback = .failure(BSLocalization.format("部分内容未清除（%@），将于下次启动时重试。", cleanupFailures.joined(separator: "、")))
                }
            } catch {
                ShowAssetCleanupRetry.clearFullCleanupPrepared()
                clearFeedback = .failure(BSLocalization.text("清除本地数据失败，请重试。"))
                await ShowAssetMediaStore.shared.releaseCommitGate()
            }
            isClearing = false
            await refreshInventory()
        }
    }
}

enum ClearDataFeedback: Equatable {
    case success(String)
    case failure(String)

    var text: String {
        switch self {
        case .success(let text): return text
        case .failure(let text): return text
        }
    }

    var isError: Bool {
        if case .failure = self { return true }
        return false
    }
}
