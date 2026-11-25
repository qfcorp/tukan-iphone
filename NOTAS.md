# Bloc de notas — Tukán iPhone (qfcorp/tukan-iphone)

Última actualización: 25 nov 2026

## Plan

1. ✅ Crear el repo **público** `qfcorp/tukan-iphone` (minutos de Mac gratis).
2. ✅ Cascarón común en Swift (WebView a pantalla completa) + generador + prueba en simulador.
3. ✅ 12 nov: **TuFlota** y **TuDron** compiladas en la Mac de GitHub y probadas en el simulador **iPhone 17**: las dos **ABRE BIEN** (costo $0).
   - ⚠️ TuFlota muestra en su portada «USD 5 per month» y «7-day free trial». Antes de enviar a Apple, el servidor
     debe esconder precios y botones de pago cuando el navegador diga `TukanIOS` (ver «Reglas de Apple»).
   - El simulador está en inglés y la web se muestra en inglés; en un iPhone en español sale en español.
4. ✅ 13 nov (noche): cuenta de Apple Developer **pagada y aprobada** (equipo `2CXYP5A9C9`, Qfcorp S.P.A. Simplificada).
   - Clave de API de App Store Connect guardada en el secreto `ASC_KEY_P8` (ID `L2M6297P3F`).
   - Las **22 fichas** creadas en App Store Connect (desarrollador «Tukán Software», idioma Español (México)).
     TuBroadcast necesitó registrar a mano su App ID `com.tukansoftware.tubroadcast` en developer.apple.com.
   - `.github/workflows/subir-testflight.yml` (app=todas, subir=si): arma sin firmar, firma al exportar con la clave de API
     y sube con `altool`. Run 43542035757: **22/22 UPLOAD SUCCEEDED**.
   - `.github/workflows/grupo-testflight.yml` + `herramientas/testflight_grupo.py`: crea en cada app el grupo interno
     «Tukán» (acceso a todas las versiones) y mete a **todos los usuarios del equipo**. Volver a correrlo cada vez que se
     agregue un usuario nuevo. Probado con API simulada y en real (22/22).
   - Probador del iPhone: correo personal invitado como usuario del equipo con rol **Marketing** (Dimitry debe tocar
     «Invitar» y aceptar el correo en el iPhone; después correr `grupo-testflight.yml`).
   - En TestFlight NO se usa «código de canje»: se entra con el correo de invitación → «Ver en TestFlight».
