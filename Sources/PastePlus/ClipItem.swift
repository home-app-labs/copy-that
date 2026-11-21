import Foundation
import CryptoKit

/// One entry of the clipboard history.
struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case text, link, image, file

        var title: String {
            switch self {
            case .text: return "Text"
            case .link: return "Link"
            case .image: return "Image"
            case .file: return "File"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    /// Plain text, the URL of a link, or file paths separated by newlines. Nil for images.
    var text: String?
    /// Extra representations kept on disk, keyed by pasteboard type (png, rtf, html) -> file name in the blobs folder.
    var blobs: [String: String] = [:]
    /// Content fingerprint: copying the same thing again moves the old entry to the front.
    var fingerprint: String
    var created = Date()
    var appName: String?
    var appBundleID: String?
    /// Set for saved snippets: the group they belong to. History entries have none.
    var groupID: UUID?
    /// Optional name the user gave a snippet.
    var title: String?
    var pixelWidth: Int?
    var pixelHeight: Int?

    var filePaths: [String] {
        kind == .file ? (text ?? "").split(separator: "\n").map(String.init) : []
    }

    /// Host of a link without "www.", taken from the string itself. Nothing is ever fetched.
    var linkHost: String? {
        guard kind == .link, let text, let host = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host
        else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return true }
        if let text, text.localizedCaseInsensitiveContains(query) { return true }
        if let title, title.localizedCaseInsensitiveContains(query) { return true }
        if let appName, appName.localizedCaseInsensitiveContains(query) { return true }
        return kind.title.localizedCaseInsensitiveContains(query)
    }
}

enum Classifier {
    /// A link is a single http(s) URL with a host and nothing else around it.
    static func isLink(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4096,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return false }
        return true
    }

    static func fingerprint(kind: ClipItem.Kind, data: Data) -> String {
        var hasher = SHA256()
        // A link is text that happens to be a URL, so both share a namespace.
        hasher.update(data: Data(((kind == .link ? .text : kind).rawValue + ":").utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// A named collection of saved snippets.
struct SnippetGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Index into the group colour palette.
    var color = 0
}

/// What was read from the pasteboard, before it becomes a stored item.
struct Capture {
    var kind: ClipItem.Kind
    var text: String?
    /// Representations to keep on disk, keyed by pasteboard type.
    var data: [String: Data] = [:]
    var pixelWidth: Int?
    var pixelHeight: Int?
    var appName: String?
    var appBundleID: String?

    var fingerprint: String {
        if kind == .image, let png = data[BlobType.png] { return Classifier.fingerprint(kind: .image, data: png) }
        return Classifier.fingerprint(kind: kind, data: Data((text ?? "").utf8))
    }

    static func text(_ string: String, rtf: Data? = nil, html: Data? = nil) -> Capture {
        var capture = Capture(kind: Classifier.isLink(string) ? .link : .text, text: string)
        if let rtf { capture.data[BlobType.rtf] = rtf }
        if let html { capture.data[BlobType.html] = html }
        return capture
    }
}

enum BlobType {
    static let png = "public.png"
    static let rtf = "public.rtf"
    static let html = "public.html"

    static func fileExtension(_ type: String) -> String {
        switch type {
        case png: return "png"
        case rtf: return "rtf"
        case html: return "html"
        default: return "bin"
        }
    }
}
