#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = IOS_ROOT.parents[1]

# Legacy files that are already too large, plus isolated feature files whose
# responsibilities should remain bounded after extraction.
HOTSPOT_BUDGETS = {
    "BeforeShow/RootView.swift": 12_000,
    "BeforeShow/UI/DesignSystem/BSTokens.swift": 11_000,
    "BeforeShow/UI/DesignSystem/BSChrome.swift": 8_000,
    "BeforeShow/UI/DesignSystem/BSStagePresentation.swift": 14_000,
    "BeforeShow/UI/DesignSystem/BSInteractionComponents.swift": 10_000,
    "BeforeShow/UI/DesignSystem/BSShowCoverComponents.swift": 12_000,
    "BeforeShow/UI/DesignSystem/BSArtistComponents.swift": 5_000,
    "BeforeShow/UI/DesignSystem/BSDrawerComponents.swift": 8_000,
    "BeforeShow/Features/Settings/SettingsView.swift": 22_000,
    "BeforeShow/Features/Settings/SettingsDebugViews.swift": 6_000,
    "BeforeShow/Features/Settings/PrivacyLocalDataView.swift": 13_000,
    "BeforeShow/Features/Settings/FeedbackView.swift": 8_000,
    "BeforeShow/Features/Settings/LanguageSettingsView.swift": 4_000,
    "BeforeShow/Features/Settings/AboutBeforeShowView.swift": 6_000,
    "BeforeShow/Features/Shows/ShowDetailView.swift": 35_000,
    "BeforeShow/Features/Shows/ShowDetailSheets.swift": 9_000,
    "BeforeShow/Features/Shows/ShowDetailPresentationSupport.swift": 7_000,
    "BeforeShow/Features/Shows/ShowCoverFullscreenPreview.swift": 8_000,
    "BeforeShow/Infrastructure/Notifications/NotificationSchedulingModels.swift": 13_000,
    "BeforeShow/Infrastructure/Notifications/LocalNotificationScheduler.swift": 19_000,
    "BeforeShow/Infrastructure/Notifications/NotificationDeepLink.swift": 6_000,
    "BeforeShow/Infrastructure/Notifications/ScheduledNotificationRequest.swift": 5_000,
    "BeforeShow/Infrastructure/Notifications/LocalNotificationCenter.swift": 14_000,
    "BeforeShow/Infrastructure/Notifications/NotificationDeepLinkRouting.swift": 8_000,
    "BeforeShow/Features/Shows/CurrentShowLibraryManagementView.swift": 27_000,
    "BeforeShow/Features/Shows/CurrentShowLibraryPolicies.swift": 6_000,
    "BeforeShow/Features/Shows/CurrentShowLibraryRows.swift": 11_000,
    "BeforeShow/Features/Footprints/FootprintDetailView.swift": 33_000,
    "BeforeShow/Features/Footprints/FootprintDetailPresentationSupport.swift": 7_000,
    "BeforeShow/Features/Footprints/FootprintDetailMediaComponents.swift": 12_000,
    "BeforeShow/Features/Companion/CompanionSharingCoordinator.swift": 22_000,
    "BeforeShow/Features/Companion/CompanionAcceptedShareInbox.swift": 5_000,
    "BeforeShow/Features/Companion/CompanionCloudSyncMarker.swift": 5_000,
    "BeforeShow/Features/Companion/CompanionAcceptedSessionImporter.swift": 8_000,
    "BeforeShow/Features/Companion/CompanionSharingPresentation.swift": 6_000,
    "BeforeShow/Features/Subscription/ProPaywallView.swift": 21_000,
    "BeforeShow/Features/Subscription/ProPaywallSupport.swift": 6_000,
    "BeforeShow/Features/Subscription/ProPaywallPresentation.swift": 12_000,
    "BeforeShow/Features/Subscription/ProPaywallPlanSelectionView.swift": 7_000,
    "BeforeShow/Features/Subscription/ProPaywallWinbackView.swift": 9_000,
    "BeforeShow/Features/Subscription/ProPaywallStoreFactory.swift": 3_000,
    "BeforeShow/Features/CurrentShow/DispersalLightsOutView.swift": 8_000,
    "BeforeShow/Features/CurrentShow/DispersalCeremonySheet.swift": 18_000,
    "BeforeShow/Features/CurrentShow/DispersalCeremonyShareView.swift": 10_000,
    "BeforeShow/Features/CurrentShow/HomeCountdownCard.swift": 24_000,
    "BeforeShow/Features/CurrentShow/HomeCountdownPresentation.swift": 14_000,
    "BeforeShow/Features/CurrentShow/HomeLivePulse.swift": 3_000,
    "BeforeShow/Features/CurrentShow/ShowAssetSheet.swift": 8_000,
    "BeforeShow/Features/CurrentShow/ShowAssetUploadView.swift": 19_000,
    "BeforeShow/Features/CurrentShow/ShowAssetViewerView.swift": 14_000,
    "BeforeShow/Infrastructure/Media/MemoryFragmentMediaStore.swift": 4_000,
    "BeforeShow/Infrastructure/Media/MemoryFragmentMediaTypes.swift": 10_000,
    "BeforeShow/Infrastructure/Media/MemoryFragmentMediaStaging.swift": 12_000,
    "BeforeShow/Infrastructure/Media/MemoryFragmentMediaCommit.swift": 9_000,
    "BeforeShow/Infrastructure/Media/MemoryFragmentMediaMaintenance.swift": 9_000,
    "BeforeShow/Infrastructure/Media/MemoryFragmentMediaFileSupport.swift": 4_000,
    "BeforeShow/Features/DynamicCover/DynamicCoverPresentation.swift": 20_000,
    "BeforeShow/Features/DynamicCover/DynamicCoverPlaybackView.swift": 14_000,
    "BeforeShow/Features/CurrentShow/DynamicCoverManagementSection.swift": 16_000,
    "BeforeShow/Features/CurrentShow/DynamicCoverImportCoordinator.swift": 11_000,
    "BeforeShow/Features/Footprints/FootprintDynamicCoverSection.swift": 8_000,
    "BeforeShow/Features/Memory/MemoryViewerVideoPage.swift": 7_000,
    "BeforeShow/Infrastructure/Media/AppAudioSession.swift": 5_000,
    "BeforeShow/Infrastructure/Media/DynamicCoverAudioTrackProbe.swift": 4_000,
    "BeforeShow/Features/Footprints/FootprintArchiveRanking.swift": 20_000,
    "BeforeShow/Features/Footprints/FootprintCityMapping.swift": 12_000,
    "BeforeShow/Features/Footprints/FootprintArchiveCovers.swift": 10_000,
    "BeforeShow/Features/Footprints/FootprintArchiveVisibility.swift": 5_000,
    "BeforeShow/Features/Footprints/FootprintArtistArtworkWriteback.swift": 4_000,
    "BeforeShow/Infrastructure/Media/DynamicCoverMediaStore.swift": 7_000,
    "BeforeShow/Infrastructure/Media/DynamicCoverMediaTypes.swift": 9_000,
    "BeforeShow/Infrastructure/Media/DynamicCoverMediaStaging.swift": 8_000,
    "BeforeShow/Infrastructure/Media/DynamicCoverMediaCommit.swift": 7_000,
    "BeforeShow/Infrastructure/Media/DynamicCoverMediaMaintenance.swift": 11_000,
    "BeforeShow/Infrastructure/Media/DynamicCoverMediaFileSupport.swift": 5_000,
    "BeforeShow/Features/CurrentShow/DynamicCoverPresentationSupport.swift": 4_000,
    "BeforeShow/Features/Subscription/ProOfferDeepLinkRouter.swift": 3_000,
    "BeforeShow/Features/Subscription/ProSubscriptionCatalog.swift": 9_000,
    "BeforeShow/Features/Subscription/ProEntitlement.swift": 6_000,
    "BeforeShow/Features/Subscription/ProSubscriptionStore.swift": 3_000,
    "BeforeShow/Features/Subscription/MockProSubscriptionStore.swift": 6_000,
    "BeforeShow/Features/Subscription/RevenueCatProSubscriptionStore.swift": 13_000,
    "BeforeShow/Features/Subscription/ProLimitPresentation.swift": 4_000,
    "BeforeShow/Features/Subscription/ProFeatureGate.swift": 6_000,
    "BeforeShow/Features/Settings/SettingsCatalog.swift": 3_000,
    "BeforeShow/Features/Settings/SettingsLanguageSupport.swift": 8_000,
    "BeforeShow/Features/Settings/SettingsMembershipPresentation.swift": 3_000,
    "BeforeShow/Features/Settings/SettingsNotificationPresentation.swift": 3_000,
    "BeforeShow/Features/Settings/AppVersionInformation.swift": 3_000,
    "BeforeShow/Features/Settings/SettingsFeedbackSupport.swift": 8_000,
    "BeforeShow/Features/Settings/LocalDataInventory.swift": 6_000,
    "BeforeShow/Infrastructure/Media/ShowAssetCleanupRetry.swift": 8_000,
    "BeforeShow/Infrastructure/Widgets/WidgetDataSync.swift": 20_000,
    "BeforeShow/Features/Footprints/FootprintDebugSeeder.swift": 18_000,
    "BeforeShow/Features/Footprints/FootprintShareComposerView.swift": 18_000,
    "BeforeShow/Infrastructure/Parsing/ShowLinkParsingService.swift": 18_000,
    "BeforeShow/Infrastructure/Media/ShowAssetMediaStore.swift": 17_000,
    "BeforeShow/Features/Onboarding/OnboardingFeatureVisuals.swift": 16_000,
    "BeforeShow/Infrastructure/Places/VenueAddressAutocomplete.swift": 16_000,
    "BeforeShow/Domain/Shows/ShowMutationCoordinator.swift": 15_000,
    "BeforeShow/Features/CurrentShow/HomeHeroPresentation.swift": 12_000,
    "BeforeShow/Features/CurrentShow/CurrentShowHomeView.swift": 24_000,
    "BeforeShow/Features/CurrentShow/CurrentShowManagementView.swift": 26_000,
    "BeforeShow/Features/CurrentShow/CurrentShowCompanionView.swift": 28_000,
    "BeforeShow/Features/CurrentShow/CurrentShowFollowUpView.swift": 8_000,
    "BeforeShow/Features/CurrentShow/CurrentShowQuickActionsView.swift": 9_000,
    "BeforeShow/Features/CurrentShow/CurrentShowRoutePresentation.swift": 5_000,
    "BeforeShow/Features/AddShow/AddShowFlowView.swift": 48_000,
    "BeforeShow/Features/AddShow/AddShowImportPresentation.swift": 15_000,
    "BeforeShow/Features/AddShow/AddShowPresentationPrimitives.swift": 6_000,
    "BeforeShow/Features/AddShow/ShowCoverLifecycle.swift": 4_000,
    "BeforeShow/Features/AddShow/ShowDraftPresentationSupport.swift": 3_000,
    "BeforeShow/Features/AddShow/AddShowCoordinatorView.swift": 9_000,
    "BeforeShow/Features/AddShow/AddShowPersistence.swift": 9_000,
    "BeforeShow/Features/AddShow/AddShowConfirmationView.swift": 12_000,
    "BeforeShow/Features/AddShow/ShowDraftEditorView.swift": 26_000,
    "BeforeShow/Features/AddShow/ShowDraftFormFields.swift": 20_000,
    "BeforeShow/Features/AddShow/ShowDraftScheduleFields.swift": 13_000,
    "BeforeShow/Features/AddShow/ShowDraftArtistFields.swift": 9_000,
    "BeforeShow/Features/AddShow/ShowDraftCoverFields.swift": 7_000,
    "BeforeShow/Features/AddShow/ShowDraftFieldComponents.swift": 4_000,
    "BeforeShow/Features/Footprints/FootprintsView.swift": 17_000,
    "BeforeShow/Features/Footprints/FootprintArchiveDomain.swift": 7_000,
    "BeforeShow/Features/Footprints/FootprintArchivePresentationSupport.swift": 12_000,
    "BeforeShow/Features/Footprints/FootprintArchiveShareCopy.swift": 7_000,
    "BeforeShow/Features/Footprints/FootprintArchiveShareView.swift": 14_000,
    "BeforeShow/Features/Footprints/FootprintArtistViews.swift": 19_000,
    "BeforeShow/Features/Footprints/FootprintCityArchiveViews.swift": 24_000,
    "BeforeShow/Features/Footprints/FootprintCoverViews.swift": 8_000,
    "BeforeShow/Features/Footprints/FootprintDashboardSections.swift": 30_000,
    "BeforeShow/Features/Footprints/FootprintDashboardView.swift": 6_000,
    "BeforeShow/Features/Footprints/FootprintDateFormatting.swift": 2_000,
    "BeforeShow/Features/Footprints/FootprintMemoriesArchiveView.swift": 12_000,
    "BeforeShow/Features/Footprints/FootprintOverviewShareSheet.swift": 3_000,
    "BeforeShow/Features/Footprints/FootprintPageShareView.swift": 7_000,
    "BeforeShow/Features/Footprints/FootprintPhotoLibrary.swift": 3_000,
    "BeforeShow/Features/Footprints/FootprintPresentationSupport.swift": 2_000,
    "BeforeShow/Features/Footprints/FootprintSearchSheet.swift": 8_000,
    "BeforeShow/Features/Footprints/FootprintShareActionSheet.swift": 10_000,
    "BeforeShow/Features/Footprints/FootprintShareExport.swift": 8_000,
    "BeforeShow/Features/Footprints/FootprintVenueArchiveView.swift": 14_000,
    "BeforeShow/Features/Footprints/FootprintYearArchiveView.swift": 19_000,
    "BeforeShow/Features/Memory/MemoryFragmentsView.swift": 32_000,
    "BeforeShow/Features/Memory/MemoryUnifiedEditorView.swift": 32_000,
    "BeforeShow/Features/Memory/MemoryPresentationModels.swift": 6_000,
    "BeforeShow/Features/Memory/MemoryCreateSheets.swift": 6_000,
    "BeforeShow/Features/Memory/MemoryFragmentEditCoordinator.swift": 6_000,
    "BeforeShow/Features/Memory/MemoryTimelineViews.swift": 11_000,
    "BeforeShow/Features/Memory/MemoryReviewViewer.swift": 13_000,
    "BeforeShow/Features/Memory/MemoryCameraPicker.swift": 4_000,
    "BeforeShow/App/BeforeShowApp.swift": 12_000,
    "BeforeShow/App/AppLifecycleMaintenance.swift": 9_000,
    "BeforeShow/App/AppPersistenceReconciliation.swift": 10_000,
    "BeforeShow/Features/Companion/CloudKitCompanionSharingService.swift": 4_000,
    "BeforeShow/Features/Companion/CloudKitCompanionInvitation.swift": 8_000,
    "BeforeShow/Features/Companion/CloudKitCompanionSessionOperations.swift": 18_000,
    "BeforeShow/Features/Companion/CloudKitCompanionSupport.swift": 9_000,
    "BeforeShow/Features/Companion/CompanionSharingModels.swift": 8_000,
    "BeforeShow/Features/Companion/CompanionSharingService.swift": 3_000,
    "BeforeShow/Features/Companion/CompanionShowMapping.swift": 5_000,
    "BeforeShow/Domain/Shows/Show.swift": 24_000,
    "BeforeShow/Domain/Shows/ShowDraft.swift": 10_000,
    "BeforeShow/Infrastructure/Parsing/ShowScreenshotRecognitionService.swift": 20_000,
    "BeforeShow/Infrastructure/Vision/OnDeviceShowScreenshotRecognizer.swift": 5_000,
    "BeforeShow/Infrastructure/Parsing/ShowLinkDraftParser.swift": 8_000,
    "BeforeShow/App/CompanionAppDelegates.swift": 6_000,
    "BeforeShow/Supporting/Debug/DebugSampleShowSeeder.swift": 30_000,
    "BeforeShow/Supporting/Debug/AppStoreWidgetPreviewView.swift": 7_000,
}

