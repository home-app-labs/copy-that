import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Snapshots for the website and tests must not flash an icon in the Dock.
        let inDock = AppSettings.shared.showInDock && Debug.snapshotDirectory == nil
        app.setActivationPolicy(inDock ? .regular : .accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        HistoryStore.shared.limit = AppSettings.shared.historyLimit
        AppSettings.shared.applyRetention()
        let hourly = Timer(timeInterval: 3600, repeats: true) { _ in AppSettings.shared.applyRetention() }
        RunLoop.main.add(hourly, forMode: .common)
        PasteboardWatcher.shared.start()
        if Debug.snapshotDirectory == nil {
            hotKey = HotKey.historyShortcut { HistoryPanel.shared.toggle() }
        }
        setUpStatusItem()
        setUpMainMenu()
        HistoryPanel.shared.trackFrontmostApp()
        Debug.runHooks()
        // The very first launch shows the history, so there is something to see besides a new icon.
        if Debug.snapshotDirectory == nil, !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { HistoryPanel.shared.show() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HistoryStore.shared.saveNow()
    }

    /// Clicking the Dock icon, or opening the app again from Spotlight or Finder, shows the history.
    /// A second click puts it away and goes back to the app that was in front.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if HistoryPanel.shared.isVisible { HistoryPanel.shared.hide(returnFocus: true) } else { HistoryPanel.shared.show() }
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        add(menu, "Show History", #selector(showHistory))
        add(menu, "Pause Capturing", #selector(togglePause)).state = AppSettings.shared.paused ? .on : .off
        return menu
    }

    /// The menu bar shown while Copy That is the active app, which happens after a click on its Dock icon.
    private func setUpMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        add(appMenu, "Show History", #selector(showHistory))
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "Hide Copy That", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        let quit = appMenu.addItem(withTitle: "Quit Copy That", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        main.addItem(withTitle: "Copy That", action: nil, keyEquivalent: "").submenu = appMenu

        // Standard editing commands, so the search field and the snippet editor behave like any text field.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let name = AppSettings.shared.paused ? "pause.rectangle" : "list.clipboard"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Copy That")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = AppSettings.shared
        menu.removeAllItems()

        let show = add(menu, "Show History", #selector(showHistory))
        show.keyEquivalent = "v"
        show.keyEquivalentModifierMask = [.command, .shift]
        if hotKey == nil {
            add(menu, "⇧⌘V is taken by another app", nil)
        }
        if !Paster.isTrusted {
            add(menu, "Allow Accessibility to Paste Automatically…", #selector(requestTrust))
        }
        if #available(macOS 15.4, *), NSPasteboard.general.accessBehavior == .alwaysDeny {
            add(menu, "Clipboard Access Is Denied: Open Settings…", #selector(openPasteboardSettings))
        }
        menu.addItem(.separator())

        add(menu, "Pause Capturing", #selector(togglePause)).state = settings.paused ? .on : .off

        let sizes = NSMenu()
        for choice in AppSettings.limitChoices {
            let item = add(sizes, "\(choice) items", #selector(setLimit(_:)))
            item.tag = choice
            item.state = settings.historyLimit == choice ? .on : .off
        }
        add(menu, "History Size", nil).submenu = sizes

        let periods = NSMenu()
        for choice in AppSettings.retentionChoices {
            let item = add(periods, choice.title, #selector(setRetention(_:)))
            item.tag = choice.days
            item.state = settings.retentionDays == choice.days ? .on : .off
        }
        add(menu, "Keep History", nil).submenu = periods

        add(menu, "Launch at Login", #selector(toggleLaunchAtLogin)).state = settings.launchAtLogin ? .on : .off
        add(menu, "Show in Dock", #selector(toggleDock)).state = settings.showInDock ? .on : .off
        add(menu, "Clear History…", #selector(clearHistory))
        menu.addItem(.separator())
        let quit = add(menu, "Quit Copy That", #selector(NSApplication.terminate(_:)))
        quit.target = NSApp
        quit.keyEquivalent = "q"
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = action == nil ? nil : self
        menu.addItem(item)
        return item
    }

    @objc private func showHistory() { HistoryPanel.shared.show() }
    @objc private func requestTrust() { Paster.requestTrust() }

    @objc private func openPasteboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func togglePause() {
        AppSettings.shared.paused.toggle()
        updateStatusIcon()
    }

    @objc private func setLimit(_ sender: NSMenuItem) { AppSettings.shared.historyLimit = sender.tag }

    @objc private func setRetention(_ sender: NSMenuItem) { AppSettings.shared.retentionDays = sender.tag }

    @objc private func toggleDock() {
        AppSettings.shared.showInDock.toggle()
        NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
    }

    @objc private func toggleLaunchAtLogin() { AppSettings.shared.launchAtLogin.toggle() }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear the clipboard history?"
        alert.informativeText = "Saved snippets are kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { HistoryStore.shared.clear() }
    }
}

/// Developer aids, driven by environment variables:
/// PASTEPLUS_DATA_DIR=/path keeps the history somewhere other than Application Support,
/// PASTEPLUS_DEMO=1 fills an empty history with sample items,
/// PASTEPLUS_SNAPSHOT_DIR=/path opens the panel, saves panel.png there after two seconds and quits,
/// PASTEPLUS_SNAPSHOT_WIDTH=1240 makes the panel that wide for the snapshot instead of the screen width.
enum Debug {
    static let snapshotDirectory = ProcessInfo.processInfo.environment["PASTEPLUS_SNAPSHOT_DIR"]
    static let snapshotWidth = snapshotDirectory == nil ? nil
        : ProcessInfo.processInfo.environment["PASTEPLUS_SNAPSHOT_WIDTH"].flatMap(Double.init).map { CGFloat($0) }

    static func runHooks() {
        let env = ProcessInfo.processInfo.environment
        if env["PASTEPLUS_DEMO"] != nil, HistoryStore.shared.items.isEmpty { seedDemo() }
        guard let snapshotDirectory else { return }
        let directory = URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
        HistoryPanel.shared.staysOpen = true
        HistoryPanel.shared.show()
        let model = HistoryPanel.shared.model
        if let query = env["PASTEPLUS_DEMO_QUERY"] { model.query = query }
        // PASTEPLUS_DEMO_FILTER=text|link|image|file opens that tab.
        if let name = env["PASTEPLUS_DEMO_FILTER"],
           let filter = HistoryFilter.kinds.first(where: { "\($0)" == name }) { model.filter = filter }
        // PASTEPLUS_DEMO_SHOW=preview opens the large preview of the selected item, as Space does.
        if env["PASTEPLUS_DEMO_SHOW"] == "preview" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { HistoryPanel.shared.showPreview() }
        }
        // PASTEPLUS_DEMO_SHOW=group|editor|newgroup opens the first group, the snippet editor or the group name field.
        else if let show = env["PASTEPLUS_DEMO_SHOW"], let group = HistoryStore.shared.groups.first {
            model.filter = .group(group.id)
            if show == "editor", let item = model.visible.first { model.beginEdit(item) }
            if show == "newgroup" { model.beginNewGroup() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            HistoryPanel.shared.snapshot(to: directory.appendingPathComponent("panel.png"))
            var info = "trusted=\(Paster.isTrusted)"
            if #available(macOS 15.4, *) { info += " accessBehavior=\(NSPasteboard.general.accessBehavior.rawValue)" }
            try? info.write(to: directory.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    private static func seedDemo() {
        let store = HistoryStore.shared
        var file = Capture(kind: .file, text: "/Applications/Safari.app")
        file.appName = "Finder"; file.appBundleID = "com.apple.finder"
        store.add(file)

        var code = Capture.text("    func add(_ capture: Capture) -> ClipItem {\n        let fingerprint = capture.fingerprint\n        items.insert(item, at: 0)\n        return item\n    }")
        code.appName = "Xcode"; code.appBundleID = "com.apple.dt.Xcode"
        store.add(code)

        var color = Capture.text("#FFB833")
        color.appName = "Digital Color Meter"; color.appBundleID = "com.apple.DigitalColorMeter"
        store.add(color)

        // A small drawn landscape stands in for a screenshot.
        let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 1.00, green: 0.62, blue: 0.42, alpha: 1),
                                NSColor(red: 0.42, green: 0.30, blue: 0.72, alpha: 1),
                                NSColor(red: 0.16, green: 0.15, blue: 0.42, alpha: 1)])!.draw(in: rect, angle: 90)
            NSColor(red: 1.00, green: 0.84, blue: 0.45, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 400, y: 170, width: 120, height: 120)).fill()
            func hills(_ points: [(Double, Double)], _ color: NSColor) {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 0, y: 0))
                points.forEach { path.line(to: NSPoint(x: $0.0, y: $0.1)) }
                path.line(to: NSPoint(x: 640, y: 0))
                path.close()
                color.setFill()
                path.fill()
            }
            hills([(0, 150), (130, 250), (240, 170), (360, 280), (500, 160), (640, 230)],
                  NSColor(red: 0.36, green: 0.31, blue: 0.70, alpha: 1))
            hills([(0, 90), (110, 160), (230, 100), (380, 190), (520, 110), (640, 150)],
                  NSColor(red: 0.20, green: 0.17, blue: 0.42, alpha: 1))
            hills([(0, 50), (200, 85), (420, 55), (640, 90)], NSColor(red: 0.12, green: 0.10, blue: 0.26, alpha: 1))
            return true
        }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            var shot = Capture(kind: .image, data: [BlobType.png: png], pixelWidth: 1280, pixelHeight: 800)
            shot.appName = "Screenshot"; shot.appBundleID = "com.apple.screencaptureui"
            store.add(shot)
        }

        var link = Capture.text("https://developer.apple.com/documentation/appkit/nspasteboard?language=swift")
        link.appName = "Safari"; link.appBundleID = "com.apple.Safari"
        store.add(link)

        let work = store.addGroup("Work")
        store.addGroup("Personal")
        store.addSnippet(text: "Best regards,\nSam", title: "Signature", group: work.id)
        store.addSnippet(text: "https://example.com/board/sprint", title: "Sprint board", group: work.id)
        store.addSnippet(text: "git log --oneline --graph --decorate -20", title: nil, group: work.id)

        var note = Capture.text("Thanks for the update. I will look at it tomorrow morning\nand come back with comments before lunch.")
        note.appName = "Notes"; note.appBundleID = "com.apple.Notes"
        store.add(note)
    }
}
