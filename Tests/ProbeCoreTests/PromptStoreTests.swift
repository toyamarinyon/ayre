import XCTest
@testable import ProbeCore

final class PromptStoreTests: XCTestCase {
    private var store: PromptStore!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PromptStoreTests-\(UUID().uuidString)")
        store = PromptStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: store.directory)
    }

    func testSlugValidation() {
        XCTAssertTrue(PromptStore.isValidSlug("design-review_2.v1"))
        for bad in ["", "-x", ".hidden", "a/b", "a..b", "日本語", "a b", String(repeating: "a", count: 129)] {
            XCTAssertFalse(PromptStore.isValidSlug(bad), bad)
        }
    }

    func testRoundTripKeepsBytesExactly() throws {
        let text = "# 設計\n\n- 🧪 e\u{301}\r\n```swift\nlet x = 1\n```\n"
        try store.save(text, slug: "plan")
        XCTAssertTrue(StrictCompare.equal(try store.text("plan"), text))
        XCTAssertThrowsError(try store.save("x", slug: "plan"))
        try store.save("x", slug: "plan", overwrite: true)
        XCTAssertEqual(try store.text("plan"), "x")
    }

    func testListTitlesSkipsInvalidAndSortsNewestFirst() throws {
        try store.save("no heading", slug: "old")
        try store.save("\n# 新しい計画\nbody", slug: "new")
        let fm = FileManager.default
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: try store.url(for: "old").path)
        try Data([0xFF, 0xFE]).write(to: store.directory.appendingPathComponent("broken.md"))
        try Data("x".utf8).write(to: store.directory.appendingPathComponent("bad name.md"))
        try Data("x".utf8).write(to: store.directory.appendingPathComponent("notes.txt"))
        let (prompts, skipped) = store.list()
        XCTAssertEqual(prompts.map(\.slug), ["new", "old"])
        XCTAssertEqual(prompts.map(\.title), ["新しい計画", "old"])
        XCTAssertEqual(skipped, 2)
        XCTAssertThrowsError(try store.text("missing"))
        XCTAssertThrowsError(try store.text("../etc"))
    }

    func testRejectsOversizedFile() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(count: PromptStore.maxBytes + 1).write(to: try store.url(for: "huge"))
        XCTAssertThrowsError(try store.text("huge"))
        XCTAssertThrowsError(try store.save(String(repeating: "a", count: PromptStore.maxBytes + 1), slug: "huge2"))
    }

    func testByteSavePreservesUTF8AndRejectsNoClobberSymlink() throws {
        let bytes = Data("# Cafe\u{301}\r\nbody\n".utf8)
        try store.save(bytes, slug: "bytes")
        XCTAssertEqual(try Data(contentsOf: store.url(for: "bytes")), bytes)
        XCTAssertEqual(PromptStore.title(of: String(decoding: bytes, as: UTF8.self), slug: "bytes"), "Cafe\u{301}")

        try FileManager.default.createSymbolicLink(at: store.url(for: "linked"), withDestinationURL: store.url(for: "bytes"))
        XCTAssertThrowsError(try store.save(Data("replacement".utf8), slug: "linked"))
        XCTAssertEqual(try Data(contentsOf: store.url(for: "bytes")), bytes)

        try store.save(Data("replacement".utf8), slug: "linked", overwrite: true)
        XCTAssertFalse(try store.url(for: "linked").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true)
    }

    func testFilterRequiresAllTerms() {
        let p = { (slug: String, title: String) in StoredPrompt(slug: slug, title: title, modified: .distantPast, utf8Count: 0, lineCount: 0) }
        let prompts = [p("auth-plan", "認証の設計"), p("ui", "画面の設計"), p("misc", "メモ")]
        XCTAssertEqual(PromptStore.filter(prompts, query: "").count, 3)
        XCTAssertEqual(PromptStore.filter(prompts, query: "設計").map(\.slug), ["auth-plan", "ui"])
        XCTAssertEqual(PromptStore.filter(prompts, query: "AUTH 設計").map(\.slug), ["auth-plan"])
        XCTAssertEqual(PromptStore.filter(prompts, query: "ＵＩ").map(\.slug), ["ui"])
        XCTAssertTrue(PromptStore.filter(prompts, query: "none").isEmpty)
    }
}
