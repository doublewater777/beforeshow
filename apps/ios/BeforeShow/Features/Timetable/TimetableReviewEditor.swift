import SwiftUI

/// Inline editor for one performance row.
struct TimetableReviewEditor: View {
    @Binding var performance: TimetableDraftPerformance
    let avatarURL: URL?
    let artistLinker: TimetableArtistLinker
    let hasOverlap: Bool
    let timeZone: TimeZone
    let onDelete: () -> Void
    let onDone: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TimetableArtistAvatar(name: performance.artistName, url: performance.appleMusicArtistID == nil ? avatarURL : performance.artistAvatarURL.flatMap(URL.init(string:)), size: 32)
                TextField(BSLocalization.text("艺人名称"), text: $performance.artistName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TimetableStyle.foreground)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(nameFocused ? TimetableStyle.mine : Color.white.opacity(0.14))
                            .frame(height: 1)
                    }
            }

            TimetableArtistConnectionView(performance: $performance, linker: artistLinker)

            HStack(spacing: 8) {
                timePicker($performance.startsAt)
                Text("–").foregroundStyle(TimetableStyle.dim)
                timePicker($performance.endsAt)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TimetableStyle.now)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(TimetableStyle.now.opacity(0.1)))
                }
                .buttonStyle(TimetablePressStyle())
                .accessibilityLabel(BSLocalization.text("删除"))
                Button(action: onDone) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TimetableStyle.background)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(TimetableStyle.foreground))
                }
                .buttonStyle(TimetablePressStyle())
                .accessibilityLabel(BSLocalization.text("完成"))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TimetableStyle.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08)))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .transition(.scale(scale: 0.98).combined(with: .opacity))
    }

    private func timePicker(_ selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(hasOverlap ? TimetableStyle.attention : TimetableStyle.mine)
            .environment(\.locale, Locale(identifier: "en_GB"))
            .environment(\.timeZone, timeZone)
    }
}
