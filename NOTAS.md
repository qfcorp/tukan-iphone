# Bloc de notas — Tukán iPhone (qfcorp/tukan-iphone)

Última actualización: 13 nov 2026

## Plan

1. ✅ Crear el repo **público** `qfcorp/tukan-iphone` (minutos de Mac gratis).
2. ✅ Cascarón común en Swift (WebView a pantalla completa) + generador + prueba en simulador.
3. ✅ 12 nov: **TuFlota** y **TuDron** compiladas en la Mac de GitHub y probadas en el simulador **iPhone 17**: las dos **ABRE BIEN** (costo $0).
   - ⚠️ TuFlota muestra en su portada «USD 5 per month» y «7-day free trial». Antes de enviar a Apple, el servidor
     debe esconder precios y botones de pago cuando el navegador diga `TukanIOS` (ver «Reglas de Apple»).
   - El simulador está en inglés y la web se muestra en inglés; en un iPhone en español sale en español.
4. ⏳ Cuando Apple active la cuenta (después de pagar los $99):
   - Crear en App Store Connect la **clave de API** (Users and Access → Integrations → App Store Connect API, rol *App Manager*).
   - Guardarla en Settings → Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.
   - Agregar al workflow: firma automática + archivo `.ipa` + subida a **TestFlight**.
   - Crear cada app en App Store Connect con su bundle ID, para **todos los países**.
5. ⏳ Probar en el iPhone de Dimitry con **TestFlight** y luego enviar a revisión de Apple.
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
