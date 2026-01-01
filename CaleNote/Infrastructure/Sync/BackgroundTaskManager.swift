import BackgroundTasks
import Network
import OSLog
import SwiftData

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private struct Identifiers {
        static let appRefresh = "com.calenote.sync.refresh"
        static let processing = "com.calenote.sync.processing"
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "BackgroundTasks")
    private let defaults = UserDefaults.standard
    private let networkMonitor = NetworkMonitor.shared

    private var syncService: CalendarSyncService?
    private var calendarListService: CalendarListService?
    private var searchIndexService: SearchIndexService?
    private var relatedIndexService: RelatedEntriesIndexService?
    private var modelContext: ModelContext?

    private init() {}

    func configure(
        syncService: CalendarSyncService,
        calendarListService: CalendarListService,
        searchIndexService: SearchIndexService,
        relatedIndexService: RelatedEntriesIndexService,
        modelContext: ModelContext
    ) {
        self.syncService = syncService
        self.calendarListService = calendarListService
        self.searchIndexService = searchIndexService
        self.relatedIndexService = relatedIndexService
        self.modelContext = modelContext
    }

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Identifiers.appRefresh, using: nil) { [weak self] task in
            self?.handleAppRefresh(task: task as? BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Identifiers.processing, using: nil) { [weak self] task in
            self?.handleProcessing(task: task as? BGProcessingTask)
        }
    }

    func scheduleAppRefresh(reason: String) {
        let request = BGAppRefreshTaskRequest(identifier: Identifiers.appRefresh)
        let interval = nextRefreshInterval()
        request.earliestBeginDate = Date().addingTimeInterval(interval)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled app refresh task (reason: \(reason, privacy: .private), interval: \(interval)s)")
        } catch {
            logger.warning("Failed to schedule app refresh task: \(error.localizedDescription)")
        }
    }

    func scheduleProcessing(reason: String) {
        guard shouldScheduleProcessing() else {
            logger.info("Skipped processing task scheduling (recently completed)")
            return
        }

        let request = BGProcessingTaskRequest(identifier: Identifiers.processing)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        let interval = nextProcessingInterval()
        request.earliestBeginDate = Date().addingTimeInterval(interval)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled processing task (reason: \(reason, privacy: .private), interval: \(interval)s)")
        } catch {
            logger.warning("Failed to schedule processing task: \(error.localizedDescription)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask?) {
        guard let task else { return }
        scheduleAppRefresh(reason: "reschedule")

        let syncTask = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performBackgroundSync()
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            let success = await syncTask.value
            self.recordRefreshResult(success)
            task.setTaskCompleted(success: success)
        }
    }

    private func handleProcessing(task: BGProcessingTask?) {
        guard let task else { return }
        scheduleProcessing(reason: "reschedule")

        let processingTask = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performBackgroundProcessing()
        }

        task.expirationHandler = {
            processingTask.cancel()
        }

        Task {
            let success = await processingTask.value
            self.recordProcessingResult(success)
            task.setTaskCompleted(success: success)
        }
    }

    @MainActor
    private func performBackgroundSync() async -> Bool {
        guard let syncService, let calendarListService else {
            logger.error("Background sync skipped: services not configured")
            return false
        }

        if syncService.isSyncing {
            logger.info("Background sync skipped: sync already in progress")
            return true
        }

        do {
            await calendarListService.syncCalendarList()
            try await syncService.performFullSync()
            logger.info("Background sync completed")
            return true
        } catch {
            logger.error("Background sync failed: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    private func performBackgroundProcessing() async -> Bool {
        guard let searchIndexService, let relatedIndexService, let modelContext else {
            logger.error("Background processing skipped: services not configured")
            return false
        }
        if let syncService {
            do {
                try syncService.cleanupExpiredTrashEntries()
            } catch {
                logger.error("Trash cleanup failed: \(error.localizedDescription)")
            }
        }
        searchIndexService.rebuildIndex(modelContext: modelContext)
        relatedIndexService.rebuildIndex(modelContext: modelContext)
        logger.info("Background processing completed")
        return true
    }

    private func nextRefreshInterval() -> TimeInterval {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let network = networkMonitor
        let lastFailed = defaults.bool(forKey: "background.refresh.failed")

        if network.isExpensive || network.isConstrained {
            let interval: TimeInterval = lowPower ? 90 * 60 : 60 * 60
            return lastFailed ? max(interval, 90 * 60) : interval
        }

        if !network.isSatisfied {
            return lastFailed ? TimeInterval(90 * 60) : TimeInterval(60 * 60)
        }

        let interval: TimeInterval = lowPower ? 60 * 60 : 15 * 60
        return lastFailed ? max(interval, 60 * 60) : interval
    }

    private func nextProcessingInterval() -> TimeInterval {
        12 * 60 * 60
    }

    private func shouldScheduleProcessing() -> Bool {
        guard let last = defaults.object(forKey: "background.processing.last") as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) > nextProcessingInterval()
    }

    private func recordRefreshResult(_ success: Bool) {
        defaults.set(Date(), forKey: "background.refresh.last")
        defaults.set(!success, forKey: "background.refresh.failed")
    }

    private func recordProcessingResult(_ success: Bool) {
        if success {
            defaults.set(Date(), forKey: "background.processing.last")
        }
    }
}

private final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.calenote.network.monitor")
    private(set) var currentPath: NWPath?

    var isSatisfied: Bool {
        currentPath?.status == .satisfied
    }

    var isExpensive: Bool {
        currentPath?.isExpensive ?? false
    }

    var isConstrained: Bool {
        currentPath?.isConstrained ?? false
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
        }
        monitor.start(queue: queue)
    }
}
