import Foundation
import BackgroundTasks
import SwiftData
import UserNotifications

/// 演出前一天天气提醒的调度器。
///
/// 三个触发入口：
/// - `registerTaskHandler(modelContainer:)`：冷启动时挂上 BGTaskScheduler handler
/// - `runOpenCheck(modelContext:)`：App 打开 / scenePhase=.active / 冷启动
/// - `scheduleNextBackgroundCheck(modelContext:)`：每次都滚到下一个"有演出的明天 20:00"
@MainActor
final class WeatherReminderScheduler {
    static let shared = WeatherReminderScheduler(
        provider: WeatherKitForecastProvider(),
        geocoding: CoreLocationGeocoding(),
        deduper: WeatherReminderDeduper(),
        calendar: .current,
        center: .current()
    )

    /// 单测 / 调试用：可以注入 fake provider、fake geocoding、fake deduper、fixed clock。
    init(
        provider: WeatherForecastProvider,
        geocoding: Geocoding,
        deduper: WeatherReminderDeduper,
        calendar: Calendar,
        center: UNUserNotificationCenter
    ) {
        self.provider = provider
        self.geocoding = geocoding
        self.deduper = deduper
        self.calendar = calendar
        self.center = center
        self.reminderHour = 20
    }

    private let provider: WeatherForecastProvider
    private let geocoding: Geocoding
    private let deduper: WeatherReminderDeduper
    private let calendar: Calendar
    private let center: UNUserNotificationCenter
    private let reminderHour: Int

    private static let backgroundTaskIdentifier = "com.doublewaterapps.beforeshow.weather.refresh"
    private weak var registeredContainer: ModelContainer?
    private var lastRegistrationToken: AnyObject?

    // MARK: - BG registration

    /// App 启动时调用一次，登记 BG handler。后续真正拿 SwiftData 在 handler 内开新 context。
    func registerTaskHandler(modelContainer: ModelContainer) {
        registeredContainer = modelContainer
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
        // BGTaskScheduler 把这个闭包派发到非主线程；UI 提交的事不归它管。
        // 用 nonisolated(unsafe) 让本地引用透传到内部 Task。Task 一次只写一次，
        // setTaskCompleted 的并发安全由 BGTaskScheduler 文档承诺。
        nonisolated(unsafe) let bgTask = task
        task.expirationHandler = {
            bgTask.setTaskCompleted(success: false)
        }
        // 把 work 和 task 解耦：先跑 work 拿到结果，再回到当前执行上下文写完成。
        // 避免把非 Sendable 的 `task` 闭包进 @MainActor Task。
        Task {
            let success = await self.runBackgroundWork(modelContainer: modelContainer)
            bgTask.setTaskCompleted(success: success)
        }
    }

    private nonisolated func runBackgroundWork(modelContainer: ModelContainer) async -> Bool {
        // ModelContext 非 Sendable：所有读写都在 @MainActor 里。
        // ModelContainer 是 Sendable，可以跨边界。
        return await runBackgroundWorkOnMain(modelContainer: modelContainer)
    }

    private func runBackgroundWorkOnMain(modelContainer: ModelContainer) async -> Bool {
        let context = ModelContext(modelContainer)
        await runOpenCheck(modelContext: context)
        scheduleNextBackgroundCheck(modelContext: context)
        return true
    }

    // MARK: - Open check (foreground fallback)

    /// App 打开时（cold start / active）扫一遍"明天有演出"的场次，逐个拉天气并按策略发通知。
    func runOpenCheck(modelContext: ModelContext) async {
        let shows = (try? modelContext.fetch(FetchDescriptor<Show>())) ?? []
        let now = Date()
        let target = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let targetStart = calendar.startOfDay(for: target)
        guard let targetEnd = calendar.date(byAdding: .day, value: 1, to: targetStart) else { return }

        for show in shows where show.changeStatus == .scheduled {
            let effectiveDate = show.effectiveDate
            guard effectiveDate >= targetStart, effectiveDate < targetEnd else { continue }

            let place = [show.venueAddress, show.city].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")

            if deduper.hasPostedToday(showID: show.id, day: targetStart, calendar: calendar) {
                continue
            }

            let decision = await fetchAndDecide(show: show, showName: show.name, place: place, targetDate: targetStart)
            guard let decision else { continue }
            await postNotification(for: decision, showID: show.id)
            deduper.markPostedToday(showID: show.id, day: targetStart, calendar: calendar)
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

    private func postNotification(for decision: WeatherReminderPolicy.Decision, showID: UUID) async {
        let (titleKey, body) = WeatherReminderPolicy.copy(for: decision)
        let content = UNMutableNotificationContent()
        content.title = titleKey
        content.body = body
        content.sound = .default
        content.userInfo = [
            "showID": showID.uuidString,
            "destination": "home",
            "source": "weatherReminder"
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "weatherReminder.\(showID.uuidString).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            // 通知权限被关 / 配额满：吞掉。打开 App 时仍可观察 decision。
        }
    }

    // MARK: - BG scheduling

    /// 滚到下一个"有演出的明天 20:00"，提交一条 BGAppRefreshTaskRequest。
    func scheduleNextBackgroundCheck(modelContext: ModelContext) {
        let shows = (try? modelContext.fetch(FetchDescriptor<Show>())) ?? []
        let now = Date()
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
            guard let fireToday = calendar.date(
                bySettingHour: reminderHour,
                minute: 0,
                second: 0,
                of: dayStart
            ) else { continue }
            // 我们只关心"演出前一天"的提醒，所以是 effective-1 那天 20:00。
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: dayStart),
                  let candidate = calendar.date(
                      bySettingHour: reminderHour,
                      minute: 0,
                      second: 0,
                      of: dayBefore
                  ) else { continue }
            // 跳过已经过去或今天的；保留还在未来的。
            guard candidate > now else { continue }
            if earliest == nil || candidate < (earliest ?? candidate) {
                earliest = candidate
            }
            _ = fireToday
        }
        return earliest
    }
}
