import Foundation
import ZeppKit

struct StrapAuthKey: Equatable, Sendable {
    static let byteCount = 16

    let bytes: Data
    let zeppAuthKey: ZeppAuthKey

    init?(bytes: Data) {
        guard bytes.count == Self.byteCount, let zeppAuthKey = ZeppAuthKey(bytes: [UInt8](bytes)) else { return nil }
        self.bytes = bytes
        self.zeppAuthKey = zeppAuthKey
    }

    static func parse(_ text: String) -> StrapAuthKey? {
        guard let normalized = HelioKeyText.normalized(text) else { return nil }
        guard let digits = ZeppHex.bytes(normalized) else { return nil }
        return StrapAuthKey(bytes: Data(digits))
    }

    var hexString: String { ZeppHex.string(bytes) }
}

extension StrapAuthKey: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "StrapAuthKey(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}
