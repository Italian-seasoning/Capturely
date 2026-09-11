import Foundation
import UserNotifications

struct NotificationService: Sendable {
    func requestAuthorization() async throws {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func notifyRecordingStarted(gameName: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Recording \(gameName)"
        content.body = "Capturely replay buffer is active."
        content.sound = nil
        let request = UNNotificationRequest(identifier: "capturely.recording.\(gameName)", content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }

    func notifyClipSaved(gameName: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Clip saved"
        content.body = "\(gameName) clip is ready in your library."
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}
