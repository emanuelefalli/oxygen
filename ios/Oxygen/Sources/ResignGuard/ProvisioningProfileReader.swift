import Foundation

enum ProvisioningProfileReader {
    private static let plistStart = Data("<?xml".utf8)
    private static let plistEnd = Data("</plist>".utf8)

    static func expirationDate(fromProfileData data: Data) -> Date? {
        guard let startRange = data.range(of: plistStart) else { return nil }
        guard let endRange = data.range(of: plistEnd, in: startRange.lowerBound..<data.endIndex) else { return nil }
        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }

    static func embeddedProfileExpirationDate(bundle: Bundle) -> Date? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(fromProfileData: data)
    }
}
