import Foundation

/// A link that hands one show to someone else's app. The show travels inside the link, so making one needs no
/// network and opening one needs no server. `https://beforeshow.doublewaterapps.com/s/<token>` opens the app where it
/// is installed and the web page where it is not; `beforeshow://s/<token>` is the web page's way back into the app.
enum ShowShareLink {
    static let host = "beforeshow.doublewaterapps.com"
    static let scheme = "beforeshow"
    /// A cover address longer than this stays out of the link, so the code printed from it stays easy to scan.
    static let coverLimit = 200
    /// Same ceiling `draft(from:)` enforces. Longer names are cut, not rejected, so the code still adds the show.
    static let nameLimit = 200

    static func sharedName(_ name: String) -> String {
        String(name.prefix(nameLimit))
    }

    private struct Payload: Codable {
        var v = 1
        /// Name.
        var n: String
        /// Date and start time, in seconds since 1970.
        var d: Int64
        var t: Int64
        /// End date and end time.
        var e: Int64?
        var f: Int64?
        /// Time zone identifier, or seconds from GMT.
        var z: String?
        var s: Int?
        /// City and venue.
        var c: String?
        var l: String?
        /// Cover, only when it is a web address.
        var p: String?
    }

    /// When and where, and the cover; the lineup stays out so even a festival's code stays sparse.
    static func url(for show: Show) -> URL {
        let calendar = show.timingCalendar()
        // A show moved to a new date travels as it now stands; its old end no longer applies.
        let postponed = show.postponedDate
        let start = postponed == nil
            ? show.startTime
            : CurrentShowTimeState.effectiveStartTime(timing: show.declaredTimingFields, calendar: calendar)
        let payload = Payload(
            n: sharedName(show.name),
            d: seconds(postponed ?? show.date),
            t: seconds(start),
            e: postponed == nil ? show.endDate.map(seconds) : nil,
            f: postponed == nil ? show.endTime.map(seconds) : nil,
            z: show.timeZoneIdentifier,
            s: show.timeZoneSecondsFromGMT,
            c: nonEmpty(show.city),
            l: nonEmpty(show.venueName),
            p: webCover(show.coverImageURL, limit: coverLimit)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = (try? encoder.encode(payload)) ?? Data()
        let token = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "https://\(host)/s/\(token)")!
    }

    /// The token of a show link, whether or not it decodes; nil for any other link.
    static func token(in url: URL) -> String? {
        let scheme = url.scheme?.lowercased(), host = url.host?.lowercased()
        let token: Substring
        if scheme == "https", host == Self.host, url.path.hasPrefix("/s/") {
            token = url.path.dropFirst(3)
        } else if scheme == Self.scheme, host == "s" {
            token = url.path.dropFirst()
        } else {
            return nil
        }
        return String(token)
    }

    /// What the add-show flow opens with, every field marked as brought in.
    static func draft(from url: URL) -> ShowDraft? {
        guard let token = token(in: url), !token.isEmpty, token.count < 4_096,
              token.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        var padded = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.v == 1,
              let name = nonEmpty(payload.n), name.count <= 200 else { return nil }

        let city = nonEmpty(payload.c) ?? "", venue = nonEmpty(payload.l) ?? ""
        var fields: Set<ShowDraftField> = [.name, .date, .startTime]
        if !city.isEmpty { fields.insert(.city) }
        if !venue.isEmpty { fields.insert(.venueName) }
        return ShowDraft(
            name: name,
            date: date(payload.d),
            startTime: date(payload.t),
            endDate: payload.e.map(date),
            endTime: payload.f.map(date),
            timeZoneSecondsFromGMT: payload.s.flatMap { abs($0) <= 18 * 3_600 ? $0 : nil },
            timeZoneIdentifier: payload.z.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 },
            city: city,
            venueName: venue,
            coverImageURL: webCover(payload.p, limit: 1_024) ?? "",
            source: .link,
            recognizedFields: fields
        )
    }

    private static func webCover(_ stored: String?, limit: Int) -> String? {
        guard let stored = nonEmpty(stored), stored.count <= limit,
              let scheme = URL(string: stored)?.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return stored
    }

    private static func seconds(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970.rounded()) }

    private static func date(_ seconds: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
