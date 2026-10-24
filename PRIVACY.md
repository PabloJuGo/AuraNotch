# Privacidad

Aura Notch es local-first: sin cuenta, sin analítica, sin red salvo comprobación de actualizaciones **opt-in** y enlaces que abra el usuario. Ningún permiso (Calendario, Automatización…) se solicita hasta que el usuario activa la función que lo necesita. El shelf guarda referencias, nunca mueve ni borra los originales; la persistencia es opt-in y todo puede borrarse desde Ajustes.

## Portada de Spotify (única petición de red de la app)

- **Qué se descarga:** la imagen de portada de la canción que suena en Spotify, desde la URL https que el propio Spotify expone (`artwork url` de la pista actual, vía Apple Events). No se descarga nada más ni se envía ningún dato propio: es un GET sin cookies, sin cuenta y sin caché en disco.
- **Cuándo:** una vez por canción nueva, solo si Spotify está abierto, la Automatización de Spotify ya está concedida (Aura nunca la pide por esto) y el ajuste está activo. Se cancela al cambiar de canción; tiempo límite de 5 s y tamaño máximo de 4 MB. La imagen se reduce y se guarda solo en memoria (8 portadas como máximo); nunca en disco.
- **Cómo desactivarlo:** Ajustes, opción de portada de Spotify (`loadSpotifyArtwork`). Con ella desactivada no se hace ninguna petición de red y se muestra el icono genérico.
- **Música (Apple):** su portada se lee localmente por Apple Events con el permiso de Automatización ya concedido; no usa red.
