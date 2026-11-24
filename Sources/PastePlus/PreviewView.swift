import SwiftUI
import AppKit
import ImageIO

/// The large preview opened with Space: the selected item at a readable size, above the strip of cards.
/// Like the cards it is drawn from what is stored locally. A link is shown as text and never opened.
struct PreviewView: View {
    /// Longer texts are cut in the preview so that it stays fast. Pasting always gives the whole text.
    static let textLimit = 20_000
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "bmp", "webp"]

    @ObservedObject var model: PanelModel
    let close: () -> Void
    @State private var overClose = false

    var body: some View {
        Group {
            if let item = model.selectedItem {
                VStack(spacing: 0) {
                    header(item)
                    Divider().opacity(0.5)
                    content(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("Nothing selected").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            if let icon = AppIcons.icon(for: item.appBundleID) {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            }
            Text(item.title ?? Self.kindTitle(item))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(Self.detail(item))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(action: close) {
                HStack(spacing: 5) {
                    Text("space").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    Text("Close").font(.system(size: 11)).foregroundStyle(.secondary)
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.primary.opacity(overClose ? 0.16 : 0.08), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { overClose = $0 }
            .help("Close the preview")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 44)
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            if let color = Classifier.hexColor(item.text ?? "") {
                colorContent(item, color)
            } else {
                textContent(item.text ?? "")
            }
        case .link:
            linkContent(item)
        case .image:
            LargeImageView(url: model.store.blobURL(item, BlobType.png)).padding(14)
        case .file:
            fileContent(item)
        }
    }

    private func textContent(_ text: String) -> some View {
        let cut = text.count > Self.textLimit
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(cut ? String(text.prefix(Self.textLimit)) : text)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if cut {
                    Text("The first \(Self.textLimit.formatted()) of \(text.count.formatted()) characters are shown. Pasting gives all of them.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
    }

    private func colorContent(_ item: ClipItem, _ color: (red: Double, green: Double, blue: Double, alpha: Double)) -> some View {
        let luminance = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        let onLight = luminance > 0.6 && color.alpha > 0.5
        return ZStack {
            Color(red: color.red, green: color.green, blue: color.blue).opacity(color.alpha)
            Text((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .foregroundStyle(onLight ? Color.black.opacity(0.8) : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background((onLight ? Color.white : Color.black).opacity(0.22), in: Capsule())
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(14)
    }

    /// Deliberately offline: only the address itself is shown, nothing is fetched.
    private func linkContent(_ item: ClipItem) -> some View {
        let tint = Color(red: 0.10, green: 0.60, blue: 0.66)
        return VStack(spacing: 14) {
            Image(systemName: "link")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(tint.opacity(0.14), in: Circle())
            Text(item.linkHost ?? "Link")
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .lineLimit(12)
            Text("Links are shown as text. Copy That never opens or loads them.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(28)
    }

    @ViewBuilder
    private func fileContent(_ item: ClipItem) -> some View {
        let paths = item.filePaths
        if paths.count == 1, Self.imageExtensions.contains((paths[0] as NSString).pathExtension.lowercased()),
           FileManager.default.fileExists(atPath: paths[0]) {
            VStack(spacing: 8) {
                LargeImageView(url: URL(fileURLWithPath: paths[0]))
                Text((paths[0] as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(14)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable().frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((path as NSString).lastPathComponent)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if !FileManager.default.fileExists(atPath: path) {
                                Text("Moved or deleted").font(.system(size: 11)).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    static func kindTitle(_ item: ClipItem) -> String {
        if item.kind == .text, Classifier.hexColor(item.text ?? "") != nil { return "Color" }
        return item.kind == .file && item.filePaths.count > 1 ? "Files" : item.kind.title
    }

    static func detail(_ item: ClipItem) -> String {
        var parts: [String] = []
        switch item.kind {
        case .text:
            if Classifier.hexColor(item.text ?? "") == nil {
                let count = item.text?.count ?? 0
                parts.append(count == 1 ? "1 character" : "\(count.formatted()) characters")
            }
        case .image:
            if let width = item.pixelWidth, let height = item.pixelHeight { parts.append("\(width) × \(height)") }
        case .file:
            if item.filePaths.count > 1 { parts.append("\(item.filePaths.count) files") }
        case .link:
            break
        }
        if let app = item.appName { parts.append(app) }
        parts.append(CardView.ago(item.created))
        return parts.joined(separator: " · ")
    }
}

/// An image at up to preview size, decoded off the main thread.
private struct LargeImageView: View {
    let url: URL?
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            } else if failed {
                Text("The image could not be read").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = nil
            failed = false
            guard let url else { failed = true; return }
            let loaded = await Task.detached(priority: .userInitiated) { ThumbnailView.load(url, maxPixelSize: 2400) }.value
            image = loaded
            failed = loaded == nil
        }
    }
}
