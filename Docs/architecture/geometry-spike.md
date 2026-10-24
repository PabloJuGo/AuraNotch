# Spike de geometría (AURA-001) — hallazgos en este Mac

Medido el 24-10-2026 con `NSScreen` (MacBook Air con notch, pantalla 1710x1107, macOS 27, una sola pantalla). Valores reales, no supuestos:

| Propiedad | Valor |
|---|---|
| `frame` | (0, 0, 1710, 1107) pt, escala 2.0 |
| `visibleFrame` | (0, 0, 1710, 1073) → la barra de menús ocupa 34 pt |
| `safeAreaInsets` | top = **33.5**, resto 0 |
| `auxiliaryTopLeftArea` | (0, 1073.5, 762.5, 33.5) |
| `auxiliaryTopRightArea` | (947.5, 1073.5, 762.5, 33.5) |
| Hueco de la cámara (deducido) | x 762.5…947.5 → **185 pt** de ancho × 33.5 de alto, centrado en x = 855 |
| `accessibilityDisplayShouldReduceMotion` | false |

## Decisiones de diseño derivadas

- **El notch se deduce, no se hardcodea:** `ScreenMetrics.notchRect` = hueco entre `auxiliaryTopLeftArea.maxX` y `auxiliaryTopRightArea.minX`, con la altura de `safeAreaInsets.top`. Sin notch (o datos incoherentes) devuelve `nil` y se usa el modo flotante.
- **Coordenadas de las áreas auxiliares:** en esta máquina (origen 0,0) local y global coinciden, así que **no se pudo comprobar** si AppKit las da en coordenadas locales o globales en una pantalla con origen desplazado. `ScreenMetrics` tolera ambas (si el área no cae dentro del `frame`, la desplaza al origen de la pantalla). Probado solo con pantallas sintéticas.
- **Anclaje:** modo notch = ventana pegada al borde superior físico (`frame.maxY`), por encima de la barra de menús; el expandido (600×460 por defecto) crece hacia abajo hasta `visibleFrame.minY` (respeta el Dock). Modo flotante = 6 pt bajo la barra de menús, dentro de `visibleFrame`.
- **Compacto:** el notch + 42 pt por lado (antes 48; ver ADR 0003: las "alas" son lo único visible junto a la cámara; no se dibuja dentro de ella). Reposo sin actividad: exactamente el hueco del notch.
- **`CGRect.height` devuelve valor absoluto:** un alto negativo parece válido. La validación de pantallas degeneradas se hace con los números antes de construir el `CGRect` (hallado por las pruebas).
- **Ventana:** frame = rect de reposo (idle/compact) cuando está asentada y rect expandido durante la transición y mientras está abierta; solo cambia el frame al asentarse, no por fotograma (la forma visible se anima dentro, desde `MotionCoordinator`). Durante la transición (~0.3 s) la zona transparente del rect expandido ya NO captura el ratón: el controlador pone `ignoresMouseEvents` según la posición del puntero respecto a la forma visible, re-evaluado en cada fotograma (ADR 0003).

## Pantalla completa — detector sin permisos (actualizado, ver ADR 0003)

Spike real (24-10-2026, macOS 27, notch): proceso hijo propio con ventana `toggleFullScreen`, proceso padre accessory leyendo
`CGWindowListCopyWindowInfo([.optionOnScreenOnly])` (sin `.excludeDesktopElements`) y `NSScreen`.

| Señal | Escritorio con ventana maximizada | App propia a pantalla completa nativa |
|---|---|---|
| Bounds de la ventana de la app (layer 0) | (0,34,1710,1073) | **(0,34,1710,1073)** — idéntico (en notch la app queda bajo la cámara); solo durante la animación mide (0,0,1710,1107) |
| `NSScreen.visibleFrame` | (0,0,1710,1073) | (0,0,1710,1073) — sin cambio |
| Ventana «Menubar» de Window Server (layer 24) | (0,0,1710,34) | (0,0,1710,34) — sigue ahí |
| Ventanas de otras apps en la lista | sí | desaparecen (otro Space), pero también ocurre en un escritorio vacío |
| Sonda `canJoinAllSpaces` `isOnActiveSpace` | true | true (se ve también en pantalla completa) |
| Sonda sin `canJoinAllSpaces` `isOnActiveSpace` | true | **false** — pero también lo sería en CUALQUIER otro escritorio normal: descartada |
| **WindowManager «Fullscreen Backdrop»** (layer −2147483622 = `desktopWindow`+1) | **no existe** | **existe** (0,0,1710,1107), junto al «Wallpaper» (−2147483624) |

Veredicto: la geometría de la app no sirve (confirma el spike anterior), pero el sistema crea el backdrop mientras el Space activo es de
pantalla completa. `FullscreenHeuristic` (pura, `FullscreenDetector.swift`) lo detecta por propietario `WindowManager` + capa
`desktopWindow + 1` (o por nombre si el sistema lo expone; el nombre no es necesario, no hace falta Screen Recording) y exige que cubra la
pantalla del panel. Segunda regla (R2, no verificada en esta máquina): ventana normal (layer 0) de otra app que cubre TODA la pantalla incluida la
franja de la barra de menús (kiosco/juegos/pantalla completa no nativa).

Tiempos medidos con el detector real (proceso hijo → veredicto): entrar = veredicto `true` en la propia notificación `activeSpaceDidChange`
(~0,6 s tras `toggleFullScreen`, al terminar la animación); salir = la lectura inmediata aún ve el backdrop, la lectura diferida a +0,4 s da `false`
(por eso hay lecturas a +0,4 s y +1,2 s tras cada evento; ni polling ni temporizadores permanentes).

Limitaciones explícitas: (1) el backdrop es un detalle interno de macOS 27 sin garantía; si cambia, el detector deja de ver los fullscreen nativos
(falla en abierto = el panel se ve, como antes) — la regla se aísla en un único `if`; (2) probado solo con una pantalla y un Space de pantalla completa
de una app propia; Split View, Stage Manager y varias pantallas con «Pantallas con Spaces independientes» no probados (se compara contra los bounds de
la pantalla del panel, `CGDisplayBounds`); (3) R2 sin verificar.

## Pendiente de verificar en hardware

- Pantalla externa conectada/desconectada con el panel abierto (solo cubierto con pantallas sintéticas y el observador de `didChangeScreenParameters`).
- Cambios de resolución/escala, sleep/wake real, varios Spaces.
