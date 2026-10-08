import Foundation
import Testing
@testable import Oxygen

struct WatermarkRuleTests {
    let now = Date(timeIntervalSince1970: 1_791_355_320)
    let sevenDaysBack = Date(timeIntervalSince1970: 1_790_750_520)

    @Test func defaultStartIsSevenDaysBack() {
        #expect(WatermarkRule.fetchStart(watermark: nil, now: now) == sevenDaysBack)
    }

    @Test func startsAtWatermarkFlooredToMinute() {
        #expect(WatermarkRule.fetchStart(watermark: Date(timeIntervalSince1970: 1_791_000_030), now: now)
                == Date(timeIntervalSince1970: 1_791_000_000))
    }

    @Test func futureWatermarkBeyondToleranceCountsAsMissing() {
        #expect(WatermarkRule.fetchStart(watermark: now.addingTimeInterval(300), now: now) == now)
        #expect(WatermarkRule.fetchStart(watermark: now.addingTimeInterval(301), now: now) == sevenDaysBack)
    }

    @Test func neverMoreThanThirtyDaysBack() {
        #expect(WatermarkRule.fetchStart(watermark: now.addingTimeInterval(-40 * 86_400), now: now)
                == Date(timeIntervalSince1970: 1_788_763_320))
    }

    @Test func advanceFollowsUpstreamCursorRule() {
        let earlier = Date(timeIntervalSince1970: 1_791_000_000)
        #expect(WatermarkRule.advanced(previous: nil, nextSince: earlier, now: now) == earlier)
        #expect(WatermarkRule.advanced(previous: nil, nextSince: now.addingTimeInterval(3600), now: now) == now)
        #expect(WatermarkRule.advanced(previous: now, nextSince: earlier, now: now) == now)
        #expect(WatermarkRule.advanced(previous: earlier, nextSince: nil, now: now) == earlier)
        #expect(WatermarkRule.advanced(previous: nil, nextSince: nil, now: now) == nil)
    }
}
