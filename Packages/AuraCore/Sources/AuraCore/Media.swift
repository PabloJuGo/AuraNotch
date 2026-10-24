import Foundation

/// Capacidades que un proveedor declara explícitamente (§5.1). La UI solo
/// muestra controles cuyas capacidades estén presentes.
public struct MediaCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let play = MediaCapabilities(rawValue: 1 << 0)
    public static let pause = MediaCapabilities(rawValue: 1 << 1)
    public static let skip = MediaCapabilities(rawValue: 1 << 2)
    public static let seek = MediaCapabilities(rawValue: 1 << 3)
    public static let artwork = MediaCapabilities(rawValue: 1 << 4)
    public static let openSource = MediaCapabilities(rawValue: 1 << 5)
}

public enum AuthorizationState: Equatable, Sendable {
    case notRequired, notDetermined, authorized, denied
}

public struct MediaItem: Equatable, Sendable {
    public var title: String
    public var artist: String?
    public var duration: TimeInterval?
    public var position: TimeInterval?
    public var isPlaying: Bool
    public var artworkData: Data?
    public init(title: String, artist: String? = nil, duration: TimeInterval? = nil,
                position: TimeInterval? = nil, isPlaying: Bool, artworkData: Data? = nil) {
        self.title = title; self.artist = artist; self.duration = duration
        self.position = position; self.isPlaying = isPlaying; self.artworkData = artworkData
    }
}

/// Contrato de proveedor multimedia (§5.1). Implementaciones por aplicación.
public protocol MediaProvider: Sendable {
    var id: String { get }
    var capabilities: MediaCapabilities { get }
    var authorizationState: AuthorizationState { get async }
    var currentItem: MediaItem? { get async }
    func play() async throws
    func pause() async throws
    func skip(forward: Bool) async throws
    func seek(to position: TimeInterval) async throws
    /// Emite cada cambio de `currentItem`; nil = fuente perdida (limpiar metadatos).
    func observe() -> AsyncStream<MediaItem?>
}
