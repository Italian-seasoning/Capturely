import SwiftUI

struct ClipMetadataEditor: View {
    var clip: Clip
    var save: (String?, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var tags: String

    init(clip: Clip, save: @escaping (String?, [String]) -> Void) {
        self.clip = clip
        self.save = save
        _title = State(initialValue: clip.title ?? "")
        _tags = State(initialValue: clip.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CLIP DETAILS")
                .font(.headline.monospaced())
                .foregroundStyle(CyberTheme.red)

            TextField("Title", text: $title)
                .accessibilityLabel("Clip title")

            TextField("Tags separated by commas", text: $tags)
                .accessibilityLabel("Clip tags")

            Text("Use commas between tags.")
                .font(.caption)
                .foregroundStyle(CyberTheme.muted)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    save(
                        ClipLibraryQuery.normalizedTitle(title),
                        ClipLibraryQuery.normalizedTags(tags.split(separator: ",").map(String.init))
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(CyberTheme.panel)
    }
}
