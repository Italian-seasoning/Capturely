import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import UserNotifications

struct PermissionSummary: Equatable, Sendable {
    var microphoneGranted: Bool
    var screenCaptureStatus: String
    var screenCaptureGranted: Bool
    var screenCaptureCanRequest: Bool
    var microphoneCanRequest: Bool
    var notificationsGranted: Bool
    var notificationsCanRequest: Bool

    init(
        microphoneGranted: Bool,
        screenCaptureStatus: String,
        screenCaptureGranted: Bool? = nil,
        screenCaptureCanRequest: Bool = true,
        microphoneCanRequest: Bool = true,
        notificationsGranted: Bool = false,
        notificationsCanRequest: Bool = true
    ) {
        self.microphoneGranted = microphoneGranted
        self.screenCaptureStatus = screenCaptureStatus
        self.screenCaptureGranted = screenCaptureGranted ?? Self.inferScreenCaptureGranted(from: screenCaptureStatus)
        self.screenCaptureCanRequest = screenCaptureCanRequest
        self.microphoneCanRequest = microphoneCanRequest
        self.notificationsGranted = notificationsGranted
        self.notificationsCanRequest = notificationsCanRequest
    }

    var needsScreenCapturePermission: Bool {
        !screenCaptureGranted && screenCaptureStatus.lowercased().contains("permission")
    }

    var screenCaptureActionTitle: String {
        if screenCaptureGranted {
            return "Ready"
        }
        return screenCaptureCanRequest ? "Request Access" : "Open System Settings"
    }

    var microphoneActionTitle: String {
        microphoneCanRequest ? "Enable" : "Open Settings"
    }

    var notificationsActionTitle: String {
        notificationsCanRequest ? "Enable" : "Open Settings"
    }

    private static func inferScreenCaptureGranted(from status: String) -> Bool {
        let normalized = status.lowercased()
        if normalized.contains("ready") || normalized.contains("granted") {
            return true
        }
        if normalized.contains("permission") || normalized.contains("denied") || normalized.contains("missing") {
            return false
        }
        return false
    }
}

@MainActor
final class PermissionService: ObservableObject {
    @Published private(set) var summary = PermissionSummary(microphoneGranted: false, screenCaptureStatus: "Not checked")

    func refresh() async {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        updateSummary(
            screenCaptureGranted: CGPreflightScreenCaptureAccess(),
            notificationsGranted: Self.notificationsAreGranted(notificationSettings.authorizationStatus),
            notificationsCanRequest: notificationSettings.authorizationStatus == .notDetermined
        )
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        summary = PermissionSummary(
            microphoneGranted: granted,
            screenCaptureStatus: summary.screenCaptureStatus,
            screenCaptureGranted: summary.screenCaptureGranted,
            screenCaptureCanRequest: summary.screenCaptureCanRequest,
            microphoneCanRequest: false,
            notificationsGranted: summary.notificationsGranted,
            notificationsCanRequest: summary.notificationsCanRequest
        )
    }

    func requestScreenCapture() async {
        let granted = CGRequestScreenCaptureAccess()
        updateSummary(screenCaptureGranted: granted, screenCaptureCanRequest: false)
    }

    func requestNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        updateSummary(
            screenCaptureGranted: summary.screenCaptureGranted,
            screenCaptureCanRequest: summary.screenCaptureCanRequest,
            notificationsGranted: granted,
            notificationsCanRequest: false
        )
    }

    private func updateSummary(
        screenCaptureGranted: Bool,
        screenCaptureCanRequest: Bool? = nil,
        notificationsGranted: Bool? = nil,
        notificationsCanRequest: Bool? = nil
    ) {
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        summary = PermissionSummary(
            microphoneGranted: microphoneStatus == .authorized,
            screenCaptureStatus: screenCaptureGranted ? "Ready" : "Screen Recording permission needed",
            screenCaptureGranted: screenCaptureGranted,
            screenCaptureCanRequest: screenCaptureCanRequest ?? summary.screenCaptureCanRequest,
            microphoneCanRequest: microphoneStatus == .notDetermined,
            notificationsGranted: notificationsGranted ?? summary.notificationsGranted,
            notificationsCanRequest: notificationsCanRequest ?? summary.notificationsCanRequest
        )
    }

    private static func notificationsAreGranted(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }
}
