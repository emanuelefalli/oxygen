import Foundation
import Testing
@testable import Oxygen

@MainActor struct ExportTests {
    let t0 = Date(timeIntervalSince1970: 1_791_355_320)

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func writeExport(rounds: [StoredRound], records: [DecodedStrapRecord], timeZone: TimeZone) throws -> URL {
        try ExportBundleWriter.write(rounds: rounds, records: records, undecodableRoundCount: 0, transitionLogText: "a\n",
                                     appVersion: "0.1.0", upstreamKitCommit: String(repeating: "a", count: 40),
                                     exportTime: t0, timeZone: timeZone, into: try temporaryDirectory())
    }

    @Test func csvQuoting() {
        #expect(CSVWriter.render(header: ["a", "b"], rows: [["1", "x,y"], ["2", "say \"hi\""], ["3", "l1\nl2"]])
                == "a,b\n1,\"x,y\"\n2,\"say \"\"hi\"\"\"\n3,\"l1\nl2\"\n")
    }

    @Test func folderNameUsesUTC() {
        #expect(ExportBundleWriter.folderName(exportTime: Date(timeIntervalSince1970: 1_791_355_333.512))
                == "oxygen-export-20261007-064213")
    }

    @Test func emptyStoreExportsHeadersOnly() throws {
        let folder = try writeExport(rounds: [], records: [], timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.count == 16)
        for type in StrapFetchType.allCases {
            let text = try String(contentsOf: folder.appendingPathComponent(type.exportFileName), encoding: .utf8)
            #expect(text == CSVWriter.render(header: ["timestamp_utc"] + StrapRecordDecoder.fieldNames(for: type), rows: []))
        }
        let manifestData = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        #expect(Set(manifest.keys) == ["app_version", "upstream_kit_commit", "export_time_utc", "time_zone_identifier",
                                       "record_counts", "round_count", "undecodable_round_count"])
        #expect((manifest["record_counts"] as! [String: Int]).values.allSatisfy { $0 == 0 })
        #expect(manifest["time_zone_identifier"] as? String == "Europe/Berlin")
    }

    @Test func timestampsAreUTCInAnyTimeZone() throws {
        let round = StoredRound(fetched: FetchedRound(fetchType: .activity, roundStart: t0, payload: Data([0x01, 0x02, 0x03]),
                                                      receivedAt: t0, nextSince: nil))
        let record = DecodedStrapRecord(fetchType: .activity, timestamp: t0,
                                        fields: StrapRecordDecoder.fieldNames(for: .activity).map { StrapRecordField(name: $0, value: "0") },
                                        receivedAt: t0)
        let folder = try writeExport(rounds: [round], records: [record], timeZone: TimeZone(identifier: "Pacific/Kiritimati")!)
        let activity = try String(contentsOf: folder.appendingPathComponent("activity.csv"), encoding: .utf8)
        #expect(activity.split(separator: "\n")[1].hasPrefix("2026-10-07T06:42:00Z,"))
        let rounds = try String(contentsOf: folder.appendingPathComponent("rounds.csv"), encoding: .utf8)
        #expect(rounds.split(separator: "\n")[1] ==
                "activity,2026-10-07T06:42:00Z,2026-10-07T06:42:00Z,039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81,010203")
    }

    @Test func zipProducesPKArchive() throws {
        let folder = try writeExport(rounds: [], records: [], timeZone: .gmt)
        let zipURL = try ExportBundleWriter.zip(folder: folder)
        #expect(try Data(contentsOf: zipURL).prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
    }
}
