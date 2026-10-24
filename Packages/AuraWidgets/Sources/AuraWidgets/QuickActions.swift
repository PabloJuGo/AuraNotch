import AppKit
import AuraDesignSystem
import Foundation
import Observation
import SwiftUI

public struct QuickActionError: Error, Equatable, Sendable { public var message: String; public init(_ m: String) { message = m } }

/// Acción SEGURA y predefinida: nada de scripts arbitrarios ni permisos.
public protocol QuickAction: Sendable {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    @MainActor func perform() async throws
}

/// Efectos del sistema que usan las acciones integradas (inyectable para pruebas).
public protocol SystemActions: Sendable {
    @MainActor
    func open(_ url: URL) -> Bool
    @MainActor func copy(_ text: String)
}

public struct WorkspaceActions: SystemActions {
    public init() {}
    @MainActor public func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    @MainActor public func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

public struct OpenSystemSettingsAction: QuickAction {
    public let id = "open-settings", symbol = "gearshape"
    public var title: String { WidgetStrings.openSettings }
    let system: any SystemActions
    public init(system: any SystemActions = WorkspaceActions()) { self.system = system }
    @MainActor public func perform() async throws {
        guard let url = URL(string: "x-apple.systempreferences:"), system.open(url) else { throw QuickActionError(WidgetStrings.actionFailed) }
    }
}

public struct OpenDownloadsAction: QuickAction {
    public let id = "open-downloads", symbol = "arrow.down.circle"
    public var title: String { WidgetStrings.openDownloads }
    let system: any SystemActions
    let folder: URL?
    public init(system: any SystemActions = WorkspaceActions(), folder: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first) {
        self.system = system; self.folder = folder
    }
    @MainActor public func perform() async throws {
        guard let folder, system.open(folder) else { throw QuickActionError(WidgetStrings.actionFailed) }
    }
}

public struct CopyDateAction: QuickAction {
    public let id = "copy-date", symbol = "doc.on.doc"
    public var title: String { WidgetStrings.copyDate }
    let system: any SystemActions
    let now: @Sendable () -> Date
    let locale: Locale
    public init(system: any SystemActions = WorkspaceActions(), now: @escaping @Sendable () -> Date = { Date() }, locale: Locale = .autoupdatingCurrent) {
        self.system = system; self.now = now; self.locale = locale
    }
    @MainActor public func perform() async throws {
        system.copy(now().formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale)))
    }
}

public enum ActionStatus: Equatable, Sendable { case running, succeeded, failed(String) }

/// Acciones favoritas: `catalog` es lo que existe; `favorites` (ids) lo que se muestra y en qué orden.
@MainActor @Observable
public final class QuickActionsService: AuraWidget {
    public let catalog: [any QuickAction]
    public private(set) var favorites: [String]
    public private(set) var status: [String: ActionStatus] = [:]
    @ObservationIgnored public var onFavoritesChange: (([String]) -> Void)?
    @ObservationIgnored private var clearTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let feedbackSeconds: Double

    public init(catalog: [any QuickAction]? = nil, favorites: [String]? = nil, feedbackSeconds: Double = 1.5) {
        let cat = catalog ?? [OpenSystemSettingsAction(), OpenDownloadsAction(), CopyDateAction()]
        self.catalog = cat; self.feedbackSeconds = feedbackSeconds
        self.favorites = Self.sanitize(favorites ?? cat.map(\.id), in: cat)
    }

    private static func sanitize(_ ids: [String], in cat: [any QuickAction]) -> [String] {
        var seen = Set<String>()
        return ids.filter { id in cat.contains { $0.id == id } && seen.insert(id).inserted }
    }

    public func setFavorites(_ ids: [String]) {
        let clean = Self.sanitize(ids, in: catalog)
        guard clean != favorites else { return }
        favorites = clean; onFavoritesChange?(clean)
    }
    public var favoriteActions: [any QuickAction] { favorites.compactMap { id in catalog.first { $0.id == id } } }

    public let manifest = WidgetManifest(id: "actions", name: WidgetStrings.actionsName, symbol: "bolt", preferredSize: .wide,
                                         permissions: [.openURLs, .pasteboardWrite])
    public var state: WidgetState { favorites.isEmpty ? .empty(message: WidgetStrings.noActionsMessage) : .ready }
    public var summary: String { "\(WidgetStrings.actionsName): " + favoriteActions.map(\.title).joined(separator: ", ") }
    public func setActive(_ active: Bool) {}
    public func makeBody() -> AnyView { AnyView(QuickActionsBody(service: self)) }

    public func run(_ id: String) async {
        guard let action = catalog.first(where: { $0.id == id }), status[id] != .running else { return }
        clearTasks[id]?.cancel()
        status[id] = .running
        do { try await action.perform(); status[id] = .succeeded }
        catch { status[id] = .failed((error as? QuickActionError)?.message ?? WidgetStrings.actionFailed) }
        clearTasks[id] = Task { [weak self, feedbackSeconds] in
            try? await Task.sleep(for: .seconds(feedbackSeconds))
            if !Task.isCancelled { self?.status[id] = nil }
        }
    }
}

struct QuickActionsBody: View {
    let service: QuickActionsService
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(service.favoriteActions, id: \.id) { a in
                let st = service.status[a.id]
                Button { Task { await service.run(a.id) } } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: a.symbol).frame(width: 18).accessibilityHidden(true)
                        Text(a.title).font(AuraFont.body).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(AuraButtonStyle(emphasis: .secondary, status: Self.control(st)))
                .accessibilityLabel(a.title)
                .accessibilityValue(Self.spoken(st))
                if case .failed(let m) = st { Text(m).font(AuraFont.secondary).foregroundStyle(AuraColor.warning.color) }
            }
        }
    }
    static func control(_ s: ActionStatus?) -> ControlStatus {
        switch s { case .running: .loading; case .succeeded: .success; case .failed: .error; case nil: .idle }
    }
    static func spoken(_ s: ActionStatus?) -> String {
        switch s { case .succeeded: WidgetStrings.done; case .failed(let m): m; default: "" }
    }
}
