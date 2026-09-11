import SwiftUI

struct LibraryView: View {
    var clips: [Clip] = []
    var reveal: (Clip) -> Void = { _ in }
    var play: (Clip) -> Void = { _ in }
    var export: (Clip) -> Void = { _ in }
    var share: (Clip) -> Void = { _ in }
    var delete: (Clip) -> Void = { _ in }
    var edit: (Clip) -> Void = { _ in }
    var toggleStar: (Clip) -> Void = { _ in }
    var isBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("02 / LIBRARY")
                        .font(.caption.monospaced().weight(.bold))
                        .tracking(2)
                        .foregroundStyle(CyberTheme.red)
                    HStack(alignment: .firstTextBaseline) {
                        Text("The highlights.")
                            .font(.system(size: 36, weight: .black))
                            .fontWidth(.condensed)
                            .tracking(-1.5)
                        Spacer()
                        Text("\(clips.count) SAVED")
                            .font(.caption.monospaced())
                            .foregroundStyle(CyberTheme.muted)
                    }
                }
                .padding(.bottom, 12)

                if clips.isEmpty {
                    CyberPanel(padding: 18, cut: 12, isHot: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(CyberTheme.red)
                            Text("NO CLIPS YET")
                                .font(.title3.weight(.black).monospaced())
                                .tracking(0.8)
                            Text("Start capture, then use Save Replay or your configured hotkey.")
                                .font(.caption.monospaced())
                                .foregroundStyle(CyberTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(clips) { clip in
                            LibraryClipRow(clip: clip, reveal: reveal, play: play, export: export, share: share, delete: delete, edit: edit, toggleStar: toggleStar)
                                .disabled(isBusy)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(CyberTheme.void)
    }
}

struct LibraryClipRow: View {
    var clip: Clip
    var reveal: (Clip) -> Void
    var play: (Clip) -> Void
    var export: (Clip) -> Void
    var share: (Clip) -> Void
    var delete: (Clip) -> Void
    var edit: (Clip) -> Void = { _ in }
    var toggleStar: (Clip) -> Void = { _ in }
    @State private var confirmsDelete = false
    @State private var thumbnailImage: NSImage?
    @State private var fileSizeDescription = "Checking size"

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 112, height: 68)
                .clipShape(CutCornerRectangle(cut: 7))
                .overlay(
                    CutCornerRectangle(cut: 7)
                        .stroke(CyberTheme.red.opacity(0.28), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.sourceAppName ?? clip.gameName)
                    .font(.system(size: 17, weight: .bold))
                    .fontWidth(.condensed)
                if let sourceAppName = clip.sourceAppName,
                   sourceAppName != clip.gameName {
                    Text(clip.gameName)
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(CyberTheme.muted)
                }
                Text(Self.dateFormatter.string(from: clip.capturedAt))
                    .font(.caption.monospaced())
                    .foregroundStyle(CyberTheme.muted)
                Text("\(clip.durationSeconds)s · \(fileSizeDescription) · \(clip.presetName)")
                    .font(.caption.monospaced())
                    .foregroundStyle(CyberTheme.muted)
            }

            Spacer()

            Button { toggleStar(clip) } label: {
                Image(systemName: clip.isStarred == true ? "star.fill" : "star").foregroundStyle(CyberTheme.red)
            }.buttonStyle(.plain).help("Star protects this clip from automatic cleanup")
                .accessibilityLabel(clip.isStarred == true ? "Unstar clip" : "Star clip")

            Button {
                performPlay()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(CyberButtonStyle(tone: .secondary))
            .help("Play clip")

            Button {
                performReveal()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(CyberButtonStyle(tone: .ghost))
            .help("Reveal in Finder")

            Menu {
                Button("Trim & mix audio…") { edit(clip) }
                if let logURL = clip.processLogURL {
                    Button("Reveal process log") { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }
                }
                Button("Export clip", systemImage: "square.and.arrow.down") { performExport() }
                Button("Share clip", systemImage: "square.and.arrow.up") { performShare() }
                Divider()
                Button("Delete clip", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More clip actions")
            .help("Export, share, or delete clip")
        }
        .padding(14)
        .background(
            CutCornerRectangle(cut: 3)
                .fill(CyberTheme.panel)
                .overlay(
                    CutCornerRectangle(cut: 3)
                        .stroke(CyberTheme.text.opacity(0.08), lineWidth: 1)
                )
        )
        .confirmationDialog("Delete this clip?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
        }
        .task(id: clip.thumbnailURL) {
            await loadThumbnail()
        }
        .task(id: clip.clipURL) {
            fileSizeDescription = await ClipPreviewLoader.fileSizeDescription(for: clip.clipURL)
        }
    }

    func performPlay() {
        play(clip)
    }

    func performReveal() {
        reveal(clip)
    }

    func performExport() {
        export(clip)
    }

    func performShare() {
        share(clip)
    }

    func performDelete() {
        delete(clip)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = thumbnailImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle()
                    .fill(CyberTheme.panelRaised)
                Image(systemName: "film")
                    .foregroundStyle(CyberTheme.red.opacity(0.74))
            }
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard let data = await ClipPreviewLoader.thumbnailData(at: clip.thumbnailURL) else {
            thumbnailImage = nil
            return
        }
        thumbnailImage = NSImage(data: data)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
