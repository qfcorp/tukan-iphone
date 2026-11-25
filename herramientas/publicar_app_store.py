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
import time
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
# China continental: Apple pide evaluacion de seguridad y declaracion AIGC (nov 2026); no distribuimos alli
SIN_DISTRIBUIR = UE | {"CHN"}
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


def quitar_paises_bloqueados(disp_id):
    """En una app que ya tiene paises, apaga China continental (y la UE) si estan encendidos."""
    apagados = []
    url = "/v2/appAvailabilities/%s/territoryAvailabilities?include=territory&limit=200" % disp_id
    while url:
        st, r = pedir("GET", url)
        ok(st, r, "leer paises de la app")
        for ta in r.get("data", []):
            terr = ((ta.get("relationships") or {}).get("territory") or {}).get("data") or {}
            if terr.get("id") in SIN_DISTRIBUIR and ta["attributes"].get("available"):
                ok(*pedir("PATCH", "/v1/territoryAvailabilities/%s" % ta["id"], {"data": {
                    "type": "territoryAvailabilities", "id": ta["id"], "attributes": {"available": False}}}),
                   "apagar " + terr["id"])
                apagados.append(terr["id"])
        url = (r.get("links") or {}).get("next")
    return apagados


def poner_paises(aid):
    st, r = pedir("GET", "/v1/apps/%s/appAvailabilityV2" % aid)
    if st == 200 and r.get("data"):
        apagados = quitar_paises_bloqueados(r["data"]["id"])
        return "ya tenia paises" + (" (apagados: %s)" % ",".join(apagados) if apagados else "")
    st, r = pedir("GET", "/v1/territories?limit=200")
    ok(st, r, "leer paises")
    todos = [t["id"] for t in r["data"]]
    paises = [p for p in todos if p not in SIN_DISTRIBUIR]
    datos, incluidos = [], []
    # Apple pide TODOS los paises: los de la UE van con available=False (falta la declaracion DSA)
    for i, p in enumerate(todos):
        local = "${t%d}" % i
        datos.append({"type": "territoryAvailabilities", "id": local})
        incluidos.append({"type": "territoryAvailabilities", "id": local, "attributes": {"available": p not in SIN_DISTRIBUIR},
                          "relationships": {"territory": {"data": {"type": "territories", "id": p}}}})
    ok(*pedir("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": aid}},
                                   "territoryAvailabilities": {"data": datos}}},
        "included": incluidos}), "paises")
    return "%d paises (sin la UE ni China continental)" % len(paises)


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


PUBLICADAS = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE"}


