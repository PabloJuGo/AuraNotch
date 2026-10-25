# SBOM básico

**Dependencias de terceros: ninguna.** Todo el código es propio (GPL-3.0). Se usan solo frameworks de Apple incluidos en macOS:
SwiftUI, AppKit, Observation, Foundation, EventKit, UserNotifications, ServiceManagement, IOKit (energía), Carbon.HIToolbox (atajo global), ApplicationServices (consulta de permiso de Automatización), CoreGraphics (lista de ventanas para pantalla completa) y Swift Testing/XCTest solo para pruebas.

Herramientas de desarrollo: Swift 6.x, `iconutil`, `codesign` (firma ad-hoc). Sin gestores de paquetes externos; `Package.resolved` no existe porque no hay dependencias.

Revisar este fichero al añadir cualquier dependencia (licencia, mantenimiento, superficie de red).
