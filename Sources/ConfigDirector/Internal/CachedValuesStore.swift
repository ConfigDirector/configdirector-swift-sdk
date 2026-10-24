import Foundation

final class CachedValuesStore: Sendable {
    private struct PendingWrite {
        var queued: CachedValues?
        var isWriting = false
    }

    private let provider: any CachingProvider
    private let clientSDKKey: String
    private let instanceID: String
    private let warnings: CachingWarnings
    private let pendingWrite = Locked(PendingWrite())
    private let pendingRead: Task<CachedValuesRead, Never>

    init(
        provider: any CachingProvider,
        clientSDKKey: String,
        instanceID: String,
        logger: any ConfigDirectorLogger
    ) {
        self.provider = provider
        self.clientSDKKey = clientSDKKey
        self.instanceID = instanceID
        let warnings = CachingWarnings(logger: logger)
        self.warnings = warnings
        pendingRead = Task {
            await Self.readEntry(from: provider, for: clientSDKKey, warnings: warnings)
        }
    }

    func read() async -> CachedValuesRead {
        await pendingRead.value
    }

    func contextTag(for context: ConfigDirectorContext?) -> ContextTag {
        ContextTag(context: context, instanceID: instanceID)
    }

    func replace(_ cachedValues: CachedValues) {
        let startsWriting = pendingWrite.withLock { pending -> Bool in
            pending.queued = cachedValues
            guard !pending.isWriting else { return false }
            pending.isWriting = true
            return true
        }
        guard startsWriting else { return }

        Task { await writeQueued() }
    }

    private func writeQueued() async {
        while let next = takeQueued() {
            await writeEntry(next)
        }
    }

    private func takeQueued() -> CachedValues? {
        pendingWrite.withLock { pending in
            defer { pending.queued = nil }
            if pending.queued == nil {
                pending.isWriting = false
            }
            return pending.queued
        }
    }

    private func writeEntry(_ cachedValues: CachedValues) async {
        let serialized: Data
        do {
            serialized = try CachedValuesEntry(clientSDKKey: clientSDKKey, cachedValues: cachedValues)
                .serialized()
        } catch {
            warnings.warnOnce(.writeFailed, "Could not keep the values on the device", error: error)
            return
        }

        let limit = provider.sizeLimit()
        if serialized.count > limit {
            warnings.warnOnce(.overTheSizeLimit, """
            The values received (\(serialized.count) bytes) exceed the caching provider's limit of \(limit) \
            bytes, so no values are kept on the device
            """)
            await Self.removeEntry(from: provider, warnings: warnings)
            return
        }

        do {
            try await provider.write(String(decoding: serialized, as: UTF8.self))
        } catch {
            warnings.warnOnce(.writeFailed, "Could not keep the values on the device", error: error)
        }
    }

    private static func readEntry(
        from provider: any CachingProvider,
        for clientSDKKey: String,
        warnings: CachingWarnings
    ) async -> CachedValuesRead {
        let stored: String?
        do {
            stored = try await provider.read()
        } catch {
            warnings.warnOnce(
                .readFailed,
                "Could not read the values kept on the device, starting without them",
                error: error
            )
            return .storageFailed
        }
        guard let stored, !stored.isEmpty else { return .nothingStored }

        guard let cachedValues = CachedValuesEntry.cachedValues(in: stored, for: clientSDKKey) else {
            warnings.warnOnce(.notAnEntry, """
            The values kept on the device could not be read and were removed, starting without them
            """)
            await removeEntry(from: provider, warnings: warnings)
            return .notAnEntry
        }
        return .stored(cachedValues)
    }

    private static func removeEntry(from provider: any CachingProvider, warnings: CachingWarnings) async {
        do {
            try await provider.remove()
        } catch {
            warnings.warnOnce(.removeFailed, "Could not remove the values kept on the device", error: error)
        }
    }
}

final class CachingWarnings: Sendable {
    enum Kind: Hashable {
        case readFailed
        case notAnEntry
        case overTheSizeLimit
        case writeFailed
        case removeFailed
    }

    private let logger: any ConfigDirectorLogger
    private let warned = Locked<Set<Kind>>([])

    init(logger: any ConfigDirectorLogger) {
        self.logger = logger
    }

    func warnOnce(_ kind: Kind, _ message: String, error: (any Error)? = nil) {
        let isFirst = warned.withLock { $0.insert(kind).inserted }
        guard isFirst else { return }
        logger.warn(message, error: error)
    }
}
