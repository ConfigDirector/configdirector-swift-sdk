import Foundation

struct UserDefaultsCachingProvider: CachingProvider, @unchecked Sendable {
    struct WriteRefused: Error, LocalizedError {
        var errorDescription: String? {
            "UserDefaults did not store the entry: a domain such as a managed configuration overrides it"
        }
    }

    private static let sizeLimitBytes = 256 * 1024

    private let defaults: UserDefaults
    private let key: String

    init(clientSDKKeyDigest: String, defaults: UserDefaults) {
        self.defaults = defaults
        key = "configdirector-sdk.cached-values." + clientSDKKeyDigest
    }

    func read() -> String? {
        defaults.string(forKey: key)
    }

    func write(_ value: String) throws {
        defaults.set(value, forKey: key)
        guard defaults.string(forKey: key) == value else {
            throw WriteRefused()
        }
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }

    func sizeLimit() -> Int {
        Self.sizeLimitBytes
    }
}
