import AuraCalendar
import AuraClipboard
import AuraMedia
import AuraShelf
import AuraWidgets
import Foundation

/// Tarjetas posibles de Inicio, de más a menos relevante (el orden de `allCases` ES el orden de relevancia).
public enum HomeCard: Int, CaseIterable, Equatable, Sendable {
    case timer, media, event, clipboard, shelf
}

/// Lo mínimo de la batería para decidir si merece una tarjeta.
public struct BatteryGlimpse: Equatable, Sendable {
    public var percent: Int?
    public var isCharging: Bool
    public var isCharged: Bool
    public var isLow: Bool
    public init(percent: Int?, isCharging: Bool, isCharged: Bool = false, isLow: Bool) {
        self.percent = percent; self.isCharging = isCharging; self.isCharged = isCharged; self.isLow = isLow
    }
}

/// Estado de cada servicio reducido a datos planos: la selección es una función pura y comprobable.
/// Un servicio ausente (módulo desactivado) o sin datos listos equivale al valor «neutro» por defecto.
public struct HomeInputs: Equatable, Sendable {
    public var timer: TimerPhase = .idle
    public var hasNowPlaying = false
    public var hasUpcomingEvent = false
    public var clipboardCount = 0
    /// El módulo está activo: su tarjeta se muestra siempre, con un texto de estado si no hay contenido.
    public var calendarEnabled = false, shelfEnabled = false, clipboardEnabled = false
    public var shelfCount = 0
    /// La batería va en la cabecera, no es tarjeta.
    public var battery: BatteryGlimpse?
    /// Algún servicio aún arranca (solo afecta al estado vacío: «Cargando…» en vez del saludo).
    public var isLoading = false
    public init() {}
}

public enum HomeModel {
    /// Tarjetas a mostrar, ordenadas. Vacío = «Quiet by default»: solo fecha y saludo.
    public static func cards(_ i: HomeInputs) -> [HomeCard] {
        var out: [HomeCard] = []
        if i.timer != .idle { out.append(.timer) }
        if i.hasNowPlaying { out.append(.media) }
        if i.hasUpcomingEvent || i.calendarEnabled { out.append(.event) }
        if i.clipboardCount > 0 || i.clipboardEnabled { out.append(.clipboard) }
        if i.shelfCount > 0 || i.shelfEnabled { out.append(.shelf) }
        return out
    }

    /// Primer evento que aún no ha terminado. Solo con el calendario YA listo: nunca se pide ni se carga nada.
    public static func nextEvent(state: CalendarState, events: [CalendarEvent], now: Date) -> CalendarEvent? {
        guard state == .ready else { return nil }
        return events.filter { $0.end > now }.min { $0.start < $1.start }
    }

    /// Eventos de hoy que aún no han terminado, en orden (los de todo el día primero). Solo con el calendario YA listo.
    public static func todayEvents(state: CalendarState, events: [CalendarEvent], now: Date, limit: Int = 3,
                                   calendar: Calendar = .current) -> [CalendarEvent] {
        guard state == .ready, let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        return Array(events.filter { $0.end > now && $0.start < tomorrow }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }.prefix(limit))
    }

    public enum Greeting: Equatable, Sendable { case morning, afternoon, evening }
    public static func greeting(hour: Int) -> Greeting {
        switch hour {
        case 5..<13: .morning
        case 13..<20: .afternoon
        default: .evening
        }
    }

    /// m:ss o h:mm:ss redondeando hacia arriba (igual que el compacto del temporizador).
    public static func clock(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension HomeInputs {
    /// Lectura puntual de los servicios reales (nil = módulo desactivado). No dispara permisos ni cargas.
    @MainActor public init(media: MediaService?, timer: TimerService?, calendar: CalendarService?,
                           shelf: ShelfService?, battery: BatteryService?, clipboard: ClipboardService? = nil, now: Date) {
        self.init()
        if let clipboard { clipboardCount = clipboard.items.count; clipboardEnabled = true }
        calendarEnabled = calendar != nil; shelfEnabled = shelf != nil
        if let timer { self.timer = timer.phase }
        if let media { hasNowPlaying = media.state == .ready && media.current != nil; isLoading = media.state == .loading }
        if let calendar { hasUpcomingEvent = !HomeModel.todayEvents(state: calendar.state, events: calendar.events, now: now).isEmpty }
        if let shelf { shelfCount = shelf.items.count }
        if let battery, battery.state == .ready, let r = battery.reading, r.hasBattery {
            self.battery = BatteryGlimpse(percent: r.percent, isCharging: r.isCharging, isCharged: r.isCharged, isLow: battery.isLow)
        }
        if let battery, battery.state == .loading { isLoading = true }
    }
}

extension HomeModel {
    /// «5 minutos 3 segundos» para VoiceOver (el reloj «5:03» se lee mal).
    public static func spoken(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded(.up)), h = s / 3600, m = s % 3600 / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? String(localized: "1 hora") : String(localized: "\(h) horas")) }
        if m > 0 { parts.append(m == 1 ? String(localized: "1 minuto") : String(localized: "\(m) minutos")) }
        if sec > 0 || parts.isEmpty { parts.append(sec == 1 ? String(localized: "1 segundo") : String(localized: "\(sec) segundos")) }
        return parts.joined(separator: " ")
    }
}
