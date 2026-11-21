import SwiftUI
import AppKit
import ImageIO

extension SnippetGroup {
    var tint: Color {
        let (r, g, b) = GroupPalette.colors[((color % GroupPalette.count) + GroupPalette.count) % GroupPalette.count]
        return Color(red: r, green: g, blue: b)
    }
}

struct HistoryView: View {
    enum Field { case search, groupName, snippetTitle, snippetText }

    @ObservedObject var model: PanelModel
    let panel: HistoryPanel
    @FocusState private var focus: Field?

    private static let contentHeight = CardView.size.height + 8

    var body: some View {
        let items = model.visible
        VStack(spacing: 0) {
            topBar(count: items.count)
            Group {
                if model.editor != nil {
                    editor
                } else if items.isEmpty {
                    emptyState
                } else {
                    cards(items)
                }
            }
            .frame(height: Self.contentHeight)
            hints
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .onChange(of: model.openCount, initial: true) { refocus() }
        .onChange(of: model.editor == nil) { refocus() }
        .onChange(of: model.groupDraft == nil) { refocus() }
    }

    /// Puts the cursor where typing is expected: the editor, the group name, otherwise the search field.
    private func refocus() {
        DispatchQueue.main.async {
            if let draft = model.editor {
                focus = draft.editableText && draft.id == nil ? .snippetText : .snippetTitle
            } else if model.groupDraft != nil {
                focus = .groupName
            } else {
                focus = .search
            }
        }
    }

    // MARK: Top bar

    private func topBar(count: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search history and snippets", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .search)
            }
            .padding(.horizontal, 10)
            .frame(width: 260, height: 28)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(HistoryFilter.kinds, id: \.self) { filter in
                        chip(filter.title, dot: nil, active: model.filter == filter, tint: .accentColor) { model.filter = filter }
                    }
                    Rectangle().fill(.primary.opacity(0.15)).frame(width: 1, height: 16).padding(.horizontal, 6)
                    ForEach(model.store.groups) { group in
                        if model.groupDraft?.id == group.id {
                            groupNameField(tint: group.tint)
                        } else {
                            chip(group.name, dot: group.tint, active: model.filter == .group(group.id), tint: group.tint) {
                                model.filter = .group(group.id)
                            }
                            .contextMenu {
                                Button("New Snippet…") { model.beginNewSnippet(in: group) }
                                Button("Rename…") { model.beginRename(group) }
                                Divider()
                                let count = model.store.snippets(in: group.id).count
                                Button(count == 0 ? "Delete Group" : "Delete Group and Its \(count) Snippet\(count == 1 ? "" : "s")",
                                       role: .destructive) { model.deleteGroup(group) }
                            }
                        }
                    }
                    if let draft = model.groupDraft, draft.id == nil {
                        groupNameField(tint: .secondary)
                    } else {
                        Button { model.beginNewGroup() } label: {
                            Label(model.store.groups.isEmpty ? "New Group" : "", systemImage: "plus")
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .foregroundStyle(.secondary)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("New group of snippets")
                    }
                }
            }
            Spacer(minLength: 8)
            Text(count == 1 ? "1 item" : "\(count) items")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func chip(_ title: String, dot: Color?, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(active ? .white : dot).frame(width: 7, height: 7) }
                Text(title).font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(active ? tint.opacity(0.9) : .clear, in: Capsule())
            .foregroundStyle(active ? .white : .primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func groupNameField(tint: Color) -> some View {
        TextField("Group name", text: Binding(get: { model.groupDraft?.name ?? "" },
                                              set: { model.groupDraft?.name = $0 }))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($focus, equals: .groupName)
            .padding(.horizontal, 10)
            .frame(width: 140, height: 24)
            .background(.primary.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.8)))
    }

    // MARK: Cards

    private func cards(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        CardView(item: item, index: index, selected: item.id == model.selectedItem?.id,
                                 group: model.store.group(item.groupID), store: model.store)
                            .id(item.id)
                            .onTapGesture(count: 2) { panel.paste(item) }
                            .simultaneousGesture(TapGesture().onEnded { model.selection = item.id })
                            .contextMenu { menu(for: item) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onChange(of: model.selection) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
            }
            .onChange(of: model.openCount) {
                if let first = items.first { proxy.scrollTo(first.id, anchor: .leading) }
            }
        }
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("Paste") { panel.paste(item) }
        if item.kind != .image { Button("Paste as Plain Text") { panel.paste(item, plainText: true) } }
        Button("Copy") { panel.copy(item) }
        Divider()
        if item.kind == .link, let text = item.text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            Button("Open in Browser") { panel.hide(); NSWorkspace.shared.open(url) }
        }
        if item.kind == .file, let path = item.filePaths.first {
            Button("Show in Finder") {
                panel.hide()
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        if item.groupID != nil { Button("Edit Snippet…") { model.beginEdit(item) } }
        Menu(item.groupID == nil ? "Save to Group" : "Move to Group") {
            ForEach(model.store.groups.filter { $0.id != item.groupID }) { group in
                Button(group.name) { model.save(item, to: group) }
            }
            if !model.store.groups.isEmpty { Divider() }
            Button("New Group…") { model.beginNewGroup(saving: item) }
        }
        Button("Delete", role: .destructive) { model.store.delete(item.id) }
    }

    private var emptyState: some View {
        let inGroup = model.filter.groupID != nil && model.query.isEmpty
        let nothingYet = model.store.history.isEmpty && model.query.isEmpty
        return VStack(spacing: 8) {
            Image(systemName: inGroup ? "square.stack.3d.up" : (nothingYet ? "clipboard" : "magnifyingglass"))
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(inGroup ? "No snippets in this group yet" : (nothingYet ? "Nothing copied yet" : "No matches"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            if inGroup {
                Text("Press ⌘N to write one, or ⌘P on a history item to save it here.")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            } else if nothingYet {
                Text("Copy something with ⌘C and it will show up here.")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Snippet editor

    private var editor: some View {
        let draft = Binding(get: { model.editor ?? SnippetDraft(groupID: UUID()) }, set: { model.editor = $0 })
        let group = model.store.group(draft.wrappedValue.groupID)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(draft.wrappedValue.id == nil ? "New Snippet" : "Edit Snippet")
                    .font(.system(size: 15, weight: .semibold))
                TextField("Name (optional)", text: draft.title)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .snippetTitle)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Menu {
                    ForEach(model.store.groups) { option in
                        Button(option.name) { model.editor?.groupID = option.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(group?.tint ?? .gray).frame(width: 8, height: 8)
                        Text(group?.name ?? "Group")
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                HStack(spacing: 8) {
                    Button("Cancel") { model.editor = nil }
                    Button("Save") { model.commitEditor() }.buttonStyle(.borderedProminent)
                }
            }
            .frame(width: 260, alignment: .leading)

            if draft.wrappedValue.editableText {
                TextEditor(text: draft.text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .snippetText)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.10)))
                    .frame(maxWidth: 760)
                Spacer(minLength: 0)
            } else {
                Text("Images and files keep their content.\nYou can name the snippet and move it to another group.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: Bottom bar

    private var hints: some View {
        HStack(spacing: 14) {
            if model.editor != nil {
                hint("⌘↩", "Save")
                hint("esc", "Cancel")
            } else if model.groupDraft != nil {
                hint("↩", "Save group")
                hint("esc", "Cancel")
            } else {
                hint("↩", "Paste")
                hint("⇧↩", "Plain text")
                hint("⌘1–9", "Quick paste")
                hint("⌘C", "Copy")
                if model.selectedItem?.groupID == nil { hint("⌘P", "Save to group") } else { hint("⌘E", "Edit") }
                hint("⌘N", "New snippet")
                hint("⌘⌫", "Delete")
                hint("⇥", "Next tab")
            }
            Spacer()
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else if !Paster.isTrusted {
                Button { Paster.requestTrust() } label: {
                    Label("Copy only: allow Accessibility to paste automatically", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: Card

struct CardView: View {
    static let size = CGSize(width: 232, height: 236)

    let item: ClipItem
    let index: Int
    let selected: Bool
    /// The group of a saved snippet; nil for history entries.
    let group: SnippetGroup?
    let store: HistoryStore

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: selected ? 3 : 1)
        )
        .shadow(color: .black.opacity(selected ? 0.25 : 0.10), radius: selected ? 8 : 3, y: 2)
        .contentShape(Rectangle())
    }

    private var tint: Color {
        if let group { return group.tint }
        switch item.kind {
        case .text: return Color(red: 0.36, green: 0.42, blue: 0.86)
        case .link: return Color(red: 0.10, green: 0.60, blue: 0.66)
        case .image: return Color(red: 0.84, green: 0.33, blue: 0.56)
        case .file: return Color(red: 0.90, green: 0.55, blue: 0.16)
        }
    }

    private var kindTitle: String {
        item.kind == .file && item.filePaths.count > 1 ? "Files" : item.kind.title
    }

    private var header: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title ?? kindTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(group == nil ? Self.ago(item.created) : (item.title == nil ? group!.name : "\(kindTitle) · \(group!.name)"))
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .opacity(0.8)
            }
            Spacer()
            if group != nil, item.appBundleID == nil {
                Image(systemName: "text.badge.star").font(.system(size: 15)).opacity(0.9)
            }
            if let icon = AppIcons.icon(for: item.appBundleID) {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                    .help(item.appName ?? "")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(tint)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(Self.preview(item.text ?? ""))
                .font(.system(size: 11.5))
                .lineSpacing(1)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        case .link:
            // Deliberately offline: the card is drawn from the URL string alone, nothing is fetched.
            VStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14), in: Circle())
                Text(item.linkHost ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
        case .image:
            ThumbnailView(url: store.blobURL(item, BlobType.png))
        case .file:
            fileContent
        }
    }

    private var fileContent: some View {
        let paths = item.filePaths
        let first = paths.first ?? ""
        return VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                .resizable().frame(width: 52, height: 52)
            Text(paths.count > 1 ? "\(paths.count) files" : (first as NSString).lastPathComponent)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
            Text(paths.count > 1
                 ? paths.prefix(3).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                 : ((first as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
        }
        .padding(10)
    }

    private var footer: some View {
        HStack {
            Text(detail)
            Spacer()
            if index < 9 { Text("⌘\(index + 1)").fontWeight(.medium) }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color.primary.opacity(0.04))
    }

    private var detail: String {
        switch item.kind {
        case .text:
            let count = item.text?.count ?? 0
            return count == 1 ? "1 character" : "\(count.formatted()) characters"
        case .link:
            return item.appName ?? "Link"
        case .image:
            if let width = item.pixelWidth, let height = item.pixelHeight { return "\(width) × \(height)" }
            return "Image"
        case .file:
            return item.appName ?? "File"
        }
    }

    /// First lines of the text, without the blank lines and common indentation it may start with.
    static func preview(_ text: String) -> String {
        var lines = text.prefix(1500).split(separator: "\n", omittingEmptySubsequences: false).prefix(16).map(String.init)
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        let indents = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " || $0 == "\t" }.count }
        let common = indents.min() ?? 0
        return lines.map { String($0.dropFirst(min(common, $0.count))) }.joined(separator: "\n")
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3600) h ago" }
        if seconds < 172_800 { return "Yesterday" }
        if seconds < 604_800 { return "\(seconds / 86_400) days ago" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: Pieces

/// A downscaled preview of a stored image, decoded off the main thread and cached.
struct ThumbnailView: View {
    let url: URL?
    @State private var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: image.size.width > image.size.height * 3 || image.size.height > image.size.width * 3 ? .fit : .fill)
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
            let loaded = await Task.detached(priority: .userInitiated) { Self.load(url) }.value
            if let loaded { Self.cache.setObject(loaded, forKey: url as NSURL) }
            image = loaded
        }
    }

    nonisolated static func load(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// Icons of the apps things were copied from.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

/// Frosted background that stays vivid although the panel's app is never active.
struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if Debug.snapshotDirectory != nil {
            // Blur cannot be rendered into a snapshot, use a flat colour there.
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return view
        }
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
