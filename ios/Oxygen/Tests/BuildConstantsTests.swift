import Testing
@testable import Oxygen

struct BuildConstantsTests {
    @Test func upstreamCommitIsFullSHA1() {
        let commit = BuildConstants.upstreamKitCommit
        #expect(commit.count == 40)
        #expect(commit.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
