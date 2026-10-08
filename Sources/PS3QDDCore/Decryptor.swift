import CommonCrypto
import Foundation

public enum DecryptorError: Error, Equatable {
    case unreadableHeader
    case notSectorAligned(bytes: Int64)
    case notAPS3Image
    case cannotCreateOutput(String)
    case shortRead(offset: Int64)
    case writeFailed(offset: Int64, code: Int32)
    case insufficientSpace(needed: Int64, available: Int64)
    case cancelled
    case decryptionFailed(status: Int32)
}

/// What a disc image looks like from the outside, before any decryption happens.
public struct DiscScan: Sendable {
    public let totalBytes: Int64
    public let encrypted: [SectorRange]

    /// Internal, not public. `Decryptor.scan` is the only thing that knows to hold these
    /// ranges against the real file length, and a hand-built scan would skip that check.
    init(totalBytes: Int64, encrypted: [SectorRange]) {
        self.totalBytes = totalBytes
        self.encrypted = encrypted
    }

    public var totalSectors: Int { Int(totalBytes / Int64(RegionMap.sectorSize)) }
    public var encryptedSectors: Int { encrypted.reduce(0) { $0 + $1.count } }
    public var isEncryptedDisc: Bool { !encrypted.isEmpty }
}

public struct DecryptProgress: Sendable {
    public let bytesDone: Int64
    public let totalBytes: Int64
    public let bytesPerSecond: Double
    public let etaSeconds: Double?

    public var fraction: Double {
        totalBytes > 0 ? Double(bytesDone) / Double(totalBytes) : 0
    }
}

public enum Decryptor {
    /// 64 MiB per pass. Big enough to keep the disk streaming, small enough that the
    /// buffer plus its scratch copy stay well inside memory.
    public static let chunkSectors = 32_768

    /// Reads and validates the region map. A file that has no valid map is not an
    /// encrypted PS3 image, and says so here rather than being quietly mangled by
    /// `decrypt`.
    public static func scan(input: URL) throws -> DiscScan {
        let size = try FileManager.default
            .attributesOfItem(atPath: input.path)[.size] as? Int64 ?? 0
        guard size % Int64(RegionMap.sectorSize) == 0 else {
            throw DecryptorError.notSectorAligned(bytes: size)
        }

        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: RegionMap.sectorSize),
              header.count == RegionMap.sectorSize
        else {
            throw DecryptorError.unreadableHeader
        }

        let ranges: [SectorRange]
        do {
            ranges = try RegionMap.encryptedRanges(header: [UInt8](header))
        } catch {
            throw DecryptorError.notAPS3Image
        }

