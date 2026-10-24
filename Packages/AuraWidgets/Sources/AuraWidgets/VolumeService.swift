import AudioToolbox
import AuraDesignSystem
import CoreAudio
import Foundation
import Observation
import SwiftUI

public struct VolumeReading: Equatable, Sendable {
    /// 0...1.
    public var level: Double
    public var isMuted: Bool
    /// false = el dispositivo no tiene interruptor de silencio; el servicio lo emula con volumen 0.
    public var canMute: Bool
    public init(level: Double, isMuted: Bool = false, canMute: Bool = true) {
        self.level = min(1, max(0, level)); self.isMuted = isMuted; self.canMute = canMute
    }
}

public enum VolumeError: Error, Equatable, Sendable {
    /// Hay salida pero no admite volumen por software (p. ej. algunas salidas HDMI/DisplayPort).
    case noControl
    /// No hay dispositivo de salida o CoreAudio falló.
    case failed
}

/// Backend de volumen inyectable (el real usa CoreAudio; las pruebas, un doble).
@MainActor public protocol VolumeBackend {
    func read() throws -> VolumeReading
    func setLevel(_ level: Double) throws
    func setMuted(_ muted: Bool) throws
    /// Avisa de cambios de volumen/silencio y de dispositivo por defecto, sin polling. Devuelve la cancelación.
    func observe(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void
}

/// CoreAudio sobre el dispositivo de salida por defecto. Volumen = `VirtualMainVolume` (el mismo control que la tecla de volumen).
/// shortcut: sin respaldo por canal (`VolumeScalar` 1/2) para dispositivos sin volumen virtual; se muestran como «sin control».
@MainActor public final class CoreAudioVolumeBackend: VolumeBackend {
    fileprivate static let system = AudioObjectID(kAudioObjectSystemObject)
    fileprivate static let defaultDevice = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
    fileprivate static let volume = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
    fileprivate static let mute = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

    fileprivate static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Dispositivo de salida por defecto, o nil si no hay.
    fileprivate static func currentDevice() -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size), a = defaultDevice
        return AudioObjectGetPropertyData(system, &a, 0, nil, &size, &id) == noErr && id != kAudioObjectUnknown ? id : nil
    }

    public init() {}

    private func settable(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address, s: DarwinBoolean = false
        return AudioObjectHasProperty(device, &a) && AudioObjectIsPropertySettable(device, &a, &s) == noErr && s.boolValue
    }

    private func get<T>(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: inout T) throws {
        var a = address, size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr else { throw VolumeError.failed }
    }

    private func set<T>(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) throws {
        var a = address, v = value
        guard AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr else { throw VolumeError.failed }
    }

    public func read() throws -> VolumeReading {
        guard let device = Self.currentDevice() else { throw VolumeError.failed }
        guard settable(device, Self.volume) else { throw VolumeError.noControl }
        var level: Float32 = 0
        try get(device, Self.volume, &level)
        let canMute = settable(device, Self.mute)
        var muted: UInt32 = 0
        if canMute { try get(device, Self.mute, &muted) }
        return VolumeReading(level: Double(level), isMuted: muted != 0, canMute: canMute)
    }

    public func setLevel(_ level: Double) throws {
        guard let device = Self.currentDevice() else { throw VolumeError.failed }
        guard settable(device, Self.volume) else { throw VolumeError.noControl }
        try set(device, Self.volume, Float32(min(1, max(0, level))))
    }

    public func setMuted(_ muted: Bool) throws {
        guard let device = Self.currentDevice() else { throw VolumeError.failed }
        guard settable(device, Self.mute) else { throw VolumeError.noControl }
        try set(device, Self.mute, UInt32(muted ? 1 : 0))
    }

    /// Escucha el dispositivo por defecto (volumen y silencio) y, en el sistema, el cambio de dispositivo; al cambiar se reengancha.
    public func observe(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let listener = DeviceListener(onChange)
        listener.start()
        return { listener.stop() }
    }

    @MainActor private final class DeviceListener {
        let onChange: @MainActor () -> Void
        var device = AudioObjectID(kAudioObjectUnknown)
        var block: AudioObjectPropertyListenerBlock?
        var systemBlock: AudioObjectPropertyListenerBlock?
        init(_ f: @escaping @MainActor () -> Void) { onChange = f }

        func start() {
            let sys: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.attach(); self?.onChange() }  // los bloques se entregan en la cola principal
            }
            systemBlock = sys
            var a = CoreAudioVolumeBackend.defaultDevice
            AudioObjectAddPropertyListenerBlock(CoreAudioVolumeBackend.system, &a, .main, sys)
            attach()
        }

        func attach() {
            detach()
            guard let id = CoreAudioVolumeBackend.currentDevice() else { return }
            let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.onChange() } }
            device = id; block = b
            var v = CoreAudioVolumeBackend.volume, m = CoreAudioVolumeBackend.mute
            AudioObjectAddPropertyListenerBlock(id, &v, .main, b)
            AudioObjectAddPropertyListenerBlock(id, &m, .main, b)
        }

        func detach() {
            if let block, device != kAudioObjectUnknown {
                var v = CoreAudioVolumeBackend.volume, m = CoreAudioVolumeBackend.mute
                AudioObjectRemovePropertyListenerBlock(device, &v, .main, block)
                AudioObjectRemovePropertyListenerBlock(device, &m, .main, block)
            }
            block = nil; device = AudioObjectID(kAudioObjectUnknown)
        }

        func stop() {
            detach()
            if let systemBlock {
                var a = CoreAudioVolumeBackend.defaultDevice
                AudioObjectRemovePropertyListenerBlock(CoreAudioVolumeBackend.system, &a, .main, systemBlock)
            }
            systemBlock = nil
        }
    }
}

