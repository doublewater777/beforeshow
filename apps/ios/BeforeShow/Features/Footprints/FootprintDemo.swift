import SwiftData
import SwiftUI

/// 还没有任何现场时的示例足迹：只活在内存里，点进去和真的足迹一样，但永远碰不到用户的数据。
@MainActor
enum FootprintDemo {
    static let badgeDefaultsSuite = "com.doublewaterapps.beforeshow.footprintDemo"

    static func makeContainer(now: Date = Date()) throws -> ModelContainer {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        for show in try shows(now: now) {
            container.mainContext.insert(show)
        }
        try container.mainContext.save()
        return container
    }

    /// 示例徽章看没看过记在一块用完即扔的地方，不吞掉用户第一次真解锁的掉落。
    static func badgeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: badgeDefaultsSuite) ?? .standard
        defaults.removePersistentDomain(forName: badgeDefaultsSuite)
        return defaults
    }

    static func shows(now: Date) throws -> [Show] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let today = calendar.startOfDay(for: now)
        return try entries.map { entry in
            let day = calendar.date(byAdding: .day, value: -entry.daysAgo, to: today) ?? today
            let start = calendar.date(byAdding: .minute, value: 19 * 60 + 30, to: day) ?? day
            let show = try Show(
                name: entry.name(),
                date: day,
                startTime: start,
                timeZoneIdentifier: timeZone,
                city: BSLocalization.text(entry.city),
                venueName: BSLocalization.text(entry.venue),
                artists: entry.artists.map { ArtistSlot(name: $0) }
            )
            show.markEnded(at: start.addingTimeInterval(entry.artists.count > 1 ? 5 * 3600 : 2.5 * 3600))
            if !entry.companions.isEmpty {
                show.setCompanionNames(entry.companions.map { BSLocalization.text($0) })
            }
            if let rating = entry.rating {
                try show.setClosingRitual(rating: rating, note: entry.note.map { BSLocalization.text($0) }, markCeremonyCompleted: true)
            }
            return show
        }
    }

    private static let timeZone = "Asia/Shanghai"

    private struct Entry {
        let daysAgo: Int
        let festival: LocalizedStringResource?
        let artists: [String]
        let city: LocalizedStringResource
        let venue: LocalizedStringResource
        var companions: [LocalizedStringResource] = []
        var rating: Int? = nil
        var note: LocalizedStringResource? = nil

        func name() -> String {
            festival.map { BSLocalization.text($0) } ?? artists.joined(separator: " · ")
        }
    }

    // 一年前差三天的那场让「那年今日」亮起来；两场音乐节把常看的乐队连成星座。
    private static let entries: [Entry] = [
        Entry(daysAgo: 16, festival: nil, artists: ["告五人"], city: "上海", venue: "梅赛德斯-奔驰文化中心", companions: ["小林"], rating: 5, note: "大合唱的时候，全场的灯都亮了。"),
        Entry(daysAgo: 48, festival: "草莓音乐节", artists: ["告五人", "落日飞车", "椅子乐团"], city: "北京", venue: "通州运河公园", companions: ["小林"]),
        Entry(daysAgo: 95, festival: nil, artists: ["万能青年旅店"], city: "杭州", venue: "MAO Livehouse", rating: 4),
        Entry(daysAgo: 150, festival: nil, artists: ["落日飞车"], city: "成都", venue: "成都东郊记忆", companions: ["阿宁"]),
        Entry(daysAgo: 230, festival: "简单生活节", artists: ["万能青年旅店", "deca joins", "惘闻"], city: "台北", venue: "华山1914文创园区"),
        Entry(daysAgo: 362, festival: nil, artists: ["草东没有派对"], city: "广州", venue: "广州体育馆", companions: ["小林", "阿宁"], rating: 5),
        Entry(daysAgo: 430, festival: nil, artists: ["告五人"], city: "杭州", venue: "杭州奥体中心体育馆"),
        Entry(daysAgo: 520, festival: nil, artists: ["deca joins"], city: "上海", venue: "MAO Livehouse"),
        Entry(daysAgo: 610, festival: "草莓音乐节", artists: ["落日飞车", "告五人", "草东没有派对"], city: "上海", venue: "世博公园", companions: ["阿宁"])
    ]
}

extension EnvironmentValues {
    @Entry var footprintBadgeDefaults: UserDefaults = .standard
}

/// 足迹 tab 在没有任何现场时显示的示例：一整套能点的足迹，底部一条提示带用户去添加第一场。
struct FootprintDemoView: View {
    let onAdd: () -> Void

    @State private var demo: (container: ModelContainer, badgeDefaults: UserDefaults)?
    @State private var failed = false

    var body: some View {
        Group {
            if let demo {
                FootprintDemoStack(onAdd: onAdd)
                    .modelContainer(demo.container)
                    .environment(\.footprintBadgeDefaults, demo.badgeDefaults)
            } else if failed {
                FootprintEmptyView(content: FootprintEmptyStateCopy.content(hasCurrentShow: false), currentShow: nil, onAdd: onAdd)
                    .background { FootprintBackground().ignoresSafeArea() }
                    .bsRootBottomChrome()
            } else {
                FootprintBackground().ignoresSafeArea()
            }
        }
        .task {
            guard demo == nil, !failed else { return }
            do {
                demo = (try FootprintDemo.makeContainer(), FootprintDemo.badgeDefaults())
            } catch {
                failed = true
            }
        }
    }
}

private struct FootprintDemoStack: View {
    let onAdd: () -> Void

    @Query(sort: \Show.date) private var shows: [Show]
    @State private var detailTarget: FootprintDetailDestination?
    @State private var isSearching = false

    var body: some View {
        let archive = FootprintArchiveBuilder.make(shows: shows)
        NavigationStack {
            FootprintDashboardView(
                archive: archive,
                covers: [:],
                allShows: shows,
                onShowSelected: { detailTarget = FootprintDetailDestination(show: $0) },
                onAdd: onAdd,
                onSearch: { isSearching = true }
            )
            .overlay(alignment: .bottom) { banner }
            .background { FootprintBackground().ignoresSafeArea() }
            .bsRootBottomChrome()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailTarget) { target in
                FootprintDetailView(show: target.show, archive: archive)
            }
            .sheet(isPresented: $isSearching) {
                FootprintSearchSheet(archive: archive, covers: [:])
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 12) {
            Text(BSLocalization.text("这是示例足迹"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Text(BSLocalization.text("添加第一场"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.background)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(BSColor.Stage.foreground, in: Capsule())
            }
            .buttonStyle(BSPressStyle())
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(BSColor.Stage.border))
        .padding(.horizontal, 20)
        .padding(.bottom, BSSpacing.sm)
        .bsAdaptiveContentWidth()
    }
}
