import BackgroundTasks
import OSLog
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundTaskManager.shared.register()
        logger.info("Registered background tasks")
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundTaskManager.shared.scheduleAppRefresh(reason: "applicationDidEnterBackground")
        BackgroundTaskManager.shared.scheduleProcessing(reason: "applicationDidEnterBackground")
    }
}
