import SwiftUI
import UIKit

// MARK: - Companion Footprint Share Tokens

enum CompanionFootprintShareTokens {
    static let baseWidth: CGFloat = 360
    static let baseHeight: CGFloat = 480
    static let renderSize = CGSize(width: baseWidth, height: baseHeight)
    static let renderScale: CGFloat = 3
    static let cardPadding: CGFloat = 24

    static let goldGlow = Color(red: 0.910, green: 0.780, blue: 0.557).opacity(0.24)
    static let blueGlow = BSColor.Stage.glowBlue.opacity(0.18)
    static let gradientTop = Color(red: 0.075, green: 0.075, blue: 0.088)
    static let gradientMid = Color(red: 0.038, green: 0.038, blue: 0.045)
    static let gradientBottom = Color(red: 0.022, green: 0.022, blue: 0.026)

    static let brand = BSColor.Stage.accent
    static let date = Color.white.opacity(0.62)
    static let footer = Color.white.opacity(0.38)
}

// MARK: - Companion Footprint Share Card

struct CompanionFootprintShareCard: View {
    let show: Show
    let sharedHistory: [Show]
    var companionName: String? = nil

    private var count: Int {
        max(1, sharedHistory.count)
    }

    private var memberNames: [String] {
        if let companionName {
            return CompanionNameList.normalized([companionName])
        }
        return CompanionNameList.normalized(show.companionNames)
    }

    private var cityText: String? {
        FootprintTextNormalizer.nonEmptyTrimmed(show.city)
    }

    private var eventLines: [String] {
        DispersalCeremonyCardCopy.eventLines(
            name: show.name,
            artistNames: show.artistNames
        )
    }

    private var dateLine: String {
        let calendar = show.timingCalendar()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        let date = formatter.string(from: show.effectiveDate)
        return [date, cityText].compactMap { $0 }.joined(separator: " · ")
    }

    private var relationshipTitle: String {
        if let companionName {
            return BSLocalization.format("我和%@一起看过\n%lld 场现场", companionName, Int64(count))
        }
        return BSLocalization.format("我们一起看过\n%lld 场现场", Int64(count))
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / CompanionFootprintShareTokens.baseWidth
            ZStack {
                background

                VStack(alignment: .leading, spacing: 0) {
                    headerBlock(scale: scale)
                    eventBlock(scale: scale)

                    Spacer(minLength: 16 * scale)

                    togetherHighlightCard(scale: scale)

                    Spacer(minLength: 16 * scale)

                    footerBlock(scale: scale)
                }
                .padding(CompanionFootprintShareTokens.cardPadding * scale)
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    CompanionFootprintShareTokens.gradientTop,
                    CompanionFootprintShareTokens.gradientMid,
                    CompanionFootprintShareTokens.gradientBottom
                ],
                startPoint: UnitPoint(x: 0.2, y: 0),
                endPoint: UnitPoint(x: 0.8, y: 1)
            )

            GeometryReader { proxy in
                ZStack {
                    Ellipse()
                        .fill(CompanionFootprintShareTokens.goldGlow)
                        .frame(
                            width: proxy.size.width * 1.05,
                            height: proxy.size.height * 0.70
                        )
                        .position(
                            x: proxy.size.width * 0.85,
                            y: proxy.size.height * 0.15
                        )
                        .blur(radius: 36)

                    Ellipse()
                        .fill(CompanionFootprintShareTokens.blueGlow)
                        .frame(
                            width: proxy.size.width * 0.95,
                            height: proxy.size.height * 0.65
                        )
                        .position(
                            x: proxy.size.width * 0.15,
                            y: proxy.size.height * 0.80
                        )
                        .blur(radius: 40)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func headerBlock(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text(BSLocalization.text("BEFORESHOW · 共同足迹"))
                .font(.system(size: 10.5 * scale, weight: .semibold))
                .tracking(1.4 * scale)
                .foregroundColor(CompanionFootprintShareTokens.brand)

            Text(dateLine)
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundColor(CompanionFootprintShareTokens.date)
        }
    }

    private func eventBlock(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            ForEach(Array(eventLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 22 * scale, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            if let venue = FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) {
                Text(venue)
                    .font(.system(size: 12 * scale, weight: .regular))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.top, 2 * scale)
            }
        }
        .padding(.top, 14 * scale)
    }

