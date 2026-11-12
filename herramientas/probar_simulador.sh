#!/bin/bash
# Prueba una app ya compilada en el simulador de iPhone (solo en macOS).
# Uso: bash herramientas/probar_simulador.sh <app>
# Deja en pruebas/<app>/: resultado.txt (ABRE BIEN o FALLA), captura.png y registro.txt
set -u
APP="$1"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
source "$RAIZ/construir/$APP/datos.env"
SALIDA="$RAIZ/pruebas/$APP"
mkdir -p "$SALIDA"
RESULTADO="$SALIDA/resultado.txt"
APP_PATH="$RAIZ/construir/$APP/compilado/Build/Products/Debug-iphonesimulator/$PRODUCTO.app"

fallar() {
  echo "FALLA: $1" | tee "$RESULTADO"
  exit 1
}

[ -d "$APP_PATH" ] || fallar "no se encontro la app compilada en $APP_PATH"

# Elegir un iPhone disponible del simulador
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
datos = json.load(sys.stdin)["devices"]
mejor = None
for runtime, equipos in datos.items():
    if "iOS" not in runtime:
        continue
    for e in equipos:
        if e["name"].startswith("iPhone"):
            mejor = e["udid"]
print(mejor or "")
')
[ -n "$UDID" ] || fallar "no hay simulador de iPhone disponible"
NOMBRE_EQUIPO=$(xcrun simctl list devices | grep "$UDID" | sed 's/ (.*//' | xargs)
echo "Simulador: $NOMBRE_EQUIPO ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b || fallar "el simulador no arranco"
xcrun simctl install "$UDID" "$APP_PATH" || fallar "no se pudo instalar la app"
xcrun simctl launch "$UDID" "$BUNDLE_ID" || fallar "la app no se pudo abrir"

# Esperar hasta 60 segundos a que la pagina cargue
CARPETA=""
for i in $(seq 1 30); do
  sleep 2
  CARPETA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
  if [ -n "$CARPETA" ] && grep -q "^CARGO" "$CARPETA/Documents/prueba_carga.txt" 2>/dev/null; then
    break
  fi
done
sleep 4
xcrun simctl io "$UDID" screenshot "$SALIDA/captura.png" >/dev/null 2>&1 || true

{
  echo "App: $APP ($BUNDLE_ID) version $VERSION ($COMPILACION)"
  echo "Simulador: $NOMBRE_EQUIPO"
  echo "Direccion: $URL_APP"
  echo "--- notas de la app ---"
  cat "$CARPETA/Documents/prueba_carga.txt" 2>/dev/null || echo "(sin notas)"
} > "$SALIDA/registro.txt"

# La app debe seguir abierta (no cerrarse sola)
if ! xcrun simctl spawn "$UDID" launchctl list | grep -q "$BUNDLE_ID"; then
  fallar "la app se cerro sola (crash)"
fi
if ! grep -q "^CARGO" "$CARPETA/Documents/prueba_carga.txt" 2>/dev/null; then
  fallar "la app abrio pero la pagina no cargo en 60 segundos"
fi

PAGINA=$(grep "^CARGO" "$CARPETA/Documents/prueba_carga.txt" | tail -1)
echo "ABRE BIEN - $PAGINA" | tee "$RESULTADO"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
exit 0
