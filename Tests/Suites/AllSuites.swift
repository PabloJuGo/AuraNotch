import AuraCore

/// Todas las suites en un punto único: las ejecutan `swift run AuraSelfTests` y `swift test` (ADR 0004).
/// Debe llamarse en el hilo principal (las suites usan AppKit/SwiftUI y el RunLoop principal).
@MainActor public func runAllSuites(_ t: SelfCheck) {
    t.expect(NotchModule.allCases.count == 6, "módulos")
    runDesignSuite(t)
    runSurfaceSuite(t)
    runShelfSuite(t)
    runPreferencesSuite(t)
    runQASuite(t)
    runMediaSuite(t)
    runWidgetsSuite(t)
    runCalendarSuite(t)
    runHomeSuite(t)
    runClipboardSuite(t)
    runAlertsSuite(t)
    runAccessibilitySuite(t)
}
