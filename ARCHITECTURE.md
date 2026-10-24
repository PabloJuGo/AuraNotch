# Arquitectura

Un único `Package.swift`; cada módulo vive en `Packages/<Nombre>/Sources/<Nombre>`. Dependencias (sin ciclos): todos → `AuraCore`; vistas → `AuraDesignSystem`; `App` es el único que conoce a todos.

| Módulo | Responsabilidad |
|---|---|
| `AuraCore` | Contratos: estados/eventos de superficie, `Transition` (AN-xx), `MediaProvider`, `SelfCheck` |
| `AuraDesignSystem` | Tokens, `NotchShape`, estilos y vistas base (compacto, marco expandido, vacío/error) |
| `AuraNotchSurface` | `NotchGeometry` (pura), `SurfaceStateMachine` (reducer puro), `MotionCoordinator`, `SurfaceWindowController` (NSPanel no activante) |
| `AuraShelf` | Referencias a archivos (bookmarks), acciones seguras, persistencia opt-in, vista |
| `AuraMedia` | Proveedores Música/Spotify, `MediaService` (prioridad, capacidades), vista |
| `AuraPreferences` | `AppSettings`, `SettingsStore`, migraciones, `LoginItem`, ventana de ajustes |
| `AuraWidgets`, `AuraCalendar` | Widgets por manifiesto; EventKit solo lectura tras permiso explícito |
| `AuraAlerts` | `AlertCenter` (un aviso a la vez, el último gana) y publicadores `MeetingAlerts`/`PowerAlerts`. Solo avisos PROPIOS (§5.5): reunión a 5 min (una única espera, sin polling), cargador/carga completa (IOPS) y temporizador; `App/AlertSources.swift` los conecta a los servicios |
| `App` | `AppCoordinator` (ciclo de vida, ajustes→host), `SurfaceRootView` (puente DESIGN↔CORE) |

Decisiones: [Docs/decisions](Docs/decisions). Reglas de oro: una sola máquina de estados y un solo coordinador de movimiento; vistas = funciones de props; sin timers en reposo; I/O fuera del MainActor; toda API de sistema con permiso va tras un protocolo inyectable y se prueba con dobles.
