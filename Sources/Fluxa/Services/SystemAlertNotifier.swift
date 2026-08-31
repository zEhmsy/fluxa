import FluxaCore
import UserNotifications

// MARK: - SystemAlertNotifier

final class SystemAlertNotifier: AlertNotifying, Sendable {
    func notify(metricID: SystemMetricID, value: Double, limit: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(metricID.title) alert"
        content.body = "\(metricID.title) is at \(SystemMetric(id: metricID, value: value).displayText)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fluxa.alert.\(metricID.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
