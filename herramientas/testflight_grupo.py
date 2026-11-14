#!/usr/bin/env python3
"""Crea en cada app de App Store Connect un grupo INTERNO de TestFlight
("Tukán") con acceso a todas las versiones, y mete ahí a los usuarios del
equipo (Dimitry). Así las apps aparecen solas en la app TestFlight del iPhone,
sin código de canje.

Usa la llave de la API de App Store Connect:
  ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_P8 (contenido del .p8) como variables.
Los correos nunca se imprimen completos (el repo es público).
"""
import glob
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"
GRUPO = "Tukán"
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def token():
    ahora = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": ahora, "exp": ahora + 1100,
         "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"], algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


TOKEN = None


def pedir(metodo, ruta, cuerpo=None):
    url = ruta if ruta.startswith("http") else API + ruta
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(url, data=datos, method=metodo, headers={
        "Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            texto = r.read().decode()
            return r.status, (json.loads(texto) if texto else {})
    except urllib.error.HTTPError as e:
        texto = e.read().decode()
        try:
            return e.code, json.loads(texto)
        except ValueError:
            return e.code, {"texto": texto}


def tapar(correo):
    nombre, _, dominio = correo.partition("@")
    return nombre[:2] + "***@" + dominio


def bundles():
    lista = []
    for f in sorted(glob.glob(os.path.join(RAIZ, "apps", "*", "app.json"))):
        with open(f, encoding="utf-8") as h:
            cfg = json.load(h)
        lista.append((os.path.basename(os.path.dirname(f)), cfg["bundle_id"]))
    lista.append(("tubroadcast", "com.tukansoftware.tubroadcast"))
    return lista


def main():
    global TOKEN
    TOKEN = token()
    st, usuarios = pedir("GET", "/users?limit=50")
    if st != 200:
        print(f"::error::No pude leer los usuarios del equipo ({st}): {usuarios}")
        return 1
    gente = [(u["attributes"]["username"], u["attributes"].get("firstName") or "Tukán",
              u["attributes"].get("lastName") or "Software") for u in usuarios["data"]]
    print("Usuarios del equipo:", ", ".join(tapar(g[0]) for g in gente))

    fallos = 0
    for carpeta, bundle in bundles():
        st, apps = pedir("GET", "/apps?filter[bundleId]=" + urllib.parse.quote(bundle))
        if st != 200 or not apps.get("data"):
            print(f"{carpeta}: SIN FICHA en App Store Connect ({st})")
            fallos += 1
            continue
        app_id = apps["data"][0]["id"]
        st, grupos = pedir("GET", f"/apps/{app_id}/betaGroups?limit=50")
        grupo = next((g for g in grupos.get("data", [])
                      if g["attributes"].get("isInternalGroup")), None)
        if not grupo:
            st, nuevo = pedir("POST", "/betaGroups", {"data": {
                "type": "betaGroups",
                "attributes": {"name": GRUPO, "isInternalGroup": True,
                               "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
            if st not in (200, 201):
                print(f"{carpeta}: no pude crear el grupo ({st}) {json.dumps(nuevo)[:300]}")
                fallos += 1
                continue
            grupo = nuevo["data"]
        gid = grupo["id"]
        estado = []
        for correo, nombre, apellido in gente:
            st, r = pedir("POST", "/betaTesters", {"data": {
                "type": "betaTesters",
                "attributes": {"email": correo, "firstName": nombre, "lastName": apellido},
                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}}}})
            if st in (200, 201):
                estado.append("agregado")
                continue
            # Ya existe como probador: lo enlazo al grupo.
            st2, ya = pedir("GET", "/betaTesters?filter[email]=" + urllib.parse.quote(correo))
            if st2 == 200 and ya.get("data"):
                tid = ya["data"][0]["id"]
                st3, r3 = pedir("POST", f"/betaGroups/{gid}/relationships/betaTesters",
                                {"data": [{"type": "betaTesters", "id": tid}]})
                estado.append("ya estaba" if st3 in (200, 204) else f"error {st3}")
                if st3 not in (200, 204):
                    print(f"   detalle: {json.dumps(r3)[:300]}")
                    fallos += 1
            else:
                estado.append(f"error {st}")
                print(f"   detalle: {json.dumps(r)[:300]}")
                fallos += 1
        print(f"{carpeta}: grupo '{grupo['attributes'].get('name', GRUPO)}' listo — "
              + ", ".join(estado))
    print("LISTO" if not fallos else f"TERMINÓ CON {fallos} PROBLEMAS")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
