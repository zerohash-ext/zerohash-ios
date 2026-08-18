import Testing
import Foundation
@testable import ZerohashSDK

@Suite("Automation error descriptions")
struct AutomationErrorDescriptionTests {

    @Test("a runner timeout names the stage that expired")
    func timeoutNamesStage() {
        #expect(RunnerError.timeout(stage: .initialLoad).localizedDescription
                == "timeout: initialLoad")
        #expect(RunnerError.timeout(stage: .scriptEvaluation).localizedDescription
                == "timeout: scriptEvaluation")
        #expect(RunnerError.timeout(stage: .navigationSettle).localizedDescription
                == "timeout: navigationSettle")
    }

    @Test("a load failure carries WebKit's own reason")
    func loadFailedCarriesDetail() {
        #expect(RunnerError.loadFailed("The Internet connection appears to be offline.")
                    .localizedDescription
                == "loadFailed: The Internet connection appears to be offline.")
    }

    @Test("navigationLost and hostUnavailable read as their case names")
    func caseNames() {
        #expect(RunnerError.navigationLost.localizedDescription == "navigationLost")
        #expect(ContextError.hostUnavailable.localizedDescription == "hostUnavailable")
    }

    @Test("no automation error surfaces Foundation's placeholder text")
    func noPlaceholderText() {
        let errors: [Error] = [
            RunnerError.timeout(stage: .initialLoad),
            RunnerError.timeout(stage: .scriptEvaluation),
            RunnerError.timeout(stage: .navigationSettle),
            RunnerError.loadFailed("boom"),
            RunnerError.navigationLost,
            ContextError.hostUnavailable,
            AutomatedRunError.timeout,
            AutomatedRunError.loadFailed("boom"),
            AutomatedRunError.abandoned,
        ]
        for e in errors {
            let d = e.localizedDescription
            #expect(!d.contains("couldn't be completed"), "placeholder text leaked: \(d)")
            #expect(!d.contains("error 0"), "case index leaked: \(d)")
        }
    }

    @Test("both runners spell a load failure the same way")
    func runnersAgreeOnLoadFailed() {
        #expect(RunnerError.loadFailed("x").localizedDescription.hasPrefix("loadFailed"))
        #expect(AutomatedRunError.loadFailed("x").localizedDescription.hasPrefix("loadFailed"))
    }
}
