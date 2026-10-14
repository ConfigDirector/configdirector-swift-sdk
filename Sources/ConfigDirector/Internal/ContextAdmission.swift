enum ContextAdmission: Equatable {
    case admitted(ConfigDirectorContext?)
    case ignoredForAnInvalidContextKind(contextKindSample: String)

    private static let contextKindMaximumCharacters = 64
    private static let contextKindSampleMaximumCharacters = 128

    init(of context: ConfigDirectorContext?) {
        switch context?.kind {
        case .none:
            self = .admitted(context)
        case let .some(contextKind) where Self.isValid(contextKind):
            self = .admitted(context)
        case let .some(contextKind):
            self = .ignoredForAnInvalidContextKind(contextKindSample: Self.sample(of: contextKind))
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
}