/// Widget de volumen del sistema. Solo escucha eventos mientras está activo (visible).
/// Un dispositivo sin control de volumen es `.empty` (no `isAvailable == false`): hay que seguir escuchando para recuperarse al cambiar de salida.
@MainActor @Observable
public final class VolumeService: AuraWidget {
    public static let step = 0.0625  // 1/16, los mismos pasos que las teclas de volumen

    public private(set) var state: WidgetState = .loading
    public private(set) var reading: VolumeReading?

    @ObservationIgnored private let backend: any VolumeBackend
    @ObservationIgnored private var cancelObserver: (@MainActor () -> Void)?
    /// Volumen previo al silencio emulado (dispositivos sin interruptor de mute).
    @ObservationIgnored private var levelBeforeMute: Double?

    public init(backend: any VolumeBackend = CoreAudioVolumeBackend()) { self.backend = backend }

    public let manifest = WidgetManifest(id: "volume", name: WidgetStrings.volumeName, symbol: "speaker.wave.2.fill", preferredSize: .wide)

    public func setActive(_ active: Bool) {
        if active, cancelObserver == nil {
            refresh()
            cancelObserver = backend.observe { [weak self] in self?.refresh() }
        } else if !active {
            cancelObserver?(); cancelObserver = nil
        }
    }
    public func retry() { refresh() }

    public func refresh() {
        do {
            reading = try backend.read(); state = .ready
        } catch VolumeError.noControl {
            reading = nil; state = .empty(message: WidgetStrings.volumeNoControl)
        } catch {
            reading = nil; state = .error(cause: WidgetStrings.volumeErrorCause, solution: WidgetStrings.volumeErrorSolution)
        }
    }

    /// Nivel 0...1. Subir el volumen quita el silencio, como en macOS.
    public func setLevel(_ level: Double) {
        guard var r = reading else { return }
        let l = min(1, max(0, level))
        do {
            try backend.setLevel(l)
            if r.isMuted, l > 0, r.canMute { try backend.setMuted(false); r.isMuted = false }
            r.level = l; reading = r
        } catch { refresh() }
    }

    public func adjust(by delta: Double) { if let r = reading { setLevel(r.level + delta) } }

    public func toggleMute() {
        guard let r = reading else { return }
        if r.canMute {
            do { try backend.setMuted(!r.isMuted); reading?.isMuted = !r.isMuted } catch { refresh() }
        } else if r.level > 0 {
            levelBeforeMute = r.level; setLevel(0)
        } else {
            setLevel(levelBeforeMute ?? 0.5)
        }
    }

    public var isSilent: Bool { reading.map { $0.isMuted || $0.level == 0 } ?? false }

    public var summary: String {
        switch state {
        case .ready:
            guard let r = reading else { return "" }
            return "\(WidgetStrings.volumeName), \(isSilent ? WidgetStrings.muted : WidgetStrings.percent(Int((r.level * 100).rounded())))"
        case .empty(let m): return "\(WidgetStrings.volumeName): \(m)"
        case .loading: return "\(WidgetStrings.volumeName): \(WidgetStrings.loading)"
        case .error(let c, _): return "\(WidgetStrings.volumeName): \(c)"
        }
    }

    public func symbol(_ r: VolumeReading) -> String {
        if r.isMuted || r.level == 0 { return "speaker.slash.fill" }
        switch r.level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    public func makeBody() -> AnyView { AnyView(VolumeBody(service: self)) }
}

struct VolumeBody: View {
    let service: VolumeService
    var body: some View {
        if let r = service.reading {
            HStack(spacing: Space.sm) {
                Button { service.toggleMute() } label: {
                    Image(systemName: service.symbol(r)).font(.title3).frame(width: 28)
                        .foregroundStyle(service.isSilent ? AuraColor.secondaryText.color : AuraColor.primaryText.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(service.isSilent ? WidgetStrings.unmute : WidgetStrings.mute)
                Slider(value: Binding(get: { service.reading?.level ?? 0 }, set: { service.setLevel($0) }), in: 0...1)
                    .accessibilityLabel(WidgetStrings.volumeLabel)
                    .accessibilityValue(WidgetStrings.percent(Int((r.level * 100).rounded())))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: service.adjust(by: VolumeService.step)
                        case .decrement: service.adjust(by: -VolumeService.step)
                        @unknown default: break
                        }
                    }
            }
        }
    }
}
