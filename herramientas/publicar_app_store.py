#!/usr/bin/env python3
"""Prepara y envia a revision de Apple las apps de iPhone, por tandas.

Uso:
  python3 herramientas/publicar_app_store.py tanda            # la tanda que toca (cola.json)
  python3 herramientas/publicar_app_store.py preparar envivo  # solo llena la ficha, no envia
  python3 herramientas/publicar_app_store.py enviar envivo    # prepara y envia esa app
  python3 herramientas/publicar_app_store.py estado           # como va cada app enviada

Lee publicacion/fichas/<app>.json, publicacion/capturas/<app>/*.png y
publicacion/cola.json. Guarda lo enviado en publicacion/estado.json.
Si Apple RECHAZA alguna app, la cola se pausa sola (cola.json "pausada": true)
y se deja aviso en publicacion/aviso.txt para abrir un issue.

Secretos (variables): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8,
REVISOR_TELEFONO (telefono de contacto para Apple) y DEMOS_REVISOR
(JSON {"app": {"usuario": "...", "clave": "..."}}, opcional).
Nunca se imprimen telefonos, correos ni claves (el repo es publico).
"""
import datetime
import glob
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import error_corto, pedir, subir_archivo  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUB = os.path.join(RAIZ, "publicacion")
IDIOMA = "es-MX"
TIPO_CAPTURA = "APP_IPHONE_67"   # pantallas de 6.7" y 6.9"
COPYRIGHT = "2026 QFCORP S.A.S."
UE = {"AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC",
      "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
      "SVN", "ESP", "SWE"}
EDITABLES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
             "INVALID_BINARY"}
RECHAZOS = {"REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


class NoLista(Exception):
    """La app todavia no se puede enviar (falta algo); no es un error grave."""


def leer(ruta, defecto):
    try:
        with open(ruta, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return defecto


def guardar(ruta, datos):
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=2)
        f.write("\n")


def ok(st, r, que):
    if st not in (200, 201, 204):
        raise RuntimeError("%s (%s): %s" % (que, st, error_corto(r)))
    return r


def ficha_de(app):
    f = leer(os.path.join(PUB, "fichas", app + ".json"), None)
    if not f:
        raise NoLista("no tiene ficha (publicacion/fichas/%s.json)" % app)
    return f


def app_id(bundle):
    st, r = pedir("GET", "/v1/apps?filter[bundleId]=" + bundle)
    ok(st, r, "buscar app")
    if not r["data"]:
        raise NoLista("no existe en App Store Connect")
    return r["data"][0]["id"]


def contacto():
    st, r = pedir("GET", "/v1/users?limit=50")
    ok(st, r, "leer usuarios")
    duenos = [u for u in r["data"] if "ACCOUNT_HOLDER" in u["attributes"].get("roles", [])] or r["data"]
    a = duenos[0]["attributes"]
    tel = os.environ.get("REVISOR_TELEFONO", "").strip()
    return {"contactFirstName": a.get("firstName") or "Tukan", "contactLastName": a.get("lastName") or "Software",
            "contactEmail": a["username"], "contactPhone": tel}


# ---------------------------------------------------------------- partes de la ficha

def poner_categorias_y_textos(aid, f):
    st, r = pedir("GET", "/v1/apps/%s/appInfos" % aid)
    ok(st, r, "leer appInfos")
    infos = [i for i in r["data"] if i["attributes"].get("appStoreState") != "READY_FOR_SALE"] or r["data"]
    info = infos[0]["id"]
    rel = {"primaryCategory": {"data": {"type": "appCategories", "id": f["categoria"]}}}
    if f.get("categoria_secundaria"):
        rel["secondaryCategory"] = {"data": {"type": "appCategories", "id": f["categoria_secundaria"]}}
    subs = f.get("subcategorias") or []
    for clave, sub in zip(("primarySubcategoryOne", "primarySubcategoryTwo"), subs):
        rel[clave] = {"data": {"type": "appCategories", "id": sub}}
    ok(*pedir("PATCH", "/v1/appInfos/" + info,
              {"data": {"type": "appInfos", "id": info, "relationships": rel}}), "categorias")

    st, r = pedir("GET", "/v1/appInfos/%s/appInfoLocalizations" % info)
    ok(st, r, "leer appInfoLocalizations")
    loc = next((l for l in r["data"] if l["attributes"]["locale"] == IDIOMA), r["data"][0])
    ok(*pedir("PATCH", "/v1/appInfoLocalizations/" + loc["id"], {"data": {
        "type": "appInfoLocalizations", "id": loc["id"],
        "attributes": {"subtitle": f["subtitulo"], "privacyPolicyUrl": f["url_privacidad"]}}}),
       "subtitulo y privacidad")
    return info


NIVELES = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
           "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation",
           "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
           "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
SI_NO = ["advertising", "ageAssurance", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
         "parentalControls", "socialMedia", "unrestrictedWebAccess", "userGeneratedContent"]


def poner_edad(info, f):
    """Clasificacion por edad: todo en NONE / False salvo lo que diga la ficha en "edad"."""
    st, r = pedir("GET", "/v1/appInfos/%s/ageRatingDeclaration" % info)
    ok(st, r, "leer clasificacion por edad")
    dec = r["data"]
    attrs = {n: "NONE" for n in NIVELES}
    attrs.update({n: False for n in SI_NO})
    attrs.update(f.get("edad", {}))
    st, r = pedir("PATCH", "/v1/ageRatingDeclarations/" + dec["id"], {"data": {
        "type": "ageRatingDeclarations", "id": dec["id"], "attributes": attrs}})
    if st not in (200, 201):
        # Quitar los campos que Apple no reconozca y probar otra vez
        malos = [e.get("source", {}).get("pointer", "").split("/")[-1] for e in r.get("errors", [])]
        for m in malos:
            attrs.pop(m, None)
        ok(*pedir("PATCH", "/v1/ageRatingDeclarations/" + dec["id"], {"data": {
            "type": "ageRatingDeclarations", "id": dec["id"], "attributes": attrs}}), "clasificacion por edad")


def poner_precio_gratis(aid):
    st, r = pedir("GET", "/v1/apps/%s/appPriceSchedule" % aid)
    if st == 200 and r.get("data"):
        st2, r2 = pedir("GET", "/v1/appPriceSchedules/%s/manualPrices?limit=5" % r["data"]["id"])
        if st2 == 200 and r2.get("data"):
            return "ya tenia precio"
    st, r = pedir("GET", "/v1/apps/%s/appPricePoints?filter[territory]=USA&limit=200" % aid)
    ok(st, r, "leer precios")
    gratis = next((p for p in r["data"] if float(p["attributes"].get("customerPrice") or 1) == 0.0), None)
    if not gratis:
        raise RuntimeError("no encontre el precio gratis")
    ok(*pedir("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": aid}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${precio1}"}]}}},
        "included": [{"type": "appPrices", "id": "${precio1}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints",
                                                                   "id": gratis["id"]}}}}]}),
       "precio gratis")
    return "gratis"


