import SwiftUI
import AppKit
import Observation

@MainActor @Observable
final class ThemePreferences {
    static let shared = ThemePreferences()
    var rgb: Int = UserDefaults.standard.object(forKey: "themeAccentRGB") as? Int ?? 0xFF995C {
        didSet { UserDefaults.standard.set(rgb, forKey: "themeAccentRGB") }
    }
    var color: Color {
        get { Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255) }
        set {
            guard let color = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            rgb = (Int((color.redComponent * 255).rounded()) << 16)
                | (Int((color.greenComponent * 255).rounded()) << 8)
                | Int((color.blueComponent * 255).rounded())
        }
    }
}

enum CyberTheme {
    static let void = Color(red: 0.055, green: 0.058, blue: 0.055)
    static let panel = Color(red: 0.09, green: 0.095, blue: 0.09)
    static let panelRaised = Color(red: 0.13, green: 0.14, blue: 0.12)
    @MainActor static var red: Color { ThemePreferences.shared.color }
    @MainActor static var deepRed: Color { red.opacity(0.3) }
    static let text = Color(red: 0.95, green: 0.95, blue: 0.88)
    static let muted = Color(red: 0.66, green: 0.69, blue: 0.61)
    static let dim = Color(red: 0.41, green: 0.44, blue: 0.38)
    static let coral = Color(red: 1.0, green: 0.40, blue: 0.31)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.18)
    static let success = Color(red: 0.31, green: 0.9, blue: 0.48)
    static let cyan = Color(red: 0.70, green: 0.76, blue: 0.57)
    static let shadow = Color(red: 0.0, green: 0.0, blue: 0.0)
}

struct CutCornerRectangle: Shape {
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let cut = min(cut, min(rect.width, rect.height) / 3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}

struct CyberPanel<Content: View>: View {
    var content: Content
    var padding: CGFloat
    var cut: CGFloat
    var isHot: Bool

