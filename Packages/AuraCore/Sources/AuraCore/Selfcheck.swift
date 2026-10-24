/// Mini runner de aserciones (sin XCTest/Testing en CLT). Ver Docs/decisions/0001.
public final class SelfCheck: @unchecked Sendable {
    public private(set) var failures = 0, passes = 0
    public init() {}
    public func expect(_ cond: @autoclosure () -> Bool, _ msg: String, file: StaticString = #fileID, line: UInt = #line) {
        if cond() { passes += 1 } else { failures += 1; print("FAIL \(file):\(line) \(msg)") }
    }
    public func summary() -> Int32 {
        print("\(passes) passed, \(failures) failed"); return failures == 0 ? 0 : 1
    }
}
