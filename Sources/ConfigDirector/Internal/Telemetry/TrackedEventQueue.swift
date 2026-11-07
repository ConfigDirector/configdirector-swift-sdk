final class TrackedEventQueue: Sendable {
    private struct State {
        var entries: [TrackedEventEntry] = []
        var warningsRaisedThisBatch: Set<TrackedEventWarning> = []

        mutating func warningsOfKeeping(_ admission: TrackedEventAdmission) -> [TrackedEventWarning] {
            switch admission {
            case let .dropped(warning):
                return [warning]
            case let .admitted(entry, warnings):
                guard entries.count < TrackedEventQueue.entriesPerBatch else { return [.batchAlreadyFull] }
                entries.append(entry)
                return warnings
            }
        }
    }

    static let entriesPerBatch = 1000

    private let state = Locked(State())

    func add(_ admission: TrackedEventAdmission) -> [TrackedEventWarning] {
        state.withLock { state in
            state.warningsOfKeeping(admission).filter { state.warningsRaisedThisBatch.insert($0).inserted }
        }
    }

    func takeBatch() -> [TrackedEventEntry] {
        state.exchange(\.self, with: State()).entries
    }

    func clear() {
        state.withLock { $0 = State() }
    }
}