    private func togetherHighlightCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            HStack {
                Text(BSLocalization.format("TOGETHER · %@", String(format: "%02d", count)))
                    .font(.system(size: 10 * scale, weight: .bold))
                    .tracking(1.3 * scale)
                    .foregroundColor(BSColor.Stage.accent)
                    .padding(.horizontal, 9 * scale)
                    .padding(.vertical, 4 * scale)
                    .background(BSColor.Stage.accent.opacity(0.16))
                    .clipShape(Capsule())

                Spacer()
            }

            Text(relationshipTitle)
                .font(.system(size: 24 * scale, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineSpacing(4 * scale)

            memberAvatarsRow(scale: scale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18 * scale)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Stage.accent.opacity(0.14),
                    BSColor.Stage.surface.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18 * scale))
        .overlay(
            RoundedRectangle(cornerRadius: 18 * scale)
                .stroke(BSColor.Stage.accent.opacity(0.24), lineWidth: 1)
        )
    }

    private func memberAvatarsRow(scale: CGFloat) -> some View {
        HStack(spacing: 12 * scale) {
            memberPill(name: BSLocalization.text("我"), initial: BSLocalization.text("我"), scale: scale)

            Image(systemName: "link")
                .font(.system(size: 11 * scale, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent.opacity(0.8))

            ForEach(Array(memberNames.enumerated()), id: \.offset) { _, name in
                memberPill(name: name, initial: String(name.prefix(1)), scale: scale)
            }
        }
        .padding(.top, 4 * scale)
    }

    private func memberPill(name: String, initial: String, scale: CGFloat) -> some View {
        HStack(spacing: 7 * scale) {
            Text(initial)
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundColor(BSColor.Stage.background)
                .frame(width: 26 * scale, height: 26 * scale)
                .background(
                    LinearGradient(
                        colors: [BSColor.Stage.accent, BSColor.Stage.glowBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())

            Text(name)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 4 * scale)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private func footerBlock(scale: CGFloat) -> some View {
        HStack {
            Text(BSLocalization.text("BeforeShow · 现场共同记忆"))
                .font(.system(size: 10.5 * scale, weight: .medium))
                .foregroundColor(CompanionFootprintShareTokens.footer)

            Spacer()

            Text(
                companionName.map { BSLocalization.format("与%@的共同足迹", $0) }
                    ?? BSLocalization.text("已收进共同足迹")
            )
                .font(.system(size: 10.5 * scale, weight: .medium))
                .foregroundColor(CompanionFootprintShareTokens.brand.opacity(0.85))
        }
    }
}

// MARK: - Companion Footprint Share Sheet

struct CompanionFootprintShareSheet: View {
    let show: Show
    let sharedHistory: [Show]
    var companionName: String? = nil
    var onSaved: (() -> Void)? = nil

    var body: some View {
        FootprintShareActionSheet(
            title: companionName.map { BSLocalization.format("分享与%@的共同足迹", $0) }
                ?? BSLocalization.text("分享共同足迹"),
            subtitle: BSLocalization.text("记录一起走过的现场，可保存图片或直接分享。"),
            previewHeight: 380,
            exportSize: CompanionFootprintShareTokens.renderSize,
            exportScale: CompanionFootprintShareTokens.renderScale,
            flexiblePreviewHeight: true,
            preview: {
                CompanionFootprintShareCard(
                    show: show,
                    sharedHistory: sharedHistory,
                    companionName: companionName
                )
                .aspectRatio(
                    CompanionFootprintShareTokens.renderSize.width
                        / CompanionFootprintShareTokens.renderSize.height,
                    contentMode: .fit
                )
            },
            exportContent: {
                CompanionFootprintShareCard(
                    show: show,
                    sharedHistory: sharedHistory,
                    companionName: companionName
                )
                .frame(
                    width: CompanionFootprintShareTokens.renderSize.width,
                    height: CompanionFootprintShareTokens.renderSize.height
                )
            },
            onSaved: onSaved
        )
    }
}
