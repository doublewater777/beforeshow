import Foundation
import SwiftUI

// MARK: - Add Show Confirmation Presentation

enum AddShowConfirmationKind: Equatable {
    case saved(AddShowSaveOutcome)
    case duplicate(AddShowSaveOutcome)

    var outcome: AddShowSaveOutcome {
        switch self {
        case .saved(let outcome), .duplicate(let outcome):
            return outcome
        }
    }

    var isDuplicate: Bool {
        if case .duplicate = self { return true }
        return false
    }
}

struct SavedShowConfirmation: Equatable {
    let showID: UUID
    let name: String
    let coverImageURL: String?
    let kind: AddShowConfirmationKind

    var outcome: AddShowSaveOutcome { kind.outcome }
}

enum AddShowDetailKind: Hashable {
    case show
    case footprint
}

struct AddShowDetailDestination: Identifiable, Hashable {
    let showID: UUID
    let kind: AddShowDetailKind

    var id: String { "\(showID.uuidString)-\(kind)" }
}

struct PendingAddShowLifecycleConfirmation: Identifiable {
    let id = UUID()
    let show: Show
}

struct AddShowLifecycleConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let showName: String
    let showStart: Date
    let canConfirmEnd: Bool
    let calendar: Calendar
    let onLive: () -> Void
    let onEnded: (Date) -> Void

    @State private var isConfirmingEndTime = false
    @State private var endTime: Date

    init(
        showName: String,
        showStart: Date,
        canConfirmEnd: Bool,
        calendar: Calendar,
        now: Date = Date(),
        onLive: @escaping () -> Void,
        onEnded: @escaping (Date) -> Void
    ) {
        self.showName = showName
        self.showStart = showStart
        self.canConfirmEnd = canConfirmEnd
        self.calendar = calendar
        self.onLive = onLive
        self.onEnded = onEnded
        _endTime = State(initialValue: max(showStart, now))
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            if isConfirmingEndTime {
                BSStageSheetHeader(
                    icon: "clock",
                    title: BSLocalization.text("实际几点结束？"),
                    subtitle: showName,
                    tint: BSColor.Stage.accent
                )

                BSSurfacePanel {
                    VStack(spacing: BSSpacing.sm) {
                        DatePicker(
                            BSLocalization.text("散场日期"),
                            selection: $endTime,
                            in: showStart...Date(),
                            displayedComponents: .date
                        )
                        DatePicker(
                            BSLocalization.text("散场时间"),
                            selection: $endTime,
                            in: showStart...Date(),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    .tint(BSColor.Stage.accent)
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
                }

                Button(BSLocalization.text("确认结束时间")) {
                    let confirmed = endTime
                    dismiss()
                    onEnded(confirmed)
                }
                .buttonStyle(BSPrimaryButtonStyle())
            } else {
                BSStageSheetHeader(
                    icon: "music.note",
                    title: BSLocalization.text("这场已经结束了吗？"),
                    subtitle: BSLocalization.text("我们看到这场已经开场，确认一下现在的状态。"),
                    tint: BSColor.Stage.accent
                )

                VStack(spacing: BSSpacing.sm) {
                    Button(BSLocalization.text("还在现场")) {
                        dismiss()
                        onLive()
                    }
                    .buttonStyle(BSPrimaryButtonStyle())

                    if canConfirmEnd {
                        Button(BSLocalization.text("已经结束")) {
                            isConfirmingEndTime = true
                        }
                        .buttonStyle(BSSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}

struct AddShowSavedConfirmationView: View {
    let confirmation: SavedShowConfirmation
    let onOpen: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: BSSpacing.xl)

            BSSurfacePanel {
                VStack(spacing: BSSpacing.lg) {
                    ZStack {
                        Circle()
                            .fill(BSColor.Stage.accent.opacity(0.16))
                            .frame(width: 58, height: 58)
                        Circle()
                            .stroke(BSColor.Stage.accent.opacity(0.46), lineWidth: 1)
                            .frame(width: 58, height: 58)
                        Image(systemName: confirmation.kind.isDuplicate ? "rectangle.on.rectangle" : "checkmark")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(BSColor.Stage.accent)
                    }

                    ShowCoverImageView(
                        urlString: confirmation.coverImageURL,
                        aspectRatio: 3.0 / 4.0,
                        contentMode: .fill,
                        cornerRadius: BSRadius.md
                    )
                    .frame(width: 96, height: 128)
                    .clipped()

                    VStack(spacing: BSSpacing.xs) {
                        Text(AddShowSuccessCopy.title(isDuplicate: confirmation.kind.isDuplicate))
                            .font(BSFont.heroTitle)
                            .foregroundColor(BSColor.Stage.foreground)
                            .multilineTextAlignment(.center)

                        Text(confirmation.name)
                            .font(BSFont.body)
                            .foregroundColor(BSColor.Stage.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        if !confirmation.kind.isDuplicate {
                            Text(AddShowSuccessCopy.status(for: confirmation.outcome))
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.Stage.dim)
                        }
                    }

                    VStack(spacing: 10) {
                        Button(action: onOpen) {
                            Text(BSLocalization.text(confirmation.kind.isDuplicate ? "查看这场现场" : "查看现场"))
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(BSColor.Stage.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)

                        Button(action: onDone) {
                            Text(BSLocalization.text("完成"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(BSColor.Stage.foreground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BSSpacing.sm)
            }
            .frame(maxWidth: 330)

            Spacer(minLength: BSSpacing.xl)
        }
        .padding(.horizontal, 20)
    }
}
