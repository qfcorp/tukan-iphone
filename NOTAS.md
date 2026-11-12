# Bloc de notas — Tukán iPhone (qfcorp/tukan-iphone)

Última actualización: 12 nov 2026

## Plan

1. ✅ Crear el repo **público** `qfcorp/tukan-iphone` (minutos de Mac gratis).
2. ✅ Cascarón común en Swift (WebView a pantalla completa) + generador + prueba en simulador.
3. ⏳ Probar compilando **TuFlota** y **TuDron** en la Mac de GitHub (sin firma de Apple) → debe decir **ABRE BIEN**.
4. ⏳ Cuando Apple active la cuenta (después de pagar los $99):
   - Crear en App Store Connect la **clave de API** (Users and Access → Integrations → App Store Connect API, rol *App Manager*).
   - Guardarla en Settings → Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.
   - Agregar al workflow: firma automática + archivo `.ipa` + subida a **TestFlight**.
   - Crear cada app en App Store Connect con su bundle ID, para **todos los países**.
5. ⏳ Probar en el iPhone de Dimitry con **TestFlight** y luego enviar a revisión de Apple.
6. ⏳ Seguir con las demás apps Tukán en **orden alfabético**.
7. ⏳ Actualizar manuales y presentaciones de cada programa con «Disponible en iPhone».

## Reglas de Apple a cuidar

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

- 12 nov 2026: repo creado por Dimitry; estructura, generador, prueba en simulador y workflow
  (TuFlota y TuDron) hechos por Claude.
