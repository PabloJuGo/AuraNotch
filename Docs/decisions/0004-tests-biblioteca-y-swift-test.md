# ADR 0004 — Suites en biblioteca, runner y `swift test`

- **Contexto:** ADR 0001 dejó un runner con aserciones propio porque las CLT no traen XCTest. Las CLT sí traen `Testing.framework` (Swift Testing) en `/Library/Developer/CommandLineTools/Library/Developer/Frameworks`, pero `swift test` no lo enlaza solo.
- **Decisión:** las suites viven en la biblioteca `AuraSuites` (`Tests/Suites`). `AuraSelfTests` (ejecutable) las corre en el hilo principal; `AuraTests` (Swift Testing) lanza ese ejecutable como subproceso y exige salida 0.
- **Por qué subproceso y no ejecutar las suites dentro de Swift Testing:** probado; las suites de integración (RunLoop, NSPanel, actores) fallan dentro del ejecutor de Swift Testing (p. ej. altas de la shelf devuelven 0). El subproceso conserva el hilo principal real.
- **Limitación:** `import Foundation` + `import Testing` falla en las CLT (`_Testing_Foundation` no resuelve), por eso la lógica con Foundation está en `Tests/Suites/SubprocessRunner.swift`.
- **Cómo ejecutar:** `swift run AuraSelfTests` (detalle de fallos) o `swift test`. Con las solas CLT, `swift test` necesita: `-Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F` con `F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks`. Con Xcode (licencia aceptada) basta `swift test`.