# Once a hotspot has been retired, do not allow a later change to recreate it
# and silently restart the flat-file architecture.
RETIRED_LEGACY_FILES = (
    "BeforeShow/AddShowFlowViews.swift",
    "BeforeShow/FootprintsArchive.swift",
    "BeforeShow/FootprintArchiveViews.swift",
    "BeforeShow/MemoryFragmentsView.swift",
    "BeforeShow/BeforeShowApp.swift",
    "BeforeShow/CompanionSharing.swift",
    "BeforeShow/UI/DesignSystem.swift",
    "BeforeShow/Features/Settings/SettingsViews.swift",
    "BeforeShow/Features/Settings/SettingsSupport.swift",
    "BeforeShow/Infrastructure/Notifications/LocalNotificationScheduling.swift",
    "BeforeShow/Features/CurrentShow/DispersalCeremonyViews.swift",
    "BeforeShow/Features/CurrentShow/ShowAssetViews.swift",
    "BeforeShow/Features/CurrentShow/DynamicCoverViews.swift",
    "BeforeShow/Features/CurrentShow/DynamicCoverPlayback.swift",
    "BeforeShow/Features/Shows/ShowDetailViews.swift",
    "BeforeShow/Features/Shows/ShowLibraryViews.swift",
    "BeforeShow/Features/AddShow/ShowDraft.swift",
    "BeforeShow/Features/Footprints/FootprintShareViews.swift",
    "BeforeShow/Features/Footprints/FootprintArchiveEnhancements.swift",
    "BeforeShow/Features/Subscription/ProSubscription.swift",
    "BeforeShow/Features/Footprints/FootprintArchiveDetailView.swift",
)