def version_editable(aid, version_nueva=None):
    st, r = pedir("GET", "/v1/apps/%s/appStoreVersions?filter[platform]=IOS&limit=10" % aid)
    ok(st, r, "leer versiones")
    for v in r["data"]:
        if v["attributes"].get("appStoreState") in EDITABLES or \
           v["attributes"].get("appVersionState") in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                                      "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}:
            return v
    estados = [v["attributes"].get("appStoreState") for v in r["data"]]
    # (25 nov 2026) Versión nueva: si todas las versiones ya están publicadas y la última compilación trae
    # otro número (p. ej. 1.0.1), se crea la versión en App Store Connect, como «+ Versión» en la web.
    ya = {v["attributes"].get("versionString") for v in r["data"]}
    if version_nueva and version_nueva not in ya and estados and all(e in PUBLICADAS for e in estados):
        r = ok(*pedir("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version_nueva},
            "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}), "crear la version " + version_nueva)
        return r["data"]
    raise NoLista("no hay version para editar (estados: %s)" % estados)


def enviar_compras(aid):
    """(25 nov 2026) Deja las compras dentro de la app (suscripciones y consumibles) listas para ir con la próxima
    versión: Apple revisa las primeras compras junto con una versión de la app. Las ya aprobadas o enviadas se saltan."""
    hechas = []
    st, r = pedir("GET", "/v1/apps/%s/subscriptionGroups?include=subscriptions&limit=20" % aid)
    ok(st, r, "leer suscripciones")
    for s in [x for x in r.get("included", []) if x["type"] == "subscriptions"]:
        if s["attributes"].get("state") not in ("READY_TO_SUBMIT", "DEVELOPER_ACTION_NEEDED", "REJECTED"):
            continue
        st2, r2 = pedir("POST", "/v1/subscriptionSubmissions", {"data": {"type": "subscriptionSubmissions",
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": s["id"]}}}}})
        if st2 in (200, 201):
            hechas.append(s["attributes"]["productId"])
        else:
            print("   aviso compra %s (%s): %s" % (s["attributes"]["productId"], st2, error_corto(r2)))
    st, r = pedir("GET", "/v1/apps/%s/inAppPurchasesV2?limit=200" % aid)
    ok(st, r, "leer compras")
    for i in r.get("data", []):
        if i["attributes"].get("state") not in ("READY_TO_SUBMIT", "DEVELOPER_ACTION_NEEDED", "REJECTED"):
            continue
        st2, r2 = pedir("POST", "/v1/inAppPurchaseSubmissions", {"data": {"type": "inAppPurchaseSubmissions",
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": i["id"]}}}}})
        if st2 in (200, 201):
            hechas.append(i["attributes"]["productId"])
        else:
            print("   aviso compra %s (%s): %s" % (i["attributes"]["productId"], st2, error_corto(r2)))
    return "%d compras van con la version" % len(hechas)


def poner_version(v, version, f):
    # App no listada (uso interno de una empresa): se publica a mano, despues de que Apple acepte la solicitud de
    # distribucion no listada (developer.apple.com/contact/request/unlisted-app/); asi nunca sale publica por error
    attrs = {"copyright": COPYRIGHT, "releaseType": "MANUAL" if f.get("no_listada") else "AFTER_APPROVAL"}
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


def cuenta_revisor(app, f, demos):
    """Cuenta de prueba para Apple. Orden: DEMOS_REVISOR[app] (JSON) y, si falta la clave, la ficha
    ("demo": {"usuario": ...}) con la clave del secreto REVISOR_CLAVE (la misma contrasena del revisor en todas
    las apps, 13 nov 2026). La clave nunca se escribe en el repo ni en el registro."""
    demo = dict(demos.get(app) or {})
    ficha = f.get("demo") or {}
    if not demo.get("usuario"):
        demo["usuario"] = ficha.get("usuario", "")
    if not demo.get("clave"):
        demo["clave"] = ficha.get("clave") or os.environ.get("REVISOR_CLAVE", "")
    return demo


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
    notas = f.get("notas_revisor", "")
    if "{video}" in notas:
        # Apple pide un video grabado en un iPhone real (regla 2.1): sin enlace no se envia
        if not f.get("video_revisor"):
            raise NoLista("falta el video de la app grabado en el iPhone (\"video_revisor\" en la ficha)")
        notas = notas.replace("{video}", f["video_revisor"])
    if f.get("no_listada"):
        notas = NOTA_NO_LISTADA + "\n\n" + notas
    attrs["notes"] = notas[:4000]
    if f.get("necesita_demo"):
        demo = cuenta_revisor(app, f, demos)
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


MIN_CAPTURAS = 3
NOTA_NO_LISTADA = ("UNLISTED DISTRIBUTION: this app is intended for unlisted distribution only (it is used by the staff "
                   "and clients of one company). We are submitting the Unlisted App Distribution request for it. "
                   "Release is set to manual: please do not treat it as a public app.")


def preparar(app, datos_contacto):
    f = ficha_de(app)
    if f.get("esperar"):
        # "esperar": "motivo" en la ficha = todavia no se envia (ej. falta instalar un arreglo en el servidor)
        raise NoLista("en espera: " + str(f["esperar"]))
    # Apple rechaza si las capturas solo muestran la pantalla de entrar (regla 2.3.3): minimo 3 fotos de la app por dentro
    if len(glob.glob(os.path.join(PUB, "capturas", app, "*.png"))) < MIN_CAPTURAS:
        raise NoLista("faltan las fotos de la app por dentro (minimo %d en publicacion/capturas/%s)" % (MIN_CAPTURAS, app))
    if "{video}" in f.get("notas_revisor", "") and not f.get("video_revisor"):
        raise NoLista("falta el video de la app grabado en el iPhone (\"video_revisor\" en la ficha)")
    aid = app_id(f["bundle_id"])
    build_id, version, compilacion = ultima_compilacion(aid)
    v = version_editable(aid, version if f.get("crear_version") else None)
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
    # Si Apple dejo un envio con "problemas sin resolver", se reenvia ese mismo
    st, r = pedir("GET", "/v1/reviewSubmissions?filter[app]=%s&filter[state]=UNRESOLVED_ISSUES&limit=5" % aid)
    if st == 200 and r.get("data"):
        envio = r["data"][0]["id"]
        # Como "Actualizar revision" en la web: volver a poner la version en ese envio
        sti, ri = pedir("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": envio}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        if sti not in (200, 201):
            print("   aviso: agregar la version al envio viejo (%s): %s" % (sti, error_corto(ri)))
        st2, r2 = pedir("PATCH", "/v1/reviewSubmissions/" + envio, {"data": {
            "type": "reviewSubmissions", "id": envio, "attributes": {"submitted": True}}})
        if st2 in (200, 201):
            return envio
        # El envio viejo (con «Information Needed») no acepta la version nueva:
        # se cancela y se hace un envio nuevo, como «Quitar de la revision» en la web.
        print("   aviso: el envio viejo no se pudo reenviar (%s): %s; se cancela y se crea uno nuevo"
              % (st2, error_corto(r2)))
        ok(*pedir("PATCH", "/v1/reviewSubmissions/" + envio, {"data": {
            "type": "reviewSubmissions", "id": envio, "attributes": {"canceled": True}}}), "cancelar el envio viejo")
        for _ in range(12):
            time.sleep(10)
            st3, r3 = pedir("GET", "/v1/reviewSubmissions/" + envio)
            if st3 == 200 and r3["data"]["attributes"].get("state") not in ("CANCELING", "UNRESOLVED_ISSUES"):
                break
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
            if d.get("estado") != "rechazada":   # solo los rechazos nuevos abren aviso
                rechazadas.append(app)
            d["estado"] = "rechazada"
        elif apple in ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "PENDING_DEVELOPER_RELEASE",
                       "ACCEPTED", "PROCESSING_FOR_DISTRIBUTION"):
            d["estado"] = "aprobada"
        elif apple in ("IN_REVIEW",):
            d["estado"] = "en_revision"
        elif apple in ("WAITING_FOR_REVIEW", "READY_FOR_REVIEW"):
            d["estado"] = "enviada"
    return rechazadas


def enviar_versiones_nuevas(estado):
    """(25 nov 2026) Apps aprobadas con «crear_version» en su ficha: si la última compilación trae otro número
    de versión (p. ej. TuBroadcast 1.0.1 con las compras de Apple), crea la versión y la envía sola, aunque
    la cola esté pausada. Devuelve la lista de apps enviadas."""
    enviadas = []
    for app, d in estado.items():
        if d.get("estado") != "aprobada":
            continue
        try:
            f = ficha_de(app)
        except Exception:  # noqa: BLE001
            continue
        if not f.get("crear_version"):
            continue
        aid = app_id(f["bundle_id"])
        try:
            _, version, _ = ultima_compilacion(aid)
        except NoLista:
            continue
        if version == d.get("version_aprobada") or version == d.get("version"):
            continue
        print("== %s (version nueva %s)" % (app, version))
        try:
            aid, vid, pasos = preparar(app, contacto())
            print("   ficha lista: " + "; ".join(pasos))
            if f.get("compras_con_version"):
                print("   " + enviar_compras(aid))
            envio = enviar(aid, vid)
            estado[app] = {"estado": "enviada", "fecha": ahora(), "version_id": vid, "envio_id": envio,
                           "version": version, "version_aprobada": d.get("version_aprobada") or d.get("version")}
            enviadas.append(app)
            print("   ENVIADA A REVISION (version %s)" % version)
        except NoLista as e:
            d["pendiente"] = str(e)
            print("   todavia no: %s" % e)
        except Exception as e:  # noqa: BLE001
            d["error"] = "%s (%s)" % (str(e)[:600], ahora())
            print("   ERROR: %s" % e)
    return enviadas


def ahora():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def tanda(solo=None):
    cola = leer(os.path.join(PUB, "cola.json"), {"orden": [], "por_tanda": 3, "pausada": False})
    estado = leer(os.path.join(PUB, "estado.json"), {})
    rechazadas = revisar_enviadas(estado)
    if not solo:
        enviar_versiones_nuevas(estado)
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
            if ficha_de(app).get("compras_con_version"):
                print("   " + enviar_compras(aid))
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
