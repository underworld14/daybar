import Foundation

/// Upgrade safety for the live store. Before a new build opens the store, the store files
/// are copied aside (the build that last opened it is recorded in a sidecar), so an update
/// that migrates the schema always leaves a restorable copy. Nothing here deletes user
/// data: only older *automatic* backups are pruned, and a store that can't be opened is
/// moved aside, never removed.
public enum StoreBackup {
    public static let storeName = "daybar.store"
    public static let sidecarName = "store-build.json"
    public static let backupsFolderName = "backups"
    public static let keptAutomaticBackups = 3

    /// The store file plus its SQLite companions.
    public static func storeFiles(in directory: URL, storeName: String = storeName) -> [URL] {
        [storeName, storeName + "-shm", storeName + "-wal"].map { directory.appendingPathComponent($0) }
    }

    public static func backupsDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent(backupsFolderName, isDirectory: true)
    }

    // MARK: Sidecar

    private struct Sidecar: Codable {
        var build: String
        var openedAt: Date
    }

    public static func lastOpenedBuild(in directory: URL) -> String? {
        let url = directory.appendingPathComponent(sidecarName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Sidecar.self, from: data))?.build
    }

    /// Call only after the store opened successfully with `build`.
    public static func recordOpened(build: String, in directory: URL, now: Date = .now) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Sidecar(build: build, openedAt: now)) else { return }
        try? data.write(to: directory.appendingPathComponent(sidecarName), options: .atomic)
    }

    // MARK: Backups

    /// Copies the store files into `backups/auto-<old>-to-<new>-<timestamp>/` when the build
    /// that last opened the store differs from `currentBuild` (or is unknown, i.e. the first
    /// launch of a build that records it). No store yet (fresh install) means no backup.
    /// Returns the backup folder, if one was made.
    @discardableResult
    public static func backupIfBuildChanged(
        in directory: URL,
        currentBuild: String,
        now: Date = .now,
        fileManager: FileManager = .default
    ) -> URL? {
        let files = storeFiles(in: directory)
        guard let store = files.first, fileManager.fileExists(atPath: store.path) else { return nil }
        let previous = lastOpenedBuild(in: directory)
        guard previous != currentBuild else { return nil }

        let name = "auto-\(sanitize(previous ?? "unknown"))-to-\(sanitize(currentBuild))-\(timestamp(now))"
        guard let folder = try? copy(files, intoNewFolderNamed: name, in: backupsDirectory(in: directory), fileManager: fileManager)
        else { return nil }
        pruneAutomaticBackups(in: directory, keeping: keptAutomaticBackups, fileManager: fileManager)
        return folder
    }

    /// Moves a store that can't be opened into `backups/unopened-<timestamp>/` so a fresh
    /// store can be created. The files are kept, never deleted.
    @discardableResult
    public static func moveStoreAside(
        in directory: URL,
        now: Date = .now,
        fileManager: FileManager = .default
    ) throws -> URL {
        let folder = try uniqueFolder(named: "unopened-\(timestamp(now))", in: backupsDirectory(in: directory), fileManager: fileManager)
        for file in storeFiles(in: directory) where fileManager.fileExists(atPath: file.path) {
            try fileManager.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
        return folder
    }

    /// Keeps the newest `count` automatic backups (folder names sort by timestamp).
    public static func pruneAutomaticBackups(in directory: URL, keeping count: Int, fileManager: FileManager = .default) {
        let root = backupsDirectory(in: directory)
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let automatic = entries
            .filter { $0.lastPathComponent.hasPrefix("auto-") }
            .sorted { creationDate($0, fileManager) > creationDate($1, fileManager) }
        for stale in automatic.dropFirst(count) {
            try? fileManager.removeItem(at: stale)
        }
    }

    // MARK: Helpers

    private static func copy(_ files: [URL], intoNewFolderNamed name: String, in root: URL, fileManager: FileManager) throws -> URL {
        let folder = try uniqueFolder(named: name, in: root, fileManager: fileManager)
        for file in files where fileManager.fileExists(atPath: file.path) {
            try fileManager.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
        return folder
    }

    private static func uniqueFolder(named name: String, in root: URL, fileManager: FileManager) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var candidate = root.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
        return candidate
    }

    private static func creationDate(_ url: URL, _ fileManager: FileManager) -> Date {
        ((try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate) ?? .distantPast
    }

    private static func timestamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return fmt.string(from: date)
    }

    private static func sanitize(_ build: String) -> String {
        build.filter { $0.isLetter || $0.isNumber || $0 == "." }
    }
}