ROOT_SWIFT_ALLOWLIST = ("RootView.swift",)

ROOT_VIEW_FORBIDDEN_TOKENS = (
    "struct AppStoreWidgetPreviewView",
    "enum DebugSampleShowSeeder",
    "import PhotosUI",
    "PhotosPickerItem",
    "DynamicCoverImportCoordinator",
    "WidgetDataSync.sync",
    "LocalNotificationCenter.shared.reconcilePortfolio",
    "struct CurrentShowManagementSection",
    "struct CurrentShowCompanionSheet",
)

HOME_HERO_FORBIDDEN_TOKENS = (
    "import PhotosUI",
    "struct CurrentShowHomeView",
    "struct CurrentShowManagementSection",
    "struct CurrentShowCompanionSheet",
)

MANAGEMENT_VIEW_FORBIDDEN_TOKENS = (
    "struct CurrentShowFollowUpSummary",
    "enum CurrentShowQuickAction",
    "struct CurrentShowQuickActionTile",
    "struct CompanionAvatarStack",
    "struct MapChooserSheet",
)

ADD_SHOW_FLOW_FORBIDDEN_TOKENS = (
    "struct AddShowLinkFailurePresentation",
    "struct AddShowMultilineInput",
    "struct AddShowNoteCard",
    "struct AddShowLinkFailureCard",
    "struct AddShowImportedBanner",
    "struct AddShowOCRStepsView",
    "struct EditShowFormCard",
    "struct AddShowInputChrome",
    "struct EditShowSaveButtonStyle",
    "enum ShowCoverLocalImageStore",
    "struct ShowCoverLifecycle",
    "struct ShowDraftFormFields",
    "struct AddShowScheduleFields",
    "struct AddShowCoverActions",
    "struct ArtistInputRow",
    "struct AddShowLabeledTextField",
)

