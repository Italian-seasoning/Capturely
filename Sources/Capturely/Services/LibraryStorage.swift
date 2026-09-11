import Foundation

struct LibraryStorage {
    struct Entry: Sendable {
        var clip: Clip
        var bytes: Int64
        var safeToRemove: Bool
    }

    static func inventory(_ clips: [Clip]) -> [Entry] {
        clips.map { clip in
            let folder = clip.folderURL.standardizedFileURL
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])) ?? []
            let expected = Set([clip.clipURL, clip.metadataURL, clip.thumbnailURL, clip.editableSourceURL, clip.processLogURL].compactMap { $0?.standardizedFileURL })
            let folderIsLink = (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? true
            let metadata = try? Data(contentsOf: clip.metadataURL)
            let identity = metadata.flatMap { try? JSONDecoder.capturely.decode(Clip.self, from: $0) }
            let safe = !folderIsLink && identity?.id == clip.id && !files.isEmpty && expected.allSatisfy { $0.deletingLastPathComponent() == folder }
                && files.allSatisfy { url in
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    return expected.contains(url.standardizedFileURL) && values?.isRegularFile == true && values?.isSymbolicLink == false
                }
            let bytes = files.reduce(Int64(0)) { sum, url in
                sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return Entry(clip: clip, bytes: bytes, safeToRemove: safe)
        }
    }

    static func removals(entries: [Entry], limitBytes: Int64, protectedIDs: Set<UUID> = []) -> [Clip] {
        guard limitBytes > 0 else { return [] }
        var total = entries.reduce(Int64(0)) { $0 + $1.bytes }
        var result: [Clip] = []
        for entry in entries.sorted(by: { $0.clip.capturedAt < $1.clip.capturedAt }) {
            guard total > limitBytes else { break }
            guard entry.safeToRemove, entry.clip.isStarred != true, !protectedIDs.contains(entry.clip.id) else { continue }
            result.append(entry.clip)
            total -= entry.bytes
        }
        return result
    }
}
