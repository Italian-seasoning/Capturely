import Combine
import Foundation
import Testing
@testable import Capturely

private final class PresentationTestFileManager: FileManager, @unchecked Sendable {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let lock = NSLock()
    private var moviesLookups = 0
    var moviesLookupCount: Int { lock.withLock { moviesLookups } }

    override func url(for directory: SearchPathDirectory, in domain: SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        if directory == .moviesDirectory { lock.withLock { moviesLookups += 1 } }
        let result = root.appendingPathComponent(directory == .moviesDirectory ? "Movies" : "Support")
        if shouldCreate { try createDirectory(at: result, withIntermediateDirectories: true) }
        return result
    }
}

@MainActor
@Suite struct CaptureBackendPresentationTests {
    @Test func hiddenAudioCallbacksAvoidPresentationSnapshotsAndPublications() {
        let files = PresentationTestFileManager()
        defer { try? FileManager.default.removeItem(at: files.root) }
        let backend = CaptureBackend(appPaths: AppPaths(fileManager: files))
        backend.setAudioPresentationActive(false)
        var updates = 0
        let subscription = backend.$health.dropFirst().sink { _ in updates += 1 }
        defer { subscription.cancel() }

        for _ in 0..<5 { backend.audioMonitorDidUpdate() }

        #expect(updates == 0)
        #expect(files.moviesLookupCount == 0)
        #expect(backend.health == .empty)
    }

    @Test func visibleAudioCallbacksContinueUpdatingHealth() {
        let files = PresentationTestFileManager()
        defer { try? FileManager.default.removeItem(at: files.root) }
        let backend = CaptureBackend(appPaths: AppPaths(fileManager: files))
        var updates = 0
        let subscription = backend.$health.dropFirst().sink { _ in updates += 1 }
        defer { subscription.cancel() }

        backend.audioMonitorDidUpdate()

        #expect(updates == 1)
        #expect(files.moviesLookupCount == 1)
        #expect(backend.health.outputFolder == files.root.appendingPathComponent("Movies/Capturely/Clips", isDirectory: true))
    }

    @Test func restoringPresentationRefreshesImmediatelyAndCoalescesRepeatedVisibility() {
        let files = PresentationTestFileManager()
        defer { try? FileManager.default.removeItem(at: files.root) }
        let backend = CaptureBackend(appPaths: AppPaths(fileManager: files))
        backend.setAudioPresentationActive(false)
        backend.audioMonitorDidUpdate()
        #expect(backend.health == .empty)

        backend.setAudioPresentationActive(true)

        #expect(backend.health.outputFolder != nil)
        #expect(files.moviesLookupCount == 1)
        backend.setAudioPresentationActive(true)
        #expect(files.moviesLookupCount == 1)
    }

    @Test func hiddenMicrophoneCallbacksDoNotPublishVisualsWithReactionFeatureOnOrOff() async {
        for reactionsEnabled in [false, true] {
            let files = PresentationTestFileManager()
            defer { try? FileManager.default.removeItem(at: files.root) }
            let backend = CaptureBackend(appPaths: AppPaths(fileManager: files))
            backend.setReactionClippingEnabled(reactionsEnabled)
            await backend.persistSettingsImmediatelyForTesting()
            backend.setAudioPresentationActive(false)
            var healthUpdates = 0
            var levelUpdates = 0
            let health = backend.$health.dropFirst().sink { _ in healthUpdates += 1 }
            let level = backend.$microphoneLevel.dropFirst().sink { _ in levelUpdates += 1 }
            defer { health.cancel(); level.cancel() }
            let lookupsBeforeCallback = files.moviesLookupCount

            backend.microphoneLevelDidUpdate()

            #expect(healthUpdates == 0)
            #expect(levelUpdates == 0)
            #expect(files.moviesLookupCount == lookupsBeforeCallback)
        }
    }
}
