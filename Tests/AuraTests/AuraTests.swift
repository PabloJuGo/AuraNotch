import AuraSuites
import Testing

/// Envoltorio de `swift test` sobre el runner `AuraSelfTests` (ADR 0004). Para ver los fallos en detalle:
/// `swift run AuraSelfTests`.
@Suite struct AuraNotchTests {
    @Test func selfTestsRunner() {
        let r = runSelfTestsSubprocess()
        #expect(r.error == nil, "\(r.error ?? "")")
        #expect(r.status == 0, "AuraSelfTests terminó con \(r.status):\n\(r.failures)\n\(r.tail)")
        #expect(r.hasSummary, "sin resumen de resultados")
    }
}
