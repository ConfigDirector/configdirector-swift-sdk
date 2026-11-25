import Foundation

enum ContextSizeLimit: Sendable {
    case identifier
    case name
    case traits
}

enum ContextAdmission: Equatable {
    case admitted(ConfigDirectorContext?)
    case ignoredForAnInvalidContextKind(contextKindSample: String)
    case ignoredOverAContextSizeLimit(ContextSizeLimit)

    private static let contextKindMaximumCharacters = 64
    private static let contextKindSampleMaximumCharacters = 128
    private static let identifierMaximumCharacters = 256
    private static let nameMaximumCharacters = 256
    private static let traitsMaximumJSONBytes = 65536

    init(of context: ConfigDirectorContext?) {
        if let contextKind = context?.kind, !Self.isValid(contextKind) {
            self = .ignoredForAnInvalidContextKind(contextKindSample: Self.sample(of: contextKind))
        } else if let sizeLimit = context.flatMap(Self.firstSizeLimitExceeded) {
            self = .ignoredOverAContextSizeLimit(sizeLimit)
        } else {
            self = .admitted(context)
        }
    }

    private static func isValid(_ contextKind: String) -> Bool {
        (1 ... contextKindMaximumCharacters).contains(contextKind.unicodeScalars.count)
            && contextKind.unicodeScalars.allSatisfy(isContextKindCharacter)
    }

    private static func isContextKindCharacter(_ character: Unicode.Scalar) -> Bool {
        ("a" ... "z").contains(character)
            || ("0" ... "9").contains(character)
            || character == "-"
            || character == "_"
    }

    private static func sample(of contextKind: String) -> String {
        let firstCharacters = contextKind.unicodeScalars.prefix(contextKindSampleMaximumCharacters)
        return String(String.UnicodeScalarView(firstCharacters))
    }

    private static func firstSizeLimitExceeded(by context: ConfigDirectorContext) -> ContextSizeLimit? {
        if hasMoreCharacters(than: identifierMaximumCharacters, in: context.id) {
            return .identifier
        }
        if hasMoreCharacters(than: nameMaximumCharacters, in: context.name) {
            return .name
        }
        if hasMoreJSONBytes(than: traitsMaximumJSONBytes, in: context.traits) {
            return .traits
        }
        return nil
    }

    private static func hasMoreCharacters(than maximumCharacters: Int, in text: String?) -> Bool {
        (text?.unicodeScalars.count ?? 0) > maximumCharacters
    }

    private static func hasMoreJSONBytes(
        than maximumBytes: Int,
        in traits: [String: ConfigDirectorContext.TraitValue]?
    ) -> Bool {
        guard let traits, let json = try? JSONEncoder.forTransportPayloads().encode(traits) else {
            return false
        }
        return json.count > maximumBytes
    }
}
