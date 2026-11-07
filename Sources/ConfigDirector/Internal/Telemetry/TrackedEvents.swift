import Foundation

struct TrackedEventEntry: Encodable, Sendable {
    var name: String
    var contextKind: String?
    var contextIdentifier: String?
    var value: TrackedEventValue?
    var details: TrackedEventDetails?
    var happenedAt: String
}

enum TrackedEventWarning: Hashable, Sendable {
    case nameOutsideTheCharacterLimit
    case valueNotAFiniteNumber
    case detailsNotReportable
    case batchAlreadyFull

    var message: String {
        switch self {
        case .nameOutsideTheCharacterLimit:
            """
            [ConfigDirectorClient] A tracked event was not reported because its name does not have 1 \
            to \(TrackedEventAdmission.nameMaximumCharacters) characters.
            """
        case .valueNotAFiniteNumber:
            """
            [ConfigDirectorClient] A tracked event was reported without its value because the value \
            is not a finite number.
            """
        case .detailsNotReportable:
            """
            [ConfigDirectorClient] A tracked event was reported without its details because they \
            have more than \(TrackedEventAdmission.detailsMaximumTopLevelKeys) top-level keys or are \
            larger than \(TrackedEventAdmission.detailsMaximumJSONBytes) bytes as JSON.
            """
        case .batchAlreadyFull:
            """
            [ConfigDirectorClient] A tracked event was not reported because \
            \(TrackedEventQueue.entriesPerBatch) tracked events are already waiting for the next \
            telemetry batch.
            """
        }
    }
}

enum TrackedEventAdmission: Sendable {
    case admitted(TrackedEventEntry, warnings: [TrackedEventWarning])
    case dropped(TrackedEventWarning)

    fileprivate static let nameMaximumCharacters = 150
    fileprivate static let detailsMaximumTopLevelKeys = 20
    fileprivate static let detailsMaximumJSONBytes = 1024

    init(name: String, context: ConfigDirectorContext?, options: TrackOptions?, happenedAt: Date) {
        guard (1 ... Self.nameMaximumCharacters).contains(name.unicodeScalars.count) else {
            self = .dropped(.nameOutsideTheCharacterLimit)
            return
        }

        let reportedContext = Self.reportedContext(of: context)
        let value = options?.value
        let details = options?.details?.mapValues(\.asSent)
        let isValueReportable = value?.isFinite ?? true
        let areDetailsReportable = details.map(Self.isWithinTheLimits) ?? true

        self = .admitted(
            TrackedEventEntry(
                name: name,
                contextKind: reportedContext?.kind,
                contextIdentifier: reportedContext?.identifier,
                value: isValueReportable ? value : nil,
                details: areDetailsReportable ? details : nil,
                happenedAt: happenedAt.telemetryTimestamp
            ),
            warnings: [
                isValueReportable ? nil : .valueNotAFiniteNumber,
                areDetailsReportable ? nil : .detailsNotReportable,
            ].compactMap(\.self)
        )
    }

    var warnings: [TrackedEventWarning] {
        switch self {
        case let .admitted(_, warnings): warnings
        case let .dropped(warning): [warning]
        }
    }

    private static func reportedContext(
        of context: ConfigDirectorContext?
    ) -> (kind: String, identifier: String)? {
        guard let context, context.isAnonymous != true, let identifier = context.id else { return nil }

        return (kind: context.kind ?? ConfigDirectorContext.defaultKind, identifier: identifier)
    }

    private static func isWithinTheLimits(_ details: TrackedEventDetails) -> Bool {
        guard details.count <= detailsMaximumTopLevelKeys,
              let json = try? JSONEncoder.forTelemetryReports().encode(details)
        else { return false }

        return json.count <= detailsMaximumJSONBytes
    }
}

private extension TrackedEventValue {
    var isFinite: Bool {
        switch self {
        case .int: true
        case let .double(value): value.isFinite
        case let .decimal(value): value.isFinite
        }
    }
}
