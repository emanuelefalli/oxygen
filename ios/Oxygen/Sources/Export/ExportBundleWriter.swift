import Foundation
import ZeppKit

enum ExportBundleWriter {
    private static let roundsHeader = ["fetch_type", "round_start_utc", "received_at_utc", "payload_sha256", "payload_hex"]
    private static let utcFormat = Date.ISO8601FormatStyle()

    private static let folderTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static func folderName(exportTime: Date) -> String {
        "oxygen-export-" + folderTimestampFormatter.string(from: exportTime)
    }

    static func write(rounds: [StoredRound], records: [DecodedStrapRecord], undecodableRoundCount: Int,
                      transitionLogText: String, appVersion: String, upstreamKitCommit: String,
                      exportTime: Date, timeZone: TimeZone, into parentDirectory: URL) throws -> URL {
        let folder = parentDirectory.appendingPathComponent(folderName(exportTime: exportTime), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

        for fetchType in StrapFetchType.allCases {
            let text = recordsCSV(for: fetchType, records: records)
            try writeText(text, to: folder.appendingPathComponent(fetchType.exportFileName))
        }
        try writeText(roundsCSV(rounds), to: folder.appendingPathComponent("rounds.csv"))

        let manifest = ExportManifest(appVersion: appVersion,
                                      upstreamKitCommit: upstreamKitCommit,
                                      exportTimeUTC: exportTime.formatted(utcFormat),
                                      timeZoneIdentifier: timeZone.identifier,
                                      recordCounts: recordCounts(records),
                                      roundCount: rounds.count,
                                      undecodableRoundCount: undecodableRoundCount)
        try manifest.encodedJSON().write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        try writeText(transitionLogText, to: folder.appendingPathComponent("transition-log.txt"))
        return folder
    }

    static func zip(folder: URL) throws -> URL {
        let destination = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }
        return destination
    }

    @MainActor static func makeArchive(store: RawStoring, transitionLogText: String, appVersion: String,
                                       upstreamKitCommit: String, exportTime: Date, timeZone: TimeZone,
                                       into parentDirectory: URL) throws -> URL {
        let rounds = try store.allRounds()
        var records: [DecodedStrapRecord] = []
        var undecodableRoundCount = 0
        for round in rounds {
            do {
                records += try StrapRecordDecoder.decode(round)
            } catch {
                undecodableRoundCount += 1
            }
        }
        let folder = try write(rounds: rounds, records: RecordDeduplicator.merge(records),
                               undecodableRoundCount: undecodableRoundCount, transitionLogText: transitionLogText,
                               appVersion: appVersion, upstreamKitCommit: upstreamKitCommit,
                               exportTime: exportTime, timeZone: timeZone, into: parentDirectory)
        return try zip(folder: folder)
    }

    private static func recordsCSV(for fetchType: StrapFetchType, records: [DecodedStrapRecord]) -> String {
        let header = ["timestamp_utc"] + StrapRecordDecoder.fieldNames(for: fetchType)
        let rows = records
            .filter { $0.fetchType == fetchType }
            .sorted { $0.timestamp < $1.timestamp }
            .map { [$0.timestamp.formatted(utcFormat)] + $0.fields.map(\.value) }
        return CSVWriter.render(header: header, rows: rows)
    }

    private static func roundsCSV(_ rounds: [StoredRound]) -> String {
        let rows = rounds.map { round in
            ["\(round.fetchType)",
             round.roundStart.formatted(utcFormat),
             round.receivedAt.formatted(utcFormat),
             round.payloadDigest,
             ZeppHex.string(round.payload)]
        }
        return CSVWriter.render(header: roundsHeader, rows: rows)
    }

    private static func recordCounts(_ records: [DecodedStrapRecord]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for fetchType in StrapFetchType.allCases {
            counts["\(fetchType)"] = 0
        }
        for record in records {
            counts["\(record.fetchType)", default: 0] += 1
        }
        return counts
    }

    private static func writeText(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
