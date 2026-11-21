import Foundation
import Combine

/// Everything the app remembers: the clipboard history (newest first) and the saved snippets with their groups.
/// Persisted as history.json and groups.json plus a folder of blobs (images, rich text).
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore(directory: HistoryStore.defaultDirectory)

    /// History entries and snippets together; snippets are the ones with a groupID.
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var groups: [SnippetGroup] = []
    /// How many history entries to keep. Snippets do not count.
    var limit: Int { didSet { trim(); scheduleSave() } }
    /// The group ⌘P saves into: the one used last.
    private(set) var lastGroupID: UUID?

    let directory: URL
    private var blobDirectory: URL { directory.appendingPathComponent("blobs", isDirectory: true) }
    private var historyFile: URL { directory.appendingPathComponent("history.json") }
    private var groupsFile: URL { directory.appendingPathComponent("groups.json") }
    private var saveWork: DispatchWorkItem?

    static var defaultDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["PASTEPLUS_DATA_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PastePlus", isDirectory: true)
    }

    init(directory: URL, limit: Int = 500) {
        self.directory = directory
        self.limit = limit
        try? FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        // The history holds whatever was copied; keep it readable by the user only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: groupsFile), let saved = try? decoder.decode([SnippetGroup].self, from: data) {
            groups = saved
        }
        if let data = try? Data(contentsOf: historyFile), let saved = try? decoder.decode([ClipItem].self, from: data) {
            // A snippet whose group is gone would be unreachable; treat it as history.
            let known = Set(groups.map(\.id))
            items = saved.map { item in
                var item = item
                if let group = item.groupID, !known.contains(group) { item.groupID = nil }
                return item
            }
        }
    }

    var history: [ClipItem] { items.filter { $0.groupID == nil } }

    /// Snippets of a group in the order they were saved, so their positions stay put.
    func snippets(in group: UUID) -> [ClipItem] { items.filter { $0.groupID == group }.reversed() }

    func group(_ id: UUID?) -> SnippetGroup? { groups.first { $0.id == id } }

    var lastGroup: SnippetGroup? { group(lastGroupID) ?? groups.first }

    // MARK: History

    /// Adds a capture to the front. Copying something already in the history moves it to the front instead.
    @discardableResult
    func add(_ capture: Capture, now: Date = Date()) -> ClipItem {
        let fingerprint = capture.fingerprint
        if let index = items.firstIndex(where: { $0.groupID == nil && $0.fingerprint == fingerprint }) {
            var existing = items.remove(at: index)
            existing.created = now
            if let name = capture.appName { existing.appName = name; existing.appBundleID = capture.appBundleID }
            items.insert(existing, at: 0)
            scheduleSave()
            return existing
        }
        let item = makeItem(capture, now: now)
        items.insert(item, at: 0)
        trim()
        scheduleSave()
        return item
    }

    private func makeItem(_ capture: Capture, now: Date) -> ClipItem {
        var item = ClipItem(kind: capture.kind, text: capture.text, fingerprint: capture.fingerprint, created: now,
                            appName: capture.appName, appBundleID: capture.appBundleID,
                            pixelWidth: capture.pixelWidth, pixelHeight: capture.pixelHeight)
        for (type, data) in capture.data {
            let name = "\(item.id.uuidString).\(BlobType.fileExtension(type))"
            if (try? data.write(to: blobDirectory.appendingPathComponent(name), options: .atomic)) != nil {
                item.blobs[type] = name
            }
        }
        return item
    }

    /// Moves a history entry to the front, as happens when it is pasted again. Snippets keep their place.
    func touch(_ id: UUID, now: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }), index != 0, items[index].groupID == nil else { return }
        var item = items.remove(at: index)
        item.created = now
        items.insert(item, at: 0)
        scheduleSave()
    }

    func delete(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        removeBlobs(of: items.remove(at: index))
        scheduleSave()
    }

    /// Clears the history. Saved snippets stay.
    func clear() {
        items.filter { $0.groupID == nil }.forEach(removeBlobs)
        items.removeAll { $0.groupID == nil }
        scheduleSave()
    }

    /// Drops history entries last copied or pasted before the given moment. Saved snippets stay.
    func removeHistory(olderThan date: Date) {
        let expired = items.filter { $0.groupID == nil && $0.created < date }
        guard !expired.isEmpty else { return }
        expired.forEach(removeBlobs)
        items.removeAll { $0.groupID == nil && $0.created < date }
        scheduleSave()
    }

    private func trim() {
        var kept = 0
        var result: [ClipItem] = []
        for item in items {
            if item.groupID != nil { result.append(item); continue }
            if kept < limit { kept += 1; result.append(item) } else { removeBlobs(of: item) }
        }
        if result.count != items.count { items = result }
    }

    // MARK: Groups and snippets

    @discardableResult
    func addGroup(_ name: String) -> SnippetGroup {
        let used = Set(groups.map(\.color))
        let color = (0..<GroupPalette.count).first { !used.contains($0) } ?? groups.count % GroupPalette.count
        let group = SnippetGroup(name: name, color: color)
        groups.append(group)
        lastGroupID = group.id
        scheduleSave()
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        scheduleSave()
    }

    /// Deletes a group together with its snippets.
    func deleteGroup(_ id: UUID) {
        items.filter { $0.groupID == id }.forEach(removeBlobs)
        items.removeAll { $0.groupID == id }
        groups.removeAll { $0.id == id }
        if lastGroupID == id { lastGroupID = nil }
        scheduleSave()
    }

    /// Saves a history entry into a group as an independent copy; a snippet is moved to the group instead.
    @discardableResult
    func save(_ id: UUID, to group: UUID, now: Date = Date()) -> ClipItem? {
        guard let index = items.firstIndex(where: { $0.id == id }), self.group(group) != nil else { return nil }
        lastGroupID = group
        defer { scheduleSave() }
        if items[index].groupID != nil {
            var moved = items.remove(at: index)
            moved.groupID = group
            items.insert(moved, at: 0)
            return moved
        }
        let source = items[index]
        var copy = source
        copy.id = UUID()
        copy.groupID = group
        copy.created = now
        copy.blobs = [:]
        for (type, name) in source.blobs {
            let newName = "\(copy.id.uuidString).\(BlobType.fileExtension(type))"
            let from = blobDirectory.appendingPathComponent(name), to = blobDirectory.appendingPathComponent(newName)
            if (try? FileManager.default.copyItem(at: from, to: to)) != nil { copy.blobs[type] = newName }
        }
        items.insert(copy, at: 0)
        return copy
    }

    /// Creates a snippet from typed text.
    @discardableResult
    func addSnippet(text: String, title: String?, group: UUID, now: Date = Date()) -> ClipItem {
        var item = makeItem(.text(text), now: now)
        item.groupID = group
        item.title = Self.clean(title)
        items.insert(item, at: 0)
        lastGroupID = group
        scheduleSave()
        return item
    }

    /// Changes a snippet's name, group and, when given, its text. Edited text is plain: stored rich text is dropped.
    func updateSnippet(_ id: UUID, title: String?, text: String?, group: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = Self.clean(title)
        items[index].groupID = group
        if let text, text != items[index].text {
            removeBlobs(of: items[index])
            items[index].blobs = [:]
            items[index].text = text
            items[index].kind = Classifier.isLink(text) ? .link : .text
            items[index].fingerprint = Capture.text(text).fingerprint
        }
        lastGroupID = group
        scheduleSave()
    }

    private static func clean(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Blobs

    func blobURL(_ item: ClipItem, _ type: String) -> URL? {
        item.blobs[type].map { blobDirectory.appendingPathComponent($0) }
    }

    func blob(_ item: ClipItem, _ type: String) -> Data? {
        blobURL(item, type).flatMap { try? Data(contentsOf: $0) }
    }

    private func removeBlobs(of item: ClipItem) {
        for name in item.blobs.values {
            try? FileManager.default.removeItem(at: blobDirectory.appendingPathComponent(name))
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        let encoder = JSONEncoder()
        for (file, data) in [(historyFile, try? encoder.encode(items)), (groupsFile, try? encoder.encode(groups))] {
            guard let data else { continue }
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
}

enum GroupPalette {
    /// RGB of the colours groups cycle through.
    static let colors: [(Double, Double, Double)] = [
        (0.20, 0.66, 0.42), (0.92, 0.38, 0.30), (0.58, 0.40, 0.86),
        (0.93, 0.66, 0.14), (0.16, 0.56, 0.90), (0.88, 0.36, 0.62),
    ]
    static var count: Int { colors.count }
}
