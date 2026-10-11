import Foundation

/// Plain Markdown notes on disk — folders are real directories, files are user-owned
/// (never bundled into the JSON backup). No caching: every call reads disk so external
/// edits appear on the next refresh. Matches `DataStore`'s `@MainActor` isolation.
@MainActor
public final class NotesStore {
    public struct NoteFile: Identifiable, Sendable {
        public let id: URL
        public let url: URL
        /// Filename minus the `.md` extension.
        public let title: String
        public let modifiedAt: Date

        public init(id: URL, url: URL, title: String, modifiedAt: Date) {
            self.id = id
            self.url = url
            self.title = title
            self.modifiedAt = modifiedAt
        }
    }

    public struct Folder: Identifiable, Sendable {
        public let id: URL
        public let url: URL
        public let name: String

        public init(id: URL, url: URL, name: String) {
            self.id = id
            self.url = url
            self.name = name
        }
    }

    public let root: URL

    public init(root: URL? = nil) {
        let base = root ?? PersistencePaths.dayBarDirectory
            .appendingPathComponent("Notes", isDirectory: true)
        self.root = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // MARK: - Queries

    /// Top-level folders, name-sorted.
    public func folders() throws -> [Folder] {
        try directories(at: root).map { url in
            Folder(id: url, url: url, name: url.lastPathComponent)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `.md` files directly inside `folder` (nil = root level), newest-modified first.
    public func notes(in folder: URL?) throws -> [NoteFile] {
        try markdownFiles(at: folder ?? root)
    }

    /// All `.md` files recursively (root + folders), newest-modified first.
    public func allNotes() throws -> [NoteFile] {
        var result = try markdownFiles(at: root)
        for folder in try directories(at: root) {
            result.append(contentsOf: try markdownFiles(at: folder, recursive: true))
        }
        return result.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Mutations

    public func createFolder(named rawName: String) throws -> URL {
        let name = sanitizedFolderName(rawName)
        let url = availableURL(for: root.appendingPathComponent(name, isDirectory: true))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    public func createNote(in folder: URL?, titled rawTitle: String = "Untitled") throws -> URL {
        let directory = folder ?? root
        let name = sanitizedNoteTitle(rawTitle)
        let url = availableURL(for: directory.appendingPathComponent(name + ".md"))
        try "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    public func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Renames the file to `newTitle` (sanitized, collision-numbered) and returns the new URL.
    @discardableResult
    public func rename(_ url: URL, to newTitle: String) throws -> URL {
        let name = sanitizedNoteTitle(newTitle)
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(name + ".md")
        guard destination != url else { return url }
        // Case-only changes can't move directly onto their own (case-insensitively
        // identical, already-existing) path — hop through a temp name so the stored
        // casing still updates.
        if destination.path.caseInsensitiveCompare(url.path) == .orderedSame {
            let temp = url.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".md")
            try FileManager.default.moveItem(at: url, to: temp)
            try FileManager.default.moveItem(at: temp, to: destination)
            return destination
        }
        let resolved = availableURL(for: destination, keepingIfSelf: url)
        try FileManager.default.moveItem(at: url, to: resolved)
        return resolved
    }

    /// Moves a note into `folder` (nil = root). Destination collisions are numbered, never overwritten.
    public func move(_ noteURL: URL, to folder: URL?) throws {
        let directory = folder ?? root
        let destination = directory.appendingPathComponent(noteURL.lastPathComponent)
        guard destination != noteURL else { return }
        let resolved = availableURL(for: destination, keepingIfSelf: noteURL)
        try FileManager.default.moveItem(at: noteURL, to: resolved)
    }

    /// Moves the item to the user's Trash; falls back to a hard delete when no Trash is available.
    /// Works for folders too (trashes their contents).
    public func trash(_ url: URL) throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Renames a folder (sanitized, collision-numbered) and returns the new URL.
    @discardableResult
    public func renameFolder(_ url: URL, to newName: String) throws -> URL {
        let name = sanitized(newName, fallback: "Folder")
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: true)
        guard destination != url else { return url }
        let resolved = availableURL(for: destination, keepingIfSelf: url)
        try FileManager.default.moveItem(at: url, to: resolved)
        return resolved
    }

    // MARK: - Disk helpers

    private func directories(at url: URL) throws -> [URL] {
        let items = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey]
        )
        return items.filter { item in
            guard !item.lastPathComponent.hasPrefix(".") else { return false }
            return (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        }
    }

    private func markdownFiles(at directory: URL, recursive: Bool = false) throws -> [NoteFile] {
        let fm = FileManager.default
        var urls: [URL]
        if recursive {
            let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: []
            )
            urls = (enumerator?.allObjects as? [URL]) ?? []
        } else {
            urls = try fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
            )
        }
        return try urls.compactMap { item in
            guard item.pathExtension.lowercased() == "md" else { return nil }
            guard !item.lastPathComponent.hasPrefix(".") else { return nil }
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return NoteFile(
                id: item,
                url: item,
                title: item.deletingPathExtension().lastPathComponent,
                modifiedAt: modified
            )
        }
        .sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Name helpers

    /// Strips `/`, `:`, and leading dots, trims whitespace; empty falls back to `fallback`.
    private func sanitized(_ raw: String, fallback: String) -> String {
        var name = raw
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? fallback : name
    }

    private func sanitizedNoteTitle(_ raw: String) -> String {
        sanitized(raw, fallback: "Untitled")
    }

    private func sanitizedFolderName(_ raw: String) -> String {
        sanitized(raw, fallback: "Folder")
    }

    /// Appends " 2", " 3", … before the extension (or at the end for folders) until free.
    /// `keepingIfSelf` lets renames/moves keep their own current path.
    private func availableURL(for proposed: URL, keepingIfSelf keep: URL? = nil) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: proposed.path) else { return proposed }

        let isDirectory = (try? proposed.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            ?? proposed.hasDirectoryPath
        let stem = isDirectory ? proposed.lastPathComponent : proposed.deletingPathExtension().lastPathComponent
        let suffix = isDirectory ? "" : "." + proposed.pathExtension

        var candidate = proposed
        var n = 2
        while fm.fileExists(atPath: candidate.path) && candidate != keep {
            candidate = proposed.deletingLastPathComponent()
                .appendingPathComponent("\(stem) \(n)\(suffix)")
            n += 1
        }
        return candidate
    }
}
