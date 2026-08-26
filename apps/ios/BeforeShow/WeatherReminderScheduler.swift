import Foundation
import BackgroundTasks
import SwiftData
import UserNotifications

protocol WeatherNotificationSubmitting: Sendable {
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: WeatherNotificationSubmitting {}

/// 演出前一天天气提醒的调度器。
///
/// 确定性兜底仍由 `LocalNotificationCenter` 排 `.oneDayBefore`（演出前一天 20:00）。
/// 本调度器只在拉到「值得提醒的天气」时，用同一 identifier 替换那条待发通知的文案。
///
/// 三个触发入口：
/// - `registerTaskHandler(modelContainer:)`：冷启动时挂上 BGTaskScheduler handler
/// - `runOpenCheck(modelContext:)`：App 打开 / scenePhase=.active / 冷启动
/// - `scheduleNextBackgroundCheck(modelContext:)`：滚到下一个有演出的前一天 10:00，早于 20:00 的日历提醒
@MainActor
final class WeatherReminderScheduler {
    static let shared = WeatherReminderScheduler(
        provider: WeatherKitForecastProvider(),
        geocoding: CoreLocationGeocoding(),
        deduper: WeatherReminderDeduper(),
        calendar: .current,
        notifications: UNUserNotificationCenter.current()
    )

    init(
        provider: WeatherForecastProvider,
        geocoding: Geocoding,
        deduper: WeatherReminderDeduper,
        calendar: Calendar,
        notifications: WeatherNotificationSubmitting,
        clock: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.geocoding = geocoding
        self.deduper = deduper
        self.calendar = calendar
        self.notifications = notifications
        self.clock = clock
        self.backgroundCheckHour = 10
    }

    private let provider: WeatherForecastProvider
    private let geocoding: Geocoding
    private let deduper: WeatherReminderDeduper
    private let calendar: Calendar
    private let notifications: WeatherNotificationSubmitting
    private let clock: () -> Date
    /// 后台天气拉取必须早于 `.oneDayBefore` 的 20:00 触发，否则 `fireDate > now` 已经不成立。
    private let backgroundCheckHour: Int
    private var inFlightKeys: Set<String> = []

    private static let backgroundTaskIdentifier = "com.doublewaterapps.beforeshow.weather.refresh"

    // MARK: - BG registration

    func registerTaskHandler(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundRefresh(task: appRefreshTask, modelContainer: modelContainer)
        }
    }

    private nonisolated func handleBackgroundRefresh(
        task: BGAppRefreshTask,
        modelContainer: ModelContainer
    ) {
        nonisolated(unsafe) let bgTask = task
        let completion = OnceFlag()
        let work = Task {
            let success = await self.runBackgroundWork(modelContainer: modelContainer)
            if !Task.isCancelled {
                completion.run {
                    bgTask.setTaskCompleted(success: success)
                }
            }
        }
        task.expirationHandler = {
            work.cancel()
            completion.run {
                bgTask.setTaskCompleted(success: false)
            }
        }
    }

    private nonisolated func runBackgroundWork(modelContainer: ModelContainer) async -> Bool {
        await runBackgroundWorkOnMain(modelContainer: modelContainer)
    }

    private func runBackgroundWorkOnMain(modelContainer: ModelContainer) async -> Bool {
        let context = ModelContext(modelContainer)
        await runOpenCheck(modelContext: context)
        guard !Task.isCancelled else { return false }
        scheduleNextBackgroundCheck(modelContext: context)
        return true
    }

    // MARK: - Open check (foreground fallback)

    func runOpenCheck(modelContext: ModelContext) async {
        let shows = (try? modelContext.fetch(FetchDescriptor<Show>())) ?? []
        let showsByID = Dictionary(uniqueKeysWithValues: shows.map { ($0.id, $0) })
        let now = clock()
        let records = ((try? modelContext.fetch(FetchDescriptor<ShowNotificationScheduleRecord>())) ?? [])
            .filter { $0.milestone == .oneDayBefore && $0.isBackfill != true && $0.fireDate > now }

        for record in records {
            if Task.isCancelled { return }
            guard let show = showsByID[record.showID], show.changeStatus == .scheduled else { continue }

            let place = [show.venueAddress, show.city].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            let reminderDay = calendar.startOfDay(for: record.fireDate)

            let flightKey = Self.flightKey(showID: show.id, day: reminderDay, calendar: calendar)
            guard !inFlightKeys.contains(flightKey) else { continue }
            if deduper.hasPostedToday(showID: show.id, day: reminderDay, calendar: calendar) {
                continue
            }
            inFlightKeys.insert(flightKey)
            defer { inFlightKeys.remove(flightKey) }

            let decision = await fetchAndDecide(show: show, showName: show.name, place: place, targetDate: reminderDay)
            if Task.isCancelled { return }
            guard let decision, decision.isWeatherAlert else {
                deduper.markPostedToday(showID: show.id, day: reminderDay, calendar: calendar)
                continue
            }
            let posted = await replaceOneDayBefore(record: record, with: decision)
            if posted {
                deduper.markPostedToday(showID: show.id, day: reminderDay, calendar: calendar)
            }
        }
    }

    private func fetchAndDecide(
        show: Show,
        showName: String,
        place: String,
        targetDate: Date
    ) async -> WeatherReminderPolicy.Decision? {
        let coord: GeocodedCoordinate?
        do {
            coord = try await geocoding.resolve(city: show.city, address: show.venueAddress)
        } catch {
            coord = nil
        }
        var forecast: DailyForecast?
        if let coord {
            do {
                forecast = try await provider.fetchDailyForecast(at: coord, date: targetDate)
            } catch {
                forecast = nil
            }
        }
        return WeatherReminderPolicy.decision(forecast: forecast, showName: showName, place: place)
    }

    /// 只替换已登记的 `.oneDayBefore` 记录，不给非焦点现场另造一条通知。
    @discardableResult
    private func replaceOneDayBefore(
        record: ShowNotificationScheduleRecord,
        with decision: WeatherReminderPolicy.Decision
    ) async -> Bool {
        let (title, body) = WeatherReminderPolicy.copy(for: decision)
        let updated = ScheduledShowNotification(
            showID: record.showID,
            milestone: .oneDayBefore,
            fireDate: record.fireDate,
            title: title,
            body: body,
            isBackfill: false
        )
        do {
            try await notifications.add(updated.makeNotificationRequest())
            record.title = title
            record.body = body
            return true
        } catch {
            return false
        }
    }

    // MARK: - BG scheduling

    func scheduleNextBackgroundCheck(modelContext: ModelContext) {
        let shows = (try? modelContext.fetch(FetchDescriptor<Show>())) ?? []
        let now = clock()
        guard let next = nextReminderFireDate(shows: shows, now: now) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = next
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 模拟器/低电量模式可能拒绝；下次 runOpenCheck 会重试。
        }
    }

    private func nextReminderFireDate(shows: [Show], now: Date) -> Date? {
        var earliest: Date?
        for show in shows where show.changeStatus == .scheduled {
            let effective = show.effectiveDate
            let dayStart = calendar.startOfDay(for: effective)
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: dayStart),
                  let candidate = calendar.date(
                    bySettingHour: backgroundCheckHour,
                    minute: 0,
                    second: 0,
                    of: dayBefore
                  ),
                  candidate > now else { continue }
            if earliest == nil || candidate < (earliest ?? candidate) {
                earliest = candidate
            }
        }
        return earliest
    }

    static func flightKey(showID: UUID, day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(showID.uuidString).\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
