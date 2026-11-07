import SwiftData
import SwiftUI

/// 花销：票价 + 路费两格。空着就是「还没填」，0 是有效金额。
struct ShowSpendingSheet: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var ticket = ""
    @State private var travel = ""
    @State private var saveFailed = false
    @FocusState private var focused: Field?

    private enum Field { case ticket, travel }

    private var currencyCode: String { show.spendingCurrencyCode }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                field(BSLocalization.text("票价"), text: $ticket, field: .ticket)
                field(BSLocalization.text("路费"), text: $travel, field: .travel)
                if saveFailed {
                    Text(BSLocalization.text("没有保存，请重试"))
                        .font(.system(size: 13))
                        .foregroundStyle(BSColor.Stage.live)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle(BSLocalization.text("花销"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: commit) { Image(systemName: "checkmark") }
                        .tint(BSColor.Stage.foreground)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .accessibilityLabel(BSLocalization.text("完成"))
                }
            }
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .preferredColorScheme(.dark)
        .onAppear {
            ticket = Self.text(show.ticketPrice)
            travel = Self.text(show.travelCost)
            focused = show.ticketPrice == nil ? .ticket : .travel
        }
    }

    private func field(_ title: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            Spacer(minLength: 8)
            Text(Locale.current.localizedCurrencySymbol(for: currencyCode))
                .font(.system(size: 15))
                .foregroundStyle(BSColor.Stage.muted)
            TextField(BSLocalization.text("还没填"), text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(BSColor.Stage.foreground)
                .focused($focused, equals: field)
                .frame(maxWidth: 140)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
    }

    private func commit() {
        do {
            try show.setSpending(ticketPrice: Self.amount(ticket), travelCost: Self.amount(travel), currencyCode: currencyCode)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveFailed = true
        }
    }

    static func amount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: .current) ?? Decimal(string: trimmed.replacingOccurrences(of: ",", with: "."))
    }

    static func text(_ amount: Decimal?) -> String {
        amount.map { NSDecimalNumber(decimal: $0).description(withLocale: Locale.current) } ?? ""
    }
}

extension Locale {
    func localizedCurrencySymbol(for code: String) -> String {
        var components = Locale.Components(locale: self)
        components.currency = Locale.Currency(code)
        return Locale(components: components).currencySymbol ?? code
    }
}

extension Show {
    func formattedSpending(_ amount: Decimal?) -> String? {
        amount.map { $0.formatted(.currency(code: spendingCurrencyCode).precision(.fractionLength(0...2))) }
    }
}
