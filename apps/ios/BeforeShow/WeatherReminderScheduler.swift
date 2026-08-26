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
/// - `scheduleNextBackgroundCheck(modelContext:)`：滚到下一个有演出的明天 20:00
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
        notificationPlanner: LocalNotificationScheduler? = nil,
        clock: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.geocoding = geocoding
        self.deduper = deduper
        self.calendar = calendar
        self.notifications = notifications
        self.notificationPlanner = notificationPlanner ?? LocalNotificationScheduler(calendar: calendar)
        self.clock = clock
        self.reminderHour = 20
    }

    private let provider: WeatherForecastProvider
    private let geocoding: Geocoding
    private let deduper: WeatherReminderDeduper
    private let calendar: Calendar
    private let notifications: WeatherNotificationSubmitting
    private let notificationPlanner: LocalNotificationScheduler
    private let clock: () -> Date
    private let reminderHour: Int
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
        let now = clock()
        let target = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let targetStart = calendar.startOfDay(for: target)
        guard let targetEnd = calendar.date(byAdding: .day, value: 1, to: targetStart) else { return }

        for show in shows where show.changeStatus == .scheduled {
            if Task.isCancelled { return }
            let effectiveDate = show.effectiveDate
            guard effectiveDate >= targetStart, effectiveDate < targetEnd else { continue }

            let place = [show.venueAddress, show.city].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")

            let flightKey = Self.flightKey(showID: show.id, day: targetStart, calendar: calendar)
            guard !inFlightKeys.contains(flightKey) else { continue }
            if deduper.hasPostedToday(showID: show.id, day: targetStart, calendar: calendar) {
                continue
            }
            inFlightKeys.insert(flightKey)
            defer { inFlightKeys.remove(flightKey) }

            let decision = await fetchAndDecide(show: show, showName: show.name, place: place, targetDate: targetStart)
            if Task.isCancelled { return }
            guard let decision, decision.isWeatherAlert else {
                deduper.markPostedToday(showID: show.id, day: targetStart, calendar: calendar)
                continue
            }
            let posted = await replaceOneDayBefore(for: show, with: decision, now: now)
            if posted {
                deduper.markPostedToday(showID: show.id, day: targetStart, calendar: calendar)
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

    /// 用天气文案替换已排好的 `.oneDayBefore` 日历通知；标识符不变，20:00 触发不变。
    @discardableResult
    private func replaceOneDayBefore(
        for show: Show,
        with decision: WeatherReminderPolicy.Decision,
        now: Date
    ) async -> Bool {
        guard let pending = notificationPlanner.futureRequests(for: show, now: now)
            .first(where: { $0.milestone == .oneDayBefore }) else {
            return false
        }
        let (title, body) = WeatherReminderPolicy.copy(for: decision)
        let updated = ScheduledShowNotification(
            showID: pending.showID,
            milestone: pending.milestone,
            fireDate: pending.fireDate,
            title: title,
            body: body,
            isBackfill: pending.isBackfill
        )
        do {
            try await notifications.add(updated.makeNotificationRequest())
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
                    bySettingHour: reminderHour,
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
