# DESIGN — Aura Notch

Implementación: `Packages/AuraDesignSystem`. **Todos los valores son iniciales y están por validar en hardware real** (MacBook con notch, Reduce Motion, alto contraste); ninguno es un valor oficial de Apple.

## 1. Principios
Superficie negra y precisa fundida con el notch; tipografía y SF Symbols del sistema; sin gradientes decorativos, sin sombras pesadas, sin animaciones permanentes. Las vistas son funciones puras de sus props (sin estado global ni timers); solo guardan estado local de hover.

## 2. Tokens (Swift: `Tokens.swift`)

### Espacio (`Space`, rejilla de 4 pt)
| Token | pt | Uso |
|---|---:|---|
| `Space.xs` | 4 | separación mínima |
| `Space.sm` | 8 | icono–etiqueta, padding horizontal de control |
| `Space.md` | 12 | elementos internos, padding del compacto |
| `Space.lg` | 16 | padding del panel |
| `Space.xl` | 24 | secciones |

### Radios (`Radius`, `NotchShape`)
| Token | Valor | Uso |
|---|---|---|
| `Radius.compact(height:)` | alto/2 (cápsula) | radio inferior del compacto |
| `Radius.panel` | 20 pt | radio inferior del expandido |
| `Radius.control` | 10 pt | controles |
| empalme superior | 6 pt compacto / 14 pt expandido | unión cóncava con el borde de pantalla (valor inicial propio) |

### Color (`AuraColor`, `TokenColor`)
Cada token tiene 4 variantes: claro, oscuro, claro+alto contraste, oscuro+alto contraste, resueltas con `NSColor` dinámico según la apariencia efectiva de la vista. **El notch es negro en cualquier apariencia, por lo que claro == oscuro** (la API mantiene el eje por si el modo flotante o los ajustes divergen). Valores sRGB (estándar → alto contraste):

| Token | Estándar | Alto contraste | Nota |
|---|---|---|---|
| `surface` | #000000 | #000000 | negro puro |
| `elevatedSurface` | blanco 11 % | blanco 17 % | hover, seleccionado, subpaneles |
| `pressedSurface` | blanco 20 % | blanco 26 % | control pulsado (añadido) |
| `primaryText` | #FFFFFF | #FFFFFF | |
| `secondaryText` | blanco 68 % | blanco 85 % | |
| `separator` | blanco 24 % | blanco 52 % | no decorativo en HC (≥3:1) |
| `accent` | (10,132,255) | (89,173,255) | |
| `warning` | (255,158,10) | (255,184,77) | |
| `destructive` | (255,69,59) | (255,115,107) | |
| `success` | (48,209,89) | (102,230,133) | añadido a los 8 de §3.2 para el estado `success` |

Contraste verificado por pruebas (WCAG 2.x): todo texto/icono ≥ 4.5:1 sobre `surface` y `elevatedSurface` en las 4 variantes; ≥ 7:1 en alto contraste. Los estados no dependen solo del color (símbolo `checkmark` / `exclamationmark.triangle`).

### Tipografía (`AuraFont`)
Fuente del sistema (San Francisco). `moduleTitle` = headline, `body` = callout, `secondary` = caption, `compact` = caption medium, `numeric` = caption con dígitos monoespaciados. macOS no tiene Dynamic Type: los estilos de SwiftUI dan tamaños fijos; revisar legibilidad en hardware.

### Movimiento (`Motion`)
Las duraciones **no se duplican**: salen de `Transition` (AuraCore, §4.3).

| Preferencia | Curva | Duración |
|---|---|---|
| `.full` | muelle amortiguado críticamente (`bounce: 0`, overshoot ≈ 0) | la del catálogo AN-01…AN-11 |
| `.reduced` (AN-12) | fundido `easeOut` | `min(catálogo, 120 ms)` |
| `.none` | sin animación (`Motion.animation` = nil) | 0 |

Preferencia efectiva = `\.auraMotion` (inyectada por el MotionCoordinator) si existe, si no `accessibilityReduceMotion` del sistema. `Motion.contentTransition(_:)`: opacidad + escala 0.97 anclada arriba en `.full`; solo opacidad si no. Uso en componentes: cambios de estado de control (AN-09, 160 ms), selección de módulo (AN-04, 180 ms). La transición de contenido entre módulos y el morph de contenedor son responsabilidad del host (un solo coordinador, §4.2.1).

