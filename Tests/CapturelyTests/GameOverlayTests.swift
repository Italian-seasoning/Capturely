import Foundation
import Testing
@testable import Capturely

@MainActor
@Test func overlayReplayDurationsRespectConfiguredBuffer() {
    #expect(GameOverlayView.replayDurations(limit: 10) == [10])
    #expect(GameOverlayView.replayDurations(limit: 30) == [15, 30])
    #expect(GameOverlayView.replayDurations(limit: 90) == [15, 30, 60, 90])
    #expect(GameOverlayView.replayDurations(limit: 0).isEmpty)
}

@MainActor @Test func overlayStaysFlushToTheSelectedScreenEdge() {
    let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let visible = CGRect(x: -1850, y: 30, width: 1850, height: 1025)
    let origin = GameOverlayController.dockedOrigin(screenFrame: screen, visibleFrame: visible, panelSize: CGSize(width: 244, height: 252))
    #expect(origin.x == -1920)
    #expect(origin.y == 803)
}