        // The boundaries come out of the file and can name anything up to 2^32, so they
        // have to be held against the real length of the disc. Without this a short file
        // carrying an oversized map sends the mark loop off the end of the mask.
        let totalSectors = Int(size / Int64(RegionMap.sectorSize))
        guard ranges.allSatisfy({ $0.start >= 0 && $0.end <= totalSectors }) else {
            throw DecryptorError.notAPS3Image
        }
        return DiscScan(totalBytes: size, encrypted: ranges)
    }

    /// Decrypts `input` into `output`, writing to a `.part` file and renaming only on
    /// success, so an interrupted run never leaves something that looks complete.
    ///
    /// `progress` is called once per chunk from the calling thread. `isCancelled` is
    /// polled at each chunk boundary, which is the finest granularity that still lets a
    /// stop feel immediate.
    public static func decrypt(
        input: URL,
        output: URL,
        key: DiscKey,
        scan: DiscScan,
        progress: @Sendable (DecryptProgress) -> Void,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws {
        let fileManager = FileManager.default
        let partURL = output.appendingPathExtension("part")
        // Both paths are checked before any work starts, so a directory sitting where the
        // output belongs is refused immediately rather than after a full decrypt.
        try requireNotDirectory(at: partURL)
        try requireNotDirectory(at: output)
        try? fileManager.removeItem(at: partURL)

        try checkFreeSpace(for: output, needed: scan.totalBytes)

        guard fileManager.createFile(atPath: partURL.path, contents: nil) else {
            throw DecryptorError.cannotCreateOutput(partURL.path)
        }

        let inHandle = try FileHandle(forReadingFrom: input)
        let outHandle = try FileHandle(forWritingTo: partURL)
        var inOpen = true
        var outOpen = true
        var finished = false
        defer {
            if inOpen { try? inHandle.close() }
            if outOpen { try? outHandle.close() }
            // The part file is this function's own creation, so it is safe to remove
            // whatever it turned out to be.
            if !finished { try? fileManager.removeItem(at: partURL) }
        }

        // One bool per sector. For a dual-layer disc that is about 12 MB, which is a
        // fair trade for turning the region lookup into an array read on the hot path.
        // Frozen into a `let` so the parallel closure captures it immutably.
        var encryptionMask = [Bool](repeating: false, count: scan.totalSectors)
        for range in scan.encrypted {
            for sector in range.start..<range.end { encryptionMask[sector] = true }
        }
        let mask = encryptionMask

        let sectorSize = RegionMap.sectorSize
        let keyBytes = key.bytes
        var sectorIndex = 0
        var bytesDone: Int64 = 0
        var samples: [(time: Double, bytes: Int64)] = []
        let started = Date()

        while sectorIndex < scan.totalSectors {
            if isCancelled() { throw DecryptorError.cancelled }

            let end = min(sectorIndex + chunkSectors, scan.totalSectors)
            let sectorCount = end - sectorIndex
            let byteCount = sectorCount * sectorSize
            let chunkOffset = Int64(sectorIndex * sectorSize)

            try inHandle.seek(toOffset: UInt64(chunkOffset))
            guard let data = try inHandle.read(upToCount: byteCount),
                  data.count == byteCount
            else {
                throw DecryptorError.shortRead(offset: chunkOffset)
            }

            var buffer = [UInt8](data)
            var scratch = [UInt8](repeating: 0, count: byteCount)
            let firstSector = sectorIndex
            let failures = FailureBox()

            buffer.withUnsafeMutableBufferPointer { bufferPointer in
                scratch.withUnsafeMutableBufferPointer { scratchPointer in
                    let source = RawBytes(pointer: bufferPointer.baseAddress!)
                    let destination = RawBytes(pointer: scratchPointer.baseAddress!)
                    DispatchQueue.concurrentPerform(iterations: sectorCount) { offset in
                        let absolute = firstSector + offset
                        guard mask[absolute] else { return }

                        // Sectors are independent of each other: the IV is derived from
                        // the absolute sector index, so they can be decrypted in any
                        // order, in parallel, without a chain.
                        let status: CCCryptorStatus = keyBytes.withUnsafeBytes { keyPointer in
                            DiscKey.iv(forSector: absolute).withUnsafeBytes { ivPointer in
                                AES128CBC.decryptRaw(
                                    key: keyPointer.baseAddress!,
                                    iv: ivPointer.baseAddress!,
                                    source: source.pointer + offset * sectorSize,
                                    destination: destination.pointer + offset * sectorSize,
                                    count: sectorSize
                                )
                            }
                        }
                        guard status == CCCryptorStatus(kCCSuccess) else {
                            // Copying nothing back would write the ciphertext through and
                            // call it a success, so the chunk is abandoned instead.
                            failures.record(status)
                            return
                        }
                        (source.pointer + offset * sectorSize)
                            .update(from: destination.pointer + offset * sectorSize, count: sectorSize)
                    }
                }
            }

            if let status = failures.firstFailure {
                throw DecryptorError.decryptionFailed(status: status)
            }

            do {
                try outHandle.write(contentsOf: buffer)
            } catch {
                throw DecryptorError.writeFailed(offset: chunkOffset, code: 0)
            }

            bytesDone += Int64(byteCount)
            sectorIndex = end

            let elapsed = Date().timeIntervalSince(started)
            samples.append((time: elapsed, bytes: bytesDone))
            while samples.count > 1, elapsed - samples[0].time > 5 { samples.removeFirst() }
            let window = elapsed - samples[0].time
            let speed = window > 0.05
                ? Double(bytesDone - samples[0].bytes) / window
                : 0
            let remaining = scan.totalBytes - bytesDone
            progress(DecryptProgress(
                bytesDone: bytesDone,
                totalBytes: scan.totalBytes,
                bytesPerSecond: speed,
                etaSeconds: speed > 1 ? Double(remaining) / speed : nil
            ))
        }

        try outHandle.close()
        outOpen = false
        try inHandle.close()
        inOpen = false

        try requireNotDirectory(at: output)
        try? fileManager.removeItem(at: output)
        try fileManager.moveItem(at: partURL, to: output)
        finished = true
    }

    /// `removeItem` deletes a directory and everything under it, and the output path is
    /// derived from the input's own filename, so a directory that happens to sit there
    /// is refused rather than emptied.
    private static func requireNotDirectory(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return
        }
        throw DecryptorError.cannotCreateOutput(url.path)
    }

    private static func checkFreeSpace(for output: URL, needed: Int64) throws {
        let directory = output.deletingLastPathComponent()
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        guard available >= needed else {
            throw DecryptorError.insufficientSpace(needed: needed, available: available)
        }
    }
}

/// Carries a raw pointer into the parallel closure. The buffers are distinct per sector,
/// so there is no actual sharing, but the compiler cannot see that.
private struct RawBytes: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<UInt8>
}

/// Collects the first failure seen by a chunk's parallel loop. The loop body cannot
/// throw, so the status is carried out and checked once the chunk is done. This is the
/// same one-way-signal shape as the app's `CancelFlag`.
private final class FailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)

    func record(_ value: CCCryptorStatus) {
        lock.lock()
        if status == CCCryptorStatus(kCCSuccess) { status = value }
        lock.unlock()
    }

    var firstFailure: CCCryptorStatus? {
        lock.lock()
        defer { lock.unlock() }
        return status == CCCryptorStatus(kCCSuccess) ? nil : status
    }
}