SHOW_DRAFT_FORM_FORBIDDEN_TOKENS = (
    "struct AddShowScheduleFields",
    "struct AddShowCoverActions",
    "struct AddShowCoverActionChip",
    "struct ArtistInputRow",
    "struct ArtistSearchPicker",
    "struct AddShowLabeledTextField",
    "struct AddShowFieldLabel",
)

FOOTPRINTS_VIEW_FORBIDDEN_TOKENS = (
    "enum FootprintCategory",
    "struct FootprintRankItem",
    "struct FootprintYearGroup",
    "struct PreparedFootprint",
    "struct FootprintArchiveSnapshot",
    "enum FootprintArchiveBuilder",
    "enum FootprintArchiveShareCopy",
    "enum FootprintPhotoLibrary",
    "struct FootprintSearchSheet",
    "struct FootprintArchiveDetailView",
    "struct FootprintShareActionSheet",
    "struct FootprintArchiveShareSheet",
    "struct FootprintArchiveShareCard",
    "private func header(_ archive: FootprintArchiveSnapshot)",
    "private func discovery(_ archive: FootprintArchiveSnapshot)",
    "private func showRow(_ show: Show)",
    "private func showDurationText(_ show: Show)",
)

FOOTPRINT_DASHBOARD_VIEW_FORBIDDEN_TOKENS = (
    "struct FootprintDashboardSections",
    "struct FootprintYearArchiveView",
    "struct FootprintArtistArchiveView",
    "struct FootprintCityArchiveView",
    "struct FootprintVenueArchiveView",
    "struct FootprintMemoriesArchiveView",
    "struct FootprintCoverView",
)

FOOTPRINT_DETAIL_VIEW_FORBIDDEN_TOKENS = (
    "enum FootprintDetailTokens",
    "enum FootprintPlaybackPolicy",
    "struct FootprintMemoryTile",
    "struct FootprintKeepsakeTile",
    "struct FootprintLocalImage",
)

DISPERSAL_CEREMONY_SHEET_FORBIDDEN_TOKENS = (
    "struct DispersalLightsOutOverlay",
    "enum DispersalCeremonyShareExport",
    "struct DispersalCeremonyShareSheet",
    "struct DispersalShareStep",
)

SHOW_ASSET_SHEET_FORBIDDEN_TOKENS = (
    "enum ShowAssetEditorOperation",
    "struct ShowAssetUploadView",
    "struct ShowAssetViewerView",
)

HOME_COUNTDOWN_CARD_FORBIDDEN_TOKENS = (
    "enum HomeCountdownDisplayState",
    "enum HomeCountdownPresentationPolicy",
    "enum HomeShowIdentityPresentation",
    "struct HomeLivePulse",
)

MEMORY_FRAGMENTS_VIEW_FORBIDDEN_TOKENS = (
    "struct MemoryUnifiedEditorView",
    "struct MemoryTimelineSection",
    "struct MemoryFragmentReviewView",
    "struct MemoryMediaViewer",
    "struct SystemMemoryCameraPicker",
    "enum MemoryFragmentEditCoordinator",
    "struct MemoryAddMediaSheet",
)

APP_ENTRY_FORBIDDEN_TOKENS = (
    "enum ForegroundMediaMaintenancePolicy",
    "func retryPendingShowAssetCleanupIfNeeded",
    "func retryPendingFullCleanup",
    "func reconcileAllMemoryMedia",
    "func reconcileMemoryFragmentShowBoundary",
    "func saveModelContextRollingBackOnFailure",
    "func reconcileAllShowAssets",
    "func reconcileAllDynamicCovers",
    "func reconcileDynamicCoverModelBoundary",
    "func reconcileShowAssetShowBoundary",
)

COMPANION_COORDINATOR_FORBIDDEN_TOKENS = (
    "final class BeforeShowAppDelegate",
    "final class BeforeShowSceneDelegate",
    "extension Show",
    "NSKeyedArchiver",
    "NSKeyedUnarchiver",
    "SecItem",
    "ShowCreationOriginMigration",
    "BSLocalization",
)

COMPANION_ACCEPTED_INBOX_FORBIDDEN_TOKENS = (
    "import Security",
    "ModelContext",
    "ShowCreationOriginMigration",
    "BSLocalization",
)

COMPANION_CLOUD_SYNC_MARKER_FORBIDDEN_TOKENS = (
    "import CloudKit",
    "CKShare.Metadata",
    "ModelContext",
    "BSLocalization",
)

COMPANION_SESSION_IMPORTER_FORBIDDEN_TOKENS = (
    "UserDefaults",
    "NSKeyedArchiver",
    "NSKeyedUnarchiver",
    "SecItem",
    "BSLocalization",
)

COMPANION_PRESENTATION_FORBIDDEN_TOKENS = (
    "UserDefaults",
    "ModelContext",
    "NSKeyedArchiver",
    "NSKeyedUnarchiver",
    "SecItem",
    "ShowCreationOriginMigration",
)

SETTINGS_ROOT_FORBIDDEN_TOKENS = (
    "struct PrivacyLocalDataView",
    "struct FeedbackView",
    "struct LanguageSettingsView",
    "struct AboutBeforeShowView",
    "enum DebugProEntitlementOption",
)

SETTINGS_CATALOG_FORBIDDEN_TOKENS = (
    "AppLanguageManager",
    "FeedbackPayloadBuilder",
    "LocalDataInventoryService",
    "ShowAssetCleanupRetry",
)

SETTINGS_LANGUAGE_FORBIDDEN_TOKENS = (
    "ModelContext",
    "FeedbackPayloadBuilder",
    "LocalDataInventoryService",
    "ShowAssetCleanupRetry",
)

SETTINGS_PRESENTATION_FORBIDDEN_TOKENS = (
    "UserDefaults",
    "WidgetCenter",
    "ModelContext",
    "UIApplication",
)

SETTINGS_FEEDBACK_FORBIDDEN_TOKENS = (
    "ModelContext",
    "WidgetCenter",
    "ShowAssetCleanupRetry",
    "ProEntitlementState",
)

SETTINGS_LOCAL_DATA_FORBIDDEN_TOKENS = (
    "UserDefaults",
    "WidgetCenter",
    "UIApplication",
    "FeedbackPayloadBuilder",
)

SHOW_ASSET_CLEANUP_RETRY_FORBIDDEN_TOKENS = (
    "BSLocalization",
    "UIApplication",
    "WidgetCenter",
    "ModelContext",
)

PRO_PAYWALL_FORBIDDEN_TOKENS = (
    "struct ProPaywallSheetView",
    "enum ProPaywallCopy",
    "struct ProPaywallHero",
    "struct ProPaywallPlanSelectionView",
    "struct ProPaywallWinbackView",
    "struct PaywallBeamShape",
    "Bundle.main.object(forInfoDictionaryKey: \"RevenueCatAPIKey\")",
)

