import SwiftData
import XCTest
@testable import BeforeShow

final class ProSubscriptionTests: XCTestCase {
    func testCatalogLoadsStandardAndWinbackProducts() {
        let products = ProSubscriptionCatalog.defaultProducts

        XCTAssertEqual(products.map(\.plan), [.monthly, .yearly, .lifetime, .yearlyDiscount, .lifetimeDiscount])
        XCTAssertEqual(products.map(\.id), [
            "com.doublewaterapps.beforeshow.pro.monthly",
            "com.doublewaterapps.beforeshow.pro.yearly",
            "com.doublewaterapps.beforeshow.pro.lifetime",
            "com.doublewaterapps.beforeshow.pro.yearly.discount",
            "com.doublewaterapps.beforeshow.pro.lifetime.discount"
        ])
        XCTAssertEqual(products.map(\.priceText), ["$1.49/月", "$4.99/年", "$8.99", "$2.99/年", "$5.99"])
        XCTAssertEqual(ProSubscriptionCatalog.standardPlans, [.monthly, .yearly, .lifetime])
        XCTAssertEqual(ProSubscriptionCatalog.winbackPlans, [.yearlyDiscount, .lifetimeDiscount])
        XCTAssertTrue(ProSubscriptionPlan.lifetime.isLifetime)
        XCTAssertTrue(ProSubscriptionPlan.lifetimeDiscount.isLifetime)
        XCTAssertFalse(ProSubscriptionPlan.yearly.isLifetime)
    }

    func testProductFramingDoesNotUseAdsOrAdRemovalCopy() {
        let blockedWords = ["广告", "去广告", "ad", "ads", "remove ads", "ad removal"]

        for product in ProSubscriptionCatalog.defaultProducts {
            let copy = ([product.displayName, product.priceText] + product.benefitCopy)
                .joined(separator: " ")
                .lowercased()

            for blockedWord in blockedWords {
                XCTAssertFalse(copy.contains(blockedWord), "\(blockedWord) should not appear in Pro copy")
            }
        }
    }

    func testPurchaseActivatesProEntitlement() async throws {
        let store = MockProSubscriptionStore()

        let products = try await store.loadProducts()
        let entitlement = try await store.purchase(productID: products[0].id)

        XCTAssertEqual(
            entitlement,
            .active(productID: ProSubscriptionCatalog.monthlyProductID, expirationDate: nil)
        )
        XCTAssertTrue(entitlement.isProActive)
    }

    func testRestoreUsesAppStoreEntitlementWithoutBeforeShowAccount() async throws {
        let restorable = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.yearlyProductID,
            expirationDate: nil
        )
        let store = MockProSubscriptionStore(restorableEntitlement: restorable)

        let restored = try await store.restorePurchases()

