import Foundation

final class InvalidContextSubmissions: Sendable {
    private struct State {
        var countsByContextKindSample: [String: Int] = [:]
        var countBeyondSampleLimit = 0
        var countsByContextSizeLimit: [ContextSizeLimit: Int] = [:]
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

    func record(contextSizeLimit: ContextSizeLimit) {
        state.withLock { state in
            if state.startTime == nil {
                state.startTime = Date()
            }

            state.countsByContextSizeLimit[contextSizeLimit, default: 0] += 1
        }
    }

    func takeAggregated() -> [AggregatedEvent<InvalidContextSubmission>] {
        let endTime = Date()

        let collected = state.exchange(\.self, with: State())
        let startTime = collected.startTime ?? endTime

        let entry = { (count: Int, event: InvalidContextSubmission) in
            AggregatedEvent(startTime: startTime, endTime: endTime, count: count, event: event)
        }

        let sampled = collected.countsByContextKindSample.map { contextKindSample, count in
            entry(count, .sampled(contextKindSample: contextKindSample))
        }
        let beyondSampleLimit = collected.countBeyondSampleLimit > 0
            ? [entry(collected.countBeyondSampleLimit, .beyondContextKindSampleLimit)]
            : []
        let overContextSizeLimits = collected.countsByContextSizeLimit.map { sizeLimit, count in
            entry(count, .overContextSizeLimit(sizeLimit))
        }

        return sampled + beyondSampleLimit + overContextSizeLimits
    }

    func clear() {
        state.withLock { $0 = State() }
    }
}
