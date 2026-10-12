import SwiftUI

struct TimetableDateField: View {
    let title: String
    @Binding var selection: Date
    let timeZone: TimeZone

    var body: some View {
        DatePicker(title, selection: $selection, displayedComponents: .date)
            .datePickerStyle(.compact)
            .font(BSFont.body)
            .foregroundStyle(TimetableStyle.foreground)
            .tint(TimetableStyle.mine)
            .environment(\.timeZone, timeZone)
            .environment(\.calendar, calendar)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
