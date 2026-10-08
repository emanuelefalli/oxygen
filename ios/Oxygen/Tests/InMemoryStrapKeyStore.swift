@testable import Oxygen

final class InMemoryStrapKeyStore: StrapKeyStoring {
    private var key: StrapAuthKey?
    private var rejected = false

    init(key: StrapAuthKey?) {
        self.key = key
    }

    func load() throws -> StrapAuthKey? {
        key
    }

    func save(_ key: StrapAuthKey) throws {
        self.key = key
        rejected = false
    }

    func markRejected() throws {
        rejected = true
    }

    func isRejected() throws -> Bool {
        rejected
    }
}
