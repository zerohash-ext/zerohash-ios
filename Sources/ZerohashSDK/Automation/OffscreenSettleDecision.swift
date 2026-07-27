import Foundation

/// Decision returned by the settle predicate after each `didFinish` of an
/// offscreen probe. See `OffscreenWebViewRunner.run(url:settle:script:timeoutMs:)`.
public enum OffscreenSettleDecision {
    case waitMore
    case evaluate
    case answer(Any?)
}