def poner_paises(aid):
    st, r = pedir("GET", "/v1/apps/%s/appAvailabilityV2" % aid)
    if st == 200 and r.get("data"):
        return "ya tenia paises"
    st, r = pedir("GET", "/v1/territories?limit=200")
    ok(st, r, "leer paises")
    todos = [t["id"] for t in r["data"]]
    paises = [p for p in todos if p not in UE]
    datos, incluidos = [], []
    # Apple pide TODOS los paises: los de la UE van con available=False (falta la declaracion DSA)
    for i, p in enumerate(todos):
        local = "${t%d}" % i
        datos.append({"type": "territoryAvailabilities", "id": local})
        incluidos.append({"type": "territoryAvailabilities", "id": local, "attributes": {"available": p not in UE},
                          "relationships": {"territory": {"data": {"type": "territories", "id": p}}}})
    ok(*pedir("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": aid}},
                                   "territoryAvailabilities": {"data": datos}}},
        "included": incluidos}), "paises")
    return "%d paises (sin la UE)" % len(paises)


def ultima_compilacion(aid):
    st, r = pedir("GET", "/v1/builds?filter[app]=%s&sort=-uploadedDate&limit=1"
                         "&include=preReleaseVersion" % aid)
    ok(st, r, "leer compilaciones")
    if not r["data"]:
        raise NoLista("no hay ninguna version subida a TestFlight")
    b = r["data"][0]
    estado = b["attributes"].get("processingState")
    if estado != "VALID":
        raise NoLista("la ultima version subida todavia esta en %s" % estado)
    if b["attributes"].get("expired"):
        raise NoLista("la ultima version subida ya vencio")
    minima = leer(os.path.join(PUB, "cola.json"), {}).get("subida_desde", "")
    if minima and _fecha(b["attributes"].get("uploadedDate")) < _fecha(minima):
        raise NoLista("la ultima version subida es vieja (antes de %s); subir una nueva" % minima)
    version = next((i["attributes"]["version"] for i in r.get("included", [])
                    if i["type"] == "preReleaseVersions"), None)
    return b["id"], version, b["attributes"].get("version")


