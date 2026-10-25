# Decisiones del proyecto

El propietario delegó las decisiones al LEAD el 24-10-2026 (nombre y licencia confirmados por él). Cada fila: decisión y motivo. Lo no verificable sin una persona o hardware concreto está en «Pendiente de verificación».

## Decididas
| # | Tema | Decisión | Motivo |
|---|---|---|---|
| 2 | Nombre | **Aura Notch** (provisional, confirmado por el propietario) | Sin disponibilidad de marca estudiada |
| 5 | Licencia | **GPL-3.0** (cambiada desde MIT el 2026-10-25) | Cero dependencias externas; compatible |
| 3 | macOS mínimo | 14+ (declarado); verificado solo en 27.0.1 | APIs usadas existen desde 14; no se afirma compatibilidad no probada |
| 4 | Distribución | Directa, firmada y notarizada; **sin sandbox**. Mac App Store descartada | Apple Events a Música/Spotify y bookmarks normales; ver API_CAPABILITIES |
| 7 | Panel claro en flotante | No: superficie siempre negra | Coherencia con el notch; menos superficie de pruebas |
| 8 | Accent | Azul fijo | Contraste garantizado sobre negro |
| 10 | Localización | Cadenas centralizadas en español; catálogo `.xcstrings` en Sprint 5 | Con Xcode se genera y valida |
| 11 | Pantalla completa | Detector heurístico sin permisos (ventana «Fullscreen Backdrop» de WindowManager); falla en abierto | ADR 0003; verificado con datos reales |
| 12/15 | Teclado y Escape | Panel toma foco solo si se abrió por clic/atajo (`KeyboardPolicy.explicitOpenOnly`); ←/→ cambian módulo | ADR 0003; no roba foco con hover |
| 14 | Artwork / seek arrastrable | Fuera de la beta | Exigen Apple Events sin acción del usuario; backlog P1 |
| 16 | Tamaño del panel | 600×460 | Contiene la rejilla de Widgets con datos reales |
| 17 | Alas del compacto | 42 pt | Mínimo que no trunca «04:59» |
| 19 | Acciones favoritas editables | Fuera de la beta (3 integradas) | Backlog P1 |
| 20 | Aviso del temporizador | Sonido «Glass» + notificación (solo `.app`, permiso al primer inicio) | Contextual, degrada a sonido |
| 21 | Rendimiento por fotograma | Medir con Instruments antes de optimizar | Sin datos, no se optimiza |
| — | Tests | Runner `AuraSelfTests` + `swift test` (Swift Testing) sobre la misma biblioteca | Ver ADR 0004 |

## Pendiente de verificación humana o de hardware
| # | Tema | Cómo cerrarlo |
|---|---|---|
| 1 | **Xcode instalado, licencia sin aceptar** | `sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch && sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (requiere contraseña). Desbloquea XCTest, Instruments, notarización |
| 6 | Transiciones a ojo (§4.5), vídeo de cada AN-xx | Revisión manual |
| 9 | Radios del empalme superior (6/14 pt) | A ojo sobre el notch real |
| 13 | Música y Spotify reales | Prueba manual con los reproductores |
| — | Calendario real, notificaciones, arrastre en Finder, VoiceOver | Prueba manual con el `.app` empaquetado |
| — | Pantallas externas, Mac sin notch, Split View, Stage Manager, sleep/wake | No hay hardware/escenario en este entorno |
| 18 | CI | Nunca ejecutado; se valida al primer push |
