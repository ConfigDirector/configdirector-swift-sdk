import Foundation

final class InvalidContextSubmissions: Sendable {
    private struct State {
        var countsByContextKindSample: [String: Int] = [:]
        var countBeyondSampleLimit = 0
        var startTime: Date?
    }

    private static let contextKindSampleLimit = 20

    private let state = Locked(State())

    func record(contextKindSample: String) {
        state.withLock { state in
            if state.startTime == nil {
                state.startTime = Date()
            }

            let isAlreadySampled = state.countsByContextKindSample[contextKindSample] != nil
            let hasRoomForAnotherSample = state.countsByContextKindSample.count < Self.contextKindSampleLimit
            if isAlreadySampled || hasRoomForAnotherSample {
                state.countsByContextKindSample[contextKindSample, default: 0] += 1
            } else {
                state.countBeyondSampleLimit += 1
            }
        }
    }

    func takeAggregated() -> [AggregatedEvent<InvalidContextSubmission>] {
        let endTime = Date()

        let collected = state.exchange(\.self, with: State())
        let startTime = collected.startTime ?? endTime

        let sampled = collected.countsByContextKindSample.map { contextKindSample, count in
            AggregatedEvent(
                startTime: startTime,
                endTime: endTime,
                count: count,
                event: InvalidContextSubmission.sampled(contextKindSample: contextKindSample)
            )
        }
        let beyondSampleLimit = collected.countBeyondSampleLimit > 0
            ? [AggregatedEvent(
                startTime: startTime,
                endTime: endTime,
                count: collected.countBeyondSampleLimit,
                event: InvalidContextSubmission.beyondContextKindSampleLimit
            )]
            : []

        return sampled + beyondSampleLimit
    }

    func clear() {
        state.withLock { $0 = State() }
    }
}
