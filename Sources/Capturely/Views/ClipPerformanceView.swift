import AppKit
import SwiftUI
import Charts

struct ClipPerformanceView: View {
    let clip: Clip
    let entries: [TimedTelemetry]
    let duration: Double
    let playbackSeconds: Double
    let comparisonClips: [Clip]
    var seek: (Double) -> Void
    @State private var metric: TelemetryMetric = .fps
    @State private var comparisonID: UUID?
    @State private var comparisonEntries: [TimedTelemetry] = []
    @State private var comparisonError: String?
    @State private var loadingComparison = false
    @State private var points: [TelemetryPoint] = []
    @State private var summary: TelemetrySummary?
    @State private var comparisonSummary: TelemetrySummary?
    @State private var comparisonRequest = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Reading", selection: $metric) {
                ForEach(TelemetryMetric.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if points.isEmpty {
                Text("No \(metric.rawValue.lowercased()) readings in this clip.").font(.callout).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Clip seconds", point.seconds), y: .value(metric.unit, point.value),
                                 series: .value("Span", point.segment))
                            .foregroundStyle(CyberTheme.red).interpolationMethod(.stepStart)
                    }
                    RuleMark(x: .value("Playback", max(0, min(duration, playbackSeconds))))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                }
                .chartXScale(domain: 0...max(0.1, duration)).chartLegend(.hidden).frame(height: 110)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plot = proxy.plotFrame,
                                      let seconds: Double = proxy.value(atX: location.x - geometry[plot].origin.x),
                                      seconds >= 0, seconds <= duration else { return }
                                seek(seconds)
                            }
                    }
                }
                .accessibilityLabel("\(metric.rawValue) over clip time")
            }
            if let summary {
                HStack {
                    Text(String(format: "Mean %.1f %@ · range %.1f–%.1f · %.1fs covered", summary.average, metric.unit, summary.minimum, summary.maximum, summary.coveredSeconds))
                        .font(.caption).monospacedDigit()
                    Spacer(minLength: 8)
                    Button { copySummary(summary) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).help("Copy sampled performance summary")
                        .accessibilityLabel("Copy performance summary")
                }
            }
            Text("Sampled readings; gaps stay empty. Click the graph or use a bookmark to seek. These samples cannot produce frame-level 1% lows.")
                .font(.caption).foregroundStyle(CyberTheme.muted)
            let candidates = comparisonClips.filter { $0.id != clip.id && $0.telemetryURL != nil }
            if !candidates.isEmpty {
                Picker("Compare with", selection: $comparisonID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(candidates) { candidate in
                        Text("\(candidate.title ?? candidate.gameName) · \(candidate.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                            .tag(Optional(candidate.id))
                    }
                }
                if loadingComparison { ProgressView().controlSize(.small) }
                if candidates.contains(where: { $0.id == comparisonID }), !loadingComparison {
                    if let current = summary,
                       let previous = comparisonSummary {
                        Text(String(format: "Mean: this %.1f · comparison %.1f · difference %+.1f %@", current.average, previous.average, current.average - previous.average, metric.unit))
                            .font(.callout).monospacedDigit()
                        Text(String(format: "Coverage: this %.1fs · comparison %.1fs. Different scenes and capture lengths can affect the result.", current.coveredSeconds, previous.coveredSeconds))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if comparisonError == nil {
                        Text("The comparison has no matching readings.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let comparisonError { Text(comparisonError).font(.callout).foregroundStyle(CyberTheme.warning) }
            }
        }
        .task(id: metric) {
            points = ClipTelemetry.points(entries, metric: metric, duration: duration)
            summary = ClipTelemetry.summary(entries, metric: metric, duration: duration)
            if let reference = comparisonClips.first(where: { $0.id == comparisonID }) {
                comparisonSummary = ClipTelemetry.summary(comparisonEntries, metric: metric, duration: Double(reference.durationSeconds))
            }
        }
        .task(id: comparisonID) {
            let requestedID = comparisonID
            let request = UUID()
            comparisonRequest = request
            comparisonEntries = []; comparisonSummary = nil; comparisonError = nil
            loadingComparison = false
            guard let candidate = comparisonClips.first(where: { $0.id == requestedID }), let url = candidate.telemetryURL else { return }
            loadingComparison = true
            defer { if comparisonRequest == request { loadingComparison = false } }
            do {
                let loaded = try await ClipTelemetry.load(url)
                try Task.checkCancellation()
                guard comparisonRequest == request, comparisonID == requestedID else { return }
                comparisonEntries = loaded
                comparisonSummary = ClipTelemetry.summary(loaded, metric: metric, duration: Double(candidate.durationSeconds))
            } catch is CancellationError { }
            catch { if comparisonRequest == request { comparisonError = error.localizedDescription } }
        }
    }

    private func copySummary(_ summary: TelemetrySummary) {
        var text = "\(clip.title ?? clip.gameName) — \(metric.rawValue)\n"
        text += String(format: "Sampled mean %.1f %@; range %.1f–%.1f; %.1fs covered of %.1fs.\n",
            summary.average, metric.unit, summary.minimum, summary.maximum, summary.coveredSeconds, duration)
        if let reference = comparisonClips.first(where: { $0.id == comparisonID }), let previous = comparisonSummary {
            text += String(format: "Comparison (%@): mean %.1f %@; %.1fs covered; difference %+.1f %@.\n",
                reference.title ?? reference.gameName, previous.average, metric.unit,
                previous.coveredSeconds, summary.average - previous.average, metric.unit)
        }
        text += "Sampled readings, not per-frame timings. Different scenes and capture lengths affect comparisons."
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
