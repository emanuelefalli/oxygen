import Foundation
import ZeppKit

struct StrapRecordField: Equatable, Sendable {
    let name: String
    let value: String
}

struct DecodedStrapRecord: Equatable, Sendable {
    let fetchType: StrapFetchType
    let timestamp: Date
    let fields: [StrapRecordField]
    let receivedAt: Date
}

enum StrapRecordDecoder {
    static func fieldNames(for type: StrapFetchType) -> [String] {
        switch type {
        case .activity:
            return ["kind", "intensity", "steps", "rawHeartRate", "unknown4", "sleep", "deepSleep", "rem"]
        case .manualHeartRate, .restingHeartRate, .maximumHeartRate:
            return ["utcOffsetQuarterHours", "rawBeatsPerMinute"]
        case .heartRateVariability:
            return ["unknown", "milliseconds"]
        case .stressManual, .stressAutomatic:
            return ["rawLevel"]
        case .bloodOxygenNormal:
            return ["isAutomatic", "rawPercent"]
        case .bloodOxygenSleep:
            return ["rawPercent", "duration", "high", "low", "signalQuality", "extended"]
        case .temperature:
            return ["unknown0", "rawCentiCelsius", "unknown2", "unknown3"]
        case .sleepRespiratoryRate:
            return ["utcOffsetQuarterHours", "breathsPerMinute", "unknown6", "unknown7"]
        case .pai:
            return ["utcOffsetQuarterHours", "lowZonePAI", "moderateZonePAI", "highZonePAI", "lowZoneMinutes",
                    "moderateZoneMinutes", "highZoneMinutes", "todayPAI", "totalPAI"]
        case .sleepSession:
            return ["midnightReference", "flag8", "flag9", "sleepStart", "sleepEnd", "rawSleepStartMinute",
                    "rawSleepEndMinute", "averageHeartRate", "score", "stages", "totalREMMinutes",
                    "totalLightMinutes", "totalDeepMinutes", "totalAwakeMinutes"]
        }
    }

    static func decode(_ round: StoredRound) throws -> [DecodedStrapRecord] {
        let parsed = try ZeppRecordParser.parse(round.fetchType.zeppFetchType,
                                                data: [UInt8](round.payload),
                                                start: round.roundStart)
        return timestampedFields(in: parsed.records).map { entry in
            DecodedStrapRecord(fetchType: round.fetchType,
                               timestamp: entry.timestamp,
                               fields: entry.fields,
                               receivedAt: round.receivedAt)
        }
    }

    private struct TimestampedFields {
        let timestamp: Date
        let fields: [StrapRecordField]
    }

    private static func timestampedFields(in batch: ZeppRecordBatch) -> [TimestampedFields] {
        switch batch {
        case .activity(let minutes):
            return minutes.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .manualHeartRate(let readings), .restingHeartRate(let readings), .maxHeartRate(let readings):
            return readings.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .hrv(let readings):
            return readings.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .manualStress(let readings):
            return readings.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .autoStress(let minutes):
            return minutes.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .spo2(let readings):
            return readings.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .sleepSpO2(let readings):
            return readings.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .temperature(let minutes):
            return minutes.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .sleepRespiratoryRate(let readings):
            return readings.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .pai(let records):
            return records.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        case .sleepSession(let sessions):
            return sessions.map { TimestampedFields(timestamp: $0.time, fields: fields(of: $0)) }
        }
    }

    private static func fields(of minute: ZeppActivityMinute) -> [StrapRecordField] {
        [
            integerField("kind", minute.kind),
            integerField("intensity", minute.intensity),
            integerField("steps", minute.steps),
            integerField("rawHeartRate", minute.rawHeartRate),
            integerField("unknown4", minute.unknown4),
            integerField("sleep", minute.sleep),
            integerField("deepSleep", minute.deepSleep),
            integerField("rem", minute.rem),
        ]
    }

    private static func fields(of reading: ZeppHeartRateReading) -> [StrapRecordField] {
        [
            integerField("utcOffsetQuarterHours", reading.utcOffsetQuarterHours),
            integerField("rawBeatsPerMinute", reading.rawBeatsPerMinute),
        ]
    }

    private static func fields(of reading: ZeppHRVReading) -> [StrapRecordField] {
        [
            integerField("unknown", reading.unknown),
            integerField("milliseconds", reading.milliseconds),
        ]
    }

    private static func fields(of reading: ZeppStressReading) -> [StrapRecordField] {
        [integerField("rawLevel", reading.rawLevel)]
    }

