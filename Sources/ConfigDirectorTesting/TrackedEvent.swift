import ConfigDirector

/// An event the code under test tracked, as a test client recorded it.
public struct TrackedEvent: Sendable, Equatable {
    /// The name the event was tracked with.
    public let name: String

    /// The context the client had when the event was tracked, if any.
    public let context: ConfigDirectorContext?

    /// The value the event was tracked with, when it is a finite number.
    public let value: TrackedEventValue?

    /// The details the event was tracked with, as the SDK sends them, when they are within the limits.
    public let details: TrackedEventDetails?

    public init(
        name: String,
        context: ConfigDirectorContext? = nil,
        value: TrackedEventValue? = nil,
        details: TrackedEventDetails? = nil
    ) {
        self.name = name
        self.context = context
        self.value = value
        self.details = details
    }
}
