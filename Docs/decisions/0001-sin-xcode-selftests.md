# ADR 0001 — Toolchain sin Xcode: SwiftPM + runner de aserciones

- **Contexto (24-10-2026):** el Mac de desarrollo (macOS 27.0.1, M4, notch con `safeAreaInsets.top = 33.5 pt`) solo tiene Command Line Tools (Swift 6.2.3). No existen los módulos `XCTest` ni `Testing`, ni `xcodebuild`, ni Instruments.
- **Decisión:** proyecto como Swift Package (`swift build`), tests como ejecutable `AuraSelfTests` (`swift run AuraSelfTests`) con `SelfCheck` de AuraCore. Migrables a XCTest sin cambiar la lógica cuando haya Xcode.
- **Consecuencias:** sin firma/notarización ni profiling con Instruments hasta instalar Xcode (ver DECISIONES.md).
