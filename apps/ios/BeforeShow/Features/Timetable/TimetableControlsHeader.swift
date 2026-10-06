import Foundation
import SwiftUI

struct TimetableControlsHeader: View {
    let days: [TimetableDay]
    @Binding var selectedDayID: UUID
    @Binding var viewMode: TimetableViewMode
    @Binding var periodFilter: TimetablePeriodFilter
    @Binding var selectedStageID: UUID?
    let currentDayStages: [TimetableStage]
    let interestedCount: Int

    var body: some View {
        VStack(spacing: BSSpacing.sm) {
            // Day selection bar (if multiple days)
            if days.count > 1 {
                multiDaySelector
            }

            // View mode picker
            Picker("", selection: $viewMode) {
                ForEach(TimetableViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Period filters capsule row (only in timeline mode)
            if viewMode == .timeline {
                periodFilterBar
            }

            // Stage filter bar (when in byStage mode)
            if viewMode == .byStage {
                stageFilterBar(stages: currentDayStages)
            }
        }
    }

    private var multiDaySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days.indices, id: \.self) { idx in
                    let day = days[idx]
                    let isSelected = day.id == selectedDayID
                    Button {
                        selectedDayID = day.id
                    } label: {
                        VStack(spacing: 2) {
                            Text(BSLocalization.format("第 %d 天", idx + 1))
                                .font(.system(size: 13, weight: .bold))
                            Text(formatDayShort(day.date))
                                .font(.system(size: 11, weight: .regular))
                        }
                        .foregroundColor(isSelected ? .black : BSColor.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(isSelected ? BSColor.Accent.warm : BSColor.surface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var periodFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimetablePeriodFilter.allCases) { filter in
                    let isSelected = periodFilter == filter
                    Button {
                        periodFilter = filter
                    } label: {
                        HStack(spacing: 4) {
                            if filter == .interested {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(isSelected ? .black : Color.red)
                            }
                            Text(periodFilterTitle(filter))
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        }
                        .foregroundColor(isSelected ? .black : BSColor.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.white : BSColor.surface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func stageFilterBar(stages: [TimetableStage]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let isAll = selectedStageID == nil
                Button {
                    selectedStageID = nil
                } label: {
                    Text(BSLocalization.text("全部舞台"))
                        .font(.system(size: 12, weight: isAll ? .semibold : .regular))
                        .foregroundColor(isAll ? .black : BSColor.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isAll ? BSColor.Accent.info : BSColor.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ForEach(stages, id: \.id) { stage in
                    let isSelected = selectedStageID == stage.id
                    Button {
                        selectedStageID = stage.id
                    } label: {
                        Text(stage.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .black : BSColor.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? BSColor.Accent.info : BSColor.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func periodFilterTitle(_ filter: TimetablePeriodFilter) -> String {
        switch filter {
        case .all:
            return BSLocalization.text("全部")
        case .now:
            return BSLocalization.text("正在演")
        case .upNext:
            return BSLocalization.text("接下来")
        case .evening:
            return BSLocalization.text("晚上")
        case .interested:
            return interestedCount > 0
                ? BSLocalization.format("想看 (%d)", interestedCount)
                : BSLocalization.text("想看")
        }
    }

    private func formatDayShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}
