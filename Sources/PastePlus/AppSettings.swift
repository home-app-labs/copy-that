import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let limitChoices = [200, 500, 1000, 2000]

    /// How long history is kept, in days; 0 keeps it until the size limit pushes it out.
    static let retentionChoices: [(days: Int, title: String)] = [
        (0, "Forever"), (1, "1 Day"), (7, "1 Week"), (30, "1 Month"), (90, "3 Months"), (365, "1 Year"),
    ]

    private let defaults = UserDefaults.standard

    /// While paused, nothing that is copied gets recorded.
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: "paused") } }
    @Published var historyLimit: Int {
        didSet {
            defaults.set(historyLimit, forKey: "historyLimit")
            HistoryStore.shared.limit = historyLimit
        }
    }

    @Published var retentionDays: Int {
        didSet {
            defaults.set(retentionDays, forKey: "retentionDays")
            applyRetention()
        }
    }

    /// Removes history older than the chosen period. Called at launch, hourly and when the setting changes.
    func applyRetention(now: Date = Date()) {
        guard retentionDays > 0 else { return }
        HistoryStore.shared.removeHistory(olderThan: now.addingTimeInterval(-Double(retentionDays) * 86_400))
    }

    private init() {
        paused = defaults.bool(forKey: "paused")
        let saved = defaults.integer(forKey: "historyLimit")
        historyLimit = saved > 0 ? saved : 500
        retentionDays = defaults.integer(forKey: "retentionDays")
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Copy That: launch at login failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