PRO_PAYWALL_VISUAL_FORBIDDEN_TOKENS = (
    "@AppStorage",
    "ProEntitlementStorage",
    "PostHogSDK",
    "ProSubscriptionStore",
    "loadProducts(",
    "restorePurchases(",
)

PRO_PAYWALL_STORE_FACTORY_FORBIDDEN_TOKENS = (
    "import SwiftUI",
    "BSLocalization",
    "PostHogSDK",
    "ProPaywallCopy",
)

PRO_OFFER_ROUTER_FORBIDDEN_TOKENS = (
    "import RevenueCat",
    "UserDefaults",
    "BSLocalization",
    "ProFeatureGate",
)

PRO_CATALOG_FORBIDDEN_TOKENS = (
    "import RevenueCat",
    "UserDefaults",
    "ObservableObject",
    "ProFeatureGate",
)

PRO_ENTITLEMENT_FORBIDDEN_TOKENS = (
    "import RevenueCat",
    "BSLocalization",
    "struct ProSubscriptionProduct",
    "ProFeatureGate",
)

PRO_STORE_CONTRACT_FORBIDDEN_TOKENS = (
    "import RevenueCat",
    "UserDefaults",
    "actor MockProSubscriptionStore",
    "struct RevenueCatProSubscriptionStore",
    "BSLocalization",
)

PRO_MOCK_STORE_FORBIDDEN_TOKENS = (
    "import RevenueCat",
    "UserDefaults",
    "BSLocalization",
    "struct ProFeatureGate",
)

PRO_REVENUECAT_STORE_FORBIDDEN_TOKENS = (
    "UserDefaults",
    "ObservableObject",
    "struct ProFeatureGate",
    "enum ProLimitReason",
)

PRO_LIMIT_PRESENTATION_FORBIDDEN_TOKENS = (
    "import RevenueCat",
    "UserDefaults",
    "struct ProFeatureGate",
    "ProSubscriptionStore",
)

PRO_FEATURE_GATE_FORBIDDEN_TOKENS = (
    "import RevenueCat",
    "UserDefaults",
    "BSLocalization",
    "ProSubscriptionStore",
    "ProSubscriptionProduct",
)

NOTIFICATION_CENTER_FORBIDDEN_TOKENS = (
    "struct LocalNotificationScheduler",
    "final class NotificationDeepLinkRouter",
    "final class BeforeShowNotificationDelegate",
    "@Model",
)

NOTIFICATION_SCHEDULER_FORBIDDEN_TOKENS = (
    "final class LocalNotificationCenter",
    "UNUserNotificationCenter",
)

SHOW_DETAIL_VIEW_FORBIDDEN_TOKENS = (
    "enum ShowDetailInformationPolicy",
    "enum ShowDetailExperienceAction",
    "struct PostponeShowSheet",
    "struct ConfirmedEndTimeEditorSheet",
    "struct ShowDetailExperienceTile",
    "struct ShowCoverFullscreenPreview",
)

SHOW_LIBRARY_MANAGEMENT_FORBIDDEN_TOKENS = (
    "enum CurrentShowLibraryFilter",
    "enum CurrentShowLibraryLayout",
    "enum CurrentShowLibraryMenuAction",
    "enum CurrentShowLibraryMenuPolicy",
    "struct CurrentShowLibraryCoverCard",
    "struct CurrentShowLibraryRow",
    "struct LibraryRowEntrance",
    "struct MyShowsEmptyView",
    "struct ShowRowView",
    "struct CurrentShowListHeroCard",
)

COMPANION_MODELS_FORBIDDEN_TOKENS = (
    "protocol CompanionSharingService",
    "struct CloudKitCompanionSharingService",
    "extension Show",
)

CLOUDKIT_COMPANION_CORE_FORBIDDEN_TOKENS = (
    "func prepareInvitation(",
    "func loadShareSystemFields(",
    "func acceptShare(",
    "func cancelSession(",
    "func fetchSession(",
    "func listAcceptedSharedSessions(",
    "func reconcileOwnerMembership(",
    "func ensureAccountAvailable(",
    "func modifyRecords(",
    "static func mapError(",
)

MEMORY_MEDIA_STORE_CORE_FORBIDDEN_TOKENS = (
    "struct MemoryDraftMedia",
    "struct MemoryCommittedMedia",
    "struct MemoryImportedFile",
    "enum MemoryMediaStoreError",
    "enum MemoryCapacity",
    "func stageCameraPhoto(",
    "func stageTransferredFile(",
    "func commit(",
    "func commitAdditions(",
    "func cleanupStaging(",
    "func cleanupImportTemp(",
    "func reconcileFragmentFiles(",
    "func reconcileAll(",
)

FOOTPRINT_ARCHIVE_RANKING_FORBIDDEN_TOKENS = (
    "final class FootprintCityCoordinateResolver",
    "enum FootprintCoverResolver",
    "struct FootprintVisibility",
    "enum FootprintAlbumArtworkWriteback",
)

FOOTPRINT_CITY_MAPPING_FORBIDDEN_TOKENS = (
    "enum FootprintArchiveRankingBuilder",
    "enum FootprintCoverResolver",
    "struct FootprintVisibility",
    "enum FootprintAlbumArtworkWriteback",
)

FOOTPRINT_ARCHIVE_COVERS_FORBIDDEN_TOKENS = (
    "final class FootprintCityCoordinateResolver",
    "struct FootprintVisibility",
    "enum FootprintAlbumArtworkWriteback",
)

FOOTPRINT_ARCHIVE_VISIBILITY_FORBIDDEN_TOKENS = (
    "enum FootprintArchiveRankingBuilder",
    "final class FootprintCityCoordinateResolver",
    "enum FootprintCoverResolver",
    "enum FootprintAlbumArtworkWriteback",
)

FOOTPRINT_ARTIST_WRITEBACK_FORBIDDEN_TOKENS = (
    "enum FootprintArchiveRankingBuilder",
    "final class FootprintCityCoordinateResolver",
    "enum FootprintCoverResolver",
    "struct FootprintVisibility",
)

DYNAMIC_COVER_MEDIA_STORE_CORE_FORBIDDEN_TOKENS = (
    "struct DynamicCoverImportedFile",
    "enum DynamicCoverMediaStoreError",
    "enum DynamicCoverCapacity",
    "struct DynamicCoverMediaStagedVideo",
    "struct DynamicCoverMediaCommittedVideo",
    "enum DynamicCoverErrorMessagePolicy",
    "func stageTransferredFile(",
    "func commit(",
    "func cleanupStaging(",
    "func cleanupImportTemp(",
    "func reconcile(",
    "func verifiedExistingRelativePaths(",
    "static func posterRelativePath(",
)