        XCTAssertEqual(restored, restorable)
        XCTAssertTrue(restored.isProActive)
    }

    func testProGateAllowsOneFreeShowPerMonth() {
        let gate = ProFeatureGate()
        let proEntitlement = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.yearlyProductID,
            expirationDate: nil
        )

        XCTAssertTrue(gate.canAddShow(showsAddedThisMonth: 0, entitlement: .free))
        XCTAssertFalse(gate.canAddShow(showsAddedThisMonth: 1, entitlement: .free))
        XCTAssertTrue(gate.canAddShow(showsAddedThisMonth: 100, entitlement: proEntitlement))
    }

    func testProGateCountsOnlyShowsCreatedInCurrentCalendarMonth() {
        let gate = ProFeatureGate()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17 UTC
        let sameMonth = Date(timeIntervalSince1970: 1_786_800_000) // 2026-08-15 UTC
        let previousMonth = Date(timeIntervalSince1970: 1_784_000_000) // 2026-07-14 UTC

        XCTAssertEqual(
            gate.showsAddedThisMonth(
                from: [sameMonth, sameMonth, previousMonth],
                now: now,
                calendar: calendar
            ),
            2
        )
    }

    /// 接受 CloudKit 同行邀请「新建」的场次是对方创建的，不该消耗本人的每月免费额度。
    func testFreeQuotaIgnoresSharesAcceptedFromCompanions() throws {
        let gate = ProFeatureGate()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17 UTC
        let thisMonth = Date(timeIntervalSince1970: 1_786_800_000) // 2026-08-15 UTC

        let accepted = try Show(
            name: "朋友的现场",
            date: now,
            startTime: now,
            creationOrigin: .companionImport,
            createdAt: thisMonth
        )
        accepted.companionIsOwner = false
        let ownShare = try Show(name: "我建的同行", date: now, startTime: now, createdAt: thisMonth)
        ownShare.companionIsOwner = true
        let manual = try Show(name: "我自己添加", date: now, startTime: now, createdAt: thisMonth)

        XCTAssertFalse(accepted.countsTowardFreeMonthlyQuota)
        XCTAssertTrue(ownShare.countsTowardFreeMonthlyQuota)
        XCTAssertTrue(manual.countsTowardFreeMonthlyQuota)

        // 只接受了一份邀请 → 本月额度未被占用，用户仍能添加自己的第一场。
        XCTAssertEqual(gate.showsAddedThisMonth(from: [accepted], now: now, calendar: calendar), 0)
        XCTAssertTrue(gate.canAddShow(
            showsAddedThisMonth: gate.showsAddedThisMonth(from: [accepted], now: now, calendar: calendar),
            entitlement: .free
        ))

        // 自己添加过一场后额度用尽，邀请导入的那份不叠加计数。
        XCTAssertEqual(
            gate.showsAddedThisMonth(from: [accepted, manual, ownShare], now: now, calendar: calendar),
            2
        )
        XCTAssertFalse(gate.canAddShow(
            showsAddedThisMonth: gate.showsAddedThisMonth(from: [accepted, manual], now: now, calendar: calendar),
            entitlement: .free
        ))
    }

    /// 额度来源必须是不可变的创建来源，不能从 `companionIsOwner` 推导：
    /// 接受邀请时会把邀请合并进用户已有的现场，那条路径也会把
    /// `companionIsOwner` 置为 false，否则已占用的额度会被凭空退还。
    func testAcceptedShareMergedIntoOwnShowDoesNotRefundQuota() throws {
        let gate = ProFeatureGate()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17 UTC
        let earlierThisMonth = Date(timeIntervalSince1970: 1_786_000_000) // 2026-08-06 UTC

        // 用户 8/6 自己添加了一场，本月唯一的免费额度已经用掉。
        let mine = try Show(name: "我自己添加", date: now, startTime: now, createdAt: earlierThisMonth)
        XCTAssertEqual(gate.showsAddedThisMonth(from: [mine], now: now, calendar: calendar), 1)
        XCTAssertFalse(gate.canAddShow(showsAddedThisMonth: 1, entitlement: .free))

        // 之后接受了同一场现场的同行邀请 → 合并进这条已有记录（participant 侧）。
        mine.companionIsOwner = false

        XCTAssertTrue(mine.countsTowardFreeMonthlyQuota)
        XCTAssertEqual(gate.showsAddedThisMonth(from: [mine], now: now, calendar: calendar), 1)
        XCTAssertFalse(gate.canAddShow(
            showsAddedThisMonth: gate.showsAddedThisMonth(from: [mine], now: now, calendar: calendar),
            entitlement: .free
        ))

        // 反向：纯粹因接受邀请而新建的现场始终不占额度。
        let imported = try Show(
            name: "朋友的现场",
            date: now,
            startTime: now,
            creationOrigin: .companionImport,
            createdAt: earlierThisMonth
        )
        imported.companionIsOwner = false
        XCTAssertEqual(gate.showsAddedThisMonth(from: [imported], now: now, calendar: calendar), 0)
        // 旧数据没有来源字段时按 .user 解释，不会退还额度。
        XCTAssertEqual(mine.creationOrigin, .user)
        XCTAssertEqual(imported.creationOrigin, .companionImport)
    }

    /// 升级前写入的旧数据没有来源值，由一次性迁移落库。旧数据无法区分
    /// 「历史纯导入」和「历史自建后被合并」（两者都只剩 companionIsOwner == false），
    /// 所以策略保守：一律标 `.user`，继续占额度，绝不凭空退还。
    @MainActor
    func testLegacyShowsGetExplicitCreationOriginOnMigration() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17 UTC
        let thisMonth = Date(timeIntervalSince1970: 1_786_000_000) // 2026-08-06 UTC

        // creationOrigin: nil 重建「升级前写入、没有来源值」的旧行。
        // 旧的 participant 侧导入行：升级前由 applyAcceptedSession 新建后标成非 owner。
        let legacyImport = try Show(
            name: "朋友的现场",
            date: now,
            startTime: now,
            creationOrigin: nil,
            createdAt: thisMonth
        )
        legacyImport.companionIsOwner = false
        // 旧的用户自建行（从未进过同行流程）。
        let legacyManual = try Show(
            name: "我自己添加",
            date: now,
            startTime: now,
            creationOrigin: nil,
            createdAt: thisMonth
        )
        // 旧的 owner 侧同行行：是用户自己添加并发出邀请的。
        let legacyOwner = try Show(
            name: "我发的邀请",
            date: now,
            startTime: now,
            creationOrigin: nil,
            createdAt: thisMonth
        )
        legacyOwner.companionIsOwner = true

        for show in [legacyImport, legacyManual, legacyOwner] {
            XCTAssertTrue(show.hasUnresolvedCreationOrigin)
            context.insert(show)
        }
        try context.save()

        ShowCreationOriginMigration.migrateIfNeeded(in: context)

        // 旧数据一律按用户自建处理（保守）：participant 侧的历史行也不例外，
        // 因为它可能本来就是用户自己添加、后来才被邀请合并的。
        XCTAssertEqual(legacyImport.creationOrigin, .user)
        XCTAssertEqual(legacyManual.creationOrigin, .user)
        XCTAssertEqual(legacyOwner.creationOrigin, .user)
        XCTAssertFalse(legacyImport.hasUnresolvedCreationOrigin)

        let gate = ProFeatureGate()
        XCTAssertEqual(
            gate.showsAddedThisMonth(from: [legacyImport, legacyManual, legacyOwner], now: now, calendar: calendar),
            3
        )

        // 迁移之后再被邀请合并（companionIsOwner 翻成 false）不会退还额度。
        legacyManual.companionIsOwner = false
        ShowCreationOriginMigration.migrateIfNeeded(in: context)
        XCTAssertEqual(legacyManual.creationOrigin, .user)
        XCTAssertEqual(gate.showsAddedThisMonth(from: [legacyManual], now: now, calendar: calendar), 1)
    }

    /// 升级前就已经发生过合并的旧数据：用户自己添加、随后接受邀请被合并，
    /// 到达升级点时 companionIsOwner == false 且带 companion 链接。
    /// 它与「历史纯导入」不可区分，必须按占额度处理，不能退还已用掉的额度。
    @MainActor
    func testLegacyMergedBeforeUpgradeKeepsConsumingQuota() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17 UTC
        let thisMonth = Date(timeIntervalSince1970: 1_786_000_000) // 2026-08-06 UTC

        let mergedBeforeUpgrade = try Show(
            name: "我自己添加后被合并",
            date: now,
            startTime: now,
            creationOrigin: nil,
            createdAt: thisMonth
        )
        mergedBeforeUpgrade.companionIsOwner = false
        mergedBeforeUpgrade.companionCloudRecordName = "session-legacy"
        context.insert(mergedBeforeUpgrade)
        try context.save()

        ShowCreationOriginMigration.migrateIfNeeded(in: context)

        XCTAssertEqual(mergedBeforeUpgrade.creationOrigin, .user)
        XCTAssertTrue(mergedBeforeUpgrade.countsTowardFreeMonthlyQuota)

        let gate = ProFeatureGate()
        XCTAssertEqual(
            gate.showsAddedThisMonth(from: [mergedBeforeUpgrade], now: now, calendar: calendar),
            1
        )
        XCTAssertFalse(gate.canAddShow(showsAddedThisMonth: 1, entitlement: .free))
    }

    /// 额度归属不能依赖启动期的执行顺序：`noteDependenciesReady()` 会立刻起 Task
    /// flush 待处理邀请，可能先于启动任务里的迁移跑完。接受邀请的路径自己会先定格
    /// 旧数据来源，所以即使 flush 抢先，用户自己添加的现场也不会被误判成导入。
    @MainActor
    func testAcceptFlushBeforeMigrationStillKeepsUserOrigin() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17 UTC
        let thisMonth = Date(timeIntervalSince1970: 1_786_000_000) // 2026-08-06 UTC

        // 升级前用户自己添加的现场（没有来源值），本月额度已占用。
        let legacyManual = try Show(
            name: "我自己添加",
            date: now,
            startTime: now,
            creationOrigin: nil,
            createdAt: thisMonth
        )
        context.insert(legacyManual)
        try context.save()

        // 模拟「flush 抢在启动迁移之前」：接受邀请路径先定格来源，再做合并。
        let shows = try context.fetch(FetchDescriptor<Show>())
        ShowCreationOriginMigration.resolveUnresolvedOrigins(in: shows)
        legacyManual.companionIsOwner = false // 合并把它标成 participant 侧
        try context.save()

        // 之后启动迁移才跑到 —— 来源已经定格，不会被改写成导入。
        ShowCreationOriginMigration.migrateIfNeeded(in: context)

        XCTAssertEqual(legacyManual.creationOrigin, .user)
        XCTAssertTrue(legacyManual.countsTowardFreeMonthlyQuota)
        let gate = ProFeatureGate()
        XCTAssertEqual(gate.showsAddedThisMonth(from: [legacyManual], now: now, calendar: calendar), 1)
        XCTAssertFalse(gate.canAddShow(showsAddedThisMonth: 1, entitlement: .free))
    }

    func testProLimitReasonsMapToExpectedUserFacingCopy() {
        XCTAssertEqual(ProLimitReason.saveLimit.title, "免费版每月可添加 1 场现场")
        XCTAssertEqual(ProLimitReason.saveLimit.message, "开通 Pro 后可以无限保存现场。")

    }

    func testEntitlementCanBePersistedForAppGates() {
        let active = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.yearlyProductID,
            expirationDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encodedEntitlement = ProEntitlementStorage.encode(active)

        XCTAssertEqual(ProEntitlementStorage.decode(encodedEntitlement), active)
        XCTAssertEqual(ProEntitlementStorage.decode("not-json"), .free)
    }

    func testExpiredProKeepsExistingLocalDataAndManualEditsAvailable() {
        let gate = ProFeatureGate()
        let expired = ProEntitlementState.expired(
            productID: ProSubscriptionCatalog.monthlyProductID,
            expirationDate: Date(timeIntervalSince1970: 1_779_552_000)
        )

        XCTAssertFalse(expired.isProActive)
        XCTAssertTrue(gate.canAccessExistingLocalData(entitlement: expired))
        XCTAssertTrue(gate.canEditManualContent(entitlement: expired))
        XCTAssertTrue(gate.canAddShow(showsAddedThisMonth: 0, entitlement: expired))
        XCTAssertFalse(gate.canAddShow(showsAddedThisMonth: 1, entitlement: expired))
    }

    func testSettingsMembershipSummaryUsesTruthfulEntitlementCopy() {
        XCTAssertEqual(
            SettingsMembershipSummary(entitlement: .free),
            SettingsMembershipSummary(title: "免费版", subtitle: "每月可添加 1 场现场")
        )
        XCTAssertEqual(
            SettingsMembershipSummary(entitlement: .active(productID: "pro", expirationDate: nil)),
            SettingsMembershipSummary(title: "Pro 已启用", subtitle: "可以无限添加现场")
        )
        XCTAssertEqual(
            SettingsMembershipSummary(
                entitlement: .expired(productID: "pro", expirationDate: Date(timeIntervalSince1970: 0))
            ),
            SettingsMembershipSummary(title: "Pro 已过期", subtitle: "已有本地内容仍可查看和编辑")
        )
    }

    func testNotificationSettingsPresentationChoosesPermissionOrSettingsAction() {
        XCTAssertEqual(
            NotificationSettingsPresentation(authorizationState: .notDetermined),
            NotificationSettingsPresentation(
                status: "尚未开启",
                action: .requestPermission
            )
        )
        XCTAssertEqual(
            NotificationSettingsPresentation(authorizationState: .denied),
            NotificationSettingsPresentation(
                status: "未开启",
                action: .openSystemSettings
            )
        )
        XCTAssertEqual(
            NotificationSettingsPresentation(authorizationState: .authorized).action,
            .openSystemSettings
        )
        XCTAssertEqual(
            NotificationSettingsPresentation(authorizationState: .provisional).action,
            .openSystemSettings
        )
    }

    func testAppVersionInformationBuildsDisplayCopyFromInfoDictionary() {
        let version = AppVersionInformation(infoDictionary: [
            "CFBundleShortVersionString": "2.3",
            "CFBundleVersion": "42"
        ])

        XCTAssertEqual(version.compactCopy, "v2.3")
        XCTAssertEqual(version.fullCopy, "版本 2.3（构建 42）")
        XCTAssertEqual(
            AppVersionInformation(infoDictionary: [:]),
            AppVersionInformation(marketingVersion: "未知版本", buildNumber: "未知构建")
        )
    }

    func testFeedbackPayloadBuilderUsesCurrentBundleVersionByDefault() throws {
        let payload = try FeedbackPayloadBuilder().build(from: FeedbackDraft(
            category: .bug,
            message: "通知没有出现",
            includesDiagnostics: true
        ))

        XCTAssertEqual(payload.diagnostics?.appVersion, AppVersionInformation.current.marketingVersion)
    }

    func testFeedbackShareTextIncludesDiagnosticsOnlyWhenUserOptedIn() {
        let withoutDiagnostics = FeedbackShareTextBuilder().build(from: FeedbackPayload(
            category: .product,
            message: "希望更快进入状态",
            diagnostics: nil
        ))
        XCTAssertEqual(withoutDiagnostics, "类型：使用感受\n反馈：希望更快进入状态")

        let withDiagnostics = FeedbackShareTextBuilder().build(from: FeedbackPayload(
            category: .bug,
            message: "设置页卡住",
            diagnostics: FeedbackDiagnostics(appVersion: "2.3", osVersion: "iOS 26.5")
        ))
        XCTAssertEqual(
            withDiagnostics,
            "类型：问题反馈\n反馈：设置页卡住\n\n诊断信息\nApp 版本：2.3\n系统版本：iOS 26.5"
        )
    }

    func testSettingsEntriesUseExpectedOrderWithoutAccountOrSync() {
        XCTAssertEqual(SettingsInformation.orderedEntries, [
            .proMembership,
            .privacyAndLocalData,
            .feedback,
            .about
        ])

        let copy = SettingsInformation.orderedEntries.map(\.rawValue).joined(separator: " ")
        XCTAssertFalse(copy.contains("账号"))
        XCTAssertFalse(copy.contains("同步"))
        XCTAssertFalse(copy.contains("默认音乐平台"))
        XCTAssertFalse(SettingsEntry.allCases.map(\.rawValue).contains("默认音乐平台"))
    }

    func testFeedbackPayloadOnlyIncludesUserChosenContent() throws {
        let builder = FeedbackPayloadBuilder {
            FeedbackDiagnostics(appVersion: "2.1", osVersion: "iOS test")
        }

        let minimalPayload = try builder.build(from: FeedbackDraft(
            category: .product,
            message: "  希望默认平台更好切换  ",
            includesDiagnostics: false
        ))

        XCTAssertEqual(minimalPayload.message, "希望默认平台更好切换")
        XCTAssertNil(minimalPayload.diagnostics)

        let diagnosticPayload = try builder.build(from: FeedbackDraft(
            category: .bug,
            message: "设置页卡住",
            includesDiagnostics: true
        ))

        XCTAssertEqual(diagnosticPayload.diagnostics, FeedbackDiagnostics(appVersion: "2.1", osVersion: "iOS test"))
    }

    func testPurchaseFailureThrowsCancelledErrorAndKeepsStateFree() async throws {
        let store = MockProSubscriptionStore()
        await store.setSimulatedError(ProSubscriptionError.purchaseCancelled)
        
        do {
            _ = try await store.purchase(productID: ProSubscriptionCatalog.monthlyProductID)
            XCTFail("Should have thrown purchaseCancelled error")
        } catch let error as ProSubscriptionError {
            XCTAssertEqual(error, .purchaseCancelled)
        } catch {
            XCTFail("Expected ProSubscriptionError")
        }
    }

    func testRestoreFailureThrowsNothingToRestoreError() async throws {
        let store = MockProSubscriptionStore()
        await store.setSimulatedError(ProSubscriptionError.nothingToRestore)
        
        do {
            _ = try await store.restorePurchases()
            XCTFail("Should have thrown nothingToRestore error")
        } catch let error as ProSubscriptionError {
            XCTAssertEqual(error, .nothingToRestore)
        } catch {
            XCTFail("Expected ProSubscriptionError")
        }
    }

    func testPaywallCopyResolvesInEnglishAndTraditionalChinese() {
        let keys = [
            "订阅月度 Pro · %@",
            "订阅年度 Pro · %@",
            "买断终身 Pro · %@",
            "以特惠价解锁 Pro · %@",
            "暂时不要",
            "再想一下？",
            "限时优惠 · 最高 40% OFF",
            "价格暂不可用",
            "推荐",
            "无限添加现场",
            "按月订阅，随时取消",
            "一次买断，永久有效"
        ]

        for code in ["en", "zh-Hant"] {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let tablePath = Bundle(path: path)?.path(forResource: "Localizable", ofType: "strings"),
                  let table = NSDictionary(contentsOfFile: tablePath) as? [String: String] else {
                XCTFail("Missing \(code) Localizable.strings in app bundle")
                continue
            }
            for key in keys {
                XCTAssertNotNil(table[key], "\(key) missing from \(code) Localizable.strings")
            }
        }
    }

    func testFollowingSystemLanguageDropsManualOverrideImmediately() {
        let originalAppLanguage = UserDefaults.standard.string(forKey: AppLanguageManager.storageKey)
        let originalAppleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages")
        // apply() 会把语言选择同步到 App Group(供组件进程读取),同样要还原,
        // 否则测试残留会让模拟器上的 widget 一直按最后一次 apply 的语言渲染。
        let groupDefaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)
        let originalGroupLanguage = groupDefaults?.string(forKey: AppLanguageManager.storageKey)
        defer {
            if let originalAppleLanguages {
                UserDefaults.standard.set(originalAppleLanguages, forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            if let originalAppLanguage {
                UserDefaults.standard.set(originalAppLanguage, forKey: AppLanguageManager.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguageManager.storageKey)
            }
            if let originalGroupLanguage {
                groupDefaults?.set(originalGroupLanguage, forKey: AppLanguageManager.storageKey)
            } else {
                groupDefaults?.removeObject(forKey: AppLanguageManager.storageKey)
            }
        }

        AppLanguageManager.apply(.zhHant)
        XCTAssertEqual(BSLocalization.text("跟随系统"), "跟隨系統")

        AppLanguageManager.apply(.en)
        XCTAssertEqual(BSLocalization.text("跟随系统"), "Follow System")

        // 切回「跟随系统」后应实时落到系统语言，而不是继续停留在手动语言。
        AppLanguageManager.apply(.system)
        XCTAssertNotEqual(BSLocalization.text("跟随系统"), "跟隨系統")
        XCTAssertEqual(
            BSLocalization.text("跟随系统"),
            AppLanguage.systemBundle()?.localizedString(forKey: "跟随系统", value: nil, table: nil)
        )
    }

    func testSystemLanguageResolvesToASupportedLocalizationBundle() {
        XCTAssertNotNil(AppLanguage.system.bundle)
        let resolved = AppLanguage.system.bundle?.preferredLocalizations.first
        XCTAssertTrue(["zh-Hans", "zh-Hant", "en"].contains(resolved), "resolved \(resolved ?? "nil")")
    }

    func testCatalogReferenceProductsAreNotPurchasablePlaceholders() {
        XCTAssertTrue(ProSubscriptionCatalog.defaultProducts.allSatisfy { !$0.isAvailable })
    }

    func testMockStoreMarksLoadedProductsAvailable() async throws {
        let products = try await MockProSubscriptionStore().loadProducts()
        XCTAssertEqual(products.count, 5)
        XCTAssertTrue(products.allSatisfy(\.isAvailable))
    }

    func testWinbackPlanFlagCoversOnlyDiscountPlans() {
        XCTAssertTrue(ProSubscriptionPlan.yearlyDiscount.isWinback)
        XCTAssertTrue(ProSubscriptionPlan.lifetimeDiscount.isWinback)
        XCTAssertFalse(ProSubscriptionPlan.monthly.isWinback)
        XCTAssertFalse(ProSubscriptionPlan.yearly.isWinback)
        XCTAssertFalse(ProSubscriptionPlan.lifetime.isWinback)
    }

    func testActiveProRejectsLifetimeDiscountPurchase() async throws {
        let active = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.yearlyProductID,
            expirationDate: nil
        )
        let store = MockProSubscriptionStore(entitlement: active)

        do {
            _ = try await store.purchase(productID: ProSubscriptionCatalog.lifetimeDiscountProductID)
            XCTFail("Winback purchase while Pro active should be rejected")
        } catch let error as ProSubscriptionError {
            XCTAssertEqual(error, .winbackNotAvailableWhileActive)
        } catch {
            XCTFail("Expected ProSubscriptionError.winbackNotAvailableWhileActive, got \(error)")
        }
    }

    func testActiveProRejectsYearlyDiscountPurchase() async throws {
        let active = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.monthlyProductID,
            expirationDate: nil
        )
        let store = MockProSubscriptionStore(entitlement: active)

        do {
            _ = try await store.purchase(productID: ProSubscriptionCatalog.yearlyDiscountProductID)
            XCTFail("Winback purchase while Pro active should be rejected")
        } catch let error as ProSubscriptionError {
            XCTAssertEqual(error, .winbackNotAvailableWhileActive)
        } catch {
            XCTFail("Expected ProSubscriptionError.winbackNotAvailableWhileActive, got \(error)")
        }
    }

    func testActiveProAllowsStandardPlanPurchase() async throws {
        let active = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.monthlyProductID,
            expirationDate: nil
        )
        let store = MockProSubscriptionStore(entitlement: active)

        let purchased = try await store.purchase(productID: ProSubscriptionCatalog.lifetimeProductID)

        XCTAssertEqual(
            purchased,
            .active(productID: ProSubscriptionCatalog.lifetimeProductID, expirationDate: nil)
        )
    }

    func testFreeProAllowsWinbackPurchase() async throws {
        let store = MockProSubscriptionStore(entitlement: .free)

        let purchased = try await store.purchase(
            productID: ProSubscriptionCatalog.lifetimeDiscountProductID
        )

        XCTAssertEqual(
            purchased,
            .active(productID: ProSubscriptionCatalog.lifetimeDiscountProductID, expirationDate: nil)
        )
        XCTAssertTrue(purchased.isProActive)
    }

    func testExpiredProAllowsWinbackPurchase() async throws {
        let expired = ProEntitlementState.expired(
            productID: ProSubscriptionCatalog.yearlyProductID,
            expirationDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let store = MockProSubscriptionStore(entitlement: expired)

        let purchased = try await store.purchase(
            productID: ProSubscriptionCatalog.yearlyDiscountProductID
        )

        XCTAssertEqual(
            purchased,
            .active(productID: ProSubscriptionCatalog.yearlyDiscountProductID, expirationDate: nil)
        )
    }
}
