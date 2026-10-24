import AuraCore
import AuraDesignSystem
import Foundation
import IOKit.ps
import Observation
import SwiftUI

public struct PowerReading: Equatable, Sendable {
    public var hasBattery: Bool
    public var percent: Int?
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isCharged: Bool
    /// Minutos hasta vaciar (con batería) o hasta completar (cargando); nil si el SO no lo estima.
    public var minutesRemaining: Int?
    public init(hasBattery: Bool, percent: Int? = nil, isCharging: Bool = false, isPluggedIn: Bool = false,
                isCharged: Bool = false, minutesRemaining: Int? = nil) {
        self.hasBattery = hasBattery; self.percent = percent; self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn; self.isCharged = isCharged; self.minutesRemaining = minutesRemaining
    }
    public static let none = PowerReading(hasBattery: false)
}

public enum PowerError: Error, Equatable, Sendable { case unavailable }

/// Fuente de energía inyectable (la real usa IOKit; las pruebas, una falsa).
@MainActor public protocol PowerSource {
    func read() throws -> PowerReading
    /// Avisa de cambios sin polling. Devuelve la función que cancela la suscripción.
    func observe(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void
}

/// IOKit: `IOPSCopyPowerSourcesInfo` para leer, `IOPSNotificationCreateRunLoopSource` para los eventos.
public struct IOKitPowerSource: PowerSource {
    public init() {}

    private final class Box { let fire: @MainActor () -> Void; init(_ f: @escaping @MainActor () -> Void) { fire = f } }

    public func read() throws -> PowerReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { throw PowerError.unavailable }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int, max = d[kIOPSMaxCapacityKey] as? Int
            let percent = cur.flatMap { c in max.flatMap { $0 > 0 ? Swift.min(100, c * 100 / $0) : nil } }
            let plugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            var minutes: Int?
            if charging {
                if let m = d[kIOPSTimeToFullChargeKey] as? Int, m >= 0 { minutes = m }
            } else if !plugged {
                let est = IOPSGetTimeRemainingEstimate()  // -1 desconocido, -2 ilimitado
                if est >= 0 { minutes = Int((est / 60).rounded()) }
                else if let m = d[kIOPSTimeToEmptyKey] as? Int, m >= 0 { minutes = m }
            }
            return PowerReading(hasBattery: true, percent: percent, isCharging: charging, isPluggedIn: plugged,
                                isCharged: d[kIOPSIsChargedKey] as? Bool ?? false, minutesRemaining: minutes)
        }
        return .none  // lista válida sin batería interna: Mac de escritorio
    }

    public func observe(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let box = Unmanaged.passRetained(Box(onChange))
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let b = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { b.fire() }  // el run loop de la fuente es el principal
        }
        guard let src = IOPSNotificationCreateRunLoopSource(callback, box.toOpaque())?.takeRetainedValue() else {
            box.release(); return {}
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        return {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            box.release()
        }
    }
}

/// Widget de batería/energía. Solo escucha eventos mientras está activo (visible).
@MainActor @Observable
public final class BatteryService: AuraWidget {
    public private(set) var state: WidgetState = .loading
    public private(set) var reading: PowerReading?
    public private(set) var lowPowerMode = false

    @ObservationIgnored private let source: any PowerSource
    @ObservationIgnored private let lowPowerProvider: @MainActor () -> Bool
    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private let lowThreshold: Int
    @ObservationIgnored private var cancelSource: (@MainActor () -> Void)?
    @ObservationIgnored private var lpmToken: NSObjectProtocol?

    public init(source: any PowerSource = IOKitPowerSource(),
                lowPowerProvider: @escaping @MainActor () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
                center: NotificationCenter = .default, lowThreshold: Int = 20) {
        self.source = source; self.lowPowerProvider = lowPowerProvider; self.center = center; self.lowThreshold = lowThreshold
    }

    public let manifest = WidgetManifest(id: "battery", name: WidgetStrings.batteryName, symbol: "battery.100percent")
    public var isLow: Bool { (reading?.percent ?? 100) <= lowThreshold && reading?.isPluggedIn == false }

    public func setActive(_ active: Bool) {
        if active, cancelSource == nil {
            refresh()
            cancelSource = source.observe { [weak self] in self?.refresh() }
            lpmToken = center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        } else if !active {
            cancelSource?(); cancelSource = nil
            if let lpmToken { center.removeObserver(lpmToken) }
            lpmToken = nil
        }
    }
    public func retry() { refresh() }

    /// Lectura puntual (también la usa `setActive`); sin ella el estado queda en `.loading`.
    public func refresh() {
        lowPowerMode = lowPowerProvider()
        do {
            let r = try source.read()
            reading = r
            state = r.hasBattery ? .ready : .empty(message: WidgetStrings.noBatteryMessage)
        } catch {
            reading = nil
            state = .error(cause: WidgetStrings.batteryErrorCause, solution: WidgetStrings.batteryErrorSolution)
        }
    }

    public var summary: String {
        switch state {
        case .ready:
            guard let r = reading else { return "" }
            return ([WidgetStrings.batteryName, r.percent.map(WidgetStrings.percent) ?? ""] + detailLines(r)).filter { !$0.isEmpty }.joined(separator: ", ")
        case .empty(let m): return "\(WidgetStrings.batteryName): \(m)"
        case .loading: return "\(WidgetStrings.batteryName): \(WidgetStrings.loading)"
        case .error(let c, _): return "\(WidgetStrings.batteryName): \(c)"
        }
    }

    /// Líneas descriptivas (estado, tiempo estimado, bajo consumo), compartidas por vista y VoiceOver.
    func detailLines(_ r: PowerReading) -> [String] {
        var out: [String] = []
        if r.isCharged { out.append(WidgetStrings.charged) }
        else if r.isCharging { out.append(WidgetStrings.charging + (r.minutesRemaining.map { " · " + WidgetStrings.timeToFull($0) } ?? "")) }
        else if r.isPluggedIn { out.append(WidgetStrings.pluggedIn) }
        else { out.append(WidgetStrings.onBattery + (r.minutesRemaining.map { " · " + WidgetStrings.timeLeft($0) } ?? "")) }
        if isLow { out.append(WidgetStrings.low) }
        if lowPowerMode { out.append(WidgetStrings.lowPower) }
        return out
    }

    func symbol(_ r: PowerReading) -> String {
        if r.isCharging || r.isCharged { return "battery.100percent.bolt" }
        switch r.percent ?? 100 {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    public func makeBody() -> AnyView { AnyView(BatteryBody(service: self)) }
}

struct BatteryBody: View {
    let service: BatteryService
    var body: some View {
        if let r = service.reading {
            let lines = service.detailLines(r)
            HStack(alignment: .center, spacing: Space.md) {
                Image(systemName: service.symbol(r)).font(.title)
                    .foregroundStyle(service.isLow ? AuraColor.warning.color : AuraColor.primaryText.color).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(r.percent.map(WidgetStrings.percent) ?? "—").font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(AuraColor.primaryText.color)
                    ForEach(lines, id: \.self) { Text($0).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(service.summary)
        }
    }
}