DYNAMIC_COVER_MEDIA_TYPES_FORBIDDEN_TOKENS = (
    "BSLocalization",
    "enum DynamicCoverErrorMessagePolicy",
)

DYNAMIC_COVER_PRESENTATION_FORBIDDEN_TOKENS = (
    "struct DynamicCoverManagementSection",
    "enum DynamicCoverImportCoordinator",
    "struct FootprintDynamicCoverSection",
    "struct MemoryViewerVideoPage",
    "enum AppAudioSession",
    "enum DynamicCoverAudioTrackProbe",
)

DYNAMIC_COVER_PLAYBACK_FORBIDDEN_TOKENS = (
    "struct MemoryViewerVideoPage",
    "enum AppAudioSession",
    "enum DynamicCoverAudioTrackProbe",
)

DYNAMIC_COVER_MANAGEMENT_FORBIDDEN_TOKENS = (
    "enum DynamicCoverImportCoordinator",
    "struct FootprintDynamicCoverSection",
    "struct DynamicCoverFlipView",
    "struct MemoryViewerVideoPage",
)

APP_AUDIO_SESSION_FORBIDDEN_TOKENS = (
    "import SwiftUI",
    "struct DynamicCoverPlaybackView",
    "struct MemoryViewerVideoPage",
)


def git(*args: str) -> str:
    return subprocess.check_output(
        ["git", *args],
        cwd=REPO_ROOT,
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()


def resolve_base_ref(explicit: str | None) -> str | None:
    candidates = [explicit]
    github_base = os.environ.get("GITHUB_BASE_REF")
    if github_base:
        candidates.extend((f"origin/{github_base}", github_base))
    candidates.append("HEAD^")

    for candidate in candidates:
        if not candidate:
            continue
        try:
            git("rev-parse", "--verify", candidate)
            return candidate
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    return None


def added_swift_files(base_ref: str | None) -> list[str]:
    if base_ref is None:
        return []
    try:
        output = git("diff", "--name-status", "--diff-filter=A", f"{base_ref}...HEAD")
    except subprocess.CalledProcessError:
        output = git("diff", "--name-status", "--diff-filter=A", base_ref, "HEAD")

    added: list[str] = []
    for line in output.splitlines():
        if not line:
            continue
        _, path = line.split("\t", 1)
        prefix = "apps/ios/"
        if path.startswith(prefix) and path.endswith(".swift"):
            added.append(path[len(prefix):])
    return added


def check_hotspot_budgets(errors: list[str]) -> None:
    for relative_path, max_bytes in HOTSPOT_BUDGETS.items():
        path = IOS_ROOT / relative_path
        if not path.exists():
            continue
        size = path.stat().st_size
        if size > max_bytes:
            errors.append(
                f"{relative_path} is {size:,} bytes (budget {max_bytes:,}). "
                "Split responsibilities before adding more code, or move code out and update the budget intentionally."
            )


def check_domain_imports(errors: list[str]) -> None:
    forbidden = ("SwiftUI", "UIKit", "Photos", "PhotosUI", "RevenueCat", "PostHog", "Vision", "CloudKit")
    domain = IOS_ROOT / "BeforeShow" / "Domain"
    if not domain.exists():
        return
    for source in sorted(domain.rglob("*.swift")):
        for line in source.read_text().splitlines():
            stripped = line.strip()
            if not stripped.startswith("import "):
                continue
            module = stripped.removeprefix("import ").split()[0]
            if module in forbidden:
                relative = source.relative_to(IOS_ROOT)
                errors.append(f"{relative} imports forbidden domain dependency {module}. Move framework-specific behavior to Infrastructure or Features.")


def check_root_swift_layout(errors: list[str]) -> None:
    root = IOS_ROOT / "BeforeShow"
    allowed = set(ROOT_SWIFT_ALLOWLIST)
    for source in sorted(root.glob("*.swift")):
        if source.name not in allowed:
            errors.append(
                f"root app source BeforeShow/{source.name} remains in the legacy flat directory. "
                "Move it into App, Domain, Features, Infrastructure, UI, or Supporting according to ownership."
            )


def check_retired_legacy_files(errors: list[str]) -> None:
    for relative_path in RETIRED_LEGACY_FILES:
        if (IOS_ROOT / relative_path).exists():
            errors.append(
                f"retired source {relative_path} exists again. "
                "Keep the implementation in its dedicated feature files instead of recreating a hotspot."
            )


def check_forbidden_tokens(
    relative_path: str,
    tokens: tuple[str, ...],
    boundary_description: str,
    errors: list[str],
) -> None:
    path = IOS_ROOT / relative_path
    if not path.exists():
        return
    content = path.read_text()
    for token in tokens:
        if token in content:
            errors.append(
                f"{relative_path} contains forbidden token {token!r}. {boundary_description}"
            )


def check_presentation_boundaries(errors: list[str]) -> None:
    check_forbidden_tokens(
        "BeforeShow/RootView.swift",
        ROOT_VIEW_FORBIDDEN_TOKENS,
        "Keep RootView limited to app/root routing and DEBUG support.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/CurrentShow/HomeHeroPresentation.swift",
        HOME_HERO_FORBIDDEN_TOKENS,
        "Keep this file limited to reusable hero snapshot/stage presentation.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/CurrentShow/CurrentShowManagementView.swift",
        MANAGEMENT_VIEW_FORBIDDEN_TOKENS,
        "Keep follow-up, quick-action, and route presentation in their dedicated CurrentShow files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/CurrentShow/ShowAssetSheet.swift",
        SHOW_ASSET_SHEET_FORBIDDEN_TOKENS,
        "Keep asset routing separate from upload-editor and viewer state owners.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/CurrentShow/HomeCountdownCard.swift",
        HOME_COUNTDOWN_CARD_FORBIDDEN_TOKENS,
        "Keep countdown state/identity policy and the reusable live pulse outside the HomeCountdownLockup state owner.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/AddShow/AddShowFlowView.swift",
        ADD_SHOW_FLOW_FORBIDDEN_TOKENS,
        "Keep flow orchestration separate from import UI, form UI, presentation primitives, and cover lifecycle support.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/AddShow/ShowDraftFormFields.swift",
        SHOW_DRAFT_FORM_FORBIDDEN_TOKENS,
        "Keep schedule, cover, artist, and reusable field presentation in their dedicated AddShow form files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Footprints/FootprintsView.swift",
        FOOTPRINTS_VIEW_FORBIDDEN_TOKENS,
        "Keep the Footprints root limited to page state/routing; archive domain, search, detail, export, share presentation, and legacy dashboard helpers belong elsewhere.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Footprints/FootprintDashboardView.swift",
        FOOTPRINT_DASHBOARD_VIEW_FORBIDDEN_TOKENS,
        "Keep the dashboard root limited to page composition; sections, archive screens, and cover presentation belong in their dedicated Footprints files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/CurrentShow/DispersalCeremonySheet.swift",
        DISPERSAL_CEREMONY_SHEET_FORBIDDEN_TOKENS,
        "Keep ceremony flow state separate from lights-out and share presentation responsibilities.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Footprints/FootprintDetailView.swift",
        FOOTPRINT_DETAIL_VIEW_FORBIDDEN_TOKENS,
        "Keep FootprintDetail page state separate from reusable detail tokens, playback policy, and media/keepsake presentation components.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Memory/MemoryFragmentsView.swift",
        MEMORY_FRAGMENTS_VIEW_FORBIDDEN_TOKENS,
        "Keep the Memory root limited to page state/routing; editor, timeline, viewer, camera, and edit coordination belong in their dedicated Memory files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/App/BeforeShowApp.swift",
        APP_ENTRY_FORBIDDEN_TOKENS,
        "Keep the App entry focused on SDK/bootstrap, scene wiring, and lifecycle orchestration; maintenance and persistence reconciliation belong in their dedicated App files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Companion/CompanionSharingCoordinator.swift",
        COMPANION_COORDINATOR_FORBIDDEN_TOKENS,
        "Keep Companion orchestration limited to invite/accept/cancel/refresh flow timing; durable inbox, cloud-sync markers, local import matching, and user copy belong in focused Companion owners.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Companion/CompanionAcceptedShareInbox.swift",
        COMPANION_ACCEPTED_INBOX_FORBIDDEN_TOKENS,
        "Keep accepted-share durable queue serialization separate from Keychain state, SwiftData import behavior, and presentation copy.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Companion/CompanionCloudSyncMarker.swift",
        COMPANION_CLOUD_SYNC_MARKER_FORBIDDEN_TOKENS,
        "Keep Companion cloud-sync opt-in persistence limited to UserDefaults/Keychain marker state.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Companion/CompanionAcceptedSessionImporter.swift",
        COMPANION_SESSION_IMPORTER_FORBIDDEN_TOKENS,
        "Keep accepted-session local Show matching/import separate from durable queue storage, Keychain state, and presentation copy.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Companion/CompanionSharingPresentation.swift",
        COMPANION_PRESENTATION_FORBIDDEN_TOKENS,
        "Keep Companion user-facing error/status copy as stateless presentation policy without persistence or SwiftData responsibilities.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Settings/SettingsView.swift",
        SETTINGS_ROOT_FORBIDDEN_TOKENS,
        "Keep settings destination pages and debug controls in focused Settings files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Settings/SettingsCatalog.swift",
        SETTINGS_CATALOG_FORBIDDEN_TOKENS,
        "Keep the Settings entry catalog free of language, feedback, local-data, and media-cleanup responsibilities.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Settings/SettingsLanguageSupport.swift",
        SETTINGS_LANGUAGE_FORBIDDEN_TOKENS,
        "Keep app-language persistence/runtime switching separate from Settings data and media responsibilities.",
        errors,
    )
    for settings_presentation_path in (
        "BeforeShow/Features/Settings/SettingsMembershipPresentation.swift",
        "BeforeShow/Features/Settings/SettingsNotificationPresentation.swift",
        "BeforeShow/Features/Settings/AppVersionInformation.swift",
    ):
        check_forbidden_tokens(
            settings_presentation_path,
            SETTINGS_PRESENTATION_FORBIDDEN_TOKENS,
            "Keep Settings presentation/value owners free of persistence, SwiftData, and UIKit action orchestration.",
            errors,
        )
    check_forbidden_tokens(
        "BeforeShow/Features/Settings/SettingsFeedbackSupport.swift",
        SETTINGS_FEEDBACK_FORBIDDEN_TOKENS,
        "Keep feedback payload/delivery support separate from SwiftData, media cleanup, and subscription state.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Settings/LocalDataInventory.swift",
        SETTINGS_LOCAL_DATA_FORBIDDEN_TOKENS,
        "Keep local-data inventory focused on Settings data inspection without UI actions or unrelated persistence policy.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Infrastructure/Media/ShowAssetCleanupRetry.swift",
        SHOW_ASSET_CLEANUP_RETRY_FORBIDDEN_TOKENS,
        "Keep the cross-feature media cleanup retry journal framework-neutral and free of Settings presentation concerns.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProPaywallView.swift",
        PRO_PAYWALL_FORBIDDEN_TOKENS,
        "Keep the primary paywall owner limited to product loading, purchase/restore, plan selection, and winback flow state; visual sections and store construction belong elsewhere.",
        errors,
    )
    for paywall_visual_path in (
        "BeforeShow/Features/Subscription/ProPaywallPresentation.swift",
        "BeforeShow/Features/Subscription/ProPaywallPlanSelectionView.swift",
        "BeforeShow/Features/Subscription/ProPaywallWinbackView.swift",
    ):
        check_forbidden_tokens(
            paywall_visual_path,
            PRO_PAYWALL_VISUAL_FORBIDDEN_TOKENS,
            "Keep paywall visual components stateless with respect to entitlement/store orchestration and analytics side effects.",
            errors,
        )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProPaywallStoreFactory.swift",
        PRO_PAYWALL_STORE_FACTORY_FORBIDDEN_TOKENS,
        "Keep default paywall store construction free of SwiftUI, user copy, and analytics responsibilities.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProOfferDeepLinkRouter.swift",
        PRO_OFFER_ROUTER_FORBIDDEN_TOKENS,
        "Keep the Pro offer router limited to presentation routing state.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProSubscriptionCatalog.swift",
        PRO_CATALOG_FORBIDDEN_TOKENS,
        "Keep subscription plans/products/catalog mapping separate from RevenueCat, persistence, routing, and quota policy.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProEntitlement.swift",
        PRO_ENTITLEMENT_FORBIDDEN_TOKENS,
        "Keep entitlement value/storage encoding separate from store adapters, catalog presentation, and quota policy.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProSubscriptionStore.swift",
        PRO_STORE_CONTRACT_FORBIDDEN_TOKENS,
        "Keep the subscription store contract/errors independent of concrete store implementations and presentation copy.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/MockProSubscriptionStore.swift",
        PRO_MOCK_STORE_FORBIDDEN_TOKENS,
        "Keep the mock store focused on deterministic store behavior without RevenueCat or presentation concerns.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/RevenueCatProSubscriptionStore.swift",
        PRO_REVENUECAT_STORE_FORBIDDEN_TOKENS,
        "Keep RevenueCat product/purchase/restore mapping separate from persistence, routing, and quota presentation.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProLimitPresentation.swift",
        PRO_LIMIT_PRESENTATION_FORBIDDEN_TOKENS,
        "Keep free-limit user copy as stateless presentation policy.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProFeatureGate.swift",
        PRO_FEATURE_GATE_FORBIDDEN_TOKENS,
        "Keep free monthly quota calculations as pure policy without store, persistence, or presentation responsibilities.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Infrastructure/Notifications/LocalNotificationCenter.swift",
        NOTIFICATION_CENTER_FORBIDDEN_TOKENS,
        "Keep notification models, scheduling policy, and tap routing outside the center orchestrator.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Infrastructure/Notifications/LocalNotificationScheduler.swift",
        NOTIFICATION_SCHEDULER_FORBIDDEN_TOKENS,
        "Keep LocalNotificationScheduler as pure scheduling policy without notification-center orchestration.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Shows/ShowDetailView.swift",
        SHOW_DETAIL_VIEW_FORBIDDEN_TOKENS,
        "Keep ShowDetail state ownership separate from sheets, preview, and presentation helpers.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Shows/CurrentShowLibraryManagementView.swift",
        SHOW_LIBRARY_MANAGEMENT_FORBIDDEN_TOKENS,
        "Keep ShowLibrary policy/rows out of the state owner and do not reintroduce removed legacy UI.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Companion/CompanionSharingModels.swift",
        COMPANION_MODELS_FORBIDDEN_TOKENS,
        "Keep Companion models/policies separate from the service protocol, CloudKit implementation, and Show persistence mapping.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Companion/CloudKitCompanionSharingService.swift",
        CLOUDKIT_COMPANION_CORE_FORBIDDEN_TOKENS,
        "Keep the CloudKit service core limited to construction/database access; invitation, session operations, and shared CloudKit support belong in their dedicated extension files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Infrastructure/Media/MemoryFragmentMediaStore.swift",
        MEMORY_MEDIA_STORE_CORE_FORBIDDEN_TOKENS,
        "Keep the Memory media store core limited to actor construction and commit/reconciliation serialization; media values, staging, commits, cleanup/reconciliation, and file helpers belong in their dedicated files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Footprints/FootprintArchiveRanking.swift",
        FOOTPRINT_ARCHIVE_RANKING_FORBIDDEN_TOKENS,
        "Keep archive ranking/year metrics separate from city mapping, cover resolution, visibility, and artist media writeback.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Footprints/FootprintCityMapping.swift",
        FOOTPRINT_CITY_MAPPING_FORBIDDEN_TOKENS,
        "Keep city mapping/MapKit resolution separate from archive ranking, cover selection, visibility, and model writeback.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Footprints/FootprintArchiveCovers.swift",
        FOOTPRINT_ARCHIVE_COVERS_FORBIDDEN_TOKENS,
        "Keep archive cover selection separate from city services, visibility policy, and artist media writeback.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Footprints/FootprintArchiveVisibility.swift",
        FOOTPRINT_ARCHIVE_VISIBILITY_FORBIDDEN_TOKENS,
        "Keep archive visibility policy separate from ranking, city services, cover resolution, and model writeback.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Footprints/FootprintArtistArtworkWriteback.swift",
        FOOTPRINT_ARTIST_WRITEBACK_FORBIDDEN_TOKENS,
        "Keep artist artwork model mutation as a narrow writeback helper rather than an archive aggregate.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Infrastructure/Media/DynamicCoverMediaStore.swift",
        DYNAMIC_COVER_MEDIA_STORE_CORE_FORBIDDEN_TOKENS,
        "Keep the DynamicCover media store core limited to actor construction, storage availability, URL resolution, and commit-gate access; media values, staging, commits, cleanup/reconciliation, and file helpers belong in their dedicated files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Infrastructure/Media/DynamicCoverMediaTypes.swift",
        DYNAMIC_COVER_MEDIA_TYPES_FORBIDDEN_TOKENS,
        "Keep user-facing DynamicCover error copy in CurrentShow presentation support, not Infrastructure media types.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/DynamicCover/DynamicCoverPresentation.swift",
        DYNAMIC_COVER_PRESENTATION_FORBIDDEN_TOKENS,
        "Keep reusable DynamicCover face/preview presentation separate from CurrentShow management, Footprints composition, Memory playback, and infrastructure services.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/DynamicCover/DynamicCoverPlaybackView.swift",
        DYNAMIC_COVER_PLAYBACK_FORBIDDEN_TOKENS,
        "Keep reusable DynamicCover playback separate from Memory video pages and infrastructure audio/probe services.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/CurrentShow/DynamicCoverManagementSection.swift",
        DYNAMIC_COVER_MANAGEMENT_FORBIDDEN_TOKENS,
        "Keep CurrentShow DynamicCover management focused on page UI state; import transactions and reusable/other-feature presentation belong elsewhere.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Infrastructure/Media/AppAudioSession.swift",
        APP_AUDIO_SESSION_FORBIDDEN_TOKENS,
        "Keep the app-wide audio session adapter framework-only and free of feature presentation.",
        errors,
    )


def check_new_file_locations(base_ref: str | None, errors: list[str]) -> None:
    for relative_path in added_swift_files(base_ref):
        if not relative_path.startswith("BeforeShow/"):
            continue
        if Path(relative_path).parent.as_posix() != "BeforeShow":
            continue
        errors.append(
            f"new app source {relative_path} was added to the legacy BeforeShow root. "
            "Place new feature code under BeforeShow/Features/<Feature>/; use App, Domain, "
            "Infrastructure, or UI only when that ownership is genuinely cross-feature."
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Guard BeforeShow iOS architecture boundaries.")
    parser.add_argument("--base-ref", default=None)
    args = parser.parse_args()

    errors: list[str] = []
    base_ref = resolve_base_ref(args.base_ref)
    check_hotspot_budgets(errors)
    check_retired_legacy_files(errors)
    check_root_swift_layout(errors)
    check_domain_imports(errors)
    check_presentation_boundaries(errors)
    check_new_file_locations(base_ref, errors)

    if errors:
        print("iOS architecture guard failed:\n")
        for error in errors:
            print(f"- {error}")
        return 1

    print("iOS architecture guard passed.")
    if base_ref:
        print(f"Compared new Swift files against {base_ref}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())