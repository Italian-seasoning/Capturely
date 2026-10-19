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

    static func audioMix(tracks: [AVAssetTrack], gains: [Double], range: ClosedRange<Double>? = nil, fadeIn: Double = 0, fadeOut: Double = 0) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.enumerated().map { index, track in
            let parameter = AVMutableAudioMixInputParameters(track: track)
            let gain = Float(gains.indices.contains(index) && gains[index].isFinite ? min(1.5, max(0, gains[index])) : 1)
            parameter.setVolume(gain, at: .zero)
            if let range {
                let length = range.upperBound - range.lowerBound
                let fadeIn = min(max(fadeIn, 0), length / 2), fadeOut = min(max(fadeOut, 0), length / 2)
                if fadeIn > 0 {
                    parameter.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain, timeRange: timeRange(range.lowerBound, fadeIn))
                }
                if fadeOut > 0 {
                    parameter.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0, timeRange: timeRange(range.upperBound - fadeOut, fadeOut))
                }
            }
            return parameter
        }
        return mix
    }

    private static func timeRange(_ start: Double, _ duration: Double) -> CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    // Unchanged single-track audio copies samples instead of re-encoding: faster saves with no generation loss.
    static func exportPresetName(gains: [Double], fadeIn: Double, fadeOut: Double) -> String {
        gains.count <= 1 && gains.allSatisfy { abs($0 - 1) < 0.001 } && fadeIn <= 0 && fadeOut <= 0
            ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
    }

    static func effectiveGains(gains: [Double], muted: Set<Int>, soloed: Set<Int>) -> [Double] {
        gains.indices.map { index in
            guard !muted.contains(index), soloed.isEmpty || soloed.contains(index) else { return 0 }
            return gains[index]
        }
    }

    static func export(source: URL, output: URL, start: Double, end: Double, gains: [Double], fadeIn: Double = 0, fadeOut: Double = 0) async throws {
        try await Task.detached(priority: .utility) {
            let asset = try await composition(from: AVURLAsset(url: source))
            let duration = try await asset.load(.duration).seconds
            guard validRange(start: start, end: end, duration: duration) else { throw ClipEditorError.invalidRange }
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let presetName = exportPresetName(gains: Array(gains.prefix(tracks.count)), fadeIn: fadeIn, fadeOut: fadeOut)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: presetName) else {
                throw ReplayComposerError.cannotCreateExporter
            }
            exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
            if !tracks.isEmpty, presetName != AVAssetExportPresetPassthrough {
                exporter.audioMix = audioMix(tracks: tracks, gains: gains, range: start...end, fadeIn: fadeIn, fadeOut: fadeOut)
            }
            try await exporter.export(to: output, as: .mov)
            guard CaptureCoordinator.isValidClipOutput(output) else { throw CaptureCoordinatorError.invalidClipOutput }
        }.value
    }
}

