import AuraCore
import Foundation
@testable import AuraAlerts

@MainActor func runAlertsSuite(_ t: SelfCheck) {
    let c = AlertCenter()
    c.post(AuraAlert(symbol: "bell", text: "x"))
    t.expect(c.current?.text == "x", "aviso publicado")
    c.dismiss()
    t.expect(c.current == nil, "aviso retirado")
    c.enabled = false
    c.post(AuraAlert(symbol: "bell", text: "y"))
    t.expect(c.current == nil, "avisos desactivados no se publican")
    runAlertSourcesSuite(t)
}

// MARK: - Fuentes de avisos (reunión, batería, temporizador)

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var d: Date
    init(_ d: Date) { self.d = d }
    var date: Date { get { lock.withLock { d } } set { lock.withLock { d = newValue } } }
}
/// `sleep` falso: anota la espera pedida y vuelve al instante (o nunca, con `hang`, para probar la cancelación).
private final class TestSleeper: @unchecked Sendable {
    private let lock = NSLock(); private var w: [TimeInterval] = []
    var hang = false
    var waits: [TimeInterval] { lock.withLock { w } }
    func sleep(_ s: TimeInterval) async throws {
        lock.withLock { w.append(s) }
        if hang { try await Task.sleep(for: .seconds(3600)) }
    }
}
@MainActor private func pump(until cond: () -> Bool) {
    let end = Date().addingTimeInterval(1)
    while !cond() && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

@MainActor func runAlertSourcesSuite(_ t: SelfCheck) {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func make(_ clock: TestClock, _ sl: TestSleeper) -> (AlertCenter, MeetingAlerts) {
        let c = AlertCenter()
        clock.date = t0
        // El reloj avanza lo que dura la espera (si no se cancela).
        return (c, MeetingAlerts(center: c, now: { clock.date }, sleep: { try await sl.sleep($0); clock.date = clock.date.addingTimeInterval($0) }))
    }

    // Reunión: una sola espera hasta start - 5 min; el aviso lleva el título y los minutos.
    let clock = TestClock(t0), sl = TestSleeper()
    let (c, m) = make(clock, sl)
    m.update([UpcomingMeeting(id: "a", title: "Reunión de equipo", start: t0.addingTimeInterval(600))])
    pump(until: { c.current != nil })
    t.expect(sl.waits == [300], "reunión: espera única hasta 5 min antes")
    t.expect(c.current?.symbol == "calendar" && c.current?.text.contains("Reunión de…") == true && c.current?.text.hasSuffix("5 min") == true, "reunión: título y «en 5 min»")
    t.expect(c.current?.spoken?.contains("5 minutos") == true, "reunión: frase para VoiceOver")

    // No se repite el aviso del mismo evento al cambiar la lista.
    c.dismiss(); m.update([UpcomingMeeting(id: "a", title: "Reunión de equipo", start: t0.addingTimeInterval(600))])
    pump(until: { c.current != nil })
    t.expect(c.current == nil, "reunión: no se avisa dos veces")

    // Todo el día y pasados: nunca avisan ni programan.
    let sl2 = TestSleeper(); let (c2, m2) = make(clock, sl2)
    m2.update([UpcomingMeeting(id: "d", title: "Festivo", start: t0.addingTimeInterval(600), isAllDay: true),
               UpcomingMeeting(id: "p", title: "Pasada", start: t0.addingTimeInterval(-60))])
    pump(until: { c2.current != nil })
    t.expect(c2.current == nil && sl2.waits.isEmpty, "reunión: ni todo el día ni pasadas")

    // Faltan menos de 5 min al enterarse: avisa ya con los minutos reales.
    let sl3 = TestSleeper(); let (c3, m3) = make(clock, sl3)
    m3.update([UpcomingMeeting(id: "s", title: "Corta", start: t0.addingTimeInterval(120))])
    pump(until: { c3.current != nil })
    t.expect(c3.current?.text.hasSuffix("2 min") == true && sl3.waits.isEmpty, "reunión: aviso inmediato con 2 min")

    // Cambian los eventos: se cancela la espera y se recalcula con la nueva lista.
    let sl4 = TestSleeper(); sl4.hang = true; let (c4, m4) = make(clock, sl4)
    m4.update([UpcomingMeeting(id: "x", title: "X", start: t0.addingTimeInterval(1000))])
    pump(until: { sl4.waits.count == 1 })
    sl4.hang = false
    m4.update([UpcomingMeeting(id: "y", title: "Y", start: t0.addingTimeInterval(400))])
    pump(until: { c4.current != nil })
    t.expect(sl4.waits == [700, 100] && c4.current?.text.hasPrefix("Y") == true, "reunión: recalcula al cambiar los eventos")
    m4.stop()

    // Simultáneas: un único aviso con «+1».
    let sl5 = TestSleeper(); let (c5, m5) = make(clock, sl5)
    m5.update([UpcomingMeeting(id: "1", title: "Uno", start: t0.addingTimeInterval(200)), UpcomingMeeting(id: "2", title: "Dos", start: t0.addingTimeInterval(200))])
    pump(until: { c5.current != nil })
    t.expect(c5.current?.text.hasSuffix("+1") == true, "reunión: simultáneas en un aviso")

    // Desactivados: no se publica nada.
    let sl6 = TestSleeper(); let (c6, m6) = make(clock, sl6); c6.enabled = false
    m6.update([UpcomingMeeting(id: "z", title: "Z", start: t0.addingTimeInterval(100))])
    pump(until: { c6.current != nil })
    t.expect(c6.current == nil, "reunión: respeta alertsEnabled")

    // Batería: la primera lectura no avisa; conectar, desconectar y carga completa sí; un aviso reemplaza al anterior.
    let pc = AlertCenter(); let p = PowerAlerts(center: pc)
    p.update(PowerSnapshot(pluggedIn: false, charged: false))
    t.expect(pc.current == nil, "batería: lectura inicial sin aviso")
    p.update(PowerSnapshot(pluggedIn: true, charged: false))
    t.expect(pc.current?.symbol == "bolt.fill", "batería: cargador conectado")
    p.update(PowerSnapshot(pluggedIn: true, charged: false))
    pc.dismiss(); p.update(PowerSnapshot(pluggedIn: true, charged: false))
    t.expect(pc.current == nil, "batería: sin cambios no avisa")
    p.update(PowerSnapshot(pluggedIn: true, charged: true))
    t.expect(pc.current?.symbol == "battery.100percent.bolt", "batería: carga completa (reemplaza al anterior)")
    p.update(PowerSnapshot(pluggedIn: false, charged: true))
    t.expect(pc.current?.symbol == "bolt.slash.fill", "batería: cargador desconectado")
    p.update(nil); pc.dismiss(); p.update(PowerSnapshot(pluggedIn: true, charged: false))
    t.expect(pc.current == nil, "batería: tras perder la lectura se vuelve a fijar la base")

    // Temporizador: el aviso propio existe y es corto.
    t.expect(AuraAlert.timerFinished.symbol == "timer" && !AuraAlert.timerFinished.text.isEmpty, "temporizador: aviso del notch")
}
