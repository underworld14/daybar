import XCTest
@testable import DayBarCore

/// Upgrade safety: automatic backups before a new build opens the store, and a store that
/// can't be opened throws instead of crashing.
@MainActor
final class StoreBackupTests: XCTestCase {
    private var directory: URL!
    private let fm = FileManager.default

    override func setUp() {
        directory = fm.temporaryDirectory.appendingPathComponent("StoreBackupTests-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: directory)
    }

    private func writeFakeStore(_ contents: String = "store") {
        for file in StoreBackup.storeFiles(in: directory) {
            fm.createFile(atPath: file.path, contents: Data(contents.utf8))
        }
    }

    private func backups() -> [String] {
        ((try? fm.contentsOfDirectory(atPath: StoreBackup.backupsDirectory(in: directory).path)) ?? []).sorted()
    }

    func testFreshInstallMakesNoBackup() {
        XCTAssertNil(StoreBackup.backupIfBuildChanged(in: directory, currentBuild: "4"))
        XCTAssertTrue(backups().isEmpty)
    }

    func testUpgradeFromAnUnrecordedBuildBacksUpAllStoreFiles() throws {
        writeFakeStore()

        let folder = try XCTUnwrap(StoreBackup.backupIfBuildChanged(in: directory, currentBuild: "4"))

        XCTAssertTrue(folder.lastPathComponent.hasPrefix("auto-unknown-to-4-"))
        let copied = try fm.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(copied, ["daybar.store", "daybar.store-shm", "daybar.store-wal"])
        XCTAssertTrue(fm.fileExists(atPath: StoreBackup.storeFiles(in: directory)[0].path), "original stays in place")
    }

    func testSameBuildMakesNoBackup() {
        writeFakeStore()
        StoreBackup.recordOpened(build: "4", in: directory)
        XCTAssertEqual(StoreBackup.lastOpenedBuild(in: directory), "4")
        XCTAssertNil(StoreBackup.backupIfBuildChanged(in: directory, currentBuild: "4"))
    }

    func testOnlyTheNewestThreeAutomaticBackupsAreKept() throws {
        writeFakeStore()
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        for build in 1...5 {
            StoreBackup.recordOpened(build: "\(build)", in: directory)
            _ = StoreBackup.backupIfBuildChanged(in: directory, currentBuild: "\(build + 1)", now: start.addingTimeInterval(TimeInterval(build)))
            Thread.sleep(forTimeInterval: 0.02) // distinct creation dates
        }
        // An "unopened" folder is never pruned.
        try fm.createDirectory(at: StoreBackup.backupsDirectory(in: directory).appendingPathComponent("unopened-x"), withIntermediateDirectories: true)
        StoreBackup.pruneAutomaticBackups(in: directory, keeping: 3)

        let automatic = backups().filter { $0.hasPrefix("auto-") }
        XCTAssertEqual(automatic.count, 3)
        XCTAssertTrue(automatic.contains { $0.hasPrefix("auto-5-to-6-") })
        XCTAssertFalse(automatic.contains { $0.hasPrefix("auto-1-to-2-") })
        XCTAssertTrue(backups().contains("unopened-x"))
    }

    func testMoveStoreAsideKeepsTheFiles() throws {
        writeFakeStore()

        let folder = try StoreBackup.moveStoreAside(in: directory)

        XCTAssertFalse(fm.fileExists(atPath: StoreBackup.storeFiles(in: directory)[0].path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path).count, 3)
        XCTAssertTrue(folder.lastPathComponent.hasPrefix("unopened-"))
    }

    func testOpenLiveRecordsTheBuildAndBacksUpOnTheNextBuild() throws {
        _ = try DataStore.openLive(directory: directory, currentBuild: "4")
        XCTAssertEqual(StoreBackup.lastOpenedBuild(in: directory), "4")
        XCTAssertTrue(backups().isEmpty, "fresh store: nothing to back up")

        _ = try DataStore.openLive(directory: directory, currentBuild: "5")

        XCTAssertEqual(StoreBackup.lastOpenedBuild(in: directory), "5")
        XCTAssertEqual(backups().filter { $0.hasPrefix("auto-4-to-5-") }.count, 1)
    }

    func testUnreadableStoreThrowsInsteadOfCrashing() {
        writeFakeStore("this is not a database")

        XCTAssertThrowsError(try DataStore.openLive(directory: directory, currentBuild: "4"))
        XCTAssertNotEqual(StoreBackup.lastOpenedBuild(in: directory), "4", "a failed open must not record the build")
    }
}
