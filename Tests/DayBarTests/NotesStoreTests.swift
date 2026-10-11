import XCTest
@testable import DayBarCore

@MainActor
final class NotesStoreTests: XCTestCase {
    private var root: URL!
    private var store: NotesStore!

    override func setUp() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = NotesStore(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testCreateFolderAndNoteWithDedupeNumbering() throws {
        let work = try store.createFolder(named: "Work")
        let work2 = try store.createFolder(named: "Work")
        XCTAssertEqual(work.lastPathComponent, "Work")
        XCTAssertEqual(work2.lastPathComponent, "Work 2")

        let a = try store.createNote(in: nil, titled: "Ideas")
        let b = try store.createNote(in: nil, titled: "Ideas")
        XCTAssertEqual(a.lastPathComponent, "Ideas.md")
        XCTAssertEqual(b.lastPathComponent, "Ideas 2.md")

        XCTAssertEqual(try store.folders().map(\.name), ["Work", "Work 2"])
        // Same names; strict mtime order is newest-first by creation sequence.
        XCTAssertEqual(Set(try store.notes(in: nil).map(\.title)), ["Ideas", "Ideas 2"])
        XCTAssertEqual(try store.notes(in: nil).first?.modifiedAt, try store.notes(in: nil).map(\.modifiedAt).max())
    }

    func testRenameSanitizesAndReturnsNewURL() throws {
        let url = try store.createNote(in: nil, titled: "Original")
        let renamed = try store.rename(url, to: "a/b")
        XCTAssertEqual(renamed.lastPathComponent, "ab.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let renamed2 = try store.rename(renamed, to: "x:y")
        XCTAssertEqual(renamed2.lastPathComponent, "xy.md")

        // Empty/sanitized-away titles fall back to "Untitled".
        let renamed3 = try store.rename(renamed2, to: "///")
        XCTAssertEqual(renamed3.lastPathComponent, "Untitled.md")
    }

    func testMoveBetweenFolders() throws {
        let work = try store.createFolder(named: "Work")
        let personal = try store.createFolder(named: "Personal")
        let note = try store.createNote(in: work, titled: "Plan")

        try store.move(note, to: personal)
        XCTAssertEqual(try store.notes(in: work).count, 0)
        XCTAssertEqual(try store.notes(in: personal).map(\.title), ["Plan"])

        // Moving to root (nil) works too — the note now lives in Personal.
        try store.move(personal.appendingPathComponent("Plan.md"), to: nil)
        XCTAssertEqual(try store.notes(in: nil).map(\.title), ["Plan"])
        XCTAssertEqual(try store.notes(in: personal).count, 0)
    }

    func testTrashRemovesFromListing() throws {
        let note = try store.createNote(in: nil, titled: "Gone")
        try store.trash(note)
        XCTAssertTrue(try store.notes(in: nil).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
    }

    func testWriteContentsRoundTrip() throws {
        let note = try store.createNote(in: nil, titled: "Journal")
        try store.write("# Hello\n\nBody text.", to: note)
        XCTAssertEqual(try store.contents(of: note), "# Hello\n\nBody text.")
    }

    func testNotesInFolderVsAllNotesScopingAndSorting() throws {
        let work = try store.createFolder(named: "Work")
        let root1 = try store.createNote(in: nil, titled: "Root")
        let deep = try store.createNote(in: work, titled: "Deep")
        let deepSub = work.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: deepSub, withIntermediateDirectories: true)
        let nested = try store.createNote(in: deepSub, titled: "Nested")

        // Give each file a distinct modification time (disk timestamps have coarse resolution).
        let base = Date.now
        try FileManager.default.setAttributes(
            [.modificationDate: base.addingTimeInterval(-30)], ofItemAtPath: root1.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: base.addingTimeInterval(-20)], ofItemAtPath: deep.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: base.addingTimeInterval(-10)], ofItemAtPath: nested.path
        )

        XCTAssertEqual(try store.notes(in: work).map(\.title), ["Deep"])
        let all = try store.allNotes().map(\.title)
        XCTAssertEqual(all, ["Nested", "Deep", "Root"])
    }

    func testCreateFolderSanitizesName() throws {
        let folder = try store.createFolder(named: "a/b:c")
        XCTAssertEqual(folder.lastPathComponent, "abc")
    }

    func testRenameFolderSanitizesAndReturnsNewURL() throws {
        let work = try store.createFolder(named: "Work")
        try store.createNote(in: work, titled: "Plan")

        let renamed = try store.renameFolder(work, to: "a/b")
        XCTAssertEqual(renamed.lastPathComponent, "ab")
        XCTAssertEqual(try store.folders().map(\.name), ["ab"])
        XCTAssertEqual(try store.notes(in: renamed).map(\.title), ["Plan"])
    }
}
