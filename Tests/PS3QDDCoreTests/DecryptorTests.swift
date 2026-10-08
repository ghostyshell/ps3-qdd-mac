import Foundation
import Testing

@testable import PS3QDDCore

@Suite("Decryptor")
struct DecryptorTests {
    static let keyHex = "A1B2C3D4E5F60718293A4B5C6D7E8F90"

    /// Builds a 12-sector image whose encrypted run is sectors 3 ..< 7, then decrypts it
    /// and checks the whole image comes back byte for byte.
    static func makeFixture() throws -> (plain: [UInt8], encrypted: [UInt8], key: DiscKey) {
        let key = try DiscKey(hex: keyHex)
        let header = RegionMapTests.header(boundaries: [2, 7, 9])
        let sectorSize = RegionMap.sectorSize
        let sectorCount = 12

        var plain = [UInt8](repeating: 0, count: sectorCount * sectorSize)
        for sector in 0..<sectorCount {
            for offset in 0..<sectorSize {
                plain[sector * sectorSize + offset] = UInt8((sector * 7 + offset) % 251)
            }
        }
        // Sector 0 holds the region map and, like every region 0, is never transformed.
        plain.replaceSubrange(0..<sectorSize, with: header)

        var encrypted = plain
        for sector in 3..<7 {
            let range = sector * sectorSize..<(sector + 1) * sectorSize
            let cipher = Encrypt.cbc(
                key: key.bytes,
                iv: DiscKey.iv(forSector: sector),
                plaintext: Array(plain[range])
            )
            encrypted.replaceSubrange(range, with: cipher)
        }
        return (plain, encrypted, key)
    }

    @Test func roundTripsASyntheticImage() throws {
        let fixture = try Self.makeFixture()
        #expect(fixture.encrypted != fixture.plain)

        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("disc.iso")
        let outputURL = directory.appendingPathComponent("out").appendingPathComponent("disc.iso")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(fixture.encrypted).write(to: inputURL)

        let scan = try Decryptor.scan(input: inputURL)
        #expect(scan.encrypted == [SectorRange(start: 3, end: 7)])
        #expect(scan.totalSectors == 12)
        #expect(scan.encryptedSectors == 4)

        let box = ProgressBox()
        try Decryptor.decrypt(
            input: inputURL, output: outputURL, key: fixture.key, scan: scan,
            progress: { box.count += 1; box.last = $0 }
        )

        #expect([UInt8](try Data(contentsOf: outputURL)) == fixture.plain)
        #expect(box.count > 0)
        #expect(box.last?.fraction == 1)
        // The .part file must not survive a successful run.
        #expect(!FileManager.default.fileExists(atPath: outputURL.path + ".part"))
    }

    @Test func removesThePartFileOnCancellation() throws {
        let fixture = try Self.makeFixture()
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("disc.iso")
        let outputURL = directory.appendingPathComponent("decrypted.iso")
        try Data(fixture.encrypted).write(to: inputURL)
        let scan = try Decryptor.scan(input: inputURL)

        #expect(throws: DecryptorError.cancelled) {
            try Decryptor.decrypt(
                input: inputURL, output: outputURL, key: fixture.key, scan: scan,
                progress: { _ in },
                isCancelled: { true }
            )
        }
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
        #expect(!FileManager.default.fileExists(atPath: outputURL.path + ".part"))
    }

    @Test func scanRejectsNonPS3Images() throws {
        let directory = try Temp.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Sector-aligned, but no usable region map.
        let junkURL = directory.appendingPathComponent("junk.iso")
        try Data([UInt8](repeating: 0xAB, count: RegionMap.sectorSize * 4)).write(to: junkURL)
        #expect(throws: DecryptorError.notAPS3Image) {
            try Decryptor.scan(input: junkURL)
        }

        // Not sector-aligned at all.
        let raggedURL = directory.appendingPathComponent("ragged.iso")
        try Data([UInt8](repeating: 0, count: 1000)).write(to: raggedURL)
        #expect(throws: DecryptorError.notSectorAligned(bytes: 1000)) {
            try Decryptor.scan(input: raggedURL)
        }

        // Truncated header.
        let tinyURL = directory.appendingPathComponent("tiny.iso")
        try Data([UInt8](repeating: 0, count: RegionMap.sectorSize)).write(to: tinyURL)
        #expect(throws: DecryptorError.notAPS3Image) {
            try Decryptor.scan(input: tinyURL)
        }
    }
}
