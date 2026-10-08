import Foundation

public enum DiscKeyError: Error, Equatable {
    case wrongLength(found: Int)
    case notHexadecimal(String)
}

/// The 16-byte AES key for one disc title.
///
/// Redump `.dkey` files are 34 bytes: 32 uppercase hex characters plus CRLF. Every one
/// of those characters is stripped before decoding, so the trailing newline, a stray
/// BOM, or a key pasted out of the aldostools page all parse the same way.
public struct DiscKey: Equatable, Sendable {
    public static let hexLength = 32
    public static let byteCount = 16

    public let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw DiscKeyError.wrongLength(found: bytes.count)
        }
        self.bytes = bytes
    }

    public init(hex: String) throws {
        let cleaned = hex.filter { !$0.isWhitespace && !$0.isNewline }
        guard cleaned.count == Self.hexLength else {
            throw DiscKeyError.wrongLength(found: cleaned.count)
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.byteCount)
        var index = cleaned.startIndex
        for _ in 0..<Self.byteCount {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw DiscKeyError.notHexadecimal(cleaned)
            }
            bytes.append(byte)
            index = next
        }
        self.bytes = bytes
    }

    /// The canonical uppercase form, for display and for writing keys.txt.
    public var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// IV for a sector: twelve zero bytes followed by the big-endian sector index.
    public static func iv(forSector sector: Int) -> [UInt8] {
        var iv = [UInt8](repeating: 0, count: AES128CBC.blockSize)
        iv[12] = UInt8((sector >> 24) & 0xFF)
        iv[13] = UInt8((sector >> 16) & 0xFF)
        iv[14] = UInt8((sector >> 8) & 0xFF)
        iv[15] = UInt8(sector & 0xFF)
        return iv
    }
}
