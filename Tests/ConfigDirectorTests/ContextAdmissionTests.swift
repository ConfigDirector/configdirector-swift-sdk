@testable import ConfigDirector
import Testing

struct ContextAdmissionTests {
    @Test func admitsNoContext() {
        #expect(ContextAdmission(of: nil) == .admitted(nil))
    }

    @Test func admitsAContextWithoutAContextKind() {
        let context = ConfigDirectorContext(id: "42")

        #expect(ContextAdmission(of: context) == .admitted(context))
    }

    @Test func admitsAContextKindOfLowercaseLettersDigitsDashesAndUnderscores() {
        let context = ConfigDirectorContext(id: "42", kind: "tenant_2-eu")

        #expect(ContextAdmission(of: context) == .admitted(context))
    }

    @Test func admitsAContextKindOf64Characters() {
        let context = ConfigDirectorContext(id: "42", kind: String(repeating: "d", count: 64))

        #expect(ContextAdmission(of: context) == .admitted(context))
    }

    @Test func ignoresAContextKindOf65Characters() {
        let contextKind = String(repeating: "d", count: 65)

        #expect(
            ContextAdmission(of: ConfigDirectorContext(id: "42", kind: contextKind))
                == .ignoredForAnInvalidContextKind(contextKindSample: contextKind)
        )
    }

    @Test func ignoresAnEmptyContextKind() {
        #expect(
            ContextAdmission(of: ConfigDirectorContext(id: "42", kind: ""))
                == .ignoredForAnInvalidContextKind(contextKindSample: "")
        )
    }

    @Test func ignoresAContextKindWithAnUppercaseLetter() {
        #expect(
            ContextAdmission(of: ConfigDirectorContext(id: "42", kind: "Tenant"))
                == .ignoredForAnInvalidContextKind(contextKindSample: "Tenant")
        )
    }

    @Test func ignoresAContextKindWithSurroundingWhitespaceRatherThanTrimmingIt() {
        #expect(
            ContextAdmission(of: ConfigDirectorContext(id: "42", kind: " user"))
                == .ignoredForAnInvalidContextKind(contextKindSample: " user")
        )
    }

    @Test func ignoresAContextKindWithALetterOutsideASCII() {
        #expect(
            ContextAdmission(of: ConfigDirectorContext(id: "42", kind: "dévice"))
                == .ignoredForAnInvalidContextKind(contextKindSample: "dévice")
        )
    }

    @Test func samplesTheFirst128CharactersOfALongerContextKind() {
        let contextKind = String(repeating: "D", count: 129)

        #expect(
            ContextAdmission(of: ConfigDirectorContext(id: "42", kind: contextKind))
                == .ignoredForAnInvalidContextKind(contextKindSample: String(repeating: "D", count: 128))
        )
    }

    @Test func cutsTheSampleOnACharacterBoundary() {
        let contextKind = String(repeating: "🚀", count: 129)

        #expect(
            ContextAdmission(of: ConfigDirectorContext(id: "42", kind: contextKind))
                == .ignoredForAnInvalidContextKind(contextKindSample: String(repeating: "🚀", count: 128))
        )
    }
}
