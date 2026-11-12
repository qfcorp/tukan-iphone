# Tukán iPhone — apps de iPhone de Tukán Software

Aquí se hacen las apps de **iPhone** de los programas Tukán, **sin tener una Mac**:
GitHub presta una Mac en la nube que compila, prueba y (más adelante) sube cada app a Apple.

> Este repositorio es **público** a propósito: en repositorios públicos los minutos de Mac
> de GitHub Actions son **gratis**. Aquí **solo** va el "cascarón" de cada app
> (nombre, ícono, color y la dirección web que abre). El código de los programas,
> las bases de datos y las claves **no** van aquí. Las claves de Apple se guardan en
> **Settings → Secrets**, que quedan ocultas aunque el repo sea público.

## Cómo funciona cada app

Cada app abre la página web del programa a pantalla completa (como en Android con `qfcorp/tukan-apps`).
Lo que se cambia en la web se ve en la app **sin subir nada a Apple**. Solo se compila otra versión
si cambia el nombre, el ícono, el color o la dirección.

La app trae, además: botón **Reintentar** si no hay internet, jalar hacia abajo para recargar,
deslizar para volver atrás, los enlaces de WhatsApp/teléfono/correo y de otros sitios se abren fuera
de la app, permisos de cámara/fotos/ubicación con su explicación, y la marca `TukanIOS` en el
navegador para que el servidor sepa que es la app de iPhone.

## Apps

| App | Carpeta | Identificador (bundle) | Dirección |
|---|---|---|---|
| Flota Tukán | `apps/tuflota` | `com.tukansoftware.flotatukan` | https://tuflota.tukanec.com/ |
| TuDron | `apps/tudron` | `com.tukansoftware.tudron` | https://tudron.tukanec.com/?r=inicio&app=1 |

## Compilar y probar (desde el celular)

1. Abre **https://github.com/qfcorp/tukan-iphone/actions**
2. Toca **Compilar y probar apps de iPhone** → **Run workflow**.
3. En **App** escribe `todas`, `tuflota` o `tudron` → **Run workflow**.
4. Espera unos 10 minutos. Debe salir el ✅ verde y en el resumen **ABRE BIEN**.
   La foto de la app en el simulador queda en **Artifacts** (`prueba-<app>`) por 3 días.

También se compila solo cada vez que se cambia algo en `apps/`, `plantilla/` o `herramientas/`.

## Agregar una app nueva

1. Crea la carpeta `apps/<app>/` con un `app.json` como el de `apps/tuflota/app.json`.
2. (Opcional) pon un `icono.png` cuadrado de 1024×1024. Si no hay, se toma el ícono más grande
   de la página web; si tampoco hay, se usa un cuadro del color de la app.
3. Sube el cambio a `main`: se compila y se prueba sola.

Campos de `app.json`: `nombre`, `nombre_corto` (lo que sale debajo del ícono), `producto`
(solo letras y números), `bundle_id`, `url`, `color_fondo` (`#RRGGBB`), `version`, `compilacion`,
`permisos` (`camara`, `fotos`, `ubicacion`: el texto que ve el cliente cuando la app pide permiso).

## Archivos

| Carpeta | Qué hay |
|---|---|
| `apps/` | Los datos de cada app |
| `plantilla/Sources/` | El código Swift común a todas las apps |
| `herramientas/generar.py` | Arma el proyecto de Xcode de una app |
| `herramientas/probar_simulador.sh` | Abre la app en el simulador de iPhone y revisa que cargue |
| `.github/workflows/` | La compilación en la Mac de GitHub |
| `NOTAS.md` | Bloc de notas: plan, lo hecho y lo que falta |
