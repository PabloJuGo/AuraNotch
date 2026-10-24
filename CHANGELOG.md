# Changelog

## Sin publicar
- Sprint 0: esqueleto SwiftPM, contratos AuraCore, catálogo de transiciones, auditoría de APIs.
- Multimedia: transporte al estilo macOS, título completo en el notch cerrado (alas anchas con texto), permiso de Spotify con diálogo real y recordado entre arranques, estado y portada al arrancar sin esperar al primer cambio de pista.
- Nuevas funciones: módulo Portapapeles (opt-in, solo en memoria), avisos en el notch (reunión próxima, cargador, temporizador), envío por AirDrop desde la estantería, widget de volumen, deslizar con dos dedos para cambiar de canción, atajos ⌘1…⌘6 y ajustes nuevos (título en el notch cerrado, avisos, portada de Spotify).
- Ajustes se abre ya por encima: el panel se pliega al pulsar el engranaje.
- Temas: color de acento (Ajustes → General → Apariencia) y ancho del texto del notch cerrado; el notch cerrado reserva solo el ancho del icono a la izquierda y el del texto a la derecha para no tapar los menús de la app.
- Inicio rediseñado: cabecera con fecha y batería, Reproduciendo con portada y controles, eventos de hoy, portapapeles reciente (si el módulo está activo) y estantería; solo aparece lo que tiene contenido.
- Panel expandido más bajo (380 pt, antes 460): ajustes en la cabecera sin barra inferior, Widgets en rejilla de 2 columnas por filas (anchos solos, estrechos por parejas, alto igualado por fila) y Multimedia centrada.
- Notch cerrado: ecualizador animado (Core Animation, 0 % de CPU en la app) mientras suena algo; con Reducir movimiento queda el símbolo estático.
- Idiomas: la interfaz está en inglés por defecto y se puede cambiar en Ajustes → General → Idioma (English, Español, Français, Deutsch, Português (Brasil), 简体中文); se aplica al reiniciar y la app ofrece el botón. Traducciones en `Resources/<idioma>.lproj`; `Scripts/check-localizations.py` comprueba que no falte ninguna clave ni cambie ningún formato.
- Notch cerrado: tamaño fijo y simétrico (hueco nativo + el mismo ala a cada lado) con cualquier actividad, sin depender del título de la canción; el título se recorta con «…». «Ancho del texto» fija el ala: Estrecho 32 pt, Normal 46 pt, Ancho 64 pt.
