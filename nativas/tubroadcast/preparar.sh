#!/bin/bash
# Arma los iconos y el proyecto de Xcode de TuBroadcast (app nativa, no es cascaron web).
# Uso (en la Mac de GitHub): bash nativas/tubroadcast/preparar.sh
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/../.." && pwd)"
SALIDA="$RAIZ/construir/tubroadcast"
rm -rf "$SALIDA"; mkdir -p "$SALIDA"
cp -R "$AQUI/Sources" "$AQUI/project.yml" "$SALIDA/"
A="$SALIDA/Assets.xcassets"; mkdir -p "$A/AppIcon.appiconset" "$A/ColorFondo.colorset"
echo '{"info":{"author":"xcode","version":1}}' > "$A/Contents.json"
# Apple exige el icono sin transparencia: se pasa por JPEG y vuelve a PNG
sips -s format jpeg -z 1024 1024 "$AQUI/icono.png" --out "$SALIDA/ic.jpg" >/dev/null
sips -s format png "$SALIDA/ic.jpg" --out "$A/AppIcon.appiconset/AppIcon.png" >/dev/null
rm "$SALIDA/ic.jpg"
cat > "$A/AppIcon.appiconset/Contents.json" <<'J'
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
J
cat > "$A/ColorFondo.colorset/Contents.json" <<'J'
{"colors":[{"idiom":"universal","color":{"color-space":"srgb","components":{"red":"0.000","green":"0.000","blue":"0.000","alpha":"1.000"}}}],"info":{"author":"xcode","version":1}}
J
cat > "$SALIDA/datos.env" <<'J'
PRODUCTO=TuBroadcast
BUNDLE_ID=com.tukansoftware.tubroadcast
URL_APP='(app nativa: camara + RTMP/SRT)'
VERSION=1.0.0
COMPILACION=1
J
cd "$SALIDA" && xcodegen generate
echo "Listo: construir/tubroadcast"
