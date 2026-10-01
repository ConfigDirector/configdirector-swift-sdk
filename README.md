# ConfigDirector Swift SDK

[![CI][ci-badge]][ci] [![Release][release-badge]][release]

Swift SDK for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with typed values, JSON Schema validation, and safe renames of live flags. Start free, no card required.

It supports iOS, iPadOS, macOS, tvOS, and watchOS.

## Install

In Xcode, go to **File → Add Package Dependencies…** and enter the package URL `https://github.com/ConfigDirector/configdirector-swift-sdk`. In a Swift package, declare it in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ConfigDirector/configdirector-swift-sdk", from: "1.7.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [.product(name: "ConfigDirector", package: "configdirector-swift-sdk")]
    ),
    .testTarget(
        name: "YourTargetTests",
        dependencies: [
            "YourTarget",
            .product(name: "ConfigDirectorTesting", package: "configdirector-swift-sdk"),
        ]
    ),
]
```

The package has two products: `ConfigDirector`, the SDK, and `ConfigDirectorTesting`, tools for testing the code that reads your configs, which only test targets link.

## Retrieve a value

```swift
import ConfigDirector

let client = try ConfigDirectorClient(clientSDKKey: "YOUR-CLIENT-SDK-KEY")
await client.initialize()

let darkMode = client.value(for: "dark-mode", default: false)
```

Full details are in the [official documentation](https://docs.configdirector.com/sdks/mobile/swift).

## Test your code

`ConfigDirectorTesting` creates a **test client**: the SDK's real client connected to an in-memory server that your test controls. No network connection is opened and no telemetry is sent.

```swift
import ConfigDirectorTesting

let testClient = makeTestClient(values: ["dark-mode": true, "max-items": 20])
await testClient.client.initialize()

let settings = Settings(client: testClient.client)
#expect(settings.isDarkMode)

testClient.setValue(false, for: "dark-mode")
#expect(!settings.isDarkMode)
```

`testClient.client` is a `ConfigDirectorClient`, so it goes anywhere your code accepts one. See [Test your code](https://docs.configdirector.com/sdks/mobile/swift#test-your-code) in the documentation for holding and failing initialization, watching values under test, and what to expect.

## Documentation

Refer to the [official documentation for the Swift SDK](https://docs.configdirector.com/sdks/mobile/swift).

There is also [a quickstart guide for ConfigDirector and any of our SDKs](https://docs.configdirector.com/getting-started/quickstart).

## Sample apps

[`Samples/`](Samples/) holds four SwiftUI apps built on this SDK — one each for iOS and iPadOS,
macOS, tvOS, and watchOS — sharing a single set of SDK-facing code so they differ only in layout.
Open the project and pick a scheme:

```bash
open Samples/ConfigDirectorSample.xcodeproj
```

They depend on this SDK as a released package, exactly as your own app would. To build them
against a checkout of this repository instead, open
[`Samples/ConfigDirectorSample-Local.xcworkspace`](Samples/ConfigDirectorSample-Local.xcworkspace).

See [`Samples/README.md`](Samples/README.md) to point them at your own ConfigDirector project.

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[ci-badge]: https://github.com/ConfigDirector/configdirector-swift-sdk/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/ConfigDirector/configdirector-swift-sdk/actions/workflows/ci.yml
[release-badge]: https://img.shields.io/github/v/release/ConfigDirector/configdirector-swift-sdk
[release]: https://github.com/ConfigDirector/configdirector-swift-sdk/releases
