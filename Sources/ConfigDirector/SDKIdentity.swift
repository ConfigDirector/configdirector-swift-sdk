/// The name and version a ConfigDirector wrapper reports to the server in place of this SDK's own.
///
/// Only wrappers maintained by ConfigDirector are represented, which is why there is no initializer
/// taking an arbitrary name.
@_spi(ConfigDirectorWrapper)
public struct SDKIdentity: Sendable {
    let name: String
    let version: String

    static let swiftClientSDK = SDKIdentity(name: Constants.sdkName, version: Constants.sdkVersion)

    /// The ConfigDirector OpenFeature provider for Swift, at `version`.
    public static func openFeatureProvider(version: String) -> SDKIdentity {
        SDKIdentity(name: "swift-openfeature-client-provider", version: version)
    }
}
