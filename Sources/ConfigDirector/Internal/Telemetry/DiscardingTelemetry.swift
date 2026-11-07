import Foundation

struct DiscardingTelemetry: TelemetryClient {
    func evaluatedConfig(_: EvaluatedConfigEvent) {}

    func recordInvalidContextSubmission(contextKindSample _: String) {}

    func trackedEvent(_: TrackedEventAdmission, context _: ConfigDirectorContext?) {}

    func updateContext(_: ConfigDirectorContext?) {}

    func flush() async {}

    func close() {}
}
