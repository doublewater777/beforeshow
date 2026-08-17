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
