import Foundation

public struct SelfTestRun: Sendable {
    public var status: Int32
    public var failures: String
    public var tail: String
    public var hasSummary: Bool
    public var error: String?
}

/// Lanza `AuraSelfTests` (junto al bundle `.xctest`) como subproceso (ADR 0004). Vive aquí, no en el test,
/// porque `import Foundation` + `import Testing` exige un módulo de interoperabilidad ausente en las CLT.
public func runSelfTestsSubprocess() -> SelfTestRun {
    // El anfitrión de pruebas recibe la ruta del .xctest como argumento (XCTest o Swift Testing según toolchain).
    let candidates = Bundle.allBundles.map(\.bundlePath) + ProcessInfo.processInfo.arguments
    // Swift Testing pasa `.../X.xctest/Contents/MacOS/X`: se recorta hasta el propio bundle.
    let products = candidates.compactMap { c in c.range(of: ".xctest").map { String(c[..<$0.upperBound]) } }
        .first.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
    guard let exe = products?.appendingPathComponent("AuraSelfTests"), FileManager.default.isExecutableFile(atPath: exe.path) else {
        return SelfTestRun(status: -1, failures: "", tail: "", hasSummary: false, error: "AuraSelfTests no está compilado junto al bundle de pruebas (buscado en \(products?.path ?? "ninguna ruta .xctest: \(candidates.prefix(4))"))")
    }
    let p = Process()
    p.executableURL = exe
    let pipe = Pipe()
    p.standardOutput = pipe; p.standardError = pipe
    do { try p.run() } catch {
        return SelfTestRun(status: -1, failures: "", tail: "", hasSummary: false, error: "\(error)")
    }
    // Se lee antes de esperar para no bloquear el subproceso si llena la tubería.
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    return SelfTestRun(status: p.terminationStatus,
                       failures: out.split(separator: "\n").filter { $0.hasPrefix("FAIL") }.joined(separator: "\n"),
                       tail: String(out.suffix(400)), hasSummary: out.contains("passed"), error: nil)
}
