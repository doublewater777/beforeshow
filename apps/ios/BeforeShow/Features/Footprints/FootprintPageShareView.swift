import SwiftUI

// MARK: - Footprint Page Share

struct FootprintPageShareSheet<Content: View>: View {
    let title: String
    let kicker: String
    let covers: [UUID: FootprintCover]
    var extraWarmup: (() async -> Void)? = nil
    let onSaved: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var scaledContentHeight: CGFloat?
    @State private var selectedDetent: PresentationDetent = .large

    var body: some View {
        FootprintShareActionSheet(
            title: BSLocalization.format("分享%@", title),
            subtitle: "",
            previewHeight: FootprintPageSharePreviewLayout.height(for: scaledContentHeight),
            exportSize: CGSize(width: FootprintDashboardExportView.layoutWidth, height: 0),
            usesIntrinsicHeight: true,
            exportScale: FootprintDashboardExportView.exportScale,
            beforeExport: {
                await FootprintCoverExportWarmup.warm(covers: covers)
                await extraWarmup?()
            },
            flexiblePreviewHeight: true,
            previewMaxHeight: scaledContentHeight,
            preview: {
                FootprintPageExportPreview(
                    title: title,
                    kicker: kicker,
                    content: content,
                    onScaledContentHeightChange: { scaledContentHeight = $0 }
                )
            },
            exportContent: { FootprintPageExportView(title: title, kicker: kicker, content: content) },
            onSaved: onSaved
        )
        .presentationDetents(
            [
                .height(FootprintPageSharePreviewLayout.sheetHeight(for: scaledContentHeight)),
                .large
            ],
            selection: $selectedDetent
        )
    }
}

struct FootprintPageExportView<Content: View>: View {
    let title: String
    let kicker: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BEFORESHOW · LIVE ARCHIVE")
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(1.65)
                    .foregroundColor(BSColor.Stage.accent)
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
            }

            VStack(alignment: .leading, spacing: 16) {
                if !kicker.isEmpty {
                    Text(kicker)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(BSColor.Stage.accent)
                }
                content()
            }

            HStack {
                Text(BSLocalization.text("开场前"))
                Spacer()
                Text(footprintFullDateText(Date(), calendar: Calendar.current))
            }
            .font(.system(size: 9.5))
            .foregroundColor(BSColor.Stage.dim)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 30)
        .frame(width: FootprintDashboardExportView.layoutWidth, alignment: .leading)
        .background(BSColor.Stage.background)
    }
}

private struct FootprintPageExportPreview<Content: View>: View {
    let title: String
    let kicker: String
    @ViewBuilder let content: () -> Content
    let onScaledContentHeightChange: (CGFloat) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / FootprintDashboardExportView.layoutWidth
            ScrollView {
                FootprintPageExportView(title: title, kicker: kicker, content: content)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        contentHeight = size.height
                        onScaledContentHeightChange(size.height * scale)
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(
                        width: geometry.size.width,
                        height: contentHeight * scale,
                        alignment: .topLeading
                    )
            }
        }
    }
}

enum FootprintPageSharePreviewLayout {
    static let maximumHeight: CGFloat = 368
    static let sheetChromeHeight: CGFloat = 148

    static func height(for scaledContentHeight: CGFloat?) -> CGFloat {
        guard let scaledContentHeight, scaledContentHeight.isFinite, scaledContentHeight > 0 else {
            return maximumHeight
        }
        return min(ceil(scaledContentHeight), maximumHeight)
    }

    static func sheetHeight(for scaledContentHeight: CGFloat?) -> CGFloat {
        height(for: scaledContentHeight) + sheetChromeHeight
    }
}
