#!/usr/bin/env python3
"""Arma el proyecto de Xcode de una app Tukan para iPhone.

Uso:  python3 herramientas/generar.py <app>
Lee:  apps/<app>/app.json  (y apps/<app>/icono.png si existe)
Deja: construir/<app>/  con project.yml (para XcodeGen), el codigo y los iconos.

El icono se toma, en este orden:
  1. apps/<app>/icono.png
  2. el icono mas grande del manifest.json de la pagina web del programa
  3. un cuadro del color de la app (respaldo, para que nunca falle)
"""
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import urllib.request
import zlib
from urllib.parse import urljoin

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAMPOS = ["nombre", "producto", "bundle_id", "url", "color_fondo", "version", "compilacion"]


def error(texto):
    print("ERROR: " + texto)
    sys.exit(1)


def leer_config(app):
    ruta = os.path.join(RAIZ, "apps", app, "app.json")
    if not os.path.exists(ruta):
        error("no existe " + ruta)
    with open(ruta, encoding="utf-8") as f:
        cfg = json.load(f)
    for campo in CAMPOS:
        if not str(cfg.get(campo, "")).strip():
            error("falta el campo '%s' en %s" % (campo, ruta))
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", cfg["color_fondo"]):
        error("color_fondo debe ser como #1D3461")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", cfg["producto"]):
        error("producto solo letras y numeros, sin tildes ni espacios")
    if not re.fullmatch(r"[a-z0-9]+(\.[a-z0-9]+)+", cfg["bundle_id"]):
        error("bundle_id invalido: " + cfg["bundle_id"])
    if not cfg["url"].startswith("https://"):
        error("la url debe empezar con https://")
    return cfg


def bajar(url, limite=5_000_000):
    pedido = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 TukanIOS-generador"})
    with urllib.request.urlopen(pedido, timeout=20) as r:
        return r.read(limite)


def icono_de_la_web(url):
    """Busca el icono mas grande del manifest de la pagina."""
    try:
        html = bajar(url).decode("utf-8", "ignore")
    except Exception as e:  # noqa: BLE001
        print("  aviso: no se pudo abrir la pagina (%s)" % e)
        return None
    candidatos = []
    manifests = []
    m = re.search(r'<link[^>]+rel=["\']manifest["\'][^>]*>', html, re.I)
    if m:
        href = re.search(r'href=["\']([^"\']+)', m.group(0))
        if href:
            manifests.append(urljoin(url, href.group(1)))
    # Si la pagina de entrada no lo enlaza (ej. pagina de login), probar los nombres de siempre.
    manifests += [urljoin(url, "/manifest.json"), urljoin(url, "/manifest.webmanifest")]
    for manifest_url in manifests:
        if candidatos:
            break
        try:
            manifest = json.loads(bajar(manifest_url).decode("utf-8", "ignore"))
            for ic in manifest.get("icons", []):
                tam = 0
                for t in str(ic.get("sizes", "")).split():
                    try:
                        tam = max(tam, int(t.lower().split("x")[0]))
                    except ValueError:
                        pass
                proposito = str(ic.get("purpose", "any"))
                # mejor sin "maskable": Apple redondea las esquinas sola
                extra = 0 if "maskable" in proposito and "any" not in proposito else 1
                candidatos.append((extra, tam, urljoin(manifest_url, ic["src"])))
        except Exception as e:  # noqa: BLE001
            print("  aviso: no se pudo leer el manifest (%s)" % e)
    for m in re.finditer(r'<link[^>]+rel=["\']apple-touch-icon[^"\']*["\'][^>]*>', html, re.I):
        href = re.search(r'href=["\']([^"\']+)', m.group(0))
        if href:
            candidatos.append((1, 180, urljoin(url, href.group(1))))
    for _, tam, src in sorted(candidatos, reverse=True):
        try:
            datos = bajar(src)
            if datos[:8] == b"\x89PNG\r\n\x1a\n":
                print("  icono de la web: %s (%spx)" % (src, tam))
                return datos
        except Exception:  # noqa: BLE001
            continue
    return None


def png_de_color(hex_color, lado=1024):
    """PNG de un solo color, sin transparencia (respaldo)."""
    r, g, b = (int(hex_color[i:i + 2], 16) for i in (1, 3, 5))
    fila = b"\x00" + bytes([r, g, b]) * lado
    crudo = fila * lado

    def trozo(tipo, datos):
        c = tipo + datos
        return struct.pack(">I", len(datos)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + trozo(b"IHDR", struct.pack(">IIBBBBB", lado, lado, 8, 2, 0, 0, 0))
            + trozo(b"IDAT", zlib.compress(crudo, 9))
            + trozo(b"IEND", b""))


def preparar_icono(datos, destino, color):
    """Deja el icono en 1024x1024 sin transparencia (Apple lo exige)."""
    tmp = destino + ".orig.png"
    with open(tmp, "wb") as f:
        f.write(datos)
    if shutil.which("sips"):
        jpg = destino + ".tmp.jpg"
        subprocess.run(["sips", "-s", "format", "jpeg", "-z", "1024", "1024", tmp, "--out", jpg],
                       check=True, capture_output=True)
        subprocess.run(["sips", "-s", "format", "png", jpg, "--out", destino],
                       check=True, capture_output=True)
        os.remove(jpg)
        os.remove(tmp)
    else:
        # Fuera de una Mac (pruebas): se usa tal cual.
        os.replace(tmp, destino)


