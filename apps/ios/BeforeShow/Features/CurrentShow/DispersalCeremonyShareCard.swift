import SwiftUI
import UIKit

enum DispersalCeremonyShareExport {
    static let renderSize = CGSize(width: 360, height: 640)
    static let renderScale: CGFloat = 3

    @MainActor
    static func renderImage(
        show: Show,
        identity: FootprintDetailIdentity,
        rating: Int?,
        note: String,
        ambientColor: Color? = nil
    ) -> UIImage? {
        let card = DispersalCeremonyShareCard(
            show: show,
            identity: identity,
            rating: rating,
            note: note,
            ambientColor: ambientColor
        )
        .frame(width: renderSize.width, height: renderSize.height)

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(
            width: renderSize.width,
            height: renderSize.height
        )
        renderer.scale = renderScale
        return renderer.uiImage
    }

    static func loadAmbientColor(for coverURLString: String?) async -> Color? {
        guard let coverURLString,
              let url = URL(string: coverURLString),
              let image = await ShowCoverImageCache.shared.image(from: url),
              let ambient = CoverAmbientColor.uiColor(from: image) else {
            return nil
        }
        return Color(ambient)
    }
}

// MARK: - 散场卡（纸本拼贴）

/// 在 360×640 的基准画布上排版,预览时整体等比缩放,保证预览与导出同构。
struct DispersalCeremonyShareCard: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String
    let ambientColor: Color?
    let transitionNamespace: Namespace.ID?

    private static let base = DispersalCeremonyShareExport.renderSize
    private static let margin: CGFloat = 27

    init(
        show: Show,
        identity: FootprintDetailIdentity,
        rating: Int?,
        note: String,
        ambientColor: Color? = nil,
        transitionNamespace: Namespace.ID? = nil
    ) {
        self.show = show
        self.identity = identity
        self.rating = rating
        self.note = note
        self.ambientColor = ambientColor
        self.transitionNamespace = transitionNamespace
    }

    private var currentRating: DispersalRating? {
        rating.flatMap(DispersalRating.from(rawValue:))
    }

    private var calendar: Calendar { show.timingCalendar() }

    private var cityText: String? {
        FootprintTextNormalizer.nonEmptyTrimmed(show.city)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.base.width
            paper
                .frame(width: Self.base.width, height: Self.base.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private var paper: some View {
        ZStack(alignment: .topLeading) {
            BSColor.Paper.background
            LinearGradient(
                colors: [BSColor.Paper.spine.opacity(0.16), BSColor.Paper.spine.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 18)

            header
            polaroid
            dateColumn
            postmark
            storyBlock
            footer
            ticketStub
        }
        .foregroundStyle(BSColor.Paper.ink)
        .clipped()
    }

    // MARK: Layers

    private var header: some View {
        HStack {
            Text(BSLocalization.format("第 %lld 场", identity.showOrdinal))
            Spacer()
        }
        .font(.system(size: 10, weight: .medium))
        .tracking(BSFont.Editorial.kickerTracking)
        .foregroundStyle(BSColor.Paper.inkMuted)
        .padding(.horizontal, Self.margin)
        .padding(.top, 22)
    }

    private var polaroid: some View {
        DispersalPolaroid(
            coverURL: show.coverImageURL,
            ambient: ambientColor,
            imageWidth: 172,
            cornerColor: BSColor.Paper.ink
        )
        .rotationEffect(.degrees(-4))
        .shadow(color: BSColor.Paper.spine.opacity(0.28), radius: 12, y: 10)
        .offset(x: 25, y: 60)
    }

    private var dateColumn: some View {
        DispersalDateColumn(
            stamp: DispersalCeremonyCardCopy.dateStamp(for: show.effectiveDate, calendar: calendar),
            caption: DispersalCeremonyCardCopy.dateCaption(for: show.effectiveDate, calendar: calendar),
            numeralSize: 68,
            color: BSColor.Paper.ink,
            captionColor: BSColor.Paper.inkMuted
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Self.margin)
        .padding(.top, 64)
    }

    private var postmark: some View {
        DispersalPostmark(
            city: cityText,
            date: BSDateFormat.dottedDate(show.effectiveDate, calendar: calendar),
            ink: BSColor.Paper.gold,
            knockout: BSColor.Paper.background,
            diameter: 90
        )
        .rotationEffect(.degrees(-12))
        .opacity(0.85)
        .offset(x: 168, y: 262)
    }

    /// 标题、评级与短评顺排,长标题把下方内容往下推而不是叠上去。
    private var storyBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleBlock
            reviewBlock
        }
        .frame(width: Self.base.width - Self.margin * 2, alignment: .leading)
        .offset(x: Self.margin, y: 356)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DispersalCeremonyCardCopy.serifTitle(show.name))
                .font(BSFont.Editorial.song(size: 28, weight: .black))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let facts = DispersalCeremonyCardCopy.factsLine(
                startTime: show.startTime,
                endedAt: show.endedAt,
                calendar: calendar
            ) {
                Text(facts)
                    .font(BSFont.Editorial.numerals(size: 15, italic: true))
                    .foregroundStyle(BSColor.Paper.inkMuted)
                    .lineLimit(1)
            }
        }
    }

    private var reviewBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ratingStamp
                if let currentRating {
                    Text(currentRating.sub)
                        .font(BSFont.Editorial.song(size: 13))
                        .foregroundStyle(BSColor.Paper.inkMuted)
                }
            }

            if let trimmedNote = FootprintTextNormalizer.nonEmptyTrimmed(note) {
                Text("\u{201C}\(trimmedNote)\u{201D}")
                    .font(BSFont.Editorial.song(size: 15))
                    .lineSpacing(6)
                    .lineLimit(3)
                    .dispersalMatchedGeometry(id: "dispersal.note", namespace: transitionNamespace)
            } else {
                Text(BSLocalization.text("散场了，现场的心跳收进这里。"))
                    .font(BSFont.Editorial.song(size: 15))
                    .foregroundStyle(BSColor.Paper.inkMuted)
            }
        }
    }

    private var ratingStamp: some View {
        let ink = currentRating?.paperInk ?? BSColor.Paper.inkMuted
        return Text(currentRating?.label ?? BSLocalization.text("已落幕"))
            .font(BSFont.Editorial.song(size: 15, weight: .black))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Rectangle().stroke(ink, lineWidth: 1.5))
            .rotationEffect(.degrees(-3))
            .dispersalMatchedGeometry(id: "dispersal.rating", namespace: transitionNamespace)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DispersalCeremonyCardCopy.footerLeading(identity: identity))
                .font(BSFont.Editorial.song(size: 13))
                .foregroundStyle(BSColor.Paper.inkMuted)
                .frame(maxWidth: 160, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            BSShareByline(tone: BSColor.Paper.inkMuted)
        }
        .padding(.leading, Self.margin)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 18)
    }

    private var ticketStub: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "ADMIT ONE")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(BSColor.Stage.accent)
                Spacer(minLength: 0)
                Text(verbatim: DispersalCeremonyCardCopy.ticketNumber(ordinal: identity.showOrdinal))
                    .font(BSFont.Editorial.numerals(size: 14))
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer(minLength: 0)
                Barcode()
                    .fill(BSColor.Stage.foreground)
                    .frame(height: 8)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)

            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(BSColor.Stage.accent.opacity(0.5))
                .frame(width: 1)
            Spacer().frame(width: 28)
        }
        .frame(width: 170, height: 66)
        .background(RoundedRectangle(cornerRadius: BSRadius.sm).fill(BSColor.Stage.surface))
        .rotationEffect(.degrees(7))
        .shadow(color: .black.opacity(0.35), radius: 9, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, -6)
        .padding(.bottom, 12)
        .accessibilityHidden(true)
    }
}

/// 票根条码:固定节奏的竖线,纯装饰。
private struct Barcode: Shape {
    func path(in rect: CGRect) -> Path {
        let widths: [CGFloat] = [1, 2, 1, 1, 3, 1, 2, 1, 1, 2, 3, 1]
        var path = Path()
        var x = rect.minX
        var index = 0
        while x < rect.maxX {
            let w = widths[index % widths.count]
            path.addRect(CGRect(x: x, y: rect.minY, width: w, height: rect.height))
            x += w + 2
            index += 1
        }
        return path
    }
}