    private static func fields(of minute: ZeppStressMinute) -> [StrapRecordField] {
        [integerField("rawLevel", minute.rawLevel)]
    }

    private static func fields(of reading: ZeppSpO2Reading) -> [StrapRecordField] {
        [
            booleanField("isAutomatic", reading.isAutomatic),
            integerField("rawPercent", reading.rawPercent),
        ]
    }

    private static func fields(of reading: ZeppSleepSpO2Reading) -> [StrapRecordField] {
        [
            integerField("rawPercent", reading.rawPercent),
            integerField("duration", reading.duration),
            bytesField("high", reading.high),
            bytesField("low", reading.low),
            bytesField("signalQuality", reading.signalQuality),
            bytesField("extended", reading.extended),
        ]
    }

    private static func fields(of minute: ZeppTemperatureMinute) -> [StrapRecordField] {
        [
            integerField("unknown0", minute.unknown0),
            integerField("rawCentiCelsius", minute.rawCentiCelsius),
            integerField("unknown2", minute.unknown2),
            integerField("unknown3", minute.unknown3),
        ]
    }

    private static func fields(of reading: ZeppRespiratoryRateReading) -> [StrapRecordField] {
        [
            integerField("utcOffsetQuarterHours", reading.utcOffsetQuarterHours),
            integerField("breathsPerMinute", reading.breathsPerMinute),
            integerField("unknown6", reading.unknown6),
            integerField("unknown7", reading.unknown7),
        ]
    }

    private static func fields(of record: ZeppPAIRecord) -> [StrapRecordField] {
        [
            integerField("utcOffsetQuarterHours", record.utcOffsetQuarterHours),
            floatingPointField("lowZonePAI", record.lowZonePAI),
            floatingPointField("moderateZonePAI", record.moderateZonePAI),
            floatingPointField("highZonePAI", record.highZonePAI),
            integerField("lowZoneMinutes", record.lowZoneMinutes),
            integerField("moderateZoneMinutes", record.moderateZoneMinutes),
            integerField("highZoneMinutes", record.highZoneMinutes),
            floatingPointField("todayPAI", record.todayPAI),
            floatingPointField("totalPAI", record.totalPAI),
        ]
    }

    private static func fields(of session: ZeppSleepSession) -> [StrapRecordField] {
        [
            dateField("midnightReference", session.midnightReference),
            integerField("flag8", session.flag8),
            integerField("flag9", session.flag9),
            dateField("sleepStart", session.sleepStart),
            dateField("sleepEnd", session.sleepEnd),
            integerField("rawSleepStartMinute", session.rawSleepStartMinute),
            integerField("rawSleepEndMinute", session.rawSleepEndMinute),
            integerField("averageHeartRate", session.averageHeartRate),
            integerField("score", session.score),
            sleepStagesField("stages", session.stages),
            integerField("totalREMMinutes", session.totalREMMinutes),
            integerField("totalLightMinutes", session.totalLightMinutes),
            integerField("totalDeepMinutes", session.totalDeepMinutes),
            integerField("totalAwakeMinutes", session.totalAwakeMinutes),
        ]
    }

    private static func integerField<Value: BinaryInteger>(_ name: String, _ value: Value) -> StrapRecordField {
        StrapRecordField(name: name, value: String(value))
    }

    private static func floatingPointField(_ name: String, _ value: Float) -> StrapRecordField {
        StrapRecordField(name: name, value: String(describing: value))
    }

    private static func booleanField(_ name: String, _ value: Bool) -> StrapRecordField {
        StrapRecordField(name: name, value: value ? "true" : "false")
    }

    private static func dateField(_ name: String, _ value: Date) -> StrapRecordField {
        StrapRecordField(name: name, value: utcText(value))
    }

    private static func bytesField(_ name: String, _ value: [UInt8]) -> StrapRecordField {
        StrapRecordField(name: name, value: ZeppHex.string(value))
    }

    private static func sleepStagesField(_ name: String, _ stages: [ZeppSleepSession.Stage]) -> StrapRecordField {
        let triples = stages.map { stage in
            "\(utcText(stage.start))/\(utcText(stage.end))/\(String(describing: stage.kind))"
        }
        return StrapRecordField(name: name, value: triples.joined(separator: ";"))
    }

    private static let utcFormat = Date.ISO8601FormatStyle()

    private static func utcText(_ date: Date) -> String {
        date.formatted(utcFormat)
    }
}
