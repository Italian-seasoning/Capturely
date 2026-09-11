import Foundation

enum ClipPreviewLoader {
    static func thumbnailData(at url: URL?) async -> Data? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
    }

    static func fileSizeDescription(for url: URL) async -> String {
        await Task.detached(priority: .utility) {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize else {
                return "Unknown size"
            }
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }.value
    }
}
