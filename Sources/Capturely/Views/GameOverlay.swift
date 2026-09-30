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
            panel.setContentSize(NSSize(width: 244, height: 252))
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
            panel.setFrameOrigin(Self.dockedOrigin(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, panelSize: panel.frame.size))
        }
        // Never activate the app or make this panel key: the game keeps focus.
        dismissTask?.cancel()
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        isVisible = true
    }

    static func dockedOrigin(screenFrame: CGRect, visibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        CGPoint(x: screenFrame.minX, y: visibleFrame.maxY - panelSize.height)
    }

    func hide() {
        isVisible = false
        panel?.ignoresMouseEvents = true
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(360)) } catch { return }
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

struct GameOverlayView: View {
    @ObservedObject var backend: CaptureBackend
    @ObservedObject var controller: GameOverlayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("capturely").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide overlay")
                    .help("Hide overlay · ⌥⌘O")
            }
            HStack {
                Text(backend.health.detectedAppName ?? "Replay buffer").lineLimit(1)
                Spacer()
                Text(isSaving ? "SAVING" : backend.status.isRecording ? "● LIVE" : "STANDBY")
                    .foregroundStyle(backend.status.isRecording ? CyberTheme.coral : CyberTheme.muted)
            }.font(.caption.weight(.medium))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(min(backend.settings.replayDurationSeconds, Int(max(0, backend.status.bufferDurationSeconds))))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("/ \(backend.settings.replayDurationSeconds)s buffered")
                    .font(.caption).foregroundStyle(CyberTheme.muted)
            }
            ProgressView(value: min(max(backend.status.bufferDurationSeconds / Double(max(backend.settings.replayDurationSeconds, 1)), 0), 1))
                .tint(CyberTheme.red).accessibilityLabel("Replay buffer")
                Button(action: backend.saveClipRequested) {
                    HStack {
                        Text(isSaving ? "Saving replay…" : "Save replay")
                        Spacer()
                        Text(backend.settings.saveClipHotkey.compactDisplayValue).font(.caption.monospaced())
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(CyberButtonStyle(tone: .primary, isEnabled: backend.status.canSaveClip))
                .disabled(!backend.status.canSaveClip)
            HStack(spacing: 6) {
                ForEach(Self.replayDurations(limit: backend.settings.replayDurationSeconds), id: \.self) { seconds in
                    Button("\(seconds)s") { backend.saveReplay(seconds: seconds) }
                        .buttonStyle(.plain).foregroundStyle(CyberTheme.text)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(CyberTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                        .disabled(!backend.status.canSaveClip)
                        .help("Save up to the last \(seconds) seconds")
                        .accessibilityLabel("Save last \(seconds) seconds")
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(CyberTheme.muted)
            HStack {
                Button {
                    if backend.status.isRecording || isSaving { backend.stopCaptureRequested() }
                    else { backend.startCaptureRequested() }
                } label: {
                    Label(backend.status.isRecording || isSaving ? "Stop" : "Start", systemImage: backend.status.isRecording || isSaving ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .medium)).frame(minHeight: 28)
                }
                .buttonStyle(.plain).disabled(isSaving)
                .accessibilityLabel(backend.status.isRecording || isSaving ? "Stop capture" : "Start capture")
                Spacer()
                Text(overlayHint).font(.system(size: 10, design: .monospaced)).foregroundStyle(CyberTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 244, height: 252)
        .foregroundStyle(CyberTheme.text)
        .background(CyberTheme.panel.opacity(0.97))
        .clipShape(dockedShape)
        .overlay {
            dockedShape
                .strokeBorder(CyberTheme.text.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            Capsule().fill(LinearGradient(colors: [CyberTheme.cyan, CyberTheme.red], startPoint: .top, endPoint: .bottom))
                .frame(width: 2, height: 210)
                .padding(.trailing, 1)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .overlay {
            if !reduceMotion {
                Rectangle().fill(LinearGradient(colors: [.clear, CyberTheme.cyan.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 70).rotationEffect(.degrees(18))
                    .keyframeAnimator(initialValue: CGFloat(-180), trigger: controller.isVisible) { view, position in
                        view.offset(x: position)
                    } keyframes: { _ in
                        LinearKeyframe(-180, duration: 0.08)
                        CubicKeyframe(360, duration: 0.62)
                    }
                    .opacity(controller.isVisible ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(dockedShape).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .mask(alignment: .topLeading) {
            Rectangle()
                .frame(height: controller.isVisible || reduceMotion ? 252 : 45)
                .animation(reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0), value: controller.isVisible)
        }
        .opacity(controller.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.12).delay(controller.isVisible || reduceMotion ? 0 : 0.22), value: controller.isVisible)
        .preferredColorScheme(ThemePreferences.shared.isLight ? .light : .dark)
    }

    private var dockedShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 18, topTrailingRadius: 18)
    }

    private var overlayHint: String {
        if case .saving = backend.recordingState { return "Saving…" }
        return "⌥⌘O to hide"
    }

    private var isSaving: Bool {
        if case .savingClip = backend.status.captureState { return true }
        return false
    }

    static func replayDurations(limit: Int) -> [Int] {
        Array(Set([15, 30, 60].filter { $0 < limit } + [limit].filter { $0 > 0 })).sorted()
    }
}
