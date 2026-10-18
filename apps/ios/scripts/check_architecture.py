#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = IOS_ROOT.parents[1]

# Every Swift source has a line cap so new files cannot quietly grow into
# hotspots. Files already past the cap are pinned at their current size and may
# only shrink; lower the pin when a file shrinks, delete it once under the cap.
SOURCE_LINE_LIMIT = 600
TEST_LINE_LIMIT = 1_000
SOURCE_ROOTS = ("BeforeShow", "BeforeShowWidgets", "Shared")
TEST_ROOTS = ("BeforeShowTests", "BeforeShowUITests")

OVERSIZE_LINE_PINS = {
    "BeforeShowTests/CompanionSharingTests.swift": 1_697,
    "BeforeShow/Features/Listening/ListeningRoomCoordinator.swift": 1_565,
    "BeforeShowTests/ProSubscriptionTests.swift": 1_169,
    "BeforeShowTests/ShowDraftTests.swift": 1_051,
    "BeforeShowTests/TimetableImportTests.swift": 1_033,
    "BeforeShow/Features/Listening/ListeningDisplayProjection.swift": 935,
    "BeforeShow/Features/AddShow/AddShowFlowView.swift": 839,
    "BeforeShow/Features/Shows/ShowDetailView.swift": 875,
    "BeforeShow/Features/Footprints/FootprintDetailView.swift": 829,
    "BeforeShow/Features/Timetable/TimetablePerformanceInspectorSheet.swift": 802,
    "BeforeShow/Features/CurrentShow/CurrentShowCompanionView.swift": 799,
    "BeforeShow/Features/Companion/CompanionJoinConfirmationView.swift": 751,
    "BeforeShowWidgets/CountdownWidgetViews.swift": 728,
    "BeforeShow/Supporting/Debug/LiveAndWidgetShowcaseView.swift": 725,
    "BeforeShow/Features/Timetable/TimetableSheet.swift": 701,
    "BeforeShow/Features/Listening/Views/ListeningPolishedBottomChrome.swift": 696,
    "BeforeShow/Features/Timetable/TimetableShareSheet.swift": 680,
    "BeforeShow/Features/CurrentShow/HomeLiveModeView.swift": 678,
    "BeforeShow/Features/CurrentShow/CurrentShowManagementView.swift": 662,
    "Shared/CurrentShowTimeState.swift": 636,
    "BeforeShow/Features/Memory/MemoryUnifiedEditorView.swift": 636,
    "BeforeShow/Features/Memory/MemoryFragmentsView.swift": 632,
    "BeforeShow/Supporting/Debug/DebugSampleShowSeeder.swift": 613,
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
    "struct FootprintMemoryTile",
    "struct FootprintKeepsakeTile",
    "struct FootprintLocalImage",
    "struct FootprintDynamicCoverSection",
    "DynamicCoverVideoPreviewView",
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
    "struct DynamicCoverFlipView",
    "struct MemoryViewerVideoPage",
)

APP_AUDIO_SESSION_FORBIDDEN_TOKENS = (
    "import SwiftUI",
    "struct DynamicCoverPlaybackView",
    "struct MemoryViewerVideoPage",
)


# ADR 0043: iOS 17 is the minimum for the app, widget, and tests. project.yml
# is the source of truth; the generated pbxproj must not drift from it and no
# target may raise its own floor.
MINIMUM_IOS_DEPLOYMENT_TARGET = "17.0"


def check_deployment_target(errors: list[str]) -> None:
    project_yml = (IOS_ROOT / "project.yml").read_text(encoding="utf-8")
    declared = re.findall(r'^\s+iOS:\s*"?([0-9.]+)"?\s*$', project_yml, re.MULTILINE)
    if declared != [MINIMUM_IOS_DEPLOYMENT_TARGET]:
        errors.append(
            f"project.yml must declare exactly one deploymentTarget iOS {MINIMUM_IOS_DEPLOYMENT_TARGET} "
            f"(found {declared or 'none'}); see ADR 0043."
        )
    if "IPHONEOS_DEPLOYMENT_TARGET" in project_yml:
        errors.append("project.yml must not override IPHONEOS_DEPLOYMENT_TARGET per target; see ADR 0043.")

    pbxproj = (IOS_ROOT / "BeforeShow.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    generated = set(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);", pbxproj))
    if generated != {MINIMUM_IOS_DEPLOYMENT_TARGET}:
        errors.append(
            f"project.pbxproj deployment targets {sorted(generated) or 'none'} differ from "
            f"{MINIMUM_IOS_DEPLOYMENT_TARGET}; rerun xcodegen generate."
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


def line_limit(relative_path: str) -> int:
    return TEST_LINE_LIMIT if relative_path.startswith(TEST_ROOTS) else SOURCE_LINE_LIMIT


def check_file_sizes(errors: list[str]) -> None:
    for root in SOURCE_ROOTS + TEST_ROOTS:
        for path in sorted((IOS_ROOT / root).rglob("*.swift")):
            relative_path = path.relative_to(IOS_ROOT).as_posix()
            lines = len(path.read_text(encoding="utf-8").splitlines())
            limit = OVERSIZE_LINE_PINS.get(relative_path, line_limit(relative_path))
            if lines > limit:
                errors.append(
                    f"{relative_path} has {lines} lines (limit {limit}). "
                    "Split responsibilities before adding more code."
                )

    for relative_path, pin in OVERSIZE_LINE_PINS.items():
        path = IOS_ROOT / relative_path
        if not path.exists():
            errors.append(f"OVERSIZE_LINE_PINS lists missing file {relative_path}; remove the pin.")
            continue
        lines = len(path.read_text(encoding="utf-8").splitlines())
        if lines <= line_limit(relative_path):
            errors.append(f"{relative_path} is back under the default limit; remove its pin.")
        elif lines < pin:
            errors.append(f"{relative_path} shrank to {lines} lines; lower its pin from {pin}.")


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
    check_deployment_target(errors)
    check_file_sizes(errors)
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
