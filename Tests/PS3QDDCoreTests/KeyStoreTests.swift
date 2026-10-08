import Foundation
import Testing

@testable import PS3QDDCore

@Suite("Key store")
struct KeyStoreTests {
    /// A real Redump title, because the alias matching has to cope with the parentheses,
    /// commas and version tag it actually carries. The keys beside it are synthetic: no
    /// real disc key is committed to this repository.
    static let title = "LittleBigPlanet (USA) (En,Ja,Fr,De,Es,It,Nl,Pt,Sv,No,Da,Fi,Zh,Ko) (v02.00)"
    static let sampleKey = "A1B2C3D4E5F60718293A4B5C6D7E8F90"

    @Test func loadsADirectoryOfDkeyFiles() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("\(Self.sampleKey)\r\n".utf8)
            .write(to: directory.appendingPathComponent("\(Self.title).dkey"))
        try Data("B2C3D4E5F60718293A4B5C6D7E8F9001\r\n".utf8)
            .write(to: directory.appendingPathComponent("LittleBigPlanet (Korea).dkey"))

        let store = try KeyStore.load(from: directory)
        #expect(store.kind == .dkeyDirectory)
        #expect(store.count >= 2)

        // The ISO filename and the .dkey filename are the same Redump title, so the
        // stem comparison has to hit.
        let key = try #require(store.key(forISO: "\(Self.title).iso"))
        #expect(key.hex == Self.sampleKey)
    }

    @Test func loadsACombinedKeysFile() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keys.txt")
        let contents = """
            # title<TAB>key
            \(Self.title)\t\(Self.sampleKey)
            LittleBigPlanet (Korea)\tB2C3D4E5F60718293A4B5C6D7E8F9001
            """
        try Data(contents.utf8).write(to: file)

        let store = try KeyStore.load(from: file)
        #expect(store.kind == .combinedFile)
        let key = try #require(store.key(forISO: "\(Self.title).iso"))
        #expect(key.hex == Self.sampleKey)
    }

    @Test func fallsBackToAPunctuationInsensitiveMatch() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keys.txt")
        // Differs from the ISO name only in punctuation; the tags must still line up.
        try Data("LittleBigPlanet_USA_En,Ja,Fr,De,Es,It,Nl,Pt,Sv,No,Da,Fi,Zh,Ko_v02.00\t\(Self.sampleKey)\n".utf8)
            .write(to: file)

        let store = try KeyStore.load(from: file)
        #expect(store.key(forISO: "\(Self.title).iso")?.hex == Self.sampleKey)
    }

    /// Region and version tags are part of a disc's identity. Dropping them would hand the
    /// USA release the Europe key, which fails silently by producing a corrupt image.
    @Test func doesNotConfuseDifferentRegions() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keys.txt")
        try Data("LittleBigPlanet (Europe) (En,Ja,Fr,De,Es,It,Nl,Pt,Sv,No,Da,Fi,Zh,Ko) (v02.00)\tC3D4E5F60718293A4B5C6D7E8F900112\n".utf8)
            .write(to: file)

        let store = try KeyStore.load(from: file)
        #expect(store.key(forISO: "\(Self.title).iso") == nil)
    }

    @Test func returnsNilForAnUnknownTitle() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keys.txt")
        try Data("\(Self.title)\t\(Self.sampleKey)\n".utf8).write(to: file)

        let store = try KeyStore.load(from: file)
        #expect(store.key(forISO: "Some Other Game (USA).iso") == nil)
    }

    @Test func rejectsAnEmptyDirectory() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: KeyStoreError.noKeysFound(directory.path)) {
            try KeyStore.load(from: directory)
        }
    }

    @Test func rejectsAMalformedLine() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keys.txt")
        try Data("Some Game\tnonsense\n".utf8).write(to: file)
        #expect(throws: KeyStoreError.malformedLine(number: 1)) {
            try KeyStore.load(from: file)
        }
    }

    @Test func aliasOrderPrefersExactNames() {
        let aliases = KeyStore.aliases(for: "Game (USA) (v01.00).iso")
        #expect(aliases.first == "game (usa) (v01.00).iso")
        #expect(aliases[1] == "game (usa) (v01.00)")
        #expect(aliases.last == "gameusav0100")
    }

    /// Titles carry spaces, so a space-separated entry has to take its key from the end.
    @Test func splitsSpaceSeparatedEntriesFromTheEnd() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keys.txt")
        try Data("\(Self.title) \(Self.sampleKey)\n".utf8).write(to: file)

        let store = try KeyStore.load(from: file)
        #expect(store.key(forISO: "\(Self.title).iso")?.hex == Self.sampleKey)
    }
}
