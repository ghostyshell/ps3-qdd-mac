import CommonCrypto
import Foundation

@testable import PS3QDDCore

enum Bytes {
    static func fromHex(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    static func toHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum Temp {
    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps3qdd-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Collects progress reports. `decrypt` calls its progress closure with a `@Sendable`
/// type, so a plain captured array would not compile.
final class ProgressBox: @unchecked Sendable {
    var count = 0
    var last: DecryptProgress?
}

/// AES-128-CBC encryption with no padding, for building round-trip fixtures.
/// Deliberately independent of `AES128CBC.decrypt` so the test is not self-confirming.
enum Encrypt {
    static func cbc(key: [UInt8], iv: [UInt8], plaintext: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: plaintext.count)
        var cryptor: CCCryptorRef?
        let createStatus = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreate(
                    CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(0),
                    keyBytes.baseAddress!, key.count, ivBytes.baseAddress!, &cryptor
                )
            }
        }
        precondition(createStatus == CCCryptorStatus(kCCSuccess))
        var moved = 0
        let updateStatus = plaintext.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                CCCryptorUpdate(
                    cryptor!, source.baseAddress!, plaintext.count,
                    destination.baseAddress!, plaintext.count, &moved
                )
            }
        }
        CCCryptorRelease(cryptor!)
        precondition(updateStatus == CCCryptorStatus(kCCSuccess) && moved == plaintext.count)
        return output
    }
}