struct ClipEditorView: View {
    var clip: Clip
    var comparisonClips: [Clip] = []
    var save: (Double, Double, [Double], Double, Double) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var duration = 0.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var gains: [Double] = []
    @State private var muted: Set<Int> = []
    @State private var soloed: Set<Int> = []
    @State private var fadeIn = 0.0
    @State private var fadeOut = 0.0
    @State private var tracks: [AVAssetTrack] = []
    @State private var busy = false
    @State private var error: String?
    @State private var telemetry: [TimedTelemetry] = []
    @State private var showsTelemetry = false
    @State private var playbackSeconds = 0.0
    @State private var timeObserver: Any?

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CUT & MIX").font(.title2.bold()).foregroundStyle(CyberTheme.red)
                Spacer()
                Button("Close") { dismiss() }.disabled(busy)
            }
            VideoPlayer(player: player).frame(height: 270)
                .overlay(alignment: .bottom) {
                    if showsTelemetry, let entry = telemetry.first(where: { playbackSeconds >= $0.seconds && playbackSeconds < $0.seconds + $0.duration }) {
                        Text(entry.reading.subtitle).font(.caption.monospaced()).multilineTextAlignment(.center)
                            .padding(8).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white).padding(.bottom, 42).allowsHitTesting(false)
                    }
                }
            if !telemetry.isEmpty {
                Toggle("Performance subtitles", isOn: $showsTelemetry)
                Text("Sampled FrameBar readings. Video stays clean; subtitles export as an optional SRT file.")
                    .font(.caption).foregroundStyle(CyberTheme.muted)
            }
            if !clip.bookmarks.isEmpty {
                HStack {
                    Text("Bookmarks").font(.callout.weight(.medium))
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(clip.bookmarks.filter { $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds < duration }) { bookmark in
                                Button(String(format: "%.1fs", bookmark.seconds)) { seek(bookmark.seconds) }
                                    .help("\(bookmark.label) at \(bookmark.seconds.formatted()) seconds")
                            }
                        }
                    }
                }
            }
            if !telemetry.isEmpty, duration > 0 {
                DisclosureGroup("Performance timeline & comparison") {
                    ClipPerformanceView(clip: clip, entries: telemetry, duration: duration,
                        playbackSeconds: playbackSeconds, comparisonClips: comparisonClips, seek: seek)
                        .padding(.top, 8)
                }
            }
            if duration > 0.1 {
                Text(String(format: "IN %.2fs   OUT %.2fs   •   %.2fs selected", start, end, end - start)).monospaced()
                TrimTimeline(start: $start, end: $end, duration: duration, playhead: playbackSeconds, seek: seek)
                    .onChange(of: start) { _, value in seek(value) }
                    .onChange(of: end) { _, value in seek(value) }
                HStack {
                    Button("Preview selection") {
                        seek(start)
                        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
                        player.play()
                    }.buttonStyle(CyberButtonStyle())
                    Spacer()
                    Text("I / O set in and out · Space play · ← → frame step").font(.caption).foregroundStyle(CyberTheme.muted)
                }
                ForEach(gains.indices, id: \.self) { index in
                    HStack {
                        Text(audioLabel(index)).frame(width: 120, alignment: .leading)
                        Button("M") { toggle(index, in: &muted) }
                            .buttonStyle(.borderedProminent)
                            .tint(muted.contains(index) ? CyberTheme.coral : CyberTheme.panelRaised)
                            .help("Mute \(audioLabel(index))")
                        Button("S") { toggle(index, in: &soloed) }
                            .buttonStyle(.borderedProminent)
                            .tint(soloed.contains(index) ? CyberTheme.red : CyberTheme.panelRaised)
                            .help("Solo \(audioLabel(index))")
                        Slider(value: $gains[index], in: 0...1.5)
                            .accessibilityLabel(audioLabel(index))
                        Text("\(Int(gains[index] * 100))%").monospacedDigit().frame(width: 42)
                    }
                }
                if !tracks.isEmpty {
                    HStack {
                        Picker("Fade in", selection: $fadeIn) { fadeOptions }.frame(width: 150)
                        Picker("Fade out", selection: $fadeOut) { fadeOptions }.frame(width: 150)
                    }
                }
                Text(clip.editableSourceURL == nil ? "Original audio is already mixed." : "Each captured app and microphone has its own mute, solo, and gain control.")
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
                        do { try await save(start, end, effectiveGains, fadeIn, fadeOut); dismiss() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }.buttonStyle(CyberButtonStyle(tone: .primary))
                    .disabled(busy || !ClipEditor.validRange(start: start, end: end, duration: duration))
            }
        }
        .padding(22)
        }
        .focusable().focusEffectDisabled()
        .onKeyPress(characters: ["i", "o", " "]) { press in
            switch press.characters {
            case "i": start = min(playbackSeconds, end - 0.1)
            case "o": end = max(playbackSeconds, start + 0.1)
            default: player.timeControlStatus == .playing ? player.pause() : player.play()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .frame(width: 640, height: 720).background(CyberTheme.void)
        .foregroundStyle(CyberTheme.text).preferredColorScheme(ThemePreferences.shared.isLight ? .light : .dark)
        .interactiveDismissDisabled(busy)
        .task {
            do {
                let asset = try await ClipEditor.composition(from: AVURLAsset(url: clip.editableSourceURL ?? clip.clipURL))
                try Task.checkCancellation()
                let loadedDuration = asset.duration.seconds
                guard loadedDuration.isFinite, loadedDuration > 0.1 else { throw ClipEditorError.invalidRange }
                tracks = asset.tracks.filter { $0.mediaType == .audio }
                gains = tracks.map { _ in 1 }
                duration = loadedDuration
                end = loadedDuration
                let item = AVPlayerItem(asset: asset)
                item.audioMix = ClipEditor.audioMix(tracks: tracks, gains: gains)
                player.replaceCurrentItem(with: item)
                if let url = clip.telemetryURL {
                    telemetry = try await ClipTelemetry.load(url)
                }
                try Task.checkCancellation()
                // The trim timeline needs the playhead even when there is no telemetry.
                timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main) { time in
                    Task { @MainActor in playbackSeconds = time.seconds }
                }
            } catch is CancellationError { /* Dismissed editors must not install new observers. */ }
            catch { self.error = error.localizedDescription }
        }
        .onChange(of: gains) { _, _ in updatePreviewMix() }
        .onChange(of: muted) { _, _ in updatePreviewMix() }
        .onChange(of: soloed) { _, _ in updatePreviewMix() }
        .onChange(of: fadeIn) { _, _ in updatePreviewMix() }
        .onChange(of: fadeOut) { _, _ in updatePreviewMix() }
        .onDisappear {
            if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
            player.pause(); player.replaceCurrentItem(with: nil)
        }
    }

    private func seek(_ seconds: Double) {
        player.pause()
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func step(_ frames: Int) -> KeyPress.Result {
        player.pause()
        player.currentItem?.step(byCount: frames)
        playbackSeconds = player.currentTime().seconds
        return .handled
    }

    @ViewBuilder private var fadeOptions: some View {
        Text("Off").tag(0.0)
        Text("0.5s").tag(0.5)
        Text("1s").tag(1.0)
        Text("2s").tag(2.0)
    }

    private func audioLabel(_ index: Int) -> String {
        clip.audioTracks.first(where: { $0.trackIndex == index })?.source.displayName ?? "Audio \(index + 1)"
    }

    private var effectiveGains: [Double] {
        ClipEditor.effectiveGains(gains: gains, muted: muted, soloed: soloed)
    }

    private func toggle(_ index: Int, in set: inout Set<Int>) {
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
    }

    private func updatePreviewMix() {
        player.currentItem?.audioMix = ClipEditor.audioMix(tracks: tracks, gains: effectiveGains, range: start...end, fadeIn: fadeIn, fadeOut: fadeOut)
    }
}