def _fecha(texto):
    """Fecha ISO de Apple (con zona horaria) -> datetime en UTC."""
    if not texto:
        return datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)
    d = datetime.datetime.fromisoformat(texto.replace("Z", "+00:00"))
    return d if d.tzinfo else d.replace(tzinfo=datetime.timezone.utc)


def version_editable(aid):
    st, r = pedir("GET", "/v1/apps/%s/appStoreVersions?filter[platform]=IOS&limit=10" % aid)
    ok(st, r, "leer versiones")
    for v in r["data"]:
        if v["attributes"].get("appStoreState") in EDITABLES or \
           v["attributes"].get("appVersionState") in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                                      "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}:
            return v
    estados = [v["attributes"].get("appStoreState") for v in r["data"]]
    raise NoLista("no hay version para editar (estados: %s)" % estados)


def poner_version(v, version, f):
    attrs = {"copyright": COPYRIGHT, "releaseType": "AFTER_APPROVAL"}
    if version and v["attributes"].get("versionString") != version:
        attrs["versionString"] = version
    ok(*pedir("PATCH", "/v1/appStoreVersions/" + v["id"], {"data": {
        "type": "appStoreVersions", "id": v["id"], "attributes": attrs}}), "datos de la version")
    st, r = pedir("GET", "/v1/appStoreVersions/%s/appStoreVersionLocalizations" % v["id"])
    ok(st, r, "leer textos de la version")
    loc = next((l for l in r["data"] if l["attributes"]["locale"] == IDIOMA), None)
    attrs = {"description": f["descripcion"], "keywords": f["palabras_clave"],
             "promotionalText": f.get("texto_promocional", ""), "supportUrl": f["url_soporte"],
             "marketingUrl": f.get("url_marketing") or None}
    if loc:
        ok(*pedir("PATCH", "/v1/appStoreVersionLocalizations/" + loc["id"], {"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}}), "descripcion")
        return loc["id"]
    attrs["locale"] = IDIOMA
    r = ok(*pedir("POST", "/v1/appStoreVersionLocalizations", {"data": {
        "type": "appStoreVersionLocalizations", "attributes": attrs,
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}}),
        "crear descripcion")
    return r["data"]["id"]


def poner_capturas(loc_id, app):
    archivos = sorted(glob.glob(os.path.join(PUB, "capturas", app, "*.png")))[:10]
    if not archivos:
        raise NoLista("no tiene capturas (publicacion/capturas/%s)" % app)
    st, r = pedir("GET", "/v1/appStoreVersionLocalizations/%s/appScreenshotSets?include=appScreenshots" % loc_id)
    ok(st, r, "leer capturas")
    conjunto = next((s for s in r["data"] if s["attributes"]["screenshotDisplayType"] == TIPO_CAPTURA), None)
    if conjunto:
        ids = [d["id"] for d in conjunto["relationships"]["appScreenshots"].get("data", [])]
        sumas = {i["id"]: i["attributes"].get("sourceFileChecksum") for i in r.get("included", [])
                 if i["type"] == "appScreenshots"}
        locales = [hashlib.md5(open(a, "rb").read()).hexdigest() for a in archivos]
        if [sumas.get(i) for i in ids] == locales:
            return "%d capturas (ya estaban)" % len(ids)
        for i in ids:
            pedir("DELETE", "/v1/appScreenshots/" + i)
        cid = conjunto["id"]
    else:
        r = ok(*pedir("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": TIPO_CAPTURA},
            "relationships": {"appStoreVersionLocalization": {"data": {
                "type": "appStoreVersionLocalizations", "id": loc_id}}}}}), "crear grupo de capturas")
        cid = r["data"]["id"]
    for ruta in archivos:
        contenido = open(ruta, "rb").read()
        r = ok(*pedir("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": os.path.basename(ruta), "fileSize": len(contenido)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": cid}}}}}),
            "reservar captura")
        sid = r["data"]["id"]
        subir_archivo(r["data"]["attributes"]["uploadOperations"], contenido)
        ok(*pedir("PATCH", "/v1/appScreenshots/" + sid, {"data": {
            "type": "appScreenshots", "id": sid,
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(contenido).hexdigest()}}}),
           "confirmar captura")
    return "%d capturas subidas" % len(archivos)


