import AVKit
import SwiftUI

enum ClipEditorError: LocalizedError {
    case invalidRange, busy
    var errorDescription: String? {
        switch self {
        case .invalidRange: "Choose a valid start and end within the clip."
        case .busy: "A save or library update is running. Try again when it finishes."
        }
    }
}

struct ClipEditor {
    static func composition(from source: AVAsset) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let duration = try await source.load(.duration)
        for mediaType in [AVMediaType.video, .audio] {
            for track in try await source.loadTracks(withMediaType: mediaType) {
                guard let destination = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw ReplayComposerError.cannotCreateExporter
                }
                try destination.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
                destination.isEnabled = true
                if mediaType == .video { destination.preferredTransform = try await track.load(.preferredTransform) }
            }
        }
        return composition
    }

    static func validRange(start: Double, end: Double, duration: Double) -> Bool {
        start.isFinite && end.isFinite && duration.isFinite && start >= 0 && end <= duration + 0.01 && end - start >= 0.1
    }

    static func audioMix(tracks: [AVAssetTrack], gains: [Double]) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.enumerated().map { index, track in
            let parameter = AVMutableAudioMixInputParameters(track: track)
            let gain = gains.indices.contains(index) && gains[index].isFinite ? min(1.5, max(0, gains[index])) : 1
            parameter.setVolume(Float(gain), at: .zero)
            return parameter
        }
        return mix
    }

    static func export(source: URL, output: URL, start: Double, end: Double, gains: [Double]) async throws {
        try await Task.detached(priority: .utility) {
            let asset = try await composition(from: AVURLAsset(url: source))
            let duration = try await asset.load(.duration).seconds
            guard validRange(start: start, end: end, duration: duration) else { throw ClipEditorError.invalidRange }
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                throw ReplayComposerError.cannotCreateExporter
            }
            exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            if !tracks.isEmpty { exporter.audioMix = audioMix(tracks: tracks, gains: gains) }
            try await exporter.export(to: output, as: .mov)
            guard CaptureCoordinator.isValidClipOutput(output) else { throw CaptureCoordinatorError.invalidClipOutput }
        }.value
    }
}

struct ClipEditorView: View {
    var clip: Clip
    var save: (Double, Double, [Double]) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var duration = 0.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var gains: [Double] = []
    @State private var tracks: [AVAssetTrack] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CUT & MIX").font(.title2.bold()).foregroundStyle(CyberTheme.red)
                Spacer()
                Button("Close") { dismiss() }.disabled(busy)
            }
            VideoPlayer(player: player).frame(height: 270)
            if duration > 0.1 {
                Text(String(format: "IN %.1fs   OUT %.1fs   •   %.1fs selected", start, end, end - start)).monospaced()
                Slider(value: $start, in: 0...max(0.01, end - 0.1)) { Text("Start") }
                    .onChange(of: start) { _, value in seek(value) }
                Slider(value: $end, in: min(duration - 0.01, start + 0.1)...duration) { Text("End") }
                    .onChange(of: end) { _, value in seek(value) }
                Button("Preview selection") {
                    seek(start)
                    player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
                    player.play()
                }.buttonStyle(CyberButtonStyle())
                ForEach(gains.indices, id: \.self) { index in
                    HStack {
                        Text(audioLabel(index)).frame(width: 100, alignment: .leading)
                        Slider(value: $gains[index], in: 0...1.5)
                            .accessibilityLabel(audioLabel(index))
                        Text("\(Int(gains[index] * 100))%").monospacedDigit().frame(width: 42)
                    }
                }
                Text(clip.editableSourceURL == nil ? "Original audio is already mixed. New dual-source recordings can keep game and mic separate." : "Game and microphone are separate. Adjust either track before saving.")
                    .font(.caption).foregroundStyle(CyberTheme.muted)
            }
            if let error { Text(error).foregroundStyle(CyberTheme.coral).font(.caption).textSelection(.enabled) }
            HStack {
                Text("Saves a new clip. Your original stays intact.").font(.caption).foregroundStyle(CyberTheme.muted)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(busy ? "Saving…" : "Save edited copy") {
                    busy = true
                    player.pause()
                    Task {
                        do { try await save(start, end, gains); dismiss() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }.buttonStyle(CyberButtonStyle(tone: .primary))
                    .disabled(busy || !ClipEditor.validRange(start: start, end: end, duration: duration))
            }
        }
        .padding(22).frame(width: 640).background(CyberTheme.void)
        .foregroundStyle(CyberTheme.text).preferredColorScheme(.dark)
        .interactiveDismissDisabled(busy)
        .task {
            do {
                let asset = try await ClipEditor.composition(from: AVURLAsset(url: clip.editableSourceURL ?? clip.clipURL))
                let loadedDuration = asset.duration.seconds
                guard loadedDuration.isFinite, loadedDuration > 0.1 else { throw ClipEditorError.invalidRange }
                tracks = asset.tracks.filter { $0.mediaType == .audio }
                gains = tracks.map { _ in 1 }
                duration = loadedDuration
                end = loadedDuration
                let item = AVPlayerItem(asset: asset)
                item.audioMix = ClipEditor.audioMix(tracks: tracks, gains: gains)
                player.replaceCurrentItem(with: item)
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: gains) { _, _ in player.currentItem?.audioMix = ClipEditor.audioMix(tracks: tracks, gains: gains) }
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
    }

    private func seek(_ seconds: Double) {
        player.pause()
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func audioLabel(_ index: Int) -> String {
        clip.editableSourceURL != nil && tracks.count == 2 ? (index == 0 ? "Game audio" : "Microphone") : "Audio \(index + 1)"
    }
}
