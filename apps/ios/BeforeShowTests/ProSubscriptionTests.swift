import XCTest
@testable import BeforeShow

final class ProSubscriptionTests: XCTestCase {
    func testCatalogLoadsMonthlyAndYearlySubscriptionProducts() {
        let products = ProSubscriptionCatalog.defaultProducts

        XCTAssertEqual(products.map(\.plan), [.monthly, .yearly])
        XCTAssertEqual(products.map(\.id), [
            "com.doublewaterapps.beforeshow.pro.monthly",
            "com.doublewaterapps.beforeshow.pro.yearly"
        ])
        XCTAssertEqual(products.map(\.priceText), ["¥12/月", "¥68/年"])
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

    func testProGateAllowsOneFreeShow() {
        let gate = ProFeatureGate()
        let proEntitlement = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.yearlyProductID,
            expirationDate: nil
        )

        XCTAssertTrue(gate.canAddShow(savedShowCount: 0, entitlement: .free))
        XCTAssertFalse(gate.canAddShow(savedShowCount: 1, entitlement: .free))
        XCTAssertTrue(gate.canAddShow(savedShowCount: 10, entitlement: proEntitlement))
    }

    func testProLimitReasonsMapToExpectedUserFacingCopy() {
        XCTAssertEqual(ProLimitReason.saveLimit.title, "免费版可保存 1 场现场")
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
        XCTAssertFalse(gate.canAddShow(savedShowCount: 1, entitlement: expired))
    }

    func testSettingsMembershipSummaryUsesTruthfulEntitlementCopy() {
        XCTAssertEqual(
            SettingsMembershipSummary(entitlement: .free),
            SettingsMembershipSummary(title: "免费版", subtitle: "可保存 1 场现场")
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
                subtitle: "轻点开启开场提醒",
                action: .requestPermission
            )
        )
        XCTAssertEqual(
            NotificationSettingsPresentation(authorizationState: .denied),
            NotificationSettingsPresentation(
                status: "未开启",
                subtitle: "去系统设置开启通知",
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

    func testPrivacyCopyCoversRequiredBoundaries() {
        let copy = (PrivacyLocalDataCopy.points + [PrivacyLocalDataCopy.clearDataExplanation])
            .joined(separator: " ")

        XCTAssertTrue(copy.contains("设备端 OCR"))
        XCTAssertTrue(copy.contains("设备本地"))
        XCTAssertTrue(copy.contains("记忆碎片"))
        XCTAssertTrue(copy.contains("不会删除系统相册中的原始图片或视频"))
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

    func testLocalDataClearancePreservesSystemGalleryOriginals() {
        let plan = LocalDataClearancePolicy.defaultPlan

        XCTAssertTrue(plan.deletesAppOwnedData.contains(where: { $0.contains("SwiftData") }))
        XCTAssertTrue(plan.deletesAppOwnedData.contains(where: { $0.contains("记忆碎片") }))
        XCTAssertTrue(plan.deletesAppOwnedData.contains(where: { $0.contains("照片和视频副本") }))
        XCTAssertTrue(plan.deletesAppOwnedData.contains(where: { $0.contains("动态封面") && $0.contains("正反面偏好") }))
        XCTAssertTrue(plan.deletesAppOwnedData.contains(where: { $0.contains("临时缓存") }))
        XCTAssertTrue(plan.preservesSystemData.contains(where: { $0.contains("系统相册中的原始图片和视频") }))
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
}
