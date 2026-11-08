import SwiftUI

/// One thermal receipt per year: ticket + travel per show, the total, and the extremes.
/// Amounts stay on this page and never go into a share image.
struct FootprintLedgerView: View {
    let archive: FootprintArchiveSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var year: Int?
    @State private var hasPickedYear = false

    private var years: [Int] { FootprintLedgerArchive.years(shows: archive.shows) }
    private static let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        let receipt = FootprintLedgerArchive.receipt(shows: archive.shows, year: year)
        ScrollView {
            VStack(spacing: 0) {
                yearChips.padding(.horizontal, 20)
                Capsule()
                    .fill(FootprintRoomPalette.printerSlot)
                    .frame(width: 300, height: 10)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 2)
                    .padding(.top, 20)
                paper(receipt)
                    .frame(width: 280)
                    .padding(.top, -5)
                if !receipt.unrecordedShowIDs.isEmpty {
                    NavigationLink {
                        FootprintLedgerBackfillView(shows: archive.shows(for: receipt.unrecordedShowIDs))
                    } label: {
                        Text(BSLocalization.format("还有 %lld 场没记", receipt.unrecordedShowIDs.count))
                            .font(.system(size: 14))
                            .foregroundStyle(BSColor.Stage.accent)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background { BSColor.Stage.background.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("账本")) } }
        .sensoryFeedback(.impact(weight: .light), trigger: year)
        .onAppear {
            if !hasPickedYear { year = years.first; hasPickedYear = true }
        }
    }

    private var yearChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(years.map(Optional.some) + [nil], id: \.self) { option in
                    let isOn = option == year
                    Button { year = option } label: {
                        Text(option.map(String.init) ?? BSLocalization.text("全部"))
                            .font(.system(size: 13, weight: isOn ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(isOn ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(0.7))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(isOn ? AnyShapeStyle(FootprintRoomPalette.receiptPaper) : AnyShapeStyle(Color.white.opacity(0.07)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private func paper(_ receipt: FootprintLedgerReceipt) -> some View {
        let money: (Decimal?) -> String = { FootprintLedgerArchive.format($0, currencyCode: receipt.currencyCode) }
        return VStack(alignment: .leading, spacing: 0) {
            Text("BEFORESHOW")
                .font(.system(size: 16, weight: .semibold).width(.condensed))
                .tracking(4)
                .frame(maxWidth: .infinity)
            Text("\(yearLabel(receipt)) · \(receipt.lines.count) SHOWS")
                .foregroundStyle(FootprintRoomPalette.receiptInk.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            dashed
            VStack(alignment: .leading, spacing: 7) {
                ForEach(receipt.lines) { line in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text("\(footprintDayText(line.date)) \(line.name)").lineLimit(1)
                            Spacer(minLength: 4)
                            Text(money(line.total)).fontWeight(.bold)
                        }
                        Text(BSLocalization.format("  票 %1$@ · 路 %2$@", money(line.ticket), money(line.travel)))
                            .foregroundStyle(FootprintRoomPalette.receiptInk.opacity(0.5))
                    }
                }
            }
            dashed
            pair(BSLocalization.text("票价"), money(receipt.ticketSum))
            pair(BSLocalization.text("路费"), money(receipt.travelSum))
            pair(BSLocalization.text("合计"), money(receipt.total))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .padding(.top, 6)
            pair(BSLocalization.text("平均每场"), money(receipt.average))
                .foregroundStyle(FootprintRoomPalette.receiptInk.opacity(0.55))
            dashed
            if let top = receipt.mostExpensive { extreme(BSLocalization.text("最贵"), top, amount: money(top.total)) }
            if receipt.lines.count > 1, let low = receipt.cheapest { extreme(BSLocalization.text("最省"), low, amount: money(low.total)) }
            barcode.padding(.top, 12)
        }
        .font(Self.mono)
        .foregroundStyle(FootprintRoomPalette.receiptInk)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 26)
        .background(FootprintRoomPalette.receiptPaper)
        .shadow(color: .black.opacity(0.55), radius: 15, y: 16)
        .bsMaskUserContent()
    }

    private func yearLabel(_ receipt: FootprintLedgerReceipt) -> String {
        if let year = receipt.year { return String(year) }
        guard let first = years.last, let last = years.first, first != last else { return years.first.map(String.init) ?? "" }
        return "\(first)–\(last)"
    }

    private func pair(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            Text(value).lineLimit(1)
        }
    }

    private func extreme(_ label: String, _ line: FootprintLedgerLine, amount: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer(minLength: 8)
            Text(line.name).lineLimit(1).truncationMode(.middle)
            Text(amount).fixedSize()
        }
    }

    private var dashed: some View {
        Line()
            .stroke(FootprintRoomPalette.receiptInk.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private var barcode: some View {
        Canvas { canvas, size in
            var x: CGFloat = 0
            var seed: UInt64 = 7
            while x < size.width {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let width: CGFloat = seed >> 62 == 0 ? 2 : 1
                canvas.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(FootprintRoomPalette.receiptInk))
                x += width + CGFloat(2 + (seed >> 61) % 3)
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// Shows without spending yet; tapping one opens the two-field sheet in place.
struct FootprintLedgerBackfillView: View {
    let shows: [Show]

    @State private var editing: Show?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(shows) { show in
                    Button { editing = show } label: {
                        HStack(spacing: 12) {
                            Text(footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()))
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(BSColor.Stage.foreground.opacity(0.5))
                            Text(show.name)
                                .font(.system(size: 14))
                                .foregroundStyle(BSColor.Stage.foreground)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(show.hasAnySpending ? "›" : BSLocalization.text("补上"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(show.hasAnySpending ? BSColor.Stage.foreground.opacity(0.4) : BSColor.Stage.accent)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .bsAdaptiveContentWidth()
        }
        .background { FootprintBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("补记花销")) } }
        .sheet(item: $editing) { ShowSpendingSheet(show: $0) }
    }
}
