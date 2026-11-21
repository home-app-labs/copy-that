import AppKit
import SwiftUI
import Combine

/// What the panel shows: the history, one kind of history entry, or a group of saved snippets.
enum HistoryFilter: Hashable {
    case all, text, link, image, file
    case group(UUID)

    static let kinds: [HistoryFilter] = [.all, .text, .link, .image, .file]

    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .link: return "Links"
        case .image: return "Images"
        case .file: return "Files"
        case .group: return "Group"
        }
    }

    var groupID: UUID? {
        if case .group(let id) = self { return id }
        return nil
    }

    func accepts(_ kind: ClipItem.Kind) -> Bool {
        switch self {
        case .all, .group: return true
        case .text: return kind == .text
        case .link: return kind == .link
        case .image: return kind == .image
        case .file: return kind == .file
        }
    }
}

/// A snippet being written or edited. `id` is nil for a new one.
struct SnippetDraft: Equatable {
    var id: UUID?
    var title = ""
    var text = ""
    var groupID: UUID
    /// Images and files only get a name and a group; their content is not editable.
    var editableText = true
}

/// A group being named. `id` is nil for a new one.
struct GroupDraft: Equatable {
    var id: UUID?
    var name = ""
    /// History entry to save into the group once it is created.
    var itemToSave: UUID?
}

/// State of the history panel: what is searched, filtered and selected.
final class PanelModel: ObservableObject {
    let store: HistoryStore
    @Published var query = "" { didSet { if query != oldValue { selectFirst() } } }
    @Published var filter = HistoryFilter.all { didSet { if filter != oldValue { selectFirst() } } }
    @Published var selection: UUID?
    /// Bumped every time the panel opens, so the search field takes focus again.
    @Published var openCount = 0
    @Published var editor: SnippetDraft?
    @Published var groupDraft: GroupDraft?
    /// Short confirmation shown in the bottom bar, e.g. "Saved to Work".
    @Published var toast: String?
    private var subscription: AnyCancellable?
    private var toastWork: DispatchWorkItem?

    init(store: HistoryStore) {
        self.store = store
        subscription = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    var filters: [HistoryFilter] { HistoryFilter.kinds + store.groups.map { .group($0.id) } }

    var visible: [ClipItem] {
        if let group = filter.groupID {
            return store.snippets(in: group).filter { $0.matches(query) }
        }
        let history = store.history.filter { filter.accepts($0.kind) && $0.matches(query) }
        // Searching from "All" also finds saved snippets, listed first.
        guard filter == .all, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return history }
        return store.items.filter { $0.groupID != nil && $0.matches(query) } + history
    }

    var selectedItem: ClipItem? {
        let items = visible
        return items.first { $0.id == selection } ?? items.first
    }

    func reset() {
        editor = nil
        groupDraft = nil
        toast = nil
        query = ""
        filter = .all
        selectFirst()
        openCount += 1
    }

    func selectFirst() { selection = visible.first?.id }

    func move(_ offset: Int) {
        let items = visible
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? 0
        selection = items[min(max(current + offset, 0), items.count - 1)].id
    }

    func cycleFilter(_ offset: Int) {
        let all = filters
        let index = all.firstIndex(of: filter) ?? 0
        filter = all[(index + offset + all.count) % all.count]
    }

    /// Deletes the selected item and keeps the selection in place.
    func deleteSelected() {
        let items = visible
        guard let item = selectedItem, let index = items.firstIndex(of: item) else { return }
        let next = index + 1 < items.count ? items[index + 1] : (index > 0 ? items[index - 1] : nil)
        store.delete(item.id)
        selection = next?.id
    }

    // MARK: Groups and snippets