    init(padding: CGFloat = 14, cut: CGFloat = 10, isHot: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
        self.cut = cut
        self.isHot = isHot
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                CutCornerRectangle(cut: cut)
                    .fill(
                        LinearGradient(
                            colors: [
                                isHot ? CyberTheme.panelRaised : CyberTheme.panel,
                                CyberTheme.panel,
                                CyberTheme.cyan.opacity(isHot ? 0.055 : 0.025)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        CutCornerRectangle(cut: cut)
                            .stroke((isHot ? CyberTheme.red : CyberTheme.text).opacity(isHot ? 0.38 : 0.10), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(CyberTheme.red.opacity(isHot ? 0.90 : 0.48))
                            .frame(width: 34, height: 2)
                            .padding(.leading, cut + 2)
                    }
            )
    }
}

struct CyberScanlines: View {
    nonisolated static func rowCount(for height: CGFloat) -> Int {
        max(Int(height / 5), 1)
    }

    var body: some View {
        Canvas { context, size in
            for row in 0..<Self.rowCount(for: size.height) {
                context.fill(
                    Path(CGRect(x: 0, y: CGFloat(row * 5), width: size.width, height: 1)),
                    with: .color(CyberTheme.red.opacity(0.18))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct CyberButtonStyle: ButtonStyle {
    var tone: Tone = .secondary
    var isEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    enum Tone {
        case primary
        case secondary
        case danger
        case ghost
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.heavy))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(
                CutCornerRectangle(cut: 6)
                    .fill(fill(isPressed: configuration.isPressed))
                    .overlay(
                        CutCornerRectangle(cut: 6)
                            .stroke(stroke, lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? 1 : 0.45)
            .shadow(color: CyberTheme.red.opacity(isHovered && isEnabled ? 0.23 : 0), radius: 9)
            .offset(y: configuration.isPressed ? 1 : (isHovered && !reduceMotion ? -1 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .contentShape(CutCornerRectangle(cut: 6))
    }

    private var foreground: Color {
        tone == .primary ? CyberTheme.void : (tone == .ghost ? CyberTheme.muted : CyberTheme.text)
    }

    private var stroke: Color {
        switch tone {
        case .danger:
            return CyberTheme.coral.opacity(0.7)
        case .primary:
            return CyberTheme.red.opacity(0.85)
        case .secondary:
            return CyberTheme.deepRed.opacity(0.82)
        case .ghost:
            return CyberTheme.dim.opacity(0.90)
        }
    }

    private func fill(isPressed: Bool) -> Color {
        let pressBoost = isPressed ? 0.08 : 0
        switch tone {
        case .primary:
            return CyberTheme.red.opacity(0.92 + pressBoost)
        case .danger:
            return CyberTheme.coral.opacity(0.14 + pressBoost)
        case .secondary:
            return CyberTheme.deepRed.opacity(0.34 + pressBoost)
        case .ghost:
            return CyberTheme.void.opacity(0.64 + pressBoost)
        }
    }
}

struct CyberSectionTitle: View {
    var title: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(CyberTheme.red)
                .frame(width: 3, height: 14)
            Text(title.uppercased())
                .font(.caption.weight(.heavy).monospaced())
                .tracking(1.1)
                .foregroundStyle(CyberTheme.text)
            if let detail {
                Text(detail.uppercased())
                    .font(.caption2.weight(.semibold).monospaced())
                    .tracking(0.8)
                    .foregroundStyle(CyberTheme.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ConsoleCard<Content: View>: View {
    var content: Content
    var padding: CGFloat

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        CyberPanel(padding: padding, cut: 10) {
            content
        }
    }
}

struct QuickSettingTile: View {
    var label: String
    var value: String
    var systemImage: String
    var meterFraction: Double? = nil
    var meterStyle: MeterBar.Style = .neutral
    var audioLevels: [Double] = []
    var reduceMotion: Bool = false
    var tint: Color = .white.opacity(0.74)

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)

                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)

            if hasMeter {
                Group {
                    if !audioLevels.isEmpty {
                        AudioLevelBars(levels: audioLevels, isActive: true, reduceMotion: reduceMotion, height: 12)
                    } else if let meterFraction {
                        MeterBar(fraction: meterFraction, tint: tint, style: meterStyle)
                    }
                }
                .frame(height: 14, alignment: .center)
                .padding(.top, 1)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78, alignment: .leading)
        .background(
            CutCornerRectangle(cut: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            isHovering ? CyberTheme.panelRaised : CyberTheme.panel,
                            tint.opacity(isHovering ? 0.12 : 0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    CutCornerRectangle(cut: 8)
                        .stroke((isHovering ? tint : CyberTheme.deepRed).opacity(isHovering ? 0.72 : 0.46), lineWidth: 1)
                )
        )
        .background(
            CutCornerRectangle(cut: 8)
                .fill(CyberTheme.deepRed.opacity(0.18))
                .offset(x: 4, y: 4)
        )
        .shadow(color: CyberTheme.shadow.opacity(0.42), radius: 8, x: 0, y: 5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var hasMeter: Bool {
        meterFraction != nil || !audioLevels.isEmpty
    }
}

struct MeterBar: View {
    enum Style: Equatable, Sendable {
        case neutral
        case qualityRamp
    }

    var fraction: Double
    var tint: Color
    var style: Style = .neutral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let clampedFraction = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(CyberTheme.dim.opacity(0.52))
                fillShape
                    .frame(width: max(4, proxy.size.width * clampedFraction))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18, extraBounce: 0), value: fraction)
    }

    @ViewBuilder
    private var fillShape: some View {
        switch style {
        case .neutral:
            Rectangle()
                .fill(tint.opacity(0.8))
        case .qualityRamp:
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: CyberTheme.deepRed, location: 0.0),
                            .init(color: CyberTheme.red, location: 0.62),
                            .init(color: CyberTheme.warning, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}

struct AudioLevelBars: View {
    var levels: [Double]
    var isActive: Bool
    var reduceMotion: Bool
    var height: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(displayLevels.indices, id: \.self) { index in
                let level = displayLevels[index]
                Rectangle()
                    .fill(barColor(for: index, level: level))
                    .frame(width: 3, height: max(3, height * CGFloat(level)))
            }
        }
        .frame(height: height, alignment: .center)
        .opacity(isActive ? 0.96 : 0.46)
        .animation(reduceMotion ? nil : .smooth(duration: 0.20, extraBounce: 0), value: displayLevels)
        .accessibilityHidden(true)
    }

    private var displayLevels: [Double] {
        let clamped = levels.suffix(24).map { min(max($0, 0), 1) }
        guard !clamped.isEmpty else {
            return Array(repeating: 0.12, count: 24)
        }
        if clamped.count >= 24 {
            return clamped
        }
        return Array(repeating: 0.10, count: 24 - clamped.count) + clamped
    }

    private func barColor(for index: Int, level: Double) -> Color {
        guard isActive else { return CyberTheme.dim.opacity(0.70) }
        if level > 0.82 {
            return CyberTheme.red.opacity(0.82)
        }
        if level > 0.62 {
            return CyberTheme.warning.opacity(0.72)
        }
        if level > 0.32 {
            return CyberTheme.text.opacity(0.72)
        }
        return CyberTheme.deepRed.opacity(0.78)
    }
}
