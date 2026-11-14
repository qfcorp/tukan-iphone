#!/bin/bash
# Saca las capturas de la App Store de una app ya compilada para el simulador.
# Usa el iPhone mas grande (pantalla de 6.9"), en espanol, con la barra de estado
# limpia (9:41, bateria llena). Las capturas salen de publicacion/fichas/<app>.json:
#   "capturas": [{"espera": 8}, {"url": "https://mismo-sitio/otra-pagina", "espera": 6}]
# Uso: bash herramientas/sacar_capturas.sh <app> <ruta-del-.app> <bundle-id>
# Deja: publicacion/capturas/<app>/01.png, 02.png ...
set -u
APP="$1"; APP_PATH="$2"; BUNDLE_ID="$3"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
FICHA="$RAIZ/publicacion/fichas/$APP.json"
SALIDA="$RAIZ/publicacion/capturas/$APP"
rm -rf "$SALIDA"; mkdir -p "$SALIDA"

[ -d "$APP_PATH" ] || { echo "FALLA: no existe $APP_PATH"; exit 1; }
[ -f "$FICHA" ] || { echo "FALLA: falta la ficha $FICHA"; exit 1; }

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys, re
datos = json.load(sys.stdin)["devices"]
op = []
for rt, eq in datos.items():
    if "iOS" not in rt: continue
    ver = tuple(int(n) for n in re.findall(r"\d+", rt.split("iOS")[-1])[:2])
    for e in eq:
        n = e["name"]
        if n.startswith("iPhone") and "Pro Max" in n:
            num = re.search(r"iPhone (\d+)", n)
            op.append((ver, int(num.group(1)) if num else 0, e["udid"]))
print(max(op)[2] if op else "")
')
[ -n "$UDID" ] || { echo "FALLA: no hay iPhone Pro Max en el simulador"; exit 1; }
echo "Simulador: $(xcrun simctl list devices | grep "$UDID" | sed 's/ (.*//' | xargs)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
# Espanol de Ecuador en todo el simulador
xcrun simctl spawn "$UDID" defaults write "Apple Global Domain" AppleLanguages -array es-419 es
xcrun simctl spawn "$UDID" defaults write "Apple Global Domain" AppleLocale -string es_EC
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP_PATH"
for P in camera microphone photos location; do xcrun simctl privacy "$UDID" grant "$P" "$BUNDLE_ID" 2>/dev/null || true; done

python3 -c '
import json, sys
for c in json.load(open(sys.argv[1], encoding="utf-8")).get("capturas") or [{"espera": 8}]:
    print(c.get("url", "-"), int(c.get("espera", 8)))
' "$FICHA" > /tmp/capturas_$APP.txt

N=0
while read -r URL ESPERA; do
  N=$((N+1))
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  if [ "$URL" = "-" ]; then
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -AppleLanguages "(es-419)" -AppleLocale es_EC
  else
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -AppleLanguages "(es-419)" -AppleLocale es_EC -capturaURL "$URL"
  fi
  sleep "$ESPERA"
  ARCH="$SALIDA/$(printf '%02d' $N).png"
  xcrun simctl io "$UDID" screenshot --type=png "$ARCH" >/dev/null 2>&1
  TAM=$(sips -g pixelWidth -g pixelHeight "$ARCH" 2>/dev/null | awk '/pixel/{print $2}' | xargs)
  echo "Captura $N: $ARCH ($TAM)"
done < /tmp/capturas_$APP.txt

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
CUENTA=$(ls "$SALIDA"/*.png 2>/dev/null | wc -l | xargs)
[ "$CUENTA" -ge 1 ] || { echo "FALLA: no salio ninguna captura"; exit 1; }
echo "LISTO: $CUENTA capturas de $APP"
