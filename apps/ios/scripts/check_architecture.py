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
    "BeforeShow/Features/Shows/ShowLibraryViews.swift": 44_000,
    "BeforeShow/Features/Footprints/FootprintDetailView.swift": 40_000,
    "BeforeShow/Features/Companion/CompanionSharingCoordinator.swift": 32_000,
    "BeforeShow/Features/Subscription/ProPaywallView.swift": 32_000,
    "BeforeShow/Features/Subscription/ProPaywallSupport.swift": 6_000,
    "BeforeShow/Features/CurrentShow/DispersalCeremonyViews.swift": 35_000,
    "BeforeShow/Features/CurrentShow/HomeCountdownCard.swift": 35_000,
    "BeforeShow/Features/CurrentShow/ShowAssetViews.swift": 33_000,
    "BeforeShow/Infrastructure/Media/MemoryFragmentMediaStore.swift": 33_000,
    "BeforeShow/Features/CurrentShow/DynamicCoverViews.swift": 32_000,
    "BeforeShow/Features/Footprints/FootprintArchiveEnhancements.swift": 30_000,
    "BeforeShow/Infrastructure/Media/DynamicCoverMediaStore.swift": 27_000,
    "BeforeShow/Features/Subscription/ProSubscription.swift": 25_000,
    "BeforeShow/Features/Settings/SettingsSupport.swift": 22_000,
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
    "BeforeShow/Features/Footprints/FootprintArchiveDetailView.swift": 21_000,
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
    "BeforeShow/Infrastructure/Notifications/LocalNotificationScheduling.swift",
    "BeforeShow/Features/Shows/ShowDetailViews.swift",
    "BeforeShow/Features/AddShow/ShowDraft.swift",
    "BeforeShow/Features/Footprints/FootprintShareViews.swift",
)

ROOT_SWIFT_ALLOWLIST = ("RootView.swift",)

ROOT_VIEW_FORBIDDEN_TOKENS = (
    "struct AppStoreWidgetPreviewView",
    "enum DebugSampleShowSeeder",
    "import PhotosUI",
    "PhotosPickerItem",
    "DynamicCoverImportCoordinator",
    "WidgetDataSync.sync",
    "LocalNotificationCenter.shared.reconcileFocus",
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
)

SETTINGS_ROOT_FORBIDDEN_TOKENS = (
    "struct PrivacyLocalDataView",
    "struct FeedbackView",
    "struct LanguageSettingsView",
    "struct AboutBeforeShowView",
    "enum DebugProEntitlementOption",
)

PRO_PAYWALL_FORBIDDEN_TOKENS = (
    "struct ProPaywallSheetView",
    "enum ProPaywallCopy",
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
        "Keep Companion orchestration separate from app lifecycle delegates and Show mapping.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Settings/SettingsView.swift",
        SETTINGS_ROOT_FORBIDDEN_TOKENS,
        "Keep settings destination pages and debug controls in focused Settings files.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/Features/Subscription/ProPaywallView.swift",
        PRO_PAYWALL_FORBIDDEN_TOKENS,
        "Keep paywall sheet/copy support outside the primary paywall state owner.",
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