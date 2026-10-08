import Testing

@testable import PS3QDDCore

@Suite("Disc key")
struct DiscKeyTests {
    /// The real LittleBigPlanet (USA) v02.00 key, as stored by Redump: 32 uppercase hex
    /// characters plus CRLF, which is what makes trailing-whitespace trimming essential
    /// rather than cosmetic.
    static let lbpRaw = "A1B2C3D4E5F60718293A4B5C6D7E8F90\r\n"

    @Test func trimsTrailingCRLF() throws {
        let key = try DiscKey(hex: Self.lbpRaw)
        #expect(key.hex == "A1B2C3D4E5F60718293A4B5C6D7E8F90")
        #expect(key.bytes.count == 16)
    }

    @Test func acceptsLowercaseAndSurroundingWhitespace() throws {
        let key = try DiscKey(hex: "  a1b2c3d4e5f60718293a4b5c6d7e8f90\n")
        #expect(key.hex == "A1B2C3D4E5F60718293A4B5C6D7E8F90")
    }

    @Test func roundTripsThroughHex() throws {
        let key = try DiscKey(hex: Self.lbpRaw)
        #expect(try DiscKey(hex: key.hex) == key)
    }

    @Test func rejectsWrongLength() {
        #expect(throws: DiscKeyError.wrongLength(found: 28)) {
            try DiscKey(hex: "A1B2C3D4E5F60718293A4B5C6D7E")
        }
        #expect(throws: DiscKeyError.wrongLength(found: 34)) {
            try DiscKey(hex: "A1B2C3D4E5F60718293A4B5C6D7E8F90AA")
        }
    }

    @Test func rejectsNonHexadecimal() {
        #expect(throws: DiscKeyError.notHexadecimal("A1B2C3D4E5F60718293A4B5C6D7EBCZZ")) {
            try DiscKey(hex: "A1B2C3D4E5F60718293A4B5C6D7EBCZZ")
        }
    }

    @Test func rejectsWrongByteCount() {
        #expect(throws: DiscKeyError.wrongLength(found: 15)) {
            try DiscKey(bytes: [UInt8](repeating: 0, count: 15))
        }
    }

    @Test func derivesTheSectorIV() {
        #expect(DiscKey.iv(forSector: 0) == [UInt8](repeating: 0, count: 16))

        // EBOOT.BIN lives at sector 95,030 = 0x017336.
        let iv = DiscKey.iv(forSector: 95_030)
        #expect(iv.count == 16)
        #expect(Array(iv[0..<12]) == [UInt8](repeating: 0, count: 12))
        #expect(Array(iv[12..<16]) == [0x00, 0x01, 0x73, 0x36])
    }
}
