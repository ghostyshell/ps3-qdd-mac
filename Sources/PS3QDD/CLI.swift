import Foundation
import PS3QDDCore

/// Headless entry point, used for verifying a decrypt end to end without a window.
/// Exits 0 on success, 2 on bad arguments, 3 when no key matches, 4 on a decrypt failure.
enum CLI {
    static func run(arguments: [String]) -> Int32 {
        guard arguments.count == 4 else {
            fail("usage: PS3QDD --decrypt <input.iso> <keys-file-or-dkey-folder> <output-dir>\n", code: 2)
        }
        let input = URL(fileURLWithPath: arguments[1])
        let keys = URL(fileURLWithPath: arguments[2])
        let outputDirectory = URL(fileURLWithPath: arguments[3])

        do {
            let store = try KeyStore.load(from: keys)
            let scan = try Decryptor.scan(input: input)
            guard let key = store.key(forISO: input.lastPathComponent) else {
                fail("no key found for \"\(input.lastPathComponent)\" among \(store.count) keys in \(keys.path)\n", code: 3)
            }

            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let output = outputDirectory.appendingPathComponent(input.lastPathComponent)

            let percent = Int((Double(scan.encryptedSectors) / Double(max(scan.totalSectors, 1))) * 100)
            note("\(input.lastPathComponent): \(scan.encrypted.count) encrypted region(s), "
                + "\(scan.encryptedSectors)/\(scan.totalSectors) sectors (\(percent)%)")

            let started = Date()
            try Decryptor.decrypt(
                input: input,
                output: output,
                key: key,
                scan: scan,
                progress: { report($0) }
            )
            let elapsed = Date().timeIntervalSince(started)
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? Int64 ?? 0
            clearProgressLine()
            note("done in \(String(format: "%.1f", elapsed))s: \(output.path) (\(size) bytes, "
                + "\(String(format: "%.0f", Double(size) / 1_048_576 / max(elapsed, 0.001))) MiB/s)")
            return 0
        } catch {
            clearProgressLine()
            fail("\(error)\n", code: 4)
        }
    }

    private static func report(_ progress: DecryptProgress) {
        var line = String(format: "\r%5.1f%%  %7.1f MiB/s", progress.fraction * 100, progress.bytesPerSecond / 1_048_576)
        if let eta = progress.etaSeconds, eta.isFinite {
            line += String(format: "  ETA %4.0fs", eta)
        }
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func clearProgressLine() {
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    }

    private static func note(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static func fail(_ text: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data(text.utf8))
        exit(code)
    }
}
