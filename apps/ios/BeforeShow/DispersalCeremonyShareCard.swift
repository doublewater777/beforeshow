import SwiftUI
import UIKit

// MARK: - 渲染 token

/// 「散场卡」渲染 token。对齐 V2 原型 editorial 构图。
/// `baseWidth = 360`,所有 metrics × `proxy.size.width / baseWidth`,
/// 渲染到 `ImageRenderer(scale: 3)` 时得到 1080×1350 PNG。
private enum DispersalCeremonyCardTokens {
    static let baseWidth: CGFloat = 360
    static let cardPadding: CGFloat = 25

    static let brandTopTracking: CGFloat = 1.5
    static let dateTopPadding: CGFloat = 20
    static let eventTopPadding: CGFloat = 7
    static let eventLineSpacing: CGFloat = 2
    static let ratingTopPadding: CGFloat = 30
    static let quoteTopPadding: CGFloat = 22
    static let quoteLineSpacing: CGFloat = 6

    static let footerMinSpacing: CGFloat = 10

    static let goldGlow = Color(red: 0.910, green: 0.780, blue: 0.557).opacity(0.26)
    static let blueGlow = Color(red: 0.322, green: 0.498, blue: 0.788).opacity(0.26)
    static let gradientTop = Color(red: 0.067, green: 0.094, blue: 0.153)
    static let gradientMid = Color(red: 0.035, green: 0.043, blue: 0.071)
    static let gradientBottom = Color(red: 0.024, green: 0.027, blue: 0.043)
    static let brand = BSColor.Stage.accent
    static let date = Color.white.opacity(0.62)
    static let quote = Color(red: 0.898, green: 0.906, blue: 0.929)
    static let footer = Color.white.opacity(0.38)
    static let neutralHeader = BSColor.Stage.muted

    static func brandFont(scale: CGFloat) -> Font {
        .system(size: 10.5 * scale, weight: .semibold)
    }

    static func dateFont(scale: CGFloat) -> Font {
        .system(size: 12 * scale, weight: .medium)
    }

    static func eventFont(scale: CGFloat) -> Font {
        .system(size: 25 * scale, weight: .bold)
    }

    static func ratingFont(scale: CGFloat) -> Font {
        .system(size: 42 * scale, weight: .bold)
    }

    static func quoteFont(scale: CGFloat) -> Font {
        .custom("Songti SC", size: 14 * scale, relativeTo: .body)
    }

    static func footerFont(scale: CGFloat) -> Font {
        .system(size: 10.5 * scale, weight: .medium)
    }
}

// MARK: - 散场卡