def swift_texto(valor):
    return json.dumps(valor, ensure_ascii=False)


def main():
    if len(sys.argv) != 2:
        error("uso: python3 herramientas/generar.py <app>")
    app = sys.argv[1]
    cfg = leer_config(app)
    salida = os.path.join(RAIZ, "construir", app)
    if os.path.exists(salida):
        shutil.rmtree(salida)
    fuentes = os.path.join(salida, "Sources")
    shutil.copytree(os.path.join(RAIZ, "plantilla", "Sources"), fuentes)

    with open(os.path.join(fuentes, "Config.swift"), "w", encoding="utf-8") as f:
        f.write("// Generado por herramientas/generar.py desde apps/%s/app.json - no editar a mano.\n" % app)
        f.write("enum Config {\n")
        f.write("    static let nombre = %s\n" % swift_texto(cfg["nombre"]))
        f.write("    static let url = %s\n" % swift_texto(cfg["url"]))
        f.write("    static let colorFondo = %s\n" % swift_texto(cfg["color_fondo"]))
        f.write("    static let version = %s\n" % swift_texto(cfg["version"]))
        f.write("}\n")

    # Iconos y color
    activos = os.path.join(salida, "Assets.xcassets")
    icon_dir = os.path.join(activos, "AppIcon.appiconset")
    os.makedirs(icon_dir)
    with open(os.path.join(activos, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f)
    propio = os.path.join(RAIZ, "apps", app, "icono.png")
    if os.path.exists(propio):
        print("  icono propio: apps/%s/icono.png" % app)
        with open(propio, "rb") as f:
            datos = f.read()
    else:
        datos = icono_de_la_web(cfg["url"])
        if not datos:
            print("  aviso: se usa un icono de respaldo del color de la app")
            datos = png_de_color(cfg["color_fondo"])
    preparar_icono(datos, os.path.join(icon_dir, "AppIcon.png"), cfg["color_fondo"])
    with open(os.path.join(icon_dir, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "AppIcon.png", "idiom": "universal",
                               "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)

    permisos = cfg.get("permisos", {})
    info = {
        "CFBundleDisplayName": cfg.get("nombre_corto", cfg["nombre"]),
        "CFBundleName": cfg["producto"],
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "CFBundleDevelopmentRegion": "es",
        "LSRequiresIPhoneOS": True,
        "ITSAppUsesNonExemptEncryption": False,
        "UILaunchScreen": {"UIColorName": "ColorFondo"},
        "UIStatusBarStyle": "UIStatusBarStyleLightContent",
        "UIViewControllerBasedStatusBarAppearance": False,
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
        "UISupportedInterfaceOrientations~ipad": [
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    }
    if permisos.get("camara"):
        info["NSCameraUsageDescription"] = permisos["camara"]
        info["NSMicrophoneUsageDescription"] = permisos["camara"]
    if permisos.get("fotos"):
        info["NSPhotoLibraryUsageDescription"] = permisos["fotos"]
    if permisos.get("ubicacion"):
        info["NSLocationWhenInUseUsageDescription"] = permisos["ubicacion"]

    # Color de la pantalla de arranque
    color_dir = os.path.join(activos, "ColorFondo.colorset")
    os.makedirs(color_dir)
    r, g, b = (int(cfg["color_fondo"][i:i + 2], 16) for i in (1, 3, 5))
    with open(os.path.join(color_dir, "Contents.json"), "w") as f:
        json.dump({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": "%.3f" % (r / 255), "green": "%.3f" % (g / 255), "blue": "%.3f" % (b / 255),
            "alpha": "1.000"}}}], "info": {"author": "xcode", "version": 1}}, f, indent=2)

    proyecto = {
        "name": cfg["producto"],
        "options": {"deploymentTarget": {"iOS": "16.0"}, "createIntermediateGroups": True},
        "targets": {cfg["producto"]: {
            "type": "application",
            "platform": "iOS",
            "sources": ["Sources", "Assets.xcassets"],
            "info": {"path": "Info.plist", "properties": info},
            "settings": {"base": {
                "PRODUCT_BUNDLE_IDENTIFIER": cfg["bundle_id"],
                "PRODUCT_NAME": cfg["producto"],
                "MARKETING_VERSION": cfg["version"],
                "CURRENT_PROJECT_VERSION": str(cfg["compilacion"]),
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "TARGETED_DEVICE_FAMILY": "1,2",
                "SWIFT_VERSION": "5.0",
                "GENERATE_INFOPLIST_FILE": "NO",
                "CODE_SIGN_STYLE": "Automatic",
                "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            }},
        }},
    }
    # XcodeGen acepta JSON con extension .yml (JSON es YAML valido).
    with open(os.path.join(salida, "project.yml"), "w", encoding="utf-8") as f:
        json.dump(proyecto, f, ensure_ascii=False, indent=2)

    with open(os.path.join(salida, "datos.env"), "w") as f:
        f.write("PRODUCTO=%s\nBUNDLE_ID=%s\nURL_APP=%s\nVERSION=%s\nCOMPILACION=%s\n" % (
            cfg["producto"], cfg["bundle_id"], cfg["url"], cfg["version"], cfg["compilacion"]))
    print("Listo: construir/%s (%s, %s)" % (app, cfg["nombre"], cfg["bundle_id"]))


if __name__ == "__main__":
    main()
