import Foundation
import SwiftUI

struct FootprintFilteredShowsView: View {
    let title: String
    let shows: [Show]
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void

    var body: some View {
        FootprintArchivePage(title: title, kicker: BSLocalization.text("关联现场"), shareCovers: covers) { isForExport in
            archiveSectionTitle(BSLocalization.text("全部现场"), BSLocalization.format("%lld 场", shows.count))
            let visibleShows = isForExport
                ? FootprintExportContentPolicy.prefix(shows, limit: FootprintExportContentPolicy.yearShowLimit)
                : shows
            ForEach(visibleShows) { show in
                footprintExportAwareNavigationLink(isForExport: isForExport) {
                    FootprintDetailView(show: show, archive: archive, onDetailVisibilityChange: onDetailVisibilityChange)
                } label: {
                    HStack(spacing: 11) {
                        FootprintCoverView(show: show, cover: covers[show.id])
                            .frame(width: 76, height: 86)
                            .clipped()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(show.name).font(BSFont.headline).foregroundColor(BSColor.Stage.foreground).lineLimit(2)
                            Text([show.city, show.venueName].compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0) }.joined(separator: " · "))
                                .font(BSFont.V3.caption).foregroundColor(BSColor.Stage.muted).lineLimit(2)
                            Text(footprintEnhancementDayText(show.effectiveDate, calendar: show.timingCalendar())).font(BSFont.V3.caption).foregroundColor(BSColor.Stage.dim)
                        }
                        Spacer(minLength: 0)
                        footprintRowChevron(isForExport: isForExport)
                    }
                    .padding(10)
                    .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
                }
            }
            if isForExport {
                footprintExportRemainingCaption(
                    total: shows.count,
                    limit: FootprintExportContentPolicy.yearShowLimit
                )
            }
        }
    }
}

@ViewBuilder
func footprintRowChevron(
    isForExport: Bool,
    size: CGFloat = 11,
    weight: Font.Weight = .regular
) -> some View {
    if !isForExport {
        Image(systemName: "chevron.right")
            .font(.system(size: size, weight: weight))
            .foregroundColor(BSColor.Stage.dim)
    }
}

@ViewBuilder
func footprintExportRemainingCaption(
    total: Int,
    limit: Int,
    style: FootprintExportContentPolicy.RemainingStyle = .shows
) -> some View {
    if let text = FootprintExportContentPolicy.remainingText(total: total, limit: limit, style: style) {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(BSColor.Stage.dim)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}

@ViewBuilder
@MainActor
func footprintExportAwareNavigationLink<Destination: View, Label: View>(
    isForExport: Bool,
    @ViewBuilder destination: () -> Destination,
    @ViewBuilder label: () -> Label
) -> some View {
    if isForExport {
        label()
    } else {
        NavigationLink(destination: destination, label: label)
            .buttonStyle(.plain)
    }
}

@ViewBuilder
@MainActor
func footprintExportAwareButton<Label: View>(
    isForExport: Bool,
    action: @escaping () -> Void,
    @ViewBuilder label: () -> Label
) -> some View {
    if isForExport {
        label()
    } else {
        Button(action: action, label: label)
            .buttonStyle(.plain)
    }
}

struct FootprintNavigationTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(BSColor.Stage.foreground)
            .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

struct FootprintArchivePage<Content: View>: View {
    let title: String
    let kicker: String
    let shareCovers: [UUID: FootprintCover]
    var extraWarmup: (() async -> Void)? = nil
    @ViewBuilder let content: (_ isForExport: Bool) -> Content
    @State private var isShowingShare = false
    @State private var toast: BSToastPayload?

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !kicker.isEmpty {
                        Text(kicker).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundColor(BSColor.Stage.accent)
                    }
                    content(false)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, BSLayout.tabBarContentInset)
            }
            .scrollIndicators(.hidden)
            .bsNavigationScrollEdge()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                FootprintNavigationTitle(title: title)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(BSLocalization.text("分享足迹"))
            }
        }
        .sheet(isPresented: $isShowingShare) {
            shareSheet()
        }
        .bsToastOverlay(toast, bottomPadding: 100)
    }

    private func shareSheet() -> some View {
        FootprintPageShareSheet(
            title: title,
            kicker: kicker,
            covers: shareCovers,
            extraWarmup: extraWarmup,
            onSaved: { presentToast(BSLocalization.text("足迹图片已保存")) },
            content: { content(true) }
        )
        .presentationCornerRadius(26)
        .presentationDragIndicator(.visible)
    }

    private func presentToast(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }
}

func archiveSectionTitle(_ title: String, _ subtitle: String = "") -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundColor(BSColor.Stage.muted)
        if !subtitle.isEmpty {
            Text(subtitle).font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
        }
    }
    .padding(.top, 4)
}

func archiveRow(rank: Int, title: String, subtitle: String, count: Int, color: Color) -> some View {
    HStack(spacing: 11) {
        Text("\(rank)").font(rank == 1 ? .system(size: 12, weight: .bold) : BSFont.tag).foregroundColor(rank == 1 ? color : BSColor.Stage.dim).frame(width: 28)
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(rank == 1 ? BSFont.headline : BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(2)
            Text(subtitle).font(BSFont.V3.caption).foregroundColor(BSColor.Stage.muted)
        }
        Spacer()
        Text(BSLocalization.format("%lld 场", count)).font(BSFont.tag).foregroundColor(rank == 1 ? color : BSColor.Stage.foreground)
    }
    .padding(13)
    .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
}

func footprintEnhancementMonthText(_ date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d.%02d", components.year ?? 0, components.month ?? 0)
}

func footprintEnhancementDayText(_ date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.month, .day], from: date)
    return String(format: "%02d.%02d", components.month ?? 0, components.day ?? 0)
}

func footprintEnhancementMonthAbbreviation(_ date: Date, calendar: Calendar) -> String {
    let month = calendar.component(.month, from: date)
    let symbols = calendar.shortMonthSymbols
    guard symbols.indices.contains(month - 1) else { return "LIVE" }
    return symbols[month - 1].uppercased()
}

func footprintEnhancementFullDateText(_ date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d.%02d.%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
}

func footprintMonthKey(_ month: Int) -> String {
    "\(month)月"
}
