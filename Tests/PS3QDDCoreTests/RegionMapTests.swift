import Testing

@testable import PS3QDDCore

@Suite("Region map")
struct RegionMapTests {
    /// Builds a sector-0 map from boundary values.
    static func header(boundaries: [Int]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: RegionMap.sectorSize)
        let n = (boundaries.count + 1) / 2
        write(Int32(n), into: &header, at: 0)
        for (index, boundary) in boundaries.enumerated() {
            write(Int32(boundary), into: &header, at: 12 + 4 * index)
        }
        return header
    }

    static func write(_ value: Int32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(value & 0xFF)
    }

    /// The real LittleBigPlanet (USA) v02.00 layout, confirmed by decrypting the disc:
    /// 4,400,000 sectors total, with sectors 5,152 ..< 4,268,896 encrypted. That range
    /// is where EBOOT.BIN (sector 95,030) recovers its SCE\0 magic.
    @Test func parsesTheRealDiscLayout() throws {
        let header = Self.header(boundaries: [5151, 4_268_896, 4_400_000])
        let ranges = try RegionMap.encryptedRanges(header: header)
        #expect(ranges == [SectorRange(start: 5152, end: 4_268_896)])
    }

    @Test func firstRunIsAlwaysPlain() throws {
        let header = Self.header(boundaries: [10, 20, 30])
        let ranges = try RegionMap.encryptedRanges(header: header)
        #expect(ranges == [SectorRange(start: 11, end: 20)])
        #expect(ranges.allSatisfy { $0.start > 0 })
    }

    @Test func handlesAlternatingRuns() throws {
        // plain 0..<3, encrypted 3..<7, plain 7..<10, encrypted 10..<14, plain 14..<20
        let header = Self.header(boundaries: [2, 7, 9, 14, 19])
        let ranges = try RegionMap.encryptedRanges(header: header)
        #expect(ranges == [SectorRange(start: 3, end: 7), SectorRange(start: 10, end: 14)])
    }

    @Test func skipsEmptyEncryptedRuns() throws {
        // A boundary pair that touch produce a zero-width encrypted run, which must not
        // become a bogus range.
        let header = Self.header(boundaries: [4, 5, 9])
        let ranges = try RegionMap.encryptedRanges(header: header)
        #expect(ranges.isEmpty)
    }

    @Test func rejectsZeroRegions() {
        let header = Self.header(boundaries: [])
        #expect(throws: RegionMapError.zeroRegions) {
            try RegionMap.encryptedRanges(header: header)
        }
    }

    @Test func rejectsOversizedMap() {
        var header = [UInt8](repeating: 0, count: RegionMap.sectorSize)
        Self.write(4096, into: &header, at: 0)
        #expect(throws: RegionMapError.mapTooLarge(entries: 8191)) {
            try RegionMap.encryptedRanges(header: header)
        }
    }

    @Test func rejectsNonMonotonicBoundaries() {
        let header = Self.header(boundaries: [10, 4, 30])
        #expect(throws: RegionMapError.nonMonotonicBoundary(index: 1)) {
            try RegionMap.encryptedRanges(header: header)
        }
    }

    @Test func rejectsShortHeader() {
        #expect(throws: RegionMapError.headerTooShort(bytes: 16)) {
            try RegionMap.encryptedRanges(header: [UInt8](repeating: 0, count: 16))
        }
    }
}
