#!/bin/bash
# Prueba una app NATIVA ya compilada en el simulador (copia de herramientas/probar_simulador.sh que ademas da permisos de camara y microfono).
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
import re
datos = json.load(sys.stdin)["devices"]
opciones = []
for runtime, equipos in datos.items():
    if "iOS" not in runtime:
        continue
    ver = tuple(int(n) for n in re.findall(r"\d+", runtime.split("iOS")[-1])[:2])
    for e in equipos:
        nombre = e["name"]
        if not nombre.startswith("iPhone"):
            continue
        num = re.search(r"iPhone (\d+)", nombre)
        # Preferir el iOS mas nuevo y un iPhone normal reciente (no SE, no Plus/Max)
        normal = 1 if num and not re.search(r"SE|Plus|Max|mini|Air|e$", nombre) else 0
        opciones.append((ver, normal, int(num.group(1)) if num else 0, e["udid"]))
print(max(opciones)[3] if opciones else "")
')
[ -n "$UDID" ] || fallar "no hay simulador de iPhone disponible"
NOMBRE_EQUIPO=$(xcrun simctl list devices | grep "$UDID" | sed 's/ (.*//' | xargs)
echo "Simulador: $NOMBRE_EQUIPO ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b || fallar "el simulador no arranco"
xcrun simctl install "$UDID" "$APP_PATH" || fallar "no se pudo instalar la app"
# Dar permiso de camara, microfono y fotos para que no salga la ventana de permiso en la prueba
for P in camera microphone photos location; do xcrun simctl privacy "$UDID" grant "$P" "$BUNDLE_ID" 2>/dev/null || true; done
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
