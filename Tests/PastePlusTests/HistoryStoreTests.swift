import XCTest
@testable import PastePlus

final class HistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("pasteplus-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(limit: Int = 500) -> HistoryStore { HistoryStore(directory: directory, limit: limit) }

    func testLinkClassification() {
        XCTAssertTrue(Classifier.isLink("https://example.com/path?q=1"))
        XCTAssertTrue(Classifier.isLink("  http://example.com\n"))
        XCTAssertFalse(Classifier.isLink("see https://example.com for details"))
        XCTAssertFalse(Classifier.isLink("example.com"))
        XCTAssertFalse(Classifier.isLink("mailto:someone@example.com"))
        XCTAssertFalse(Classifier.isLink("https://"))
        XCTAssertEqual(Capture.text("https://www.example.com/a").kind, .link)
        XCTAssertEqual(Capture.text("just words").kind, .text)
    }

    func testHexColorDetection() throws {
        let amber = try XCTUnwrap(Classifier.hexColor(" #FFB833\n"))
        XCTAssertEqual(amber.red, 1, accuracy: 0.001)
        XCTAssertEqual(amber.green, 184.0 / 255, accuracy: 0.001)
        XCTAssertEqual(amber.alpha, 1)
        XCTAssertEqual(try XCTUnwrap(Classifier.hexColor("#0f8")).green, 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(Classifier.hexColor("#00000080")).alpha, 128.0 / 255, accuracy: 0.001)
        XCTAssertNil(Classifier.hexColor("FFB833"))
        XCTAssertNil(Classifier.hexColor("#FFB83"))
        XCTAssertNil(Classifier.hexColor("#GGGGGG"))
        XCTAssertNil(Classifier.hexColor("color: #FFB833"))
    }

    func testLinkHostComesFromTheStringAlone() {
        let item = makeStore().add(.text("https://www.example.com/some/page"))
        XCTAssertEqual(item.linkHost, "example.com")
    }

    func testNewestFirstAndDuplicatesMoveToFront() {
        let store = makeStore()
        store.add(.text("one"))
        store.add(.text("two"))
        store.add(.text("three"))
        XCTAssertEqual(store.items.map(\.text), ["three", "two", "one"])

        store.add(.text("one"))
        XCTAssertEqual(store.items.map(\.text), ["one", "three", "two"])
    }

    func testFileAndTextWithSameStringAreSeparate() {
        let store = makeStore()
        store.add(.text("/tmp/a.txt"))
        store.add(Capture(kind: .file, text: "/tmp/a.txt"))
        XCTAssertEqual(store.items.count, 2)
    }

    func testLimitDropsOldestHistoryButKeepsSnippets() {
        let store = makeStore(limit: 2)
        let group = store.addGroup("Work")
        let first = store.add(.text("one"))
        store.save(first.id, to: group.id)
        store.add(.text("two"))
        store.add(.text("three"))
        store.add(.text("four"))
        XCTAssertEqual(store.history.map(\.text), ["four", "three"])
        XCTAssertEqual(store.snippets(in: group.id).map(\.text), ["one"])
    }

    func testSavingCopiesTheEntryAndItsBlobs() throws {
        let store = makeStore()
        let group = store.addGroup("Shots")
        let item = store.add(Capture(kind: .image, data: [BlobType.png: Data([1, 2, 3])]))
        let saved = try XCTUnwrap(store.save(item.id, to: group.id))
        XCTAssertNotEqual(saved.id, item.id)

        store.delete(item.id)
        XCTAssertEqual(store.blob(saved, BlobType.png), Data([1, 2, 3]))
        // Copying the same thing again is a new history entry, the snippet is left alone.
        store.add(Capture(kind: .image, data: [BlobType.png: Data([1, 2, 3])]))
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.snippets(in: group.id).count, 1)
    }

    func testSnippetsKeepTheirOrderAndCanBeEditedAndMoved() {
        let store = makeStore()
        let work = store.addGroup("Work"), home = store.addGroup("Home")
        let a = store.addSnippet(text: "a", title: " Greeting ", group: work.id)
        let b = store.addSnippet(text: "b", title: "", group: work.id)
        XCTAssertEqual(a.title, "Greeting")
        XCTAssertNil(b.title)
        store.touch(a.id)
        XCTAssertEqual(store.snippets(in: work.id).map(\.text), ["a", "b"])

        store.updateSnippet(b.id, title: "Site", text: "https://example.com", group: home.id)
        XCTAssertEqual(store.snippets(in: work.id).map(\.text), ["a"])
        XCTAssertEqual(store.snippets(in: home.id).map(\.kind), [.link])
        XCTAssertEqual(store.lastGroup?.id, home.id)
    }

    func testDeletingGroupRemovesItsSnippets() {
        let store = makeStore()
        let group = store.addGroup("Temp")
        store.addSnippet(text: "x", title: nil, group: group.id)
        store.add(.text("history"))
        store.deleteGroup(group.id)
        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertEqual(store.items.map(\.text), ["history"])
    }

    func testPanelModelGroupsAndSearch() {
        let store = makeStore()
        store.add(.text("hello history"))
        let model = PanelModel(store: store)

        model.selectFirst()
        model.saveSelected()
        XCTAssertEqual(store.groups.map(\.name), ["Saved"])
        let group = store.groups[0]

        model.filter = .group(group.id)
        model.beginNewSnippet()
        model.editor?.text = "typed snippet"
        model.editor?.title = "Mine"
        model.commitEditor()
        XCTAssertNil(model.editor)
        XCTAssertEqual(model.visible.map(\.text), ["hello history", "typed snippet"])

        model.filter = .all
        XCTAssertEqual(model.visible.count, 1)
        model.query = "mine"
        XCTAssertEqual(model.visible.map(\.text), ["typed snippet"])

        model.query = ""
        model.beginNewGroup()
        model.groupDraft?.name = "Work"
        model.commitGroupDraft()
        XCTAssertEqual(store.groups.map(\.name), ["Saved", "Work"])
        XCTAssertEqual(model.filter, .group(store.groups[1].id))
    }

    func testImageBlobIsStoredAndRemoved() throws {
        let store = makeStore()
        let item = store.add(Capture(kind: .image, data: [BlobType.png: Data([1, 2, 3])]))
        let url = try XCTUnwrap(store.blobURL(item, BlobType.png))
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))

        store.delete(item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testOldHistoryExpiresButSnippetsStay() {
        let store = makeStore()
        let now = Date()
        let group = store.addGroup("Keep")
        store.addSnippet(text: "old snippet", title: nil, group: group.id, now: now.addingTimeInterval(-90 * 86_400))
        store.add(.text("old"), now: now.addingTimeInterval(-8 * 86_400))
        store.add(.text("recent"), now: now.addingTimeInterval(-6 * 86_400))
        store.removeHistory(olderThan: now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(store.history.map(\.text), ["recent"])
        XCTAssertEqual(store.snippets(in: group.id).map(\.text), ["old snippet"])
    }

    func testClearKeepsSnippets() {
        let store = makeStore()
        let group = store.addGroup("Keep")
        store.addSnippet(text: "keep", title: nil, group: group.id)
        store.add(.text("drop"))
        store.clear()
        XCTAssertEqual(store.items.map(\.text), ["keep"])
    }

    func testHistorySurvivesReload() {
        let store = makeStore()
        store.add(.text("https://example.com"))
        store.add(.text("hello", rtf: Data("rtf".utf8)))
        let group = store.addGroup("Work")
        store.addSnippet(text: "snippet", title: "Name", group: group.id)
        store.saveNow()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.history.map(\.text), ["hello", "https://example.com"])
        XCTAssertEqual(reloaded.history.map(\.kind), [.text, .link])
        XCTAssertEqual(reloaded.blob(reloaded.history[0], BlobType.rtf), Data("rtf".utf8))
        XCTAssertEqual(reloaded.groups.map(\.name), ["Work"])
        XCTAssertEqual(reloaded.snippets(in: group.id).map(\.title), ["Name"])
    }

    func testSearchAndFilter() {
        let store = makeStore()
        store.add(.text("Hello World"))
        store.add(.text("https://example.com/docs"))
        let model = PanelModel(store: store)

        model.query = "world"
        XCTAssertEqual(model.visible.map(\.text), ["Hello World"])
        model.query = ""
        model.filter = .link
        XCTAssertEqual(model.visible.map(\.text), ["https://example.com/docs"])
    }

    func testPreviewDropsLeadingBlankLinesAndIndentation() {
        XCTAssertEqual(CardView.preview("\n\n    a\n      b"), "a\n  b")
    }
}
