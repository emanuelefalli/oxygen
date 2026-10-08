// Adapted from ios/OpenCircuitKit/Sources/ZeppKit/HelioSyncPolicy.swift at upstream 63e2796d323cea42d4835cf364bd0a4ebfa99682.
import Foundation
import ZeppKit

enum WatermarkRule {
    static func fetchStart(watermark: Date?, now: Date) -> Date {
        let first = HelioFetchPlan.floorToMinute(now.addingTimeInterval(-HelioFetchPlan.firstSyncLookback))
        guard let watermark, watermark <= now.addingTimeInterval(HelioFetchPlan.futureTolerance) else {
            return first
        }
        let oldest = HelioFetchPlan.floorToMinute(now.addingTimeInterval(-HelioFetchPlan.maxLookback))
        let latest = HelioFetchPlan.floorToMinute(now)
        return min(max(HelioFetchPlan.floorToMinute(watermark), oldest), latest)
    }

    static func advanced(previous: Date?, nextSince: Date?, now: Date) -> Date? {
        guard let nextSince else {
            return previous
        }
        let clamped = min(nextSince, HelioFetchPlan.floorToMinute(now))
        guard let previous else {
            return clamped
        }
        return max(previous, clamped)
    }
}
