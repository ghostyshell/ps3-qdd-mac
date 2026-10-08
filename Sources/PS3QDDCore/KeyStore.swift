import Foundation

public enum KeyStoreError: Error, Equatable {
    case unsupportedSource(String)
    case noKeysFound(String)
    case malformedLine(number: Int, text: String)
}

/// A lookup table from disc title to AES key, loaded either from a directory of
/// Redump `.dkey` files or from a single combined `Title<TAB>key` file.
public struct KeyStore: Sendable {
    public enum Kind: Sendable {
        case dkeyDirectory
        case combinedFile
    }

    public let kind: Kind
    public let sourceURL: URL
    private let entries: [String: DiscKey]

    public var count: Int { entries.count }

    /// `~/Library/Application Support/PS3QDD/keys.txt`, written by `scripts/prepare-keys.sh`.
    public static var defaultFileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("PS3QDD", isDirectory: true)
            .appendingPathComponent("keys.txt", isDirectory: false)
    }

    public static func load(from url: URL) throws -> KeyStore {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw KeyStoreError.unsupportedSource(url.path)
        }
        return isDirectory.boolValue
            ? try loadDirectory(url)
            : try loadCombinedFile(url)
    }

    private init(kind: Kind, sourceURL: URL, entries: [String: DiscKey]) {
        self.kind = kind
        self.sourceURL = sourceURL
        self.entries = entries
    }

    private static func loadDirectory(_ url: URL) throws -> KeyStore {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var entries: [String: DiscKey] = [:]
        for file in contents where file.pathExtension.lowercased() == "dkey" {
            guard let raw = try? String(contentsOf: file, encoding: .utf8),
                  let key = try? DiscKey(hex: raw)
            else { continue }
            for alias in aliases(for: file.lastPathComponent) {
                entries[alias] = key
            }
        }
        guard !entries.isEmpty else { throw KeyStoreError.noKeysFound(url.path) }
        return KeyStore(kind: .dkeyDirectory, sourceURL: url, entries: entries)
    }

    private static func loadCombinedFile(_ url: URL) throws -> KeyStore {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var entries: [String: DiscKey] = [:]
        for (offset, line) in raw.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("#") { continue }
            guard let (title, key) = splitEntry(text) else {
                throw KeyStoreError.malformedLine(number: offset + 1, text: text)
            }
            for alias in aliases(for: title) {
                entries[alias] = key
            }
        }
        guard !entries.isEmpty else { throw KeyStoreError.noKeysFound(url.path) }
        return KeyStore(kind: .combinedFile, sourceURL: url, entries: entries)
    }

    /// `Title<TAB>key`, or whitespace-separated with the key last. Titles contain spaces,
    /// and Redump titles contain parentheses and commas, so the key has to be identified
    /// from the end rather than by splitting on the first delimiter.
    private static func splitEntry(_ text: String) -> (title: String, key: DiscKey)? {
        if let tab = text.firstIndex(of: "\t") {
            let title = String(text[..<tab]).trimmingCharacters(in: .whitespaces)
            guard let key = try? DiscKey(hex: String(text[text.index(after: tab)...])) else { return nil }
            return (title, key)
        }
        guard let lastSpace = text.lastIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        let title = String(text[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        guard let key = try? DiscKey(hex: String(text[text.index(after: lastSpace)...])) else { return nil }
        return (title, key)
    }

    /// The key for an ISO, trying the full filename first, then the stem, then a form with
    /// punctuation removed, so `Game (USA) (v01.00).iso` still finds an entry filed as
    /// `Game_USA_v01.00`.
    ///
    /// The punctuation-stripped form deliberately keeps region and version tags. Dropping
    /// them would make the USA and Europe releases of one game collide, and returning the
    /// wrong key corrupts the output silently rather than failing.
    public func key(forISO name: String) -> DiscKey? {
        for alias in Self.aliases(for: name) {
            if let key = entries[alias] { return key }
        }
        return nil
    }

    /// Lookup keys, most specific first, deduplicated with order preserved.
    static func aliases(for name: String) -> [String] {
        let filename = name.lowercased()
        var result = [filename]

        let stem = strippingKnownExtension(filename)
        if stem != filename { result.append(stem) }

        let unpunctuated = stem.filter { $0.isLetter || $0.isNumber }

        var seen = Set<String>()
        return (result + [unpunctuated]).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Only real disc-image extensions are stripped. Cutting at the last dot
    /// unconditionally would turn a Redump version tag like `(v02.00)` into `(v02`, and
    /// then two different revisions of the same disc would look alike.
    private static let knownExtensions: Set<String> = ["iso", "dkey", "txt", "bin", "img"]

    private static func strippingKnownExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return name }
        let fileExtension = String(name[name.index(after: dot)...])
        return knownExtensions.contains(fileExtension) ? String(name[..<dot]) : name
    }
}
