# API_CAPABILITIES — APIs y permisos (AURA-012)

Entorno de verificación: macOS 27.0.1 (26A434), MacBook M4 con notch, Swift 6.2.3 (solo CLT). Estados: ✅ verificado aquí · 🟡 documentado/hipótesis, **sin verificar** · ❌ descartado.

## Geometría
| API | Estado | Notas |
|---|---|---|
| `NSScreen.safeAreaInsets` | ✅ | `top = 33.5 pt` en este Mac. Sin notch debe ser 0 (🟡, falta Mac sin notch/externo). |
| `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` | 🟡 | A medir en el spike de CORE (ver Docs/architecture/geometry-spike.md). |

## Multimedia (proveedores por aplicación, §5.1)
No hay API pública universal de «Now Playing» para terceros.

| Vía | Estado | Permiso | Capacidades |
|---|---|---|---|
| `MediaRemote.framework` (privado) | ❌ P0 | — | Presente en disco, pero es API privada (§14: no depender en P0). |
| `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` | ❌ | — | Públicas, pero solo describen/controlan **la propia app**, no otras. |
| Music.app: `DistributedNotificationCenter` `com.apple.Music.playerInfo` | 🟡 | ninguno | Metadatos y estado (título, artista, duración, estado) sin permisos. Verificar con reproducción real. |
| Music.app: Apple Events (ScriptingBridge/NSAppleScript) | 🟡 | Automation (TCC, por app) | play/pause/next/prev/seek, posición, artwork. |
| Spotify: `com.spotify.client.PlaybackStateChanged` + Apple Events | 🟡 | Automation para control | Análogo a Music. |
| Navegadores/otros | ❌ P0 | — | Fuera de alcance P0 (§5.1). |

**Hallazgo ✅:** un Apple Event a *System Events* sin permiso concedido **bloquea hasta timeout (-1712)** esperando el diálogo TCC. Todo envío de Apple Events debe ser asíncrono, con timeout propio, solo tras acción explícita del usuario y nunca en arranque.

**Decisión propuesta (a ratificar en Sprint 3):** primer proveedor = **Music.app** (lectura por notificación sin permiso; control tras opt-in de Automation). Spotify segundo. Ambos instalados en el Mac de desarrollo.

## Otras
| API | Estado | Notas |
|---|---|---|
| EventKit | 🟡 | Sprint 4; permiso `requestFullAccessToEvents` bajo demanda. |
| `SMAppService` (login item) | 🟡 | Requiere app empaquetada (.app); sin Xcode, empaquetar con script. |
| `UNUserNotificationCenter` | 🟡 | Requiere bundle id y firma. |
| Avisos en el notch (`AuraAlerts`) | ✅ | Solo PROPIOS (§5.5): reunión (EventKit ya concedido), IOPS (`IOPSNotificationCreateRunLoopSource`) y fin de temporizador. Sin lectura de notificaciones de otras apps ni permisos nuevos. |
| `XCTest` / `Testing` / Instruments | ❌ aquí | No en CLT; ver ADR 0001. |

## Resultados de verificación Sprint 3 (multimedia)
Implementación: `Packages/AuraMedia` (`MusicProvider`, `SpotifyProvider`, `MediaService`, `MediaView`). Verificado = comprobado por `swift run AuraSelfTests` con dobles; **pendiente = requiere reproductor real**.

