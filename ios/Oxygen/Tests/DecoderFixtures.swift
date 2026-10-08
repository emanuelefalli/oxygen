// Adapted from ios/OpenCircuitKit/Tests/ZeppKitTests/RecordParserTests.swift at upstream 63e2796d323cea42d4835cf364bd0a4ebfa99682.
import Foundation
import Testing
@testable import Oxygen

struct DecoderFixture: Sendable, CustomTestStringConvertible {
    let fetchType: StrapFetchType
    let roundStart: Date
    let payload: [UInt8]
    let expectedRecordCount: Int
    let expectedFirstTimestamp: Date
    let expectedFirstFields: [StrapRecordField]

    var testDescription: String { "\(fetchType)" }
}

extension DecoderFixture {
    static let all: [DecoderFixture] = [
        activity,
        heartRate(.manualHeartRate),
        pai,
        stressManual,
        stressAutomatic,
        bloodOxygenNormal,
        bloodOxygenSleep,
        temperature,
        sleepRespiratoryRate,
        heartRate(.restingHeartRate),
        heartRate(.maximumHeartRate),
        sleepSession,
        heartRateVariability,
    ]

    private static let upstreamRoundStart = Date(timeIntervalSince1970: 1_790_632_800)

    private static let activity = DecoderFixture(
        fetchType: .activity,
        roundStart: upstreamRoundStart,
        payload: [0x01, 0x20, 0x0c, 0x48, 0x00, 0x81, 0x82, 0x83,
                  0x73, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00,
                  0x78, 0x05, 0x00, 0x00, 0x11, 0x7f, 0xff, 0x00],
        expectedRecordCount: 3,
        expectedFirstTimestamp: upstreamRoundStart,
        expectedFirstFields: fields(["kind": "1", "intensity": "32", "steps": "12", "rawHeartRate": "72",
                                     "unknown4": "0", "sleep": "1", "deepSleep": "2", "rem": "3"]))

    private static func heartRate(_ fetchType: StrapFetchType) -> DecoderFixture {
        DecoderFixture(
            fetchType: fetchType,
            roundStart: upstreamRoundStart,
            payload: littleEndian32(1_790_600_000) + [0x08, 0x3a] + littleEndian32(1_790_686_400) + [0xec, 0xff],
            expectedRecordCount: 2,
            expectedFirstTimestamp: Date(timeIntervalSince1970: 1_790_600_000),
            expectedFirstFields: fields(["utcOffsetQuarterHours": "8", "rawBeatsPerMinute": "58"]))
    }

    private static let heartRateVariability = DecoderFixture(
        fetchType: .heartRateVariability,
        roundStart: upstreamRoundStart,
        payload: [0x8c, 0xe4, 0xba, 0x6a, 0x08, 0x2a, 0xb8, 0xe5, 0xba, 0x6a, 0x08, 0x39],
        expectedRecordCount: 2,
        expectedFirstTimestamp: Date(timeIntervalSince1970: 1_790_633_100),
        expectedFirstFields: fields(["unknown": "8", "milliseconds": "42"]))

    private static let stressManual = DecoderFixture(
        fetchType: .stressManual,
        roundStart: upstreamRoundStart,
        payload: littleEndian32(1_790_600_000) + [0x2d] + littleEndian32(1_790_600_060) + [0xff],
        expectedRecordCount: 2,
        expectedFirstTimestamp: Date(timeIntervalSince1970: 1_790_600_000),
        expectedFirstFields: fields(["rawLevel": "45"]))

    private static let stressAutomatic = DecoderFixture(
        fetchType: .stressAutomatic,
        roundStart: upstreamRoundStart,
        payload: [0x00, 0x27, 0xff, 0x64, 0x65],
        expectedRecordCount: 5,
        expectedFirstTimestamp: upstreamRoundStart,
        expectedFirstFields: fields(["rawLevel": "0"]))

    private static let bloodOxygenNormal = DecoderFixture(
        fetchType: .bloodOxygenNormal,
        roundStart: upstreamRoundStart,
        payload: [0x02] + bloodOxygenRecord(1_790_600_000, 0xe1) + bloodOxygenRecord(1_790_600_600, 0x5f)
            + bloodOxygenRecord(1_790_601_200, 0x80),
        expectedRecordCount: 3,
        expectedFirstTimestamp: Date(timeIntervalSince1970: 1_790_600_000),
        expectedFirstFields: fields(["isAutomatic": "true", "rawPercent": "97"]))

    private static let bloodOxygenSleep = DecoderFixture(
        fetchType: .bloodOxygenSleep,
        roundStart: upstreamRoundStart,
        payload: [0x02] + littleEndian32(1_790_600_000) + [0x60, 0x1e] + [UInt8](1...24),
        expectedRecordCount: 1,
        expectedFirstTimestamp: Date(timeIntervalSince1970: 1_790_600_000),
        expectedFirstFields: fields(["rawPercent": "96", "duration": "30", "high": "010203040506",
                                     "low": "0708090a0b0c", "signalQuality": "0d0e0f1011121314",
                                     "extended": "15161718"]))

    private static let temperature = DecoderFixture(
        fetchType: .temperature,
        roundStart: upstreamRoundStart,
        payload: [3456, 0x7fff, -32768, 1999, 4501, 2000].flatMap(temperatureMinute),
        expectedRecordCount: 6,
        expectedFirstTimestamp: upstreamRoundStart,
        expectedFirstFields: fields(["unknown0": "32767", "rawCentiCelsius": "3456", "unknown2": "23130",
                                     "unknown3": "23130"]))

