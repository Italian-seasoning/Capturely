import AVFoundation
import ScreenCaptureKit
import Testing
@testable import Capturely

@Test func replaySnapshotSurvivesRetentionAndOutOfOrderCompletion() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let writer = ReplaySegmentWriter(directory: root, maximumDurationSeconds: 4)
    for index in [1, 0] {
        let url = root.appendingPathComponent("\(index).mov")
        try Data([UInt8(index)]).write(to: url)
        writer.registerCompletedSegment(url: url, startedAt: Date(timeIntervalSince1970: Double(index)), durationSeconds: 2)
    }
    let snapshot = try writer.snapshotSegments(forReplayDuration: 4, to: root.appendingPathComponent("export"))
    #expect(snapshot.map(\.startedAt) == [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1)])
    let newest = root.appendingPathComponent("new.mov")
    try Data([2]).write(to: newest)
    writer.registerCompletedSegment(url: newest, startedAt: Date(timeIntervalSince1970: 2), durationSeconds: 4)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("0.mov").path))
    #expect(try snapshot.map { try Data(contentsOf: $0.url) } == [Data([0]), Data([1])])
}

@Test func gamingPresetAndIndependentAudioGains() {
    var settings = AppSettings.defaults
    settings.recordsMicrophone = true
    settings.systemAudioMix = 0.6
    settings.microphoneMix = 1.2
    let preset = CapturePreset.balanced.applying(settings: settings)
    #expect(preset.maximumFramesPerSecond == 60)
    #expect(preset.maximumHeight == 1080)
    #expect(preset.audioGains == [0.6, 1.2])
    let segment = ReplaySegment(url: URL(fileURLWithPath: "/unused"), startedAt: Date(), durationSeconds: 2, audioGains: preset.audioGains!)
    #expect(ReplayComposer.needsAudioMix(segments: [segment]))
    #expect(!ReplayComposer.canCopySingleSegmentWithoutExport(segments: [segment], targetDurationSeconds: nil, audioGain: 1))
    let size = CaptureCoordinator.cappedCaptureSize(width: 1919, height: 1079, maximumHeight: 1080)
    #expect(size.width % 2 == 0 && size.height % 2 == 0)
}

// Exercises real hardware encoding, segment rotation, independent audio tracks,
// export, and video decoding without requiring Screen Recording permission.
@Test func hardwareReplayRecordsBothAudioSourcesAndExportsPlayableVideo() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = ReplaySegmentWriter(directory: root, maximumDurationSeconds: 10, segmentDurationSeconds: 1)
    var preset = CapturePreset.balanced
    preset.recordsMicrophone = true
    preset.audioGains = [0.7, 0.8]
    try writer.startRecording(preset: preset)
    for frame in 0..<150 {
        let time = CMTime(value: Int64(frame), timescale: 60)
        writer.append(sampleBuffer: try videoSample(at: time, frame: frame), type: .screen)
        writer.append(sampleBuffer: try audioSample(at: time, frequency: 440), type: .audio)
        writer.append(sampleBuffer: try audioSample(at: time, frequency: 880), type: .microphone)
        try await Task.sleep(for: .milliseconds(17))
    }
    await writer.stopRecording()
    let segments = writer.recentSegments(forReplayDuration: 10)
    #expect(segments.count >= 2)
    #expect(writer.healthMetrics.performance.videoSamplesAppended >= 140)
    for segment in segments {
        let tracks = try await AVURLAsset(url: segment.url).loadTracks(withMediaType: .audio)
        #expect(tracks.count == 2)
    }
    let output = root.appendingPathComponent("mixed.mov")
    let compositionResult = try await ReplayComposer().compose(segments: segments, outputURL: output, targetDurationSeconds: 2, audioGain: 1)
    if ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
        #expect(compositionResult.strategy == .ffmpegAudioOnly)
    }
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration)
    #expect(duration.seconds > 1.5 && duration.seconds < 2.5)
    #expect(try await asset.loadTracks(withMediaType: .audio).count >= 1)
    let image = try await AVAssetImageGenerator(asset: asset).image(at: CMTime(seconds: 1, preferredTimescale: 600))
    #expect(image.image.width == 320)
    let original = root.appendingPathComponent("editable.mov")
    _ = try await ReplayComposer(preservesAudioTracks: true).compose(segments: segments, outputURL: original, targetDurationSeconds: 2)
    #expect(try await AVURLAsset(url: original).loadTracks(withMediaType: .audio).count == 2)
    let edited = root.appendingPathComponent("edited.mov")
    try await ClipEditor.export(source: original, output: edited, start: 0.25, end: 1.25, gains: [0, 1])
    let editedAsset = AVURLAsset(url: edited)
    #expect(abs(try await editedAsset.load(.duration).seconds - 1) < 0.1)
    #expect(try await AVAssetImageGenerator(asset: editedAsset).image(at: CMTime(seconds: 0.4, preferredTimescale: 600)).image.width == 320)
    let energy = try await toneEnergy(asset: editedAsset)
    #expect(energy.microphone > 0.001)
    #expect(energy.game < energy.microphone * 0.25)
}

private func toneEnergy(asset: AVAsset) async throws -> (game: Double, microphone: Double) {
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32])
    reader.add(output)
    guard reader.startReading() else { throw TestMediaError.creation }
    var values: [Float] = []
    while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
        let length = CMBlockBufferGetDataLength(block)
        var data = [Float](repeating: 0, count: length / 4)
        _ = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        values += data
    }
    guard reader.status == .completed, !values.isEmpty else { throw TestMediaError.creation }
    func magnitude(_ frequency: Double) -> Double {
        var real = 0.0, imaginary = 0.0
        for (index, sample) in values.enumerated() {
            let phase = Double(index) / 48000 * frequency * 2 * Double.pi
            real += Double(sample) * cos(phase)
            imaginary += Double(sample) * sin(phase)
        }
        return hypot(real, imaginary) / Double(values.count)
    }
    return (magnitude(440), magnitude(880))
}

private func videoSample(at time: CMTime, frame: Int) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer else { throw TestMediaError.creation }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    memset(CVPixelBufferGetBaseAddress(pixelBuffer), Int32(frame % 255), CVPixelBufferGetDataSize(pixelBuffer))
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    let result = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
    guard result == noErr, let sample else { throw TestMediaError.creation }
    return sample
}

private func audioSample(at time: CMTime, frequency: Double) throws -> CMSampleBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let samples = (0..<800).map { index in Float(sin((time.seconds + Double(index) / 48_000) * frequency * 2 * .pi) * 0.2) }
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 3200, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: 3200, flags: 0, blockBufferOut: &block) == noErr, let block else { throw TestMediaError.creation }
    _ = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: 3200) }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var size = 4
    var sample: CMSampleBuffer?
    let status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format.formatDescription, sampleCount: 800, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
    guard status == noErr, let sample else { throw TestMediaError.creation }
    return sample
}

private enum TestMediaError: Error { case creation }
