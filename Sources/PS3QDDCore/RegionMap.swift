import Foundation

/// A contiguous run of sectors, half-open: `start ..< end`, in 2048-byte sectors.
public struct SectorRange: Equatable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var count: Int { end - start }
    public func contains(_ sector: Int) -> Bool { sector >= start && sector < end }
}

public enum RegionMapError: Error, Equatable {
    case headerTooShort(bytes: Int)
    case zeroRegions
    case mapTooLarge(entries: Int)
    case nonMonotonicBoundary(index: Int)
}

/// Parses the region map that sits in the first sector of a PS3 disc image.
///
/// Sector 0 holds `n = BE_u32(0)` followed by `2n - 1` boundary values at
/// `BE_u32(12 + 4j)`. Regions alternate plain, encrypted, plain, ... starting with
/// plain, so only the odd-indexed ones are AES-encrypted. Region 0 is always plain:
/// it is where the map itself lives.
public enum RegionMap {
    public static let sectorSize = 2048

    public static func encryptedRanges(header: [UInt8]) throws -> [SectorRange] {
        guard header.count >= sectorSize else {
            throw RegionMapError.headerTooShort(bytes: header.count)
        }
        let count = bigEndianUInt32(header, at: 0)
        guard count > 0 else { throw RegionMapError.zeroRegions }

        let entries = 2 * count - 1
        guard 12 + 4 * entries <= sectorSize else {
            throw RegionMapError.mapTooLarge(entries: entries)
        }

        var ranges: [SectorRange] = []
        var lba = 0
        var previous = -1
        for index in 0..<entries {
            let boundary = bigEndianUInt32(header, at: 12 + 4 * index)
            guard boundary > previous else {
                throw RegionMapError.nonMonotonicBoundary(index: index)
            }
            previous = boundary

            // An odd boundary excludes the sector it points at from the run that ends
            // there, so a plain region stops one sector earlier than its boundary.
            let last = boundary - (index % 2 == 1 ? 1 : 0)
            if index % 2 == 1, last >= lba {
                ranges.append(SectorRange(start: lba, end: last + 1))
            }
            lba = last + 1
        }
        return ranges
    }

    private static func bigEndianUInt32(_ bytes: [UInt8], at offset: Int) -> Int {
        (Int(bytes[offset]) << 24)
            | (Int(bytes[offset + 1]) << 16)
            | (Int(bytes[offset + 2]) << 8)
            | Int(bytes[offset + 3])
    }
}
