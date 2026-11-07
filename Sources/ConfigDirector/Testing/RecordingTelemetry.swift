package typealias TrackedEventRecorder = @Sendable (
    _ name: String,
    _ context: ConfigDirectorContext?,
    _ value: TrackedEventValue?,
    _ details: TrackedEventDetails?
) -> Void

struct RecordingTelemetry: TelemetryClient {
    let logger: any ConfigDirectorLogger
    let record: TrackedEventRecorder

    func trackedEvent(_ admission: TrackedEventAdmission, context: ConfigDirectorContext?) {
        for warning in admission.warnings {
            logger.warn(warning.message)
        }

        switch admission {
        case .dropped:
            break
        case let .admitted(entry, _):
            record(entry.name, context, entry.value, entry.details)
        }
    }

    func evaluatedConfig(_: EvaluatedConfigEvent) {}

    func recordInvalidContextSubmission(contextKindSample _: String) {}

    func updateContext(_: ConfigDirectorContext?) {}

    func flush() async {}

    func close() {}
}