/// V2 editorial 构图,左对齐,评分词是主视觉,不是居中大 emoji。
///
///   BEFORESHOW · 散场记录
///   2026.07.28 · 杭州
///   陈绮贞
///   漫漫长夜 Cheer20
///   🔥 夯爆了
///   “最后一首歌结束的时候,灯亮得特别慢。”
///   我的第 12 场现场                         开场前
///
/// 无评分时:评分行替换为 "已落幕"。无散场文字时:quote 整段隐藏。
struct DispersalCeremonyShareCard: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String

    private var currentRating: DispersalRating? {
        guard let rating else { return nil }
        return DispersalRating.from(rawValue: rating)
    }

    private var trimmedNote: String? {
        FootprintTextNormalizer.nonEmptyTrimmed(note)
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

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / DispersalCeremonyCardTokens.baseWidth
            ZStack {
                background

                ViewThatFits(in: .vertical) {
                    cardBody(scale: scale, eventLineLimit: 2, quoteMaxLines: 6)
                    cardBody(scale: scale, eventLineLimit: 2, quoteMaxLines: 3)
                    cardBody(scale: scale, eventLineLimit: 2, quoteMaxLines: 0)
                    cardBody(scale: scale, eventLineLimit: 1, quoteMaxLines: 0)
                }
                .padding(DispersalCeremonyCardTokens.cardPadding * scale)
            }
        }
    }

    // MARK: 子区块

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DispersalCeremonyCardTokens.gradientTop,
                    DispersalCeremonyCardTokens.gradientMid,
                    DispersalCeremonyCardTokens.gradientBottom
                ],
                startPoint: UnitPoint(x: 0.15, y: 0),
                endPoint: UnitPoint(x: 0.9, y: 1)
            )

            GeometryReader { proxy in
                ZStack {
                    Ellipse()
                        .fill(DispersalCeremonyCardTokens.goldGlow)
                        .frame(
                            width: proxy.size.width * 1.10,
                            height: proxy.size.height * 0.85
                        )
                        .position(
                            x: proxy.size.width * 0.80,
                            y: proxy.size.height * 0.05
                        )
                        .blur(radius: 36)

                    Ellipse()
                        .fill(DispersalCeremonyCardTokens.blueGlow)
                        .frame(
                            width: proxy.size.width * 1.05,
                            height: proxy.size.height * 0.90
                        )
                        .position(
                            x: proxy.size.width * 0.10,
                            y: proxy.size.height * 0.25
                        )
                        .blur(radius: 40)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func cardBody(scale: CGFloat, eventLineLimit: Int, quoteMaxLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DispersalCeremonyCardCopy.brand)
                .font(DispersalCeremonyCardTokens.brandFont(scale: scale))
                .tracking(DispersalCeremonyCardTokens.brandTopTracking * scale)
                .foregroundColor(DispersalCeremonyCardTokens.brand)

            Text(dateLine)
                .font(DispersalCeremonyCardTokens.dateFont(scale: scale))
                .foregroundColor(DispersalCeremonyCardTokens.date)
                .padding(.top, DispersalCeremonyCardTokens.dateTopPadding * scale)

            eventBlock(scale: scale, lineLimit: eventLineLimit)
            ratingBlock(scale: scale)

            if let trimmedNote, quoteMaxLines > 0 {
                quoteBlock(text: trimmedNote, scale: scale, lineLimit: quoteMaxLines)
            }

            Spacer(minLength: DispersalCeremonyCardTokens.footerMinSpacing * scale)
            footerBlock(scale: scale)
        }
    }

    private func eventBlock(scale: CGFloat, lineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: DispersalCeremonyCardTokens.eventLineSpacing * scale) {
            ForEach(Array(eventLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(DispersalCeremonyCardTokens.eventFont(scale: scale))
                    .foregroundColor(.white)
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, DispersalCeremonyCardTokens.eventTopPadding * scale)
    }

    private func ratingBlock(scale: CGFloat) -> some View {
        Group {
            if let currentRating {
                Text(DispersalCeremonyCardCopy.ratingTitle(currentRating))
                    .font(DispersalCeremonyCardTokens.ratingFont(scale: scale))
                    .foregroundColor(currentRating.tint)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            } else {
                Text(BSLocalization.text("已落幕"))
                    .font(DispersalCeremonyCardTokens.ratingFont(scale: scale))
                    .foregroundColor(DispersalCeremonyCardTokens.neutralHeader)
            }
        }
        .padding(.top, DispersalCeremonyCardTokens.ratingTopPadding * scale)
    }

    private func quoteBlock(text: String, scale: CGFloat, lineLimit: Int) -> some View {
        Text("\u{201C}\(text)\u{201D}")
            .font(DispersalCeremonyCardTokens.quoteFont(scale: scale))
            .foregroundColor(DispersalCeremonyCardTokens.quote)
            .lineSpacing(DispersalCeremonyCardTokens.quoteLineSpacing * scale)
            .multilineTextAlignment(.leading)
            .lineLimit(lineLimit)
            .padding(.top, DispersalCeremonyCardTokens.quoteTopPadding * scale)
    }

    private func footerBlock(scale: CGFloat) -> some View {
        HStack {
            Text(DispersalCeremonyCardCopy.footerLeading(identity: identity))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 8)
            Text(DispersalCeremonyCardCopy.footerTrailing)
        }
        .font(DispersalCeremonyCardTokens.footerFont(scale: scale))
        .foregroundColor(DispersalCeremonyCardTokens.footer)
    }

    // MARK: 派生文本

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
}