    private static let sleepRespiratoryRate = DecoderFixture(
        fetchType: .sleepRespiratoryRate,
        roundStart: upstreamRoundStart,
        payload: littleEndian32(1_790_600_000) + [0x08, 0x0e, 0x00, 0x01],
        expectedRecordCount: 1,
        expectedFirstTimestamp: Date(timeIntervalSince1970: 1_790_600_000),
        expectedFirstFields: fields(["utcOffsetQuarterHours": "8", "breathsPerMinute": "14", "unknown6": "0",
                                     "unknown7": "1"]))

    private static let pai = DecoderFixture(
        fetchType: .pai,
        roundStart: upstreamRoundStart,
        payload: paiRecord(type: 0x05, timestamp: 1_790_600_000) + paiRecord(type: 0x00, timestamp: 1_790_686_400)
            + paiRecord(type: 0x07, timestamp: 1_790_700_000),
        expectedRecordCount: 1,
        expectedFirstTimestamp: Date(timeIntervalSince1970: 1_790_600_000),
        expectedFirstFields: fields(["utcOffsetQuarterHours": "8", "lowZonePAI": "1.5", "moderateZonePAI": "2.5",
                                     "highZonePAI": "3.5", "lowZoneMinutes": "10", "moderateZoneMinutes": "20",
                                     "highZoneMinutes": "30", "todayPAI": "12.25", "totalPAI": "87.5"]))

    private static let sleepSession = DecoderFixture(
        fetchType: .sleepSession,
        roundStart: upstreamRoundStart,
        payload: sleepSessionRecord(stages: [(1380, 1400, 0x07), (1400, 1500, 0x04), (1510, 1600, 0x05),
                                             (1600, 1700, 0x08), (1700, 1860, 0x02)]),
        expectedRecordCount: 1,
        expectedFirstTimestamp: Date(timeIntervalSince1970: 1_790_650_000),
        expectedFirstFields: fields([
            "midnightReference": "2026-09-28T22:00:00Z",
            "flag8": "1",
            "flag9": "1",
            "sleepStart": "2026-09-28T21:00:00Z",
            "sleepEnd": "2026-09-29T05:00:00Z",
            "rawSleepStartMinute": "1380",
            "rawSleepEndMinute": "1860",
            "averageHeartRate": "54",
            "score": "81",
            "stages": expectedSleepStages,
            "totalREMMinutes": "95",
            "totalLightMinutes": "250",
            "totalDeepMinutes": "110",
            "totalAwakeMinutes": "25",
        ]))

    private static let expectedSleepStages = [
        "2026-09-28T21:00:00Z/2026-09-28T21:20:00Z/awake",
        "2026-09-28T21:20:00Z/2026-09-28T23:00:00Z/light",
        "2026-09-28T23:10:00Z/2026-09-29T00:40:00Z/deep",
        "2026-09-29T00:40:00Z/2026-09-29T02:20:00Z/rem",
        "2026-09-29T02:20:00Z/2026-09-29T05:00:00Z/other(2)",
    ].joined(separator: ";")

    private static func fields(_ pairs: KeyValuePairs<String, String>) -> [StrapRecordField] {
        pairs.map { StrapRecordField(name: $0.key, value: $0.value) }
    }

    private static func littleEndian16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xff), UInt8(value >> 8)]
    }

    private static func littleEndian32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xff) }
    }

    private static func temperatureMinute(_ centiCelsius: Int16) -> [UInt8] {
        littleEndian16(0x7fff) + littleEndian16(UInt16(bitPattern: centiCelsius)) + littleEndian16(0x5a5a)
            + littleEndian16(0x5a5a)
    }

    private static func bloodOxygenRecord(_ timestamp: UInt32, _ value: UInt8) -> [UInt8] {
        littleEndian32(timestamp) + [value] + [UInt8](repeating: 0xee, count: 60)
    }

    private static func paiRecord(type: UInt8, timestamp: UInt32) -> [UInt8] {
        var record: [UInt8] = [type] + littleEndian32(timestamp) + [0x08] + [UInt8](repeating: 0xaa, count: 31)
        for value in [Float(1.5), 2.5, 3.5] {
            record += littleEndian32(value.bitPattern)
        }
        record += littleEndian16(10) + littleEndian16(20) + littleEndian16(30)
        for value in [Float(12.25), 87.5] {
            record += littleEndian32(value.bitPattern)
        }
        record += [UInt8](repeating: 0xbb, count: 39)
        return record
    }

    private static func sleepSessionRecord(stages: [(UInt16, UInt16, UInt8)]) -> [UInt8] {
        var record = [UInt8](repeating: 0, count: 594)
        func put16(_ value: UInt16, _ offset: Int) {
            record.replaceSubrange(offset..<(offset + 2), with: littleEndian16(value))
        }
        func put32(_ value: UInt32, _ offset: Int) {
            record.replaceSubrange(offset..<(offset + 4), with: littleEndian32(value))
        }
        put32(1_790_650_000, 0x000)
        put32(1_790_632_800, 0x004)
        record[0x008] = 1
        record[0x009] = 1
        put16(1380, 0x00a)
        put16(1860, 0x00c)
        record[0x015] = 54
        record[0x016] = 81
        record[0x054] = UInt8(stages.count)
        for (index, stage) in stages.enumerated() {
            let base = 0x056 + 5 * index
            put16(stage.0, base)
            put16(stage.1, base + 2)
            record[base + 4] = stage.2
        }
        put16(95, 0x24a)
        put16(250, 0x24c)
        put16(110, 0x24e)
        put16(25, 0x250)
        return record
    }
}
