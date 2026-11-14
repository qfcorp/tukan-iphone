"""Conexion con la API de App Store Connect (comun a las herramientas).

Variables: ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_P8 (contenido del archivo .p8).
"""
import json
import os
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
_token = {"valor": None, "vence": 0}


def _firmar():
    import jwt  # PyJWT
    ahora = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": ahora, "exp": ahora + 1100,
         "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"], algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def token():
    if time.time() > _token["vence"]:
        _token["valor"] = _firmar()
        _token["vence"] = time.time() + 900
    return _token["valor"]


def pedir(metodo, ruta, cuerpo=None):
    """Devuelve (codigo, json). ruta puede empezar con /v1, /v2 o ser URL completa."""
    url = ruta if ruta.startswith("http") else API + ruta
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(url, data=datos, method=metodo, headers={
        "Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    for intento in range(3):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                texto = r.read().decode()
                return r.status, (json.loads(texto) if texto else {})
        except urllib.error.HTTPError as e:
            texto = e.read().decode()
            if e.code in (429, 500, 502, 503, 504) and intento < 2:
                time.sleep(5 * (intento + 1))
                continue
            try:
                return e.code, json.loads(texto)
            except ValueError:
                return e.code, {"texto": texto[:500]}
        except urllib.error.URLError:
            if intento == 2:
                raise
            time.sleep(5)


def error_corto(respuesta):
    errores = respuesta.get("errors") if isinstance(respuesta, dict) else None
    if not errores:
        return json.dumps(respuesta)[:400]
    partes = []
    for e in errores:
        partes.append("%s: %s" % (e.get("title", ""), e.get("detail", "")))
        # Apple pone la razon real en meta.associatedErrors
        for ruta, asociados in ((e.get("meta") or {}).get("associatedErrors") or {}).items():
            for a in asociados:
                partes.append("  - %s %s" % (a.get("code", ""), a.get("detail") or a.get("title", "")))
    return " | ".join(partes)[:3000]


def subir_archivo(operaciones, contenido):
    """Sube un archivo por partes segun las uploadOperations de Apple."""
    for op in operaciones:
        parte = contenido[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=parte, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req, timeout=120) as r:
            r.read()
