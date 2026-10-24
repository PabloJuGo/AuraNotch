import AppKit
import AuraCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Dónde está la portada de la pista actual: bytes ya locales (Música) o una URL que da el reproductor (Spotify).
public enum ArtworkLocation: Equatable, Sendable {
    case data(Data)
    case remote(URL)
}

/// Extensión ADITIVA al contrato de AuraCore: proveedores que saben localizar su portada.
public protocol MediaArtworkSource: MediaProvider {
    /// nil = sin portada o sin permiso. Nunca debe mostrar diálogos ni lanzar la app.
    func artworkLocation() async -> ArtworkLocation?
}

/// Descarga de una portada remota. Inyectable: las pruebas no usan la red real.
public protocol ArtworkDataLoader: Sendable {
    func data(from url: URL) async throws -> Data
}

/// Única petición de red de la app. Solo https, sin cookies ni caché en disco, tiempo límite corto y tamaño máximo.
/// (ATS además bloquea cualquier redirección a http.)
public struct URLSessionArtworkLoader: ArtworkDataLoader {
    private let session: URLSession

    public init() {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        c.timeoutIntervalForResource = 8
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        session = URLSession(configuration: c)
    }

    public func data(from url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw URLError(.unsupportedURL) }
        let (bytes, response) = try await session.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= Int64(ArtworkImage.maxBytes)
        else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > ArtworkImage.maxBytes { throw URLError(.dataLengthExceedsMaximum) }
        }
        return data
    }
}

enum ArtworkImage {
    static let maxBytes = 4_000_000
    static let maxPixel = 256  // la vista pinta 72 pt: 256 px cubre @2x y no guarda imágenes enormes en memoria

    /// Valida que son bytes de imagen reales y los reduce a un JPEG pequeño. nil = descartar. Llamar fuera del MainActor.
    static func thumbnail(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maxBytes, let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
}