5. 🚀 14 nov: **publicación en la App Store, 3 cada 3 horas** (pedido de Dimitry).
   - Enviadas a revisión de Apple: **EN VIVO Tycoon** y **QF Deportes** (14 nov ~11:00 Ecuador) y **TuBroadcast** (~11:45).
   - Todo automático en `.github/workflows/publicar-app-store.yml` (cada 3 horas) + `herramientas/publicar_app_store.py`:
     llena textos, capturas, edad, precio gratis, países (sin la UE: falta declaración DSA), revisor y envía.
     Lee `publicacion/fichas/<app>.json`, `publicacion/capturas/<app>/`, `publicacion/cola.json` (orden, pausada,
     `subida_desde`) y guarda en `publicacion/estado.json`. Modos: tanda / preparar / enviar / estado.
   - **Si Apple rechaza una app, la cola se pausa sola** y se abre un issue en GitHub.
   - Capturas: `.github/workflows/capturas-app-store.yml` + `herramientas/sacar_capturas.sh` (iPhone 6.9", español, 9:41).
     En la ficha: `"capturas": [{"espera": 8, "url": "...", "argumentos": [...]}]`.
   - Secretos: `ASC_KEY_P8`, `REVISOR_TELEFONO` (puesto por Dimitry 14 nov), `DEMOS_REVISOR` (opcional, JSON `{"app": {"usuario": "...", "clave": "..."}}`) y **`REVISOR_CLAVE`** (25 nov: la misma
     contraseña del revisor de Google Play en todas las apps; el usuario `revisor.google@tukanec.com` va en `"demo"` de cada ficha).
     Ficha con `"esperar": "motivo"` = no se envía todavía.
   - Privacidad de la app (no hay API): se llena en App Store Connect a mano. Hecha: TuBroadcast y QF Deportes (no recogen
     datos), EN VIVO (nombre, correo, partida, chat, ID, uso y errores; vinculados, sin rastreo). **Falta en las otras 19.**
   - Cambios en la plantilla: apps **solo iPhone** (sin iPad), **bloqueo de anuncios y rastreadores** (Google Ads/Analytics,
     Meta Pixel...) para no necesitar permiso de rastreo, y argumento `-capturaURL` para capturas.
6. ⏳ Probar en el iPhone de Dimitry con **TestFlight** y luego enviar a revisión de Apple (capturas, descripción,
   privacidad, cuenta demo para el revisor, declaración de comerciante UE).
   - Internas (JD Entregas, JD Logística, QF ERP, QF Flota): primero intentar App Store pública; si Apple las rechaza,
     quedan solo en TestFlight y hay que **subir versión nueva cada 90 días** (las versiones de TestFlight vencen a los 90 días:
     las del 13 nov vencen ~11 feb 2027).
6. ✅ 13 nov: agregadas **todas** las apps (18 en total): las 15 de Android que faltaban (mismo nombre, paquete, color e ícono que en
   `qfcorp/tukan-apps`) + el juego **EN VIVO Tycoon** (`apps/envivo`, juego.tukanec.com). La dirección abre con `app=ios`
   (u `origen=ios`) en vez de `app=play`, para que el servidor no muestre el cobro de Google Play.
   - También **QF ERP**, **QF Flota** (erp.tupassec.com, mismos bundle ID que en `erp-qf-patches/apps_ios`) y **QF Deportes**
     (`com.qfproducciones.app`, qfproducciones.com). Dimitry autorizó (13 nov) pasar sus cascarones a este repo público porque
     `erp-qf-patches` es privado y GitHub lo tiene bloqueado hasta el 1 de diciembre. El código del ERP no se publica. Total: **21 apps**.
   - 13 nov: Dimitry dijo que **Android no hace falta compilar ahora**, solo iPhone.
   - **TuBroadcast** no es cascarón web: se escribió una **app nativa en Swift** en `nativas/tubroadcast/` (13 nov) con
     HaishinKit 2.3.0 (RTMP/RTMPS y SRT): cámara trasera/frontal, micrófono on/off, linterna, varias conexiones guardadas,
     resolución 720p/1080p, fps, bitrate y enlaces de configuración `tubroadcast://set/v1?...` (formato Grove de Larix).
     Se compila con `.github/workflows/compilar-nativas.yml` y se prueba con `nativas/probar_nativa.sh`.
     **Falta** (para igualar a Android): licencia del Panel Tukán Central, control remoto (Tuner), overlays, retorno de audio,
     grabación, NDI, HEVC y bitrate adaptable. La cámara real solo se puede probar en un iPhone (TestFlight).
7. ⏳ Actualizar manuales y presentaciones de cada programa con «Disponible en iPhone».

## TuBroadcast iPhone Pro (23 nov 2026, rama `tubroadcast-ios-pro`)

Decisiones de Dimitry (23 nov 2026), hechas en `nativas/tubroadcast`:

- **Gratis** (sin plan): RTMP y SRT, máximo **720p**, marca de agua **«TuBroadcast»** quemada en el video que sale
  (HaishinKit en modo `offscreen` + `TextScreenObject`) y también en la vista; la transmisión **se corta sola a los 5 minutos**
  con el aviso «La versión gratis transmite hasta 5 minutos. Activa un plan para seguir.» (`Sources/Limites.swift`).
- **Planes**: Básico = RTMP/RTMPS sin límites (con Básico, una conexión SRT va con los límites gratis); Completo = RTMP + SRT
  sin límites; Pase 24 h = todo. Se decide por los módulos `rtmp` / `srt` de la licencia firmada.
- **Compra dentro de la app con Apple (StoreKit 2)** (`Sources/Tienda.swift`). 20 productos, precios SOLO de Apple
  (`Product.displayPrice`):
  - Suscripciones auto-renovables, **un solo grupo «TuBroadcast»**: `tubroadcast.basico.N.mes`, `tubroadcast.basico.N.anio`,
    `tubroadcast.completo.N.mes`, `tubroadcast.completo.N.anio`.
  - Consumible: `tubroadcast.pase24.N`. N = 1, 3, 5, 10 celulares.
  - Niveles sugeridos en el grupo (1 = el mayor; mes y año del mismo plan comparten nivel): Completo 10 → 1, Completo 5 → 2,
    Completo 3 → 3, Completo 1 → 4, Básico 10 → 5, Básico 5 → 6, Básico 3 → 7, Básico 1 → 8.
  - La compra lleva `appAccountToken` = UUID guardado en el llavero. Luego la app manda al panel
    `POST https://panel.tukanec.com/tubroadcast_api.php?a=apple_compra` con
    `{dispositivo, modelo, version, versionApp, transaccion: <jwsRepresentation>, app_cuenta: <UUID en minúsculas>}`.
    Respuesta = la de `activar` + `{codigo, plan, celulares, expira}`. Si `celulares > 1` se muestra el código del paquete
    («Comparte este código con los otros celulares del paquete») con botones Copiar y Compartir.
  - La transacción solo se termina (`finish`) cuando el panel la acepta; sin internet queda pendiente y se reintenta al abrir la
    app (`Transaction.unfinished`) o con «Restaurar compras» (`AppStore.sync`). Se escucha `Transaction.updates` (renovaciones).
  - «Gestionar suscripción» abre `AppStore.showManageSubscriptions`.
- **Activar con código** `TB-XXXX-XXXX` (pagaron por fuera o los otros celulares del paquete): `POST a=activar`, mismo JSON que
  Android `{codigo, dispositivo, modelo, versionApp}`. Regla de Apple 3.1.1 / 3.1.3(b): la app **no** tiene enlaces ni textos
  para comprar fuera (ni web, ni precios externos, ni Plux): solo el campo del código.
- **Liberar este celular** (Ajustes > Licencia): `POST a=liberar {dispositivo, token}` → `{ok, mensaje, cambios_restantes}`;
  con 429 se muestra el mensaje del servidor. Al liberar, la app vuelve a la versión gratis.
- **Licencia** (`Sources/Licencia.swift`, `Sources/GestorLicencia.swift`): firma ECDSA P-256 verificada con CryptoKit y la
  **misma llave pública que Android**; latido cada 30 s con licencia (`a=latido`, 401 = vuelve a gratis); sin internet vale
  hasta 72 h. Id del celular = UUID propio en el llavero (no IDFA).
- **Pantalla Planes**: productos agrupados por 1/3/5/10 celulares, mensual/anual/pase, texto de renovación automática y enlaces a
  [Términos](https://tukansoftware.com/terminos.html) y [Privacidad](https://tuner.tukanec.com/?r=privacidad).
- El video sale vertical u horizontal según cómo se tenga el celular al tocar EN VIVO (antes siempre 1280×720).

**Pruebas** (`nativas/tubroadcast/Tests`, target `TuBroadcastTests`, corren en `compilar-nativas.yml`, paso «Pruebas automaticas»):
StoreKitTest con `TuBroadcast.storekit` (20 productos, precios de ejemplo; también está en el esquema para el simulador),
compra → `apple_compra` (panel falso con `URLProtocol`), pase 24 h, compra sin internet que se reintenta, activar con código
(bien, código malo, firma falsa, sin internet), liberar (OK y 429), latido (renueva, 401, sin internet, más de 72 h), licencia
firmada válida / alterada / otra llave / vencida / otro celular, firma hecha con openssl (como el panel PHP) y límites gratis
(720p, marca de agua, 5 minutos con reloj falso, también en el `Motor`).
Cuando la app corre como anfitriona de las pruebas no arranca latidos, compras ni cámara.
- ✅ 23 nov 2026: run **45210059784** de `compilar-nativas.yml` en la rama: **38 de 38 pruebas pasan** y la app **ABRE BIEN**.
- Ojo 1: error de Apple (FB22237318) con los simuladores **iOS 26.3 a 26.5**: `xcodebuild test` no carga el `.storekit` y
  SKTestSession falla («Error saving configuration file», SKInternalErrorDomain 3). El workflow elige el simulador iOS más
  nuevo que **no** esté en ese rango (hoy iOS 26.2 en la Mac de GitHub). Las pruebas se firman con firma local «-».
- Ojo 2: dentro de XCTest, `Product.purchase()` se queda esperando la hoja de pago de Apple en el simulador. Las pruebas compran
  con `SKTestSession.buyProduct(identifier:options:)` (con el `appAccountToken`) y pasan por `Tienda.procesar`, que es el mismo
  camino que usa la app después de `purchase()`, `Transaction.updates` y `Transaction.unfinished`. `purchase()` en sí solo se
  prueba a mano (TestFlight / sandbox).
- Contrato final del panel (rama `tubroadcast-apple` de tukan-central, e70e276): `apple_compra` → 200 con `expira` en segundos
  unix; errores 400 / 402 (firma mala, vencida, revocada, sandbox no permitido) / 403 (paquete lleno: usar «Liberar este
  celular») / 429, y la app siempre muestra el `mensaje` del servidor (la compra queda sin terminar y se reintenta).
  `liberar` → 200 `{ok, mensaje, cambios_restantes, codigo}`, 429 (se muestra el mensaje), 401 (el celular queda libre igual).
  Con paquete de 1 celular, restaurar en otro iPhone mueve la compra a ese iPhone.

**Falta antes de enviar a Apple:**
1. En App Store Connect: crear los 20 productos con esos IDs (grupo «TuBroadcast»), precios, nombres en español, captura
   para revisión de cada uno, y aceptar el **Acuerdo de apps de pago** (datos bancarios y fiscales).
2. Panel: `apple_compra`, `apple_notificacion` y `liberar` (lo está haciendo otro compañero en `tukan-central`). El panel debe
   comparar `app_cuenta` con el `appAccountToken` del JWS sin importar mayúsculas.
3. Actualizar en App Store Connect la **privacidad de la app** (ahora sí se manda al panel: id propio del celular, modelo y
   compras, para que funcione la app; sin rastreo) y las notas para el revisor (cómo probar las compras y el código).
4. Probar en un iPhone real con TestFlight (sandbox): cámara, marca de agua en YouTube/vMix, corte a los 5 minutos, compra.

## EN VIVO Tycoon 1.0.1: compras con Apple (25 nov 2026)

- La plantilla trae el puente `tukanAppStore` (`plantilla/Sources/TiendaApple.swift`, StoreKit 2) solo si `apps/<app>/app.json`
  tiene `"compras_apple": true` (hoy solo `envivo`). El juego lo usa desde `js/appstore.js` (repo `qfcorp/envivo-tycoon`):
  acciones `productos`, `comprar` (con `cuenta` = `apple_cuenta` → appAccountToken), `terminar`, `pendientes`, `restaurar`
  y el evento de ventana `tukanAppStore`. Revisado el 25 nov: los dos lados calzan (nombres, parámetros y respuestas).
- Lista de compras: `publicacion/compras/envivo.json` (sale de `php server/bin/apple_productos.php` en el juego; ids
  `envivo.<id>`, nombre <= 30, detalle <= 45, `precio_usd`, `tipo` CONSUMABLE / NON_CONSUMABLE). Si cambia el catálogo
  del juego, volver a generarla. `python3 herramientas/crear_compras.py probar` también revisa estas listas (sin Apple).
- Crear/completar en App Store Connect: workflow `crear-compras.yml` con `modo=envivo` (se puede repetir; no duplica).
- Captura de revisión de las compras: `publicacion/capturas/envivo/revision/tienda.png` (1290x2796, Tienda > Créditos,
  sacada con el arnés de `tests/test_appstore.js` del juego). No entra en las capturas de la ficha (solo `capturas/envivo/*.png`).
- Ficha: `"crear_version": true` y `"compras_con_version": true` (las compras se mandan a revisión junto con la versión 1.0.1).

## Reglas de Apple a cuidar

- ✅ 13 nov: **respaldo dentro de la app** (`plantilla/Sources/TukanApp.swift`, `enum Pagos`): esconde con CSS las partes de pago comunes
  de Tukán (`.tukan-pago`, `#pago-tarjeta`, `.tukan-sugerencia`, `#pago-play`, `.boton-play`, `.modulo-precio`, `.solo-web`…), pone la clase
  `tukan-ios` en `<html>` y **no abre** páginas de pago (pagos.tukanec.com, Plux, Payphone, PayPal, Stripe, Google Play, `r=play_compra`).
  El servidor de cada programa además los esconde de verdad cuando el navegador dice `TukanIOS` (en curso, 13 nov).

- **Pagos dentro de la app:** Apple obliga a usar su cobro (In‑App Purchase) para planes que se venden
  dentro de la app. Los programas se cobran por la web (Plux). En la app de iPhone **no** debe salir
  ningún botón de pagar ni precios: el servidor debe esconderlos cuando el navegador diga `TukanIOS`
  (igual que se hace con la app de Google Play). **Pendiente** en cada programa.
- **App que es solo una página web** (regla 4.2): la app trae funciones propias (sin internet,
  recargar, permisos de cámara/ubicación). Si Apple la rechaza, se agregan notificaciones push.
- **Cuenta de prueba para el revisor:** Apple pide usuario y clave de demo de cada programa.
- **Nombres:** no usar nombres de entidades públicas (como pasó con «SRI» en Google Play).

## Costos

- Compilar aquí: **$0** (repo público).
- Tope de gasto en GitHub (cuenta qfcorp): Actions en **$0 con uso bloqueado** y **sin tarjeta**:
  nunca hay cobros sorpresa. Para subirlo a $5 primero habría que poner una tarjeta en GitHub.
- Apple Developer: **$99 al año** (lo paga Dimitry).

## Historial

- 25 nov 2026: **EN VIVO Tycoon 1.0.1**: lista de 28 compras de Apple (`publicacion/compras/envivo.json`), captura de revisión,
  ficha con versión nueva + compras y notas del revisor con cómo probar las compras.

- 23 nov 2026: **TuBroadcast iPhone Pro** (rama `tubroadcast-ios-pro`): versión gratis con límites, compras con Apple (StoreKit 2),
  activar con código, liberar celular y licencia del Panel Tukán Central. 38/38 pruebas y ABRE BIEN (run 45210059784).

- 13 nov 2026 (13:35): JD Entregas y TuSpa relanzadas: **ABRE BIEN**. Con la plantilla sin precios, **las 22 apps de iPhone ABRE BIEN** (21 cascarones + TuBroadcast nativa).

- 13 nov 2026 (12:48): con la plantilla que esconde precios (9decc7c): **19 de 21 cascarones ABRE BIEN** + TuBroadcast nativa ABRE BIEN. JD Entregas y TuSpa los canceló GitHub por falta de Mac (no por código): relanzados.

- 13 nov 2026 (11:20): **17 de 22 ABRE BIEN** en el simulador: TuBroadcast (nativa), EN VIVO Tycoon, QF ERP, QF Flota, Flota Tukán, JD Entregas, JD Logística, TuAcademia, TuEvento, TuFactura, TuGroomer, TuGuardería, TuLavadora, TuMecánica, TuPlanner, TuSalón y TuSpa. Las otras 5 (QF Deportes, TuDron, TuHospedaje, TuVocalía, Tukán Mensajes) las canceló GitHub porque no había Mac libre («not acquired by Runner»), no por error del código: se volvieron a lanzar.

- 13 nov 2026: TuBroadcast nativa para iPhone (primera versión) en `nativas/tubroadcast`, con su propio workflow.

- 13 nov 2026: agregadas QF ERP, QF Flota y QF Deportes (21 en total). El workflow deja correr a la vez «todas» y una app sola sin cancelarse.
- 13 nov 2026: agregadas 16 apps (15 Tukán/JD + juego EN VIVO Tycoon). Generador probado con las 18 (todas «Listo»). Compilación y prueba en simulador en GitHub Actions.

- 12 nov 2026 (tarde): textos de ficha para la App Store (`appstore/TEXTOS_APP_STORE.md`, Flota Tukán y TuDron, es/en), guía de primeros pasos y manual corto de iPhone (`docs/`, con PDF), sin precios ni pagos. Falta: capturas de la ficha, cuenta de demo del revisor y que el servidor esconda precios con `TukanIOS`.
- 12 nov 2026: primera compilación: TuFlota ABRE BIEN; TuDron fallaba por el «&» de su dirección en la prueba (arreglado). Segunda: las dos ABRE BIEN.
- 12 nov 2026: repo creado por Dimitry; estructura, generador, prueba en simulador y workflow
  (TuFlota y TuDron) hechos por Claude.