| Punto | Estado |
|---|---|
| Parseo tolerante de payloads (Playing/Paused/Stopped, claves ausentes, caracteres de control, números como String/NSNumber, longitudes) | ✅ con payloads sintéticos |
| `DistributedNotificationCenter` entrega a la propia app una notificación `com.apple.Music.playerInfo` sintética (observar no pide permiso) | ✅ (la clave/nombre reales siguen sin confirmar) |
| Nombres de clave reales de Music (`Name`, `Artist`, `Album`, `Total Time` ms, `Player State`) y de Spotify (`Duration` ms, `Playback Position` s) | 🟡 de documentación de terceros; verificar con reproducción real |
| Music: ¿notifica en pausa/reanudar/seek? ¿incluye posición? | 🟡 se asume que no hay posición en Music (no se muestra barra) |
| Notificación de Stopped y cierre de la app → fuente perdida (`nil`) | ✅ Stopped sintético; cierre vía `NSWorkspace.didTerminateApplicationNotification` 🟡 sin probar con app real |
| `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)` | ✅ compila (API pública); 🟡 su comportamiento (códigos -1744/-1743/-600, sin diálogo) NO se ha ejecutado contra apps reales |
| Solicitud con `askUserIfNeeded: true` (solo al pulsar «Permitir control», fuera del MainActor) | 🟡 sin probar; con la app cerrada devuelve -600 y no hay diálogo |
| Control (play/pause/next/previous/seek) por `NSAppleScript` con `with timeout` + carrera externa | ✅ lógica y mapeo de errores con transporte falso; 🟡 transporte real sin ejecutar |
| Códigos de error mapeados: -1743 denegado, -1744 sin permiso, -1712 timeout, -600/-609 app cerrada | 🟡 de documentación; confirmar con ejecución real |
| Artwork Música: `data of artwork 1 of current track` por Apple Events, solo con Automation ya concedido y `if ... is running` (no relanza la app); se valida y reduce con ImageIO (<= 256 px, máx. 4 MB) fuera del MainActor | ✅ lógica con dobles; 🟡 el tipo de descriptor real (`data` de NSAppleEventDescriptor) y apps sin portada, sin ejecutar con Música real |
| Artwork Spotify: `artwork url of current track` por Apple Events + GET https con `URLSession` efímera (sin cookies/caché, 5 s, 4 MB), caché en memoria por URL (8), cancelable al cambiar de pista. **Única petición de red de la app**; solo si `MediaService.loadsRemoteArtwork` (ajuste `loadSpotifyArtwork`, por defecto activo). Ver PRIVACY.md | ✅ con cargador falso (http rechazado, fallo, caché, cancelación, ajuste off); 🟡 la propiedad `artwork url` y la descarga real sin probar con Spotify |
| Estado inicial: Music/Spotify solo notifican al cambiar, así que al arrancar no hay `currentItem` hasta el primer evento | ✅ por diseño; 🟡 confirmar |

## Hallazgo ✅ (LEAD, macOS 27.0.1): `AEDeterminePermissionToAutomateTarget` se bloquea
Con `askUserIfNeeded: false`, la consulta **no devolvió en >25 s** en un proceso de prueba independiente (Music y Spotify instalados). La suposición «consulta sin diálogo e inmediata» era falsa aquí. `ScriptablePlayerProvider.authorizationState` la ejecuta en un hilo aparte con timeout de 1,5 s y no apila consultas pendientes (prueba de regresión en `MediaTests.swift`). Causa exacta sin determinar (¿diálogo TCC pendiente de otra app? ¿proceso padre?): reprobar fuera de T3 Code/terminal del agente.

## Widget de volumen y controles de sistema descartados
| Control | Estado | Notas |
|---|---|---|
| Volumen de salida (CoreAudio: `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, `kAudioDevicePropertyMute`, oyentes `AudioObjectAddPropertyListenerBlock`) | ✅ | API pública, sin permisos. Lectura real verificada en este Mac (`VolumeService`, sin polling). Salidas sin volumen virtual (algunas HDMI/DisplayPort) se muestran como «sin control»; sin respaldo por canal. 🟡 Escritura, cambio de dispositivo en caliente y HDMI real sin probar. |
| Brillo de pantalla | ❌ | Solo existen `DisplayServices` / `CoreDisplay` (privados) o DDC por I2C en externos (no estable). No se implementa. |
| Micrófono / cámara (silenciar o forzar) | ❌ | macOS no ofrece API pública para apagarlos ni para silenciar la entrada de otras apps por el usuario; solo se puede leer el uso, y eso (`kAudioDevicePropertyDeviceIsRunningSomewhere`) no es control. No se implementa. |
| Modo Concentración | ❌ | No hay API pública para leer o cambiar Focus de forma estable (`ControlCenter`/`donotdisturb` son privados; los atajos requieren Atajos del usuario). No se implementa. |
