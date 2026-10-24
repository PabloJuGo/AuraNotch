import Foundation

/// Formato de horarios con calendario/zona/idioma inyectados (pruebas deterministas, cambio de zona).
struct CalendarFormat {
    var calendar: Calendar
    var now: Date

    private func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = calendar.locale ?? .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    func time(_ d: Date) -> String { formatter("jmm").string(from: d) }

    func day(_ d: Date) -> String {
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 99
        switch delta {
        case 0: return CalendarStrings.today
        case 1: return CalendarStrings.tomorrow
        case -1: return CalendarStrings.yesterday
        default: return formatter("EEEdMMM").string(from: d)
        }
    }

    /// Texto único para pantalla y VoiceOver: «hoy de 10:00 a 11:00».
    func when(_ e: CalendarEvent) -> String {
        if e.isAllDay {
            // El fin de un evento de día completo es exclusivo (00:00 del día siguiente) o 23:59 según el origen.
            let last = calendar.startOfDay(for: e.end.addingTimeInterval(-1))
            if last <= calendar.startOfDay(for: e.start) { return CalendarStrings.allDay(day: day(e.start)) }
            return CalendarStrings.allDayRange(from: day(e.start), to: day(last))
        }
        if calendar.isDate(e.start, inSameDayAs: e.end) || e.end <= e.start {
            return CalendarStrings.timed(day: day(e.start), from: time(e.start), to: time(e.end))
        }
        // Un fin exactamente a medianoche pertenece al día anterior.
        if e.end == calendar.startOfDay(for: e.end), calendar.isDate(e.start, inSameDayAs: e.end.addingTimeInterval(-1)) {
            return CalendarStrings.timed(day: day(e.start), from: time(e.start), to: time(e.end))
        }
        return CalendarStrings.timedCrossing(day: day(e.start), from: time(e.start), endDay: day(e.end), to: time(e.end))
    }

    func title(_ e: CalendarEvent) -> String {
        let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? CalendarStrings.untitled : t
    }

    func calendarName(_ e: CalendarEvent) -> String {
        let t = e.calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? CalendarStrings.unnamedCalendar : t
    }

    func spoken(_ e: CalendarEvent) -> String {
        CalendarStrings.spoken(title: title(e), when: when(e), calendar: calendarName(e))
    }
}
