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

    func testProGateAllowsOneFreeShowAndFirstGenerationOnly() {
        let gate = ProFeatureGate()
        let proEntitlement = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.yearlyProductID,
            expirationDate: nil
        )

        XCTAssertTrue(gate.canAddShow(savedShowCount: 0, entitlement: .free))
        XCTAssertFalse(gate.canAddShow(savedShowCount: 1, entitlement: .free))
        XCTAssertTrue(gate.canAddShow(savedShowCount: 10, entitlement: proEntitlement))

        XCTAssertTrue(gate.canGenerate(
            feature: .candidateSongs,
            hasUsedFreeAllowance: false,
            entitlement: .free
        ))
        XCTAssertFalse(gate.canGenerate(
            feature: .candidateSongs,
            hasUsedFreeAllowance: true,
            entitlement: .free
        ))
        XCTAssertTrue(gate.canGenerate(
            feature: .candidateSongs,
            hasUsedFreeAllowance: true,
            entitlement: proEntitlement
        ))
    }

    func testFreeGenerationAllowanceIsTrackedPerFeature() {
        let gate = ProFeatureGate()
        let usage = ProUsageSnapshot(
            savedShowCount: 1,
            usedFreeGenerationFeatures: [.candidateSongs, .outboundTripDraft]
        )

        XCTAssertFalse(gate.canGenerate(feature: .candidateSongs, usage: usage, entitlement: .free))
        XCTAssertFalse(gate.canGenerate(feature: .outboundTripDraft, usage: usage, entitlement: .free))
        XCTAssertTrue(gate.canGenerate(feature: .returnTripDraft, usage: usage, entitlement: .free))
    }

    func testProLimitReasonsMapToExpectedUserFacingCopy() {
        XCTAssertEqual(ProLimitReason.saveLimit.title, "免费版可保存 1 场现场")
        XCTAssertEqual(ProLimitReason.saveLimit.message, "开通 Pro 后可以无限保存现场。")

        XCTAssertEqual(ProLimitReason.candidateSongsRegeneration.title, "重复生成需要 Pro")
        XCTAssertTrue(ProLimitReason.candidateSongsRegeneration.message.contains("候选曲目"))
        XCTAssertTrue(ProLimitReason.roundTripRegeneration.message.contains("去程和返程计划"))
    }

    func testEntitlementAndFreeUsageCanBePersistedForAppGates() {
        let active = ProEntitlementState.active(
            productID: ProSubscriptionCatalog.yearlyProductID,
            expirationDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encodedEntitlement = ProEntitlementStorage.encode(active)

        XCTAssertEqual(ProEntitlementStorage.decode(encodedEntitlement), active)
        XCTAssertEqual(ProEntitlementStorage.decode("not-json"), .free)

        let used = ProUsageStorage.markUsed(.candidateSongs, in: "")
        XCTAssertEqual(ProUsageStorage.decodeUsedFreeGenerationFeatures(used), [.candidateSongs])

        let usedTwice = ProUsageStorage.markUsed(.returnTripDraft, in: used)
        XCTAssertEqual(
            ProUsageStorage.decodeUsedFreeGenerationFeatures(usedTwice),
            [.candidateSongs, .returnTripDraft]
        )
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
        XCTAssertTrue(gate.canAddShowFragment(entitlement: expired))
        XCTAssertFalse(gate.canAddShow(savedShowCount: 1, entitlement: expired))
        XCTAssertFalse(gate.canGenerate(feature: .candidateSongs, hasUsedFreeAllowance: true, entitlement: expired))
    }

    func testSettingsEntriesUseExpectedOrderWithoutAccountOrSync() {
        XCTAssertEqual(SettingsInformation.orderedEntries, [
            .proMembership,
            .defaultMusicPlatform,
            .privacyAndLocalData,
            .feedback,
            .about
        ])

        let copy = SettingsInformation.orderedEntries.map(\.rawValue).joined(separator: " ")
        XCTAssertFalse(copy.contains("账号"))
        XCTAssertFalse(copy.contains("同步"))
    }

    func testPrivacyCopyCoversRequiredBoundaries() {
        let copy = (PrivacyLocalDataCopy.points + [PrivacyLocalDataCopy.clearDataExplanation])
            .joined(separator: " ")

        XCTAssertTrue(copy.contains("设备端 OCR"))
        XCTAssertTrue(copy.contains("相册引用"))
        XCTAssertTrue(copy.contains("App 内创建的语音片段"))
        XCTAssertTrue(copy.contains("用户主动触发"))
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
        XCTAssertTrue(plan.deletesAppOwnedData.contains(where: { $0.contains("App 内录音") }))
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
