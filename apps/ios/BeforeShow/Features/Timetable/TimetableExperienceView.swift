import SwiftData
import SwiftUI

/// Main timetable screen: the stage matrix plus a floating dock for the
/// "想看" filter and sharing.
struct TimetableExperienceView: View {
    let timetable: Timetable
    let show: Show?
    @Binding var selectedDayID: UUID
    let avatarURL: (String) -> URL?

    @Environment(\.modelContext) private var modelContext
    @State private var wantOnly: Bool
    @State private var isSharing = false
    @Namespace private var dockIndicator

    init(timetable: Timetable, show: Show?, selectedDayID: Binding<UUID>, avatarURL: @escaping (String) -> URL?) {
        self.timetable = timetable
        self.show = show
        _selectedDayID = selectedDayID
        self.avatarURL = avatarURL
        var wantOnly = false
        #if DEBUG
        wantOnly = ProcessInfo.processInfo.arguments.contains("--timetable-filter-interested")
        #endif
        _wantOnly = State(initialValue: wantOnly)
    }

    private var currentDay: TimetableDay? {
        timetable.orderedDays.first { $0.id == selectedDayID } ?? timetable.orderedDays.first
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
    }

    private var interestedCount: Int {
        currentDay?.performances.filter(\.isInterested).count ?? 0
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let day = currentDay {
                TimetableStageMatrixView(
                    day: day,
                    now: context.date,
                    timeZone: timeZone,
                    wantOnly: wantOnly,
                    avatarURL: avatarURL,
                    onToggleInterested: toggleInterested
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        .sheet(isPresented: $isSharing) {
            TimetableShareSheet(timetable: timetable, show: show, avatarURL: avatarURL)
        }
    }

    // MARK: - Dock

    private var dock: some View {
        ZStack {
            HStack(spacing: 0) {
                dockOption(isOn: !wantOnly, tint: Color.white.opacity(0.14)) {
                    Text(BSLocalization.text("全部"))
                        .foregroundStyle(wantOnly ? TimetableStyle.muted : TimetableStyle.foreground)
                }
                .frame(width: 76)
                .onTapGesture { setWantOnly(false) }

                dockOption(isOn: wantOnly, tint: TimetableStyle.mine) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(wantOnly ? TimetableStyle.background : TimetableStyle.mine)
                        Text(BSLocalization.text("想看"))
                        Text("\(interestedCount)").font(TimetableStyle.mono(14, weight: .semibold))
                    }
                    .foregroundStyle(wantOnly ? TimetableStyle.background : TimetableStyle.muted)
                }
                .frame(width: 112)
                .onTapGesture { setWantOnly(true) }
            }
            .font(.system(size: 14, weight: .bold))
            .padding(4)
            .glassEffect(.regular, in: Capsule())

            Button {
                isSharing = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TimetableStyle.foreground)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(TimetablePressStyle())
            .glassEffect(.regular, in: Circle())
            .accessibilityLabel(BSLocalization.text("分享"))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
        }
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: wantOnly)
    }

    private func dockOption<Label: View>(isOn: Bool, tint: Color, @ViewBuilder label: () -> Label) -> some View {
        label()
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isOn {
                    Capsule().fill(tint).matchedGeometryEffect(id: "dock", in: dockIndicator)
                }
            }
            .contentShape(Capsule())
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func setWantOnly(_ value: Bool) {
        withAnimation(TimetableStyle.pressSpring) { wantOnly = value }
    }

    // MARK: - Actions

    private func toggleInterested(_ performance: TimetablePerformance) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            performance.isInterested.toggle()
        }
        try? modelContext.save()
    }
}
