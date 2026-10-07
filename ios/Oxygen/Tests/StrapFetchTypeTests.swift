import Testing
@testable import Oxygen

struct StrapFetchTypeTests {
    @Test func syncOrderIsAscendingCodes() {
        #expect(StrapFetchType.syncOrder.map(\.rawValue) ==
                [0x01, 0x02, 0x0d, 0x12, 0x13, 0x25, 0x26, 0x2e, 0x38, 0x3a, 0x3d, 0x48, 0x49])
    }

    @Test func nextInSyncOrder() {
        #expect(StrapFetchType.temperature.nextInSyncOrder == .sleepRespiratoryRate)
        #expect(StrapFetchType.heartRateVariability.nextInSyncOrder == nil)
    }

    @Test func exportFileName() {
        #expect(StrapFetchType.heartRateVariability.exportFileName == "heartRateVariability.csv")
    }
}
