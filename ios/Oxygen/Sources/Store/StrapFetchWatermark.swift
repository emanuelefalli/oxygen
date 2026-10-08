import Foundation
import SwiftData

@Model final class StrapFetchWatermark {
    @Attribute(.unique) var fetchTypeCode: Int
    var watermark: Date

    init(fetchTypeCode: Int, watermark: Date) {
        self.fetchTypeCode = fetchTypeCode
        self.watermark = watermark
    }
}
