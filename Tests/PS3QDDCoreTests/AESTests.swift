import Testing

@testable import PS3QDDCore

/// NIST SP 800-38A, F.2.2: CBC-AES128.Decrypt over the four-block sample.
@Suite("AES-128-CBC")
struct AESTests {
    static let key = "2b7e151628aed2a6abf7158809cf4f3c"
    static let iv = "000102030405060708090a0b0c0d0e0f"
    static let ciphertext =
        "7649abac8119b246cee98e9b12e9197d"
        + "5086cb9b507219ee95db113a917678b2"
        + "73bed6b8e3c1743b7116e69e22229516"
        + "3ff1caa1681fac09120eca307586e1a7"
    static let plaintext =
        "6bc1bee22e409f96e93d7e117393172a"
        + "ae2d8a571e03ac9c9eb76fac45af8e51"
        + "30c81c46a35ce411e5fbc1191a0a52ef"
        + "f69f2445df4f9b17ad2b417be66c3710"

    @Test func matchesNISTVector() throws {
        let output = try AES128CBC.decrypt(
            key: Bytes.fromHex(Self.key),
            iv: Bytes.fromHex(Self.iv),
            input: Bytes.fromHex(Self.ciphertext)
        )
        #expect(Bytes.toHex(output) == Self.plaintext)
    }

    /// The whole disc depends on this: each sector is exactly 128 blocks and must come
    /// back exactly 128 blocks. A padded implementation would return 144.
    @Test func appliesNoPadding() throws {
        let output = try AES128CBC.decrypt(
            key: Bytes.fromHex(Self.key),
            iv: Bytes.fromHex(Self.iv),
            input: Bytes.fromHex(Self.ciphertext)
        )
        #expect(output.count == 64)
    }

    @Test func rejectsWrongSizes() {
        #expect(throws: AESError.badKeyLength(bytes: 15)) {
            try AES128CBC.decrypt(key: [UInt8](repeating: 0, count: 15), iv: Bytes.fromHex(Self.iv), input: [UInt8](repeating: 0, count: 16))
        }
        #expect(throws: AESError.badBlockLength(bytes: 15)) {
            try AES128CBC.decrypt(key: Bytes.fromHex(Self.key), iv: Bytes.fromHex(Self.iv), input: [UInt8](repeating: 0, count: 15))
        }
        #expect(throws: AESError.badBlockLength(bytes: 17)) {
            try AES128CBC.decrypt(key: Bytes.fromHex(Self.key), iv: Bytes.fromHex(Self.iv), input: [UInt8](repeating: 0, count: 17))
        }
    }

    @Test func emptyInputIsEmptyOutput() throws {
        let output = try AES128CBC.decrypt(key: Bytes.fromHex(Self.key), iv: Bytes.fromHex(Self.iv), input: [])
        #expect(output.isEmpty)
    }
}
