import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class ApplicationAudioCapture {
    var onDiagnosticEvent: (@Sendable (CaptureDiagnosticEvent) -> Void)?

    private struct ActiveStream {
        var stream: SCStream
        var output: ApplicationAudioStreamOutput
    }

    private let writer: ReplaySegmentWriter
    private let sampleQueue = DispatchQueue(label: "capturely.application-audio", qos: .utility)
    private var activeStreams: [ActiveStream] = []
    private var generation = 0

    init(writer: ReplaySegmentWriter) {
        self.writer = writer
    }

    func start(sources: [AudioSourceDescriptor], selectedDisplayID: UInt32?) async {
        await stop()
        guard !sources.isEmpty else { return }
        generation += 1
        let startedGeneration = generation

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard generation == startedGeneration else { return }
            guard let display = selectedDisplayID.flatMap({ id in content.displays.first { $0.displayID == id } }) ?? content.displays.first else {
                return
            }

            for source in sources.prefix(4) {
                guard let bundleIdentifier = source.bundleIdentifier,
                      let application = content.applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                    onDiagnosticEvent?(.init(kind: .isolatedAudioUnavailable, message: "Isolated audio unavailable: \(source.displayName) is not running"))
                    continue
                }

                do {
                    let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
                    let configuration = SCStreamConfiguration()
                    configuration.width = 2
                    configuration.height = 2
                    configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
                    configuration.queueDepth = 1
                    configuration.capturesAudio = true
                    configuration.excludesCurrentProcessAudio = true
                    configuration.sampleRate = 48_000
                    configuration.channelCount = 2

                    let output = ApplicationAudioStreamOutput(sourceID: source.id, writer: writer)
                    let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                    try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: sampleQueue)
                    try await stream.startCapture()
                    guard generation == startedGeneration else {
                        try? await stream.stopCapture()
                        return
                    }
                    activeStreams.append(ActiveStream(stream: stream, output: output))
                } catch {
                    onDiagnosticEvent?(.init(kind: .isolatedAudioUnavailable, message: "Isolated audio failed for \(source.displayName): \(error.localizedDescription)"))
                }
            }
        } catch {
            onDiagnosticEvent?(.init(kind: .isolatedAudioUnavailable, message: "Isolated audio discovery failed: \(error.localizedDescription)"))
        }
    }

    func stop() async {
        generation += 1
        let streams = activeStreams
        activeStreams = []
        for active in streams {
            try? await active.stream.stopCapture()
        }
    }
}

private final class ApplicationAudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let sourceID: String
    private let writer: ReplaySegmentWriter

    init(sourceID: String, writer: ReplaySegmentWriter) {
        self.sourceID = sourceID
        self.writer = writer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        writer.appendAudio(sampleBuffer: sampleBuffer, sourceID: sourceID)
    }
}
