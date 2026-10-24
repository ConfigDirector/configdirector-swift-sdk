import Foundation

/// A store for the values the client keeps on the device between launches.
///
/// The client keeps the last values it received from ConfigDirector as one string whose format
/// belongs to the SDK, and reads it back on the next launch. Implement this to keep that string
/// somewhere other than `UserDefaults`, for example in an encrypted store, or to allow a larger
/// entry than the default store does. One instance serves one client.
///
/// A provider never stops the client: a `read` that throws is logged once and the client starts
/// without kept values, and a `write` or `remove` that throws is logged once and leaves the entry
/// that was there.
public protocol CachingProvider: Sendable {
    /// The stored entry, or `nil` when nothing is stored.
    func read() async throws -> String?

    /// Replaces the stored entry with `value`.
    func write(_ value: String) async throws

    /// Removes the stored entry, if any.
    func remove() async throws

    /// The largest entry, in bytes, the store accepts. The client measures every entry against it
    /// before writing, and removes the entry instead when it is larger.
    func sizeLimit() -> Int
}

/// Whether, and where, the client keeps the last values it received on the device, to serve them
/// on the next launch of the same context until live values arrive. See
/// ``ConfigDirectorClientOptions/caching``.
public struct CachingOptions: Sendable {
    /// Whether to keep the last values received. With `false`, nothing is read or written, even
    /// when a ``provider`` is given. Defaults to `true`.
    public var enabled: Bool

    /// The store for the values. Defaults to the app's `UserDefaults`, under a key derived from
    /// the client SDK key, with a size limit of 256 KB.
    public var provider: (any CachingProvider)?

    public init(enabled: Bool = true, provider: (any CachingProvider)? = nil) {
        self.enabled = enabled
        self.provider = provider
    }
}
