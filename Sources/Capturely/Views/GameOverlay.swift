import AppKit
import SwiftUI

@MainActor
final class GameOverlayController: ObservableObject {
    @Published private(set) var isVisible = false
    private var dismissTask: Task<Void, Never>?
    private var panel: GameOverlayPanel?
    private var savedPanel: GameOverlayPanel?
    private var savedDismissTask: Task<Void, Never>?

    func showSaved(clip: Clip) {
        savedDismissTask?.cancel()
        let toast = savedPanel ?? GameOverlayPanel()
        savedPanel = toast
        toast.title = "Capturely Replay Saved"
        toast.ignoresMouseEvents = true
        toast.setContentSize(NSSize(width: 300, height: 64))
        toast.contentView = NSHostingView(rootView:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last \(clip.durationSeconds)s saved").font(.headline)
                    Text("Replay is in your library").font(.caption)
                }
                Spacer()
            }.padding(14).frame(width: 300, height: 64)
                .foregroundStyle(CyberTheme.void)
                .background(CutCornerRectangle(cut: 8).fill(CyberTheme.red)))
        if let screen = panel?.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            toast.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - 324, y: screen.visibleFrame.maxY - 88 - (isVisible ? 144 : 0)))
        }
        toast.orderFrontRegardless()
        savedDismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.savedPanel?.orderOut(nil)
        }
    }

    func toggle(backend: CaptureBackend) {
        if isVisible {
            hide()
            return
        }
        if panel == nil {
            let panel = GameOverlayPanel()
            panel.setContentSize(NSSize(width: 208, height: 350))
            panel.isMovableByWindowBackground = false
            panel.hasShadow = false
            panel.contentView = NSHostingView(rootView: GameOverlayView(backend: backend, controller: self, dismiss: { [weak self] in self?.hide() }))
            self.panel = panel
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == backend.settings.selectedDisplayID
        } ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            panel.setFrameOrigin(CGPoint(x: screen.frame.minX, y: screen.frame.maxY - panel.frame.height))
        }
        // Never activate the app or make this panel key: the game keeps focus.
        dismissTask?.cancel()
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        isVisible = false
        panel?.ignoresMouseEvents = true
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            guard let self, !isVisible else { return }
            panel?.orderOut(nil)
        }
    }
}

@MainActor
final class GameOverlayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: -1000, y: -1000, width: 300, height: 132),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Capturely In-Game Overlay"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct GameOverlayView: View {
    @ObservedObject var backend: CaptureBackend
    @ObservedObject var controller: GameOverlayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle").foregroundStyle(CyberTheme.red)
                Text("capturely").font(.system(size: 15, weight: .black)).fontWidth(.condensed)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide overlay")
                    .help("Hide overlay · ⌥⌘O")
            }
            Text(backend.status.isRecording ? "● LIVE" : "○ STANDBY")
                .font(.caption.monospaced().bold())
                .foregroundStyle(backend.status.isRecording ? CyberTheme.coral : CyberTheme.muted)
            VStack(spacing: 10) {
                Button(action: backend.saveClipRequested) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Save replay")
                        Text(backend.settings.saveClipHotkey.compactDisplayValue).font(.caption.monospaced())
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(CyberButtonStyle(tone: .primary, isEnabled: backend.status.canSaveClip))
                .disabled(!backend.status.canSaveClip)
                Button {
                    if backend.status.isRecording { backend.stopCaptureRequested() }
                    else { backend.startCaptureRequested() }
                } label: {
                    Label(backend.status.isRecording ? "Stop capture" : "Start capture", systemImage: backend.status.isRecording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CyberButtonStyle(tone: backend.status.isRecording ? .danger : .secondary))
                .accessibilityLabel(backend.status.isRecording ? "Stop capture" : "Start capture")
            }
            HStack(spacing: 6) {
                ForEach([15, 30, 60], id: \.self) { seconds in
                    Button("\(seconds)s") { backend.saveReplay(seconds: seconds) }
                        .buttonStyle(.plain).foregroundStyle(CyberTheme.red)
                        .disabled(!backend.status.canSaveClip)
                        .help("Save up to the last \(seconds) seconds")
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(CyberTheme.muted)
            Text(backend.status.isRecording ? backend.status.bufferLengthDescription : "Not recording")
                .font(.caption.monospaced()).foregroundStyle(CyberTheme.muted)
            Text("⌥⌘O").font(.caption.monospaced()).foregroundStyle(CyberTheme.red)
            Spacer(minLength: 0)
        }
        .padding(20)
        .padding(.top, 12)
        .frame(width: 208, height: 350)
        .foregroundStyle(CyberTheme.text)
        .background(.black)
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 32))
        .overlay {
            UnevenRoundedRectangle(bottomTrailingRadius: 32)
                .strokeBorder(CyberTheme.red.opacity(0.65), lineWidth: 1)
                .opacity(controller.isVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.24).delay(controller.isVisible && !reduceMotion ? 0.22 : 0), value: controller.isVisible)
                .allowsHitTesting(false)
        }
        .mask {
            OverlayLiquidReveal(progress: controller.isVisible ? 1 : 0, reducedMotion: reduceMotion)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.22, 0.8, 0.2, 1, duration: 0.56), value: controller.isVisible)
        }
        .preferredColorScheme(.dark)
    }

    private var overlayHint: String {
        if case .saving = backend.recordingState { return "Saving…" }
        return "⌥⌘O to hide"
    }
}

private struct OverlayLiquidReveal: Shape {
    var progress: CGFloat
    var reducedMotion: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = min(max(progress, 0), 1)
        guard p > 0 else { return Path() }
        if reducedMotion { return Path(CGRect(x: 0, y: 0, width: rect.width, height: rect.height * p)) }
        // A curved leading edge pours down from the corner without distorting controls.
        let crest = sin(p * .pi) * 110
        let edge = p * (rect.height + 110)
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: edge - crest))
        path.addCurve(to: CGPoint(x: 0, y: edge),
                      control1: CGPoint(x: rect.width * 0.72, y: edge - crest * 1.4),
                      control2: CGPoint(x: rect.width * 0.3, y: edge + crest * 0.45))
        path.closeSubpath()
        return path
    }
}
