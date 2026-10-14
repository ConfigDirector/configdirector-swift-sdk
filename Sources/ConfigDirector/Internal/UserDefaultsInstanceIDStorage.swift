import Foundation

/// Keeps the instance ID record in the app's own `UserDefaults`, which lives in the app container
/// and goes away with an uninstall, so a session never outlives the install.
///
/// `UserDefaults` is documented as thread-safe but is not marked `Sendable`.
struct UserDefaultsInstanceIDStorage: InstanceIDStorage, @unchecked Sendable {
    private static let key = "configdirector-sdk.instance-id"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func read() -> String? {
        defaults.string(forKey: Self.key)
    }

    /// `UserDefaults` reports nothing about a write, so the record is read back: a value another
    /// domain overrides, such as a managed configuration, comes back as that value instead.
    func write(_ record: String) -> Bool {
        defaults.set(record, forKey: Self.key)
        return defaults.string(forKey: Self.key) == record
    }
}
