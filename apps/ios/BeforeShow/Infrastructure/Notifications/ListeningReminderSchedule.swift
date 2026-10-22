import Foundation

/// All dates are event-local civil days; this calculation never reads durable state.
enum ListeningReminderSchedule {
    private struct Target {
        let disc: ListeningReminderRoster.Disc?
        var artist: ListeningReminderRoster.Artist?
    }

    private static func queue(_ roster: ListeningReminderRoster) -> [Target] {
        guard let artist = roster.artists.first else { return [] }
        if roster.isMultiArtist {
            var remaining = roster.artists.map { artist -> [Target] in
                let entry = artist.featuredPlaylist ?? artist.albums.first
                return [Target(disc: entry, artist: artist)]
                    + artist.albums.filter { $0.id != entry?.id }.map { Target(disc: $0, artist: artist) }
            }
            var themes = [roster.singalong, roster.latest, roster.deepCuts].compactMap { $0 }
            var result: [Target] = []
            var count = 0
            while remaining.contains(where: { !$0.isEmpty }) {
                for index in remaining.indices where !remaining[index].isEmpty {
                    result.append(remaining[index].removeFirst())
                    count += 1
                    if count % 2 == 0, !themes.isEmpty {
                        result.append(Target(disc: themes.removeFirst()))
                    }
                }
            }
            return result
        }
        let discs = [roster.singalong, artist.albums.first, artist.featuredPlaylist,
                     roster.latest, roster.deepCuts].compactMap { $0 } + artist.albums.dropFirst()
        return discs.map { Target(disc: $0, artist: artist) }
    }

    static func requests(
        showID: UUID, showName: String, roster: ListeningReminderRoster, showDate: Date,
        addedAt: Date, now: Date, calendar: Calendar, blockedDays: Set<Date>
    ) -> [ScheduledShowNotification] {
        guard !roster.artists.isEmpty else { return [] }
        let queue = queue(roster)
        let uncached = !queue.contains { $0.disc != nil }
        let opening = calendar.startOfDay(for: showDate)
        var day = calendar.startOfDay(for: addedAt)
        var previous: Date?
        var index = 0
        var nodesSinceListening = 0
        let listeningBoundary = roster.lastListenedAt ?? addedAt
        var result: [ScheduledShowNotification] = []
        while day < opening {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day)! }
            let distance = calendar.dateComponents([.day], from: day, to: opening).day ?? 0
            let candidate = distance >= 31 ? calendar.component(.weekday, from: day) == 7
                : distance >= 15 ? distance % 3 == 0 : distance >= 2
            guard candidate, !blockedDays.contains(day),
                  let fire = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day), fire >= addedAt else { continue }
            if uncached, let previous, (calendar.dateComponents([.day], from: previous, to: day).day ?? 0) < 3 { continue }
            if let last = roster.lastListenedAt, calendar.isDate(day, inSameDayAs: last) { continue }
            if fire > listeningBoundary {
                guard nodesSinceListening < 3 || distance >= 31 || distance % 3 == 0 else { continue }
            }
            // Observed payloads keep their actual targets when the roster is rebuilt.
            // Missing/cleared notifications retain the documented theoretical fallback.
            if fire <= now, roster.deliveredDiscIDsByDay[day] != nil {
                if fire > listeningBoundary { nodesSinceListening += 1 }
                previous = day
                continue
            }
            let target: Target
            var isRepeat = false
            if uncached {
                target = Target(disc: nil, artist: roster.artists[index % roster.artists.count])
            } else {
                if fire > now {
                    while index < queue.count, let disc = queue[index].disc,
                          roster.completedDiscIDs.contains(disc.id)
                            || roster.deliveredDiscIDsByDay.values.contains(disc.id) { index += 1 }
                }
                if index < queue.count {
                    target = queue[index]
                    index += 1
                } else {
                    guard let disc = roster.singalong, !roster.completedDiscIDs.contains(disc.id) else { continue }
                    if let previous, (calendar.dateComponents([.day], from: previous, to: day).day ?? 0) < 2 { continue }
                    target = Target(disc: disc)
                    isRepeat = true
                }
            }
            if uncached { index += 1 }
            if fire > listeningBoundary { nodesSinceListening += 1 }
            previous = day
            guard fire > now else { continue }
            let line: String
            if isRepeat {
                line = BSLocalization.text("离现场越来越近了，再听听这份热门歌单吧。")
            } else if let disc = target.disc {
                if disc.id == roster.singalong?.id {
                    line = BSLocalization.text("收录了现场常演的热门歌，可以先熟悉一下。")
                } else if disc.id == roster.latest?.id {
                    line = BSLocalization.text("听听参演艺人最近发行的新歌。")
                } else if disc.id == roster.deepCuts?.id {
                    line = BSLocalization.text("热门曲目之外，这些作品也值得一听。")
                } else if let artist = target.artist, disc.id == artist.featuredPlaylist?.id {
                    line = BSLocalization.format("从这份精选歌单开始，认识一下%@。", artist.name)
                } else if let artist = target.artist {
                    line = BSLocalization.format("听听%1$@的专辑《%2$@》。", artist.name, disc.title)
                } else {
                    continue
                }
            } else {
                line = BSLocalization.format("来听听%@的歌。", target.artist?.name ?? "")
            }
            result.append(ScheduledShowNotification(
                showID: showID, milestone: .listeningReminder, fireDate: fire,
                title: showName,
                body: line,
                destination: .listen, discID: target.disc?.id, artistID: target.artist?.id, artistName: target.artist?.name
            ))
        }
        return result
    }
}