/// One bar with draggable in/out handles and the playhead; clicking the bar seeks.
struct TrimTimeline: View {
    @Binding var start: Double
    @Binding var end: Double
    var duration: Double
    var playhead: Double
    var seek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let x = { (seconds: Double) in CGFloat(seconds / duration) * width }
            let seconds = { (location: CGFloat) in min(max(Double(location / width) * duration, 0), duration) }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(CyberTheme.panelRaised)
                    .contentShape(Rectangle())
                    .onTapGesture { location in seek(seconds(location.x)) }
                RoundedRectangle(cornerRadius: 4).fill(CyberTheme.red.opacity(0.35))
                    .frame(width: max(0, x(end) - x(start))).offset(x: x(start)).allowsHitTesting(false)
                Rectangle().fill(CyberTheme.text).frame(width: 2).offset(x: x(min(max(playhead, 0), duration)) - 1).allowsHitTesting(false)
                handle(label: "Start", value: $start, range: 0...max(0, end - 0.1)).offset(x: x(start) - 6)
                    .gesture(DragGesture(coordinateSpace: .named("trim")).onChanged { start = min(seconds($0.location.x), end - 0.1) })
                handle(label: "End", value: $end, range: min(duration, start + 0.1)...duration).offset(x: x(end) - 6)
                    .gesture(DragGesture(coordinateSpace: .named("trim")).onChanged { end = max(seconds($0.location.x), start + 0.1) })
            }
            .coordinateSpace(name: "trim")
        }
        .frame(height: 34)
    }

    private func handle(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(CyberTheme.red).frame(width: 12)
            .help(label)
            .accessibilityRepresentation {
                Slider(value: value, in: range) { Text(label) }
            }
    }
}