## 3. Anatomía

### `NotchShape`
Silueta con esquinas superiores unidas al borde de pantalla (empalme cóncavo de radio `topRadius`) y esquinas inferiores convexas (`bottomRadius`). El rect incluye los empalmes (`topRadius` por lado). `animatableData` interpola ambos radios; el tamaño lo anima el frame. Los radios se recortan al rect actual, de modo que tamaños intermedios degenerados no producen artefactos.

### Compacto (`CompactContent`)
Izquierda: icono SF Symbol de la única actividad dominante. Centro: hueco `centerGap` para el notch físico. Derecha: texto breve (1 línea, truncado) **o** anillo de progreso estático. `nil` = idle: no dibuja ni aparece en VoiceOver. Iconos: media `waveform`/`pause.fill`, transferencia `arrow.down.circle`, temporizador `timer`, error `exclamationmark.triangle.fill` (warning).

### Expandido (`ExpandedChrome`)
Cabecera (título del módulo + `ModuleNavBar` discreta) → contenido (slot genérico) → separador → pie (acciones opcionales + ajustes `gearshape`). `topInset` reserva la zona del notch físico. Padding horizontal = empalme (14) + `Space.lg`. Orden de foco/VoiceOver: título → navegación → contenido → pie.

### Navegación (`ModuleNavBar`)
Un botón de icono por `NotchModule` (`house`, `music.note`, `tray`, `calendar`, `square.grid.2x2`). Tab con Full Keyboard Access; flechas ←/→ cambian la selección. VoiceOver: grupo «Módulos», etiqueta por módulo y rasgo «seleccionado».

### Vacío y error
`EmptyStateView` (símbolo, título, mensaje, acción opcional). `ErrorStateView` (UI-18): título, **causa**, **solución**, «Reintentar» y, si procede, «Abrir Ajustes del Sistema».

## 4. Estados de control (`ControlState`, `ControlAppearance`, `AuraButtonStyle`)
| Estado | Primer plano | Fondo | Extra |
|---|---|---|---|
| normal | secondary/primary text | ninguno (`filled`: elevatedSurface) | |
| hover | primaryText | elevatedSurface | |
| pressed | primaryText | pressedSurface | |
| focus | primaryText | como normal | anillo `accent` 2 pt |
| disabled | secondaryText al 40 % | como normal | sin contraste exigido (WCAG 1.4.3) |
| loading | secondaryText | como normal | `ProgressView` pequeño; valor VoiceOver «Cargando» |
| success | success | como normal | `checkmark`; «Completado» |
| error | destructive | como normal | `exclamationmark.triangle`; «Ha fallado» |

Precedencia: disabled > loading/success/error > pressed > hover > focus > normal. El anillo de foco se dibuja siempre que el control tenga foco de teclado. `loading/success/error` se pasan con `AuraButtonStyle(status:)`. Hit-area mínima 28×28 pt.

## 5. Cadenas
Todas en `Strings.swift`, claves en español vía `String(localized:)`; localizar = añadir catálogo de cadenas (no hay recursos todavía).

## 6. Verificación
- `swift run AuraSelfTests` (suite `DesignTests.swift`): rejilla 4 pt, duraciones = catálogo con/sin Reduce Motion, interpolación de `NotchShape`, contraste WCAG por variante y por estado de control, mapeo de apariencias, cadenas y SF Symbols existentes.
- Capturas de revisión: `AURA_RENDER_DIR=/tmp/aura-renders swift run --scratch-path .build-design AuraSelfTests` (ImageRenderer, sin ventana, tema oscuro). Limitaciones: `ProgressView` no se rasteriza con ImageRenderer (aparece un símbolo de prohibido en la captura de «loading»; en una ventana real es el indicador nativo); no hay hover/foco/VoiceOver reales ni animaciones en las capturas.
- **No verificado** (requiere ventana/hardware): navegación por flechas, Full Keyboard Access, orden de VoiceOver, hover real, apariencias de alto contraste en sesión real (`NSAppearance(named: .accessibilityHighContrast*)` devuelve la normal fuera de una sesión con «Aumentar contraste»), fluidez de animaciones, aspecto sobre el notch físico.
