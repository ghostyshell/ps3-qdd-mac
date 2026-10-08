import CommonCrypto
import Foundation

public enum AESError: Error, Equatable {
    case badKeyLength(bytes: Int)
    case badBlockLength(bytes: Int)
    case cryptorCreationFailed(status: Int32)
    case updateFailed(status: Int32, produced: Int)
}

/// AES-128 in CBC mode with no padding.
///
/// Deliberately built on `CCCryptorCreate`/`CCCryptorUpdate`, never the one-shot
/// `CCCrypt`. `CCCrypt` silently applies PKCS#7 padding, which would corrupt every
/// disc sector: each one is exactly 128 blocks and must decrypt to exactly 128 blocks.
public enum AES128CBC {
    public static let blockSize = 16
    public static let keySize = 16

    /// Decrypts `input` into a fresh buffer. `input.count` must be a multiple of 16.
    public static func decrypt(key: [UInt8], iv: [UInt8], input: [UInt8]) throws -> [UInt8] {
        guard key.count == keySize else { throw AESError.badKeyLength(bytes: key.count) }
        guard iv.count == blockSize else { throw AESError.badBlockLength(bytes: iv.count) }
        guard input.count % blockSize == 0 else { throw AESError.badBlockLength(bytes: input.count) }
        if input.isEmpty { return [] }

        let count = input.count
        var output = [UInt8](repeating: 0, count: count)
        let status: CCCryptorStatus = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                input.withUnsafeBytes { source in
                    output.withUnsafeMutableBytes { destination in
                        decryptRaw(
                            key: keyBytes.baseAddress!,
                            iv: ivBytes.baseAddress!,
                            source: source.baseAddress!,
                            destination: destination.baseAddress!,
                            count: count
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else {
            throw AESError.updateFailed(status: status, produced: count)
        }
        return output
    }

    /// The hot path used by the decryption engine, which must not allocate per sector.
    /// `source` and `destination` must both be readable/writable for `count` bytes.
    /// Returns a `CCCryptorStatus`; the caller writes `destination` back over `source`.
    @inline(__always)
    internal static func decryptRaw(
        key: UnsafeRawPointer,
        iv: UnsafeRawPointer,
        source: UnsafeRawPointer,
        destination: UnsafeMutableRawPointer,
        count: Int
    ) -> CCCryptorStatus {
        // `kCCSuccess` imports as `Int`; the CCCryptorStatus API is `Int32`.
        let success = CCCryptorStatus(kCCSuccess)
        var cryptor: CCCryptorRef?
        let createStatus = CCCryptorCreate(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(0),
            key,
            keySize,
            iv,
            &cryptor
        )
        guard createStatus == success, let cryptor else { return createStatus }
        defer { CCCryptorRelease(cryptor) }

        var moved = 0
        let updateStatus = CCCryptorUpdate(cryptor, source, count, destination, count, &moved)
        guard updateStatus == success, moved == count else { return updateStatus }
        return success
    }
}