    func show(toast message: String) {
        toastWork?.cancel()
        toast = message
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    /// The group new snippets go to: the one on screen, else the one used last, else a fresh "Saved".
    private func targetGroup() -> SnippetGroup {
        store.group(filter.groupID) ?? store.lastGroup ?? store.addGroup("Saved")
    }

    func save(_ item: ClipItem, to group: SnippetGroup) {
        guard store.save(item.id, to: group.id) != nil else { return }
        show(toast: item.groupID == nil ? "Saved to \(group.name)" : "Moved to \(group.name)")
    }

    /// ⌘P: saves the selected history entry into the last used group.
    func saveSelected() {
        guard let item = selectedItem, item.groupID == nil else { return }
        save(item, to: store.lastGroup ?? store.addGroup("Saved"))
    }

    func beginNewGroup(saving item: ClipItem? = nil) {
        editor = nil
        groupDraft = GroupDraft(itemToSave: item?.id)
    }

    func beginRename(_ group: SnippetGroup) {
        editor = nil
        groupDraft = GroupDraft(id: group.id, name: group.name)
    }

    func commitGroupDraft() {
        guard let draft = groupDraft else { return }
        groupDraft = nil
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let id = draft.id {
            store.renameGroup(id, to: name)
            return
        }
        let group = store.addGroup(name)
        if let itemID = draft.itemToSave, let item = store.items.first(where: { $0.id == itemID }) {
            save(item, to: group)
        } else {
            filter = .group(group.id)
        }
    }

    func deleteGroup(_ group: SnippetGroup) {
        if filter.groupID == group.id { filter = .all }
        store.deleteGroup(group.id)
    }

    func beginNewSnippet(in group: SnippetGroup? = nil) {
        groupDraft = nil
        editor = SnippetDraft(groupID: (group ?? targetGroup()).id)
    }

    func beginEdit(_ item: ClipItem) {
        guard let group = item.groupID else { return }
        groupDraft = nil
        let textual = item.kind == .text || item.kind == .link
        editor = SnippetDraft(id: item.id, title: item.title ?? "", text: textual ? item.text ?? "" : "",
                              groupID: group, editableText: textual)
    }

    func commitEditor() {
        guard let draft = editor else { return }
        if let id = draft.id {
            if draft.editableText, draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            store.updateSnippet(id, title: draft.title, text: draft.editableText ? draft.text : nil, group: draft.groupID)
            editor = nil
            filter = .group(draft.groupID)
            selection = id
        } else {
            guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let item = store.addSnippet(text: draft.text, title: draft.title, group: draft.groupID)
            editor = nil
            query = ""
            filter = .group(draft.groupID)
            selection = item.id
        }
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The strip of cards at the bottom of the screen. It never activates the app,
/// so the app you were typing in stays frontmost and receives the paste.
final class HistoryPanel: NSObject, NSWindowDelegate {
    static let shared = HistoryPanel()
    static let height: CGFloat = 348

    let model = PanelModel(store: .shared)
    /// Set by debug snapshots so the panel survives losing focus.
    var staysOpen = false
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var askedForTrust = false

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide(returnFocus: true) : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame.insetBy(dx: 10, dy: 0)
        var frame = NSRect(x: area.minX, y: area.minY + 10, width: area.width, height: Self.height)
        if let width = Debug.snapshotWidth { frame.size.width = width }

        panel.setFrame(frame.offsetBy(dx: 0, dy: -24), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.panel else { return event }
                return self.handle(event) ? nil : event
            }
        }
    }

    /// Closes the panel. With `returnFocus`, and when Copy That itself is the active app (it was opened
    /// from the Dock), the app that was in front before comes back, so a paste lands there.
    func hide(returnFocus: Bool = false) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        guard returnFocus, NSApp.isActive else { return }
        if let previousApp, !previousApp.isTerminated { previousApp.activate() } else { NSApp.hide(nil) }
    }

    /// The app the user was in before Copy That came to the front.
    private var previousApp: NSRunningApplication?

    /// Remembers which other app was active last. Needed when the panel is opened from the Dock,
    /// because that click makes Copy That the active app.
    func trackFrontmostApp() {
        let own = Bundle.main.bundleIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != own { previousApp = app }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != own, app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            self?.previousApp = app
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(model: model, panel: self))
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        if !staysOpen { hide() }
    }

    // MARK: Actions

    /// Puts the item on the clipboard, closes the panel and pastes into the app underneath.
    func paste(_ item: ClipItem, plainText: Bool = false) {
        PasteboardWatcher.shared.write(item, plainText: plainText)
        // Opened from the Dock, the other app first has to come back to the front: give it a moment longer.
        let delay = NSApp.isActive ? 0.35 : 0.12
        hide(returnFocus: true)
        if Paster.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Paster.sendPaste() }
        } else if !askedForTrust {
            // Without Accessibility the item is only copied; ask once per launch.
            askedForTrust = true
            Paster.requestTrust()
        }
    }

    /// Copies without pasting.
    func copy(_ item: ClipItem) {
        PasteboardWatcher.shared.write(item)
        hide(returnFocus: true)
    }

    /// Returns true when the key was used by the panel rather than the search field.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let command = flags.contains(.command)
        let key = Int(event.keyCode)
        // While something is being typed, only Esc and the confirming key belong to the panel.
        if model.editor != nil {
            if key == 53 { model.editor = nil; return true }
            if (key == 36 || key == 76) && command { model.commitEditor(); return true }
            return false
        }
        if model.groupDraft != nil {
            if key == 53 { model.groupDraft = nil; return true }
            if key == 36 || key == 76 { model.commitGroupDraft(); return true }
            return false
        }
        switch key {
        case 53: // esc
            if model.query.isEmpty { hide(returnFocus: true) } else { model.query = "" }
            return true
        case 123: model.move(command ? -10_000 : -1); return true
        case 124: model.move(command ? 10_000 : 1); return true
        case 125, 126: return true
        case 36, 76: // return, enter
            if let item = model.selectedItem { paste(item, plainText: flags.contains(.shift)) }
            return true
        case 48: // tab
            model.cycleFilter(flags.contains(.shift) ? -1 : 1)
            return true
        case 51 where command: // ⌘⌫
            model.deleteSelected()
            return true
        default: break
        }
        guard command else { return false }
        // Key codes rather than characters, so the shortcuts work in any keyboard layout.
        let digitKeys = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        if let position = digitKeys.firstIndex(of: key) {
            let items = model.visible
            if position < items.count { paste(items[position], plainText: flags.contains(.shift)) }
            return true
        }
        switch key {
        case 8: // C
            if let item = model.selectedItem { copy(item) }
            return true
        case 35: // P
            model.saveSelected()
            return true
        case 45: // N
            model.beginNewSnippet()
            return true
        case 14: // E
            if let item = model.selectedItem { model.beginEdit(item) }
            return true
        default:
            return false
        }
    }

    /// Debug aid: renders the panel into a PNG.
    func snapshot(to url: URL) {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
