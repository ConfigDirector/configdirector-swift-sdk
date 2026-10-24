import Foundation
import Testing

/// The parent of every suite that touches `UserDefaults`. Serialized because the argument domain a
/// write-refusal test overrides is shared by the whole process, so no two of these tests may run at
/// once, whichever suite they belong to.
@Suite(.serialized)
enum UserDefaultsStorageTests {
    /// A suite of its own in a temporary directory: `UserDefaults` takes a path as a suite name and
    /// keeps the plist there, so the test leaves nothing in the user's Preferences folder.
    static func withDefaults<Outcome>(
        _ body: (UserDefaults) async throws -> Outcome
    ) async throws -> Outcome {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("configdirector-sdk-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try #require(
            UserDefaults(suiteName: directory.appendingPathComponent("storage.plist").path)
        )

        return try await body(defaults)
    }
}
