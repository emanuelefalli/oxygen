import Foundation

struct ExportManifest: Encodable, Equatable {
    let appVersion: String
    let upstreamKitCommit: String
    let exportTimeUTC: String
    let timeZoneIdentifier: String
    let recordCounts: [String: Int]
    let roundCount: Int
    let undecodableRoundCount: Int

    private enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case upstreamKitCommit = "upstream_kit_commit"
        case exportTimeUTC = "export_time_utc"
        case timeZoneIdentifier = "time_zone_identifier"
        case recordCounts = "record_counts"
        case roundCount = "round_count"
        case undecodableRoundCount = "undecodable_round_count"
    }

    func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