def poner_compilacion(v, build_id):
    ok(*pedir("PATCH", "/v1/appStoreVersions/%s/relationships/build" % v["id"],
              {"data": {"type": "builds", "id": build_id}}), "elegir la version subida")


def poner_revisor(v, app, f, datos_contacto):
    demos = {}
    try:
        demos = json.loads(os.environ.get("DEMOS_REVISOR") or "{}")
    except ValueError:
        print("   aviso: DEMOS_REVISOR no es JSON valido")
    st, r = pedir("GET", "/v1/appStoreVersions/%s/appStoreReviewDetail" % v["id"])
    actual = r.get("data") if st == 200 else None
    attrs = dict(datos_contacto)
    if not attrs["contactPhone"]:
        if actual and actual["attributes"].get("contactPhone"):
            attrs.pop("contactPhone")
        else:
            raise NoLista("falta el telefono de contacto para Apple (secreto REVISOR_TELEFONO)")
    attrs["notes"] = f.get("notas_revisor", "")
    if f.get("necesita_demo"):
        demo = demos.get(app) or {}
        if demo.get("usuario") and demo.get("clave"):
            attrs.update(demoAccountRequired=True, demoAccountName=demo["usuario"],
                         demoAccountPassword=demo["clave"])
        elif not (actual and actual["attributes"].get("demoAccountName")):
            raise NoLista("falta la cuenta de prueba para el revisor (DEMOS_REVISOR)")
    else:
        attrs["demoAccountRequired"] = False
    if actual:
        ok(*pedir("PATCH", "/v1/appStoreReviewDetails/" + actual["id"], {"data": {
            "type": "appStoreReviewDetails", "id": actual["id"], "attributes": attrs}}), "datos del revisor")
    else:
        ok(*pedir("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}}),
           "datos del revisor")


def preparar(app, datos_contacto):
    f = ficha_de(app)
    aid = app_id(f["bundle_id"])
    build_id, version, compilacion = ultima_compilacion(aid)
    v = version_editable(aid)
    pasos = []
    ok(*pedir("PATCH", "/v1/apps/" + aid, {"data": {"type": "apps", "id": aid, "attributes": {
        "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT" if f.get("contenido_terceros")
        else "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}}), "derechos de contenido")
    info = poner_categorias_y_textos(aid, f)
    poner_edad(info, f)
    pasos.append(poner_precio_gratis(aid))
    pasos.append(poner_paises(aid))
    loc = poner_version(v, version, f)
    pasos.append(poner_capturas(loc, app))
    poner_compilacion(v, build_id)
    poner_revisor(v, app, f, datos_contacto)
    pasos.append("version %s (%s)" % (version, compilacion))
    return aid, v["id"], pasos


def enviar(aid, vid):
    st, r = pedir("GET", "/v1/reviewSubmissions?filter[app]=%s&filter[state]=READY_FOR_REVIEW&limit=5" % aid)
    envio = r["data"][0]["id"] if st == 200 and r.get("data") else None
    if not envio:
        r = ok(*pedir("POST", "/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}), "crear envio")
        envio = r["data"]["id"]
    st, r = pedir("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": envio}},
                          "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    if st not in (200, 201) and "already" not in json.dumps(r).lower():
        raise RuntimeError("agregar al envio (%s): %s" % (st, error_corto(r)))
    ok(*pedir("PATCH", "/v1/reviewSubmissions/" + envio, {"data": {
        "type": "reviewSubmissions", "id": envio, "attributes": {"submitted": True}}}), "enviar a revision")
    return envio


# ---------------------------------------------------------------- cola

def revisar_enviadas(estado):
    """Actualiza el estado de las enviadas. Devuelve la lista de rechazadas."""
    rechazadas = []
    for app, d in estado.items():
        if d.get("estado") not in ("enviada", "en_revision", "aprobada", "rechazada"):
            continue
        st, r = pedir("GET", "/v1/appStoreVersions/%s" % d["version_id"])
        if st != 200:
            continue
        a = r["data"]["attributes"]
        apple = a.get("appVersionState") or a.get("appStoreState")
        d["apple"] = apple
        if apple in RECHAZOS or a.get("appStoreState") in RECHAZOS:
            d["estado"] = "rechazada"
            rechazadas.append(app)
        elif apple in ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "PENDING_DEVELOPER_RELEASE",
                       "ACCEPTED", "PROCESSING_FOR_DISTRIBUTION"):
            d["estado"] = "aprobada"
        elif apple in ("IN_REVIEW",):
            d["estado"] = "en_revision"
    return rechazadas


def ahora():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def tanda(solo=None):
    cola = leer(os.path.join(PUB, "cola.json"), {"orden": [], "por_tanda": 3, "pausada": False})
    estado = leer(os.path.join(PUB, "estado.json"), {})
    rechazadas = revisar_enviadas(estado)
    aviso = []
    if rechazadas and not solo:
        cola["pausada"] = True
        cola["motivo"] = "Apple rechazo: " + ", ".join(rechazadas)
        aviso.append("Apple RECHAZO: %s. La cola se pauso. Revisar el motivo en App Store Connect "
                     "(Resolution Center), corregir y volver a poner \"pausada\": false en "
                     "publicacion/cola.json." % ", ".join(rechazadas))
    if cola.get("pausada") and not solo:
        print("COLA PAUSADA:", cola.get("motivo", ""))
        guardar(os.path.join(PUB, "estado.json"), estado)
        guardar(os.path.join(PUB, "cola.json"), cola)
        if aviso:
            open(os.path.join(PUB, "aviso.txt"), "w", encoding="utf-8").write("\n".join(aviso) + "\n")
        return 0

    candidatas = solo or [a for a in cola["orden"]
                          if estado.get(a, {}).get("estado") not in ("enviada", "en_revision", "aprobada",
                                                                      "rechazada")]
    cupo = len(candidatas) if solo else int(cola.get("por_tanda", 3))
    datos_contacto = contacto()
    enviadas = 0
    for app in candidatas:
        if enviadas >= cupo:
            break
        print("== %s" % app)
        try:
            aid, vid, pasos = preparar(app, datos_contacto)
            print("   ficha lista: " + "; ".join(pasos))
            envio = enviar(aid, vid)
            estado[app] = {"estado": "enviada", "fecha": ahora(), "version_id": vid, "envio_id": envio}
            enviadas += 1
            print("   ENVIADA A REVISION")
        except NoLista as e:
            estado.setdefault(app, {})["pendiente"] = str(e)
            print("   todavia no: %s" % e)
        except Exception as e:  # noqa: BLE001
            estado.setdefault(app, {})["error"] = "%s (%s)" % (str(e)[:600], ahora())
            print("   ERROR: %s" % e)
    guardar(os.path.join(PUB, "estado.json"), estado)
    guardar(os.path.join(PUB, "cola.json"), cola)
    if aviso:
        open(os.path.join(PUB, "aviso.txt"), "w", encoding="utf-8").write("\n".join(aviso) + "\n")
    faltan = [a for a in cola["orden"] if estado.get(a, {}).get("estado") is None]
    print("RESUMEN: %d enviadas en esta tanda; faltan %d en la cola" % (enviadas, len(faltan)))
    return 0


def solo_preparar(apps):
    datos_contacto = contacto()
    fallos = 0
    for app in apps:
        print("== %s" % app)
        try:
            _, _, pasos = preparar(app, datos_contacto)
            print("   ficha lista (NO enviada): " + "; ".join(pasos))
        except NoLista as e:
            print("   todavia no: %s" % e)
        except Exception as e:  # noqa: BLE001
            fallos += 1
            print("   ERROR: %s" % e)
    return 1 if fallos else 0


def ver_estado():
    estado = leer(os.path.join(PUB, "estado.json"), {})
    revisar_enviadas(estado)
    for app, d in estado.items():
        print("%-12s %-12s %s %s" % (app, d.get("estado", "-"), d.get("apple", ""), d.get("pendiente", "")))
    guardar(os.path.join(PUB, "estado.json"), estado)
    return 0


if __name__ == "__main__":
    modo = sys.argv[1] if len(sys.argv) > 1 else "tanda"
    apps = [a for a in ",".join(sys.argv[2:]).split(",") if a]
    if modo == "tanda":
        sys.exit(tanda())
    if modo == "enviar":
        sys.exit(tanda(solo=apps))
    if modo == "preparar":
        sys.exit(solo_preparar(apps))
    if modo == "estado":
        sys.exit(ver_estado())
    print(__doc__)
    sys.exit(2)
