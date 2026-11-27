#!/usr/bin/env python3
"""
Crea en App Store Connect las 20 compras de TuBroadcast (23 nov 2026, contrato de apps pagadas ya activo):
  - Grupo de suscripción «TuBroadcast» con 16 suscripciones (Básico/Completo × 1/3/5/10 celulares × mes/año).
  - 4 consumibles «Pase de 24 horas» (1/3/5/10 celulares).
Los productos, nombres y niveles salen de nativas/tubroadcast/TuBroadcast.storekit (la misma lista que usa la app);
los precios, de la regla de Dimitry (ver BASE y precio_objetivo).
Precio: el punto de precio de Apple en EE. UU. más cercano; los demás países con la equivalencia de Apple.
Países: los mismos de la app (sin la UE ni China continental).
Modelo de precios de suscripciones de Apple (2026): cada suscripción tiene «tipos de plan»; aquí solo se usa
UPFRONT (pago completo por adelantado: plan en los países de la app + precio UPFRONT en cada uno). La opción
MONTHLY (pago mensual con compromiso de 12 meses) no se configura.
También pone la dirección de avisos del servidor (App Store Server Notifications V2) del Panel Tukán Central.
Se puede correr varias veces: lo que ya existe no se duplica.

Uso:  python3 herramientas/crear_compras.py [probar]
      probar = solo muestra lo que haría (sin llamar a Apple).
      python3 herramientas/crear_compras.py capturas <carpeta>
      sube planes_01.png / _03 / _05 / _10 como captura de revisión de cada compra.
      python3 herramientas/crear_compras.py lista <bundle> <lista.json> [carpeta_capturas]
      compras simples de una app web (p. ej. publicacion/compras/envivo.json); «probar» también revisa esas listas.
      python3 herramientas/crear_compras.py diagnostico
      solo lee: estado de las 20 compras, plan UPFRONT vs precios vs países de la app, textos, capturas, grupo.
"""
import json
import os
import sys

DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, DIR)
REPO = os.path.dirname(DIR)

BUNDLE = "com.tukansoftware.tubroadcast"
LOCALE = "es-MX"
AVISOS_URL = "https://panel.tukanec.com/tubroadcast_api.php?a=apple_notificacion"
AVISOS_POR_APP = {"com.tukanec.envivo": "https://juego.tukanec.com/api/apple/notificacion"}
STOREKIT = os.path.join(REPO, "nativas", "tubroadcast", "TuBroadcast.storekit")
# Precios (decisión de Dimitry, 23 nov 2026): los mismos de Google Play para 1 celular; paquete = precio × celulares × 0,85;
# anual = 12 × el mensual (sin meses de regalo). Apple usa el punto de precio más cercano.
BASE = {"basico": 5.99, "completo": 10.99, "pase24": 3.99}


PLAN = "UPFRONT"   # tipo de plan de suscripción (modelo de precios de Apple de 2026)


def cuerpo_plan(sid, paises, plan_id=None):
    """POST (o PATCH si plan_id) de /v1/subscriptionPlanAvailabilities: plan UPFRONT en esos países."""
    territorios = {"data": [{"type": "territories", "id": p} for p in paises]}
    if plan_id:
        return {"data": {"type": "subscriptionPlanAvailabilities", "id": plan_id,
                         "attributes": {"availableInNewTerritories": False},
                         "relationships": {"availableTerritories": territorios}}}
    return {"data": {"type": "subscriptionPlanAvailabilities",
                     "attributes": {"planType": PLAN, "availableInNewTerritories": False},
                     "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                       "availableTerritories": territorios}}}


def cuerpo_precio(sid, pais, punto):
    """POST /v1/subscriptionPrices: precio UPFRONT desde ya en un país."""
    return {"data": {"type": "subscriptionPrices",
                     "attributes": {"startDate": None, "preserveCurrentPrice": False, "planType": PLAN},
                     "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                       "territory": {"data": {"type": "territories", "id": pais}},
                                       "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": punto}}}}}


def precio_objetivo(producto_id):
    """tubroadcast.<plan>.<N>[.mes|.anio] → precio en dólares según la regla de Dimitry."""
    partes = producto_id.split(".")
    plan, n = partes[1], int(partes[2])
    mensual = BASE[plan] * (1 if n == 1 else n * 0.85)
    return round(mensual * (12 if partes[-1] == "anio" else 1), 2)


NOTA_REVISOR = ("Unlocks TuBroadcast without limits (no 5-minute cut, no watermark, up to 1080p) on the number of phones "
                "in the plan. Sold only with Apple In-App Purchase. Test it in the app: Settings (gear) > License > See plans.")


def nombre_corto(nombre, maximo=30):
    """Apple deja hasta 30 letras en el nombre visible: «(10 celulares)» pasa a «(10 cel.)» si no entra."""
    if len(nombre) <= maximo:
        return nombre
    n = nombre.replace(" celulares)", " cel.)").replace(" celular)", " cel.)")
    if len(n) <= maximo:
        return n
    return n.replace("Pase de 24 horas", "Pase 24 horas").replace(" mensual", " mes").replace(" anual", " año")[:maximo]


def productos():
    """Lee el .storekit: devuelve (suscripciones, consumibles) como listas de dicts simples."""
    d = json.load(open(STOREKIT, encoding="utf-8"))
    subs = []
    for g in d["subscriptionGroups"]:
        for s in g["subscriptions"]:
            loc = s["localizations"][0]
            subs.append({
                "id": s["productID"],
                "periodo": {"P1M": "ONE_MONTH", "P1Y": "ONE_YEAR"}[s["recurringSubscriptionPeriod"]],
                "precio": precio_objetivo(s["productID"]),
                "nivel": int(s["groupNumber"]),
                "nombre": nombre_corto(loc["displayName"]),
                "descripcion": loc["description"][:45],
            })
    cons = []
    for p in d.get("products", []):
        loc = p["localizations"][0]
        cons.append({"id": p["productID"], "precio": precio_objetivo(p["productID"]),
                     "nombre": nombre_corto(loc["displayName"]), "descripcion": loc["description"][:45]})
    return subs, cons


def mas_cercano(puntos, precio):
    """Del listado de puntos de precio (id, customerPrice) elige el más cercano al precio pedido."""
    return min(puntos, key=lambda p: (abs(float(p[1]) - precio), float(p[1])))


# ------------------------------------------------------------------ Apple

def todos(pedir, ok, ruta):
    """GET con páginas: devuelve (data, included)."""
    data, inc = [], []
    while ruta:
        r = ok(*pedir("GET", ruta), "leer " + ruta.split("?")[0])
        data += r.get("data", [])
        inc += r.get("included", [])
        ruta = (r.get("links") or {}).get("next")
    return data, inc


def correr(solo=None):
    """solo = productId: hace solo esa suscripción (sin los pases); para probar un cambio antes de aplicarlo a todas."""
    from asc import error_corto, pedir
    from publicar_app_store import app_id

    def ok(st, r, que):
        if st not in (200, 201, 204):
            raise RuntimeError("%s (%s): %s" % (que, st, error_corto(r)))
        return r

    aid = app_id(BUNDLE)
    print("App TuBroadcast:", aid)

    # Países donde está la app (sin la UE ni China)
    r = ok(*pedir("GET", "/v1/apps/%s/appAvailabilityV2" % aid), "leer disponibilidad")
    ta, inc = todos(pedir, ok, "/v2/appAvailabilities/%s/territoryAvailabilities?include=territory&limit=200" % r["data"]["id"])
    paises = sorted({t["relationships"]["territory"]["data"]["id"] for t in ta if t["attributes"].get("available")})
    print("Países de la app:", len(paises))

    # Avisos del servidor (V2) al Panel Tukán Central
    ok(*pedir("PATCH", "/v1/apps/" + aid, {"data": {"type": "apps", "id": aid, "attributes": {
        "subscriptionStatusUrl": AVISOS_URL, "subscriptionStatusUrlVersion": "V2",
        "subscriptionStatusUrlForSandbox": AVISOS_URL, "subscriptionStatusUrlVersionForSandbox": "V2"}}}), "poner avisos V2")
    print("Avisos V2 →", AVISOS_URL)

    subs, cons = productos()
    if solo:
        subs, cons = [x for x in subs if x["id"] == solo], []
        assert subs, "no existe " + solo
        print("SOLO:", solo)
    territorios = sorted(t["id"] for t in todos(pedir, ok, "/v1/territories?limit=200")[0])
    print("Territorios de Apple (precio de suscripción en todos):", len(territorios))

    # Grupo de suscripción
    grupos, _ = todos(pedir, ok, "/v1/apps/%s/subscriptionGroups?limit=50" % aid)
    grupo = next((g for g in grupos if g["attributes"]["referenceName"] == "TuBroadcast"), None)
    if not grupo:
        grupo = ok(*pedir("POST", "/v1/subscriptionGroups", {"data": {"type": "subscriptionGroups",
                    "attributes": {"referenceName": "TuBroadcast"},
                    "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}), "crear grupo")["data"]
        ok(*pedir("POST", "/v1/subscriptionGroupLocalizations", {"data": {"type": "subscriptionGroupLocalizations",
            "attributes": {"locale": LOCALE, "name": "TuBroadcast"},
            "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": grupo["id"]}}}}}), "nombre del grupo")
        print("Grupo creado:", grupo["id"])
    gid = grupo["id"]
    existentes = {s["attributes"]["productId"]: s for s in todos(pedir, ok, "/v1/subscriptionGroups/%s/subscriptions?limit=50" % gid)[0]}

    for s in subs:
        sub = existentes.get(s["id"])
        if not sub:
            sub = ok(*pedir("POST", "/v1/subscriptions", {"data": {"type": "subscriptions", "attributes": {
                "name": s["id"], "productId": s["id"], "subscriptionPeriod": s["periodo"], "groupLevel": s["nivel"],
                "familySharable": False, "reviewNote": NOTA_REVISOR},
                "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": gid}}}}}), "crear " + s["id"])["data"]
        sid = sub["id"]
        locs, _ = todos(pedir, ok, "/v1/subscriptions/%s/subscriptionLocalizations" % sid)
        if not any(l["attributes"]["locale"] == LOCALE for l in locs):
            ok(*pedir("POST", "/v1/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations",
                "attributes": {"locale": LOCALE, "name": s["nombre"], "description": s["descripcion"]},
                "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}}), "texto " + s["id"])
        # Modelo de precios 2026: plan UPFRONT (pago completo por adelantado) en los países de la app.
        # La opción MONTHLY (pago mensual con compromiso de 12 meses) NO se configura (decisión de Dimitry).
        pas, _ = todos(pedir, ok, "/v1/subscriptions/%s/planAvailabilities" % sid)
        upfront = next((pa for pa in pas if (pa.get("attributes") or {}).get("planType") == PLAN), None)
        if not upfront:
            ok(*pedir("POST", "/v1/subscriptionPlanAvailabilities", cuerpo_plan(sid, paises)), "plan UPFRONT " + s["id"])
            print("  %-28s plan UPFRONT creado en %d países" % (s["id"], len(paises)))
            pas, _ = todos(pedir, ok, "/v1/subscriptions/%s/planAvailabilities" % sid)
            upfront = next(pa for pa in pas if (pa.get("attributes") or {}).get("planType") == PLAN)
        ter, _ = todos(pedir, ok, "/v1/subscriptionPlanAvailabilities/%s/availableTerritories?limit=200" % upfront["id"])
        en_plan = [t["id"] for t in ter]
        if set(paises) - set(en_plan):
            en_plan = ampliar_plan(en_plan, paises)
            ok(*pedir("PATCH", "/v1/subscriptionPlanAvailabilities/" + upfront["id"],
                      cuerpo_plan(sid, en_plan, upfront["id"])), "países del plan " + s["id"])
            print("  %-28s plan UPFRONT: ahora en %d países (incluye todos los de la app)" % (s["id"], len(en_plan)))
        # Precio UPFRONT en TODOS los territorios de Apple (27 nov 2026, autorizado por Dimitry): sin esto Apple deja la
        # suscripción en MISSING_METADATA («Debes añadir un precio»). La app sigue sin UE ni China: allí no se vende.
        precios, _ = todos(pedir, ok, "/v1/subscriptions/%s/prices?filter[planType]=%s&include=territory,subscriptionPricePoint&limit=200"
                           % (sid, PLAN))
        faltan = sorted(set(territorios) - {pais_de(p) for p in precios})
        if not faltan:
            print("  %-28s ya tenía precio UPFRONT en los %d territorios" % (s["id"], len(territorios)))
            continue
        # Punto de EE. UU.: el que ya está en vigor (un precio en vigor no se cambia aquí) o el más cercano al objetivo
        usa = next((p for p in precios if pais_de(p) == "USA"), None)
        if usa:
            pp = (usa["relationships"]["subscriptionPricePoint"]["data"]["id"], "(el que ya tenía)")
        else:
            puntos, _ = todos(pedir, ok, "/v1/subscriptions/%s/pricePoints?filter[territory]=USA&filter[planType]=%s&limit=200" % (sid, PLAN))
            pp = mas_cercano([(p["id"], p["attributes"]["customerPrice"]) for p in puntos], s["precio"])
        eq, _ = todos(pedir, ok, "/v1/subscriptionPricePoints/%s/equalizations?include=territory&limit=200" % pp[0])
        por_pais = {"USA": pp[0]}
        for e in eq:
            t = ((e.get("relationships") or {}).get("territory") or {}).get("data") or {}
            if t.get("id"):
                por_pais[t["id"]] = e["id"]

        def poner(lista):
            hechos, rechazados = 0, []
            for pais in lista:
                if pais not in por_pais:
                    rechazados.append((pais, "sin equivalencia"))
                    continue
                st, r = pedir("POST", "/v1/subscriptionPrices", cuerpo_precio(sid, pais, por_pais[pais]))
                if st in (200, 201):
                    hechos += 1
                else:
                    rechazados.append((pais, "%s: %s" % (st, error_corto(r)[:240])))
            return hechos, rechazados

        hechos, rechazados = poner(faltan)
        fuera_del_plan = [p for p, _ in rechazados if p not in en_plan and p in por_pais]
        if fuera_del_plan:
            # Apple no acepta precio donde el plan no está: se amplía SOLO el plan de la suscripción (no la app)
            print("  %-28s Apple rechazó %d precios fuera del plan (p. ej. %s: %s); amplío el plan UPFRONT"
                  % (s["id"], len(fuera_del_plan), rechazados[0][0], rechazados[0][1][:160]))
            en_plan = ampliar_plan(en_plan, paises, fuera_del_plan)
            ok(*pedir("PATCH", "/v1/subscriptionPlanAvailabilities/" + upfront["id"],
                      cuerpo_plan(sid, en_plan, upfront["id"])), "ampliar plan " + s["id"])
            mas, rechazados = poner(fuera_del_plan)
            hechos += mas
        print("  %-28s US$%s · %d territorios nuevos con precio UPFRONT de %d que faltaban" % (s["id"], pp[1], hechos, len(faltan)))
        for pais, motivo in rechazados[:10]:
            print("     aviso precio %s %s" % (pais, motivo))

    # Consumibles: Pase de 24 horas
    iaps = {i["attributes"]["productId"]: i for i in todos(pedir, ok, "/v1/apps/%s/inAppPurchasesV2?limit=200" % aid)[0]}
    for c in cons:
        iap = iaps.get(c["id"])
        if not iap:
            iap = ok(*pedir("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
                "name": c["id"], "productId": c["id"], "inAppPurchaseType": "CONSUMABLE",
                "familySharable": False, "reviewNote": NOTA_REVISOR},
                "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}), "crear " + c["id"])["data"]
        iid = iap["id"]
        locs, _ = todos(pedir, ok, "/v2/inAppPurchases/%s/inAppPurchaseLocalizations" % iid)
        if not any(l["attributes"]["locale"] == LOCALE for l in locs):
            ok(*pedir("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations",
                "attributes": {"locale": LOCALE, "name": c["nombre"], "description": c["descripcion"]},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}}), "texto " + c["id"])
        st, r = pedir("GET", "/v2/inAppPurchases/%s/inAppPurchaseAvailability" % iid)
        if st != 200 or not r.get("data"):
            ok(*pedir("POST", "/v1/inAppPurchaseAvailabilities", {"data": {"type": "inAppPurchaseAvailabilities",
                "attributes": {"availableInNewTerritories": False},
                "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                                  "availableTerritories": {"data": [{"type": "territories", "id": p} for p in paises]}}}}),
               "países " + c["id"])
        st, r = pedir("GET", "/v2/inAppPurchases/%s/iapPriceSchedule" % iid)
        if st == 200 and r.get("data"):
            # Apple crea el horario vacío: solo cuenta si ya tiene un precio puesto
            st2, r2 = pedir("GET", "/v1/inAppPurchasePriceSchedules/%s/manualPrices?limit=1" % r["data"]["id"])
            if st2 == 200 and r2.get("data"):
                print("  %-28s ya tenía precio" % c["id"])
                continue
        puntos, _ = todos(pedir, ok, "/v2/inAppPurchases/%s/pricePoints?filter[territory]=USA&limit=200" % iid)
        pp = mas_cercano([(p["id"], p["attributes"]["customerPrice"]) for p in puntos], c["precio"])
        ok(*pedir("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules",
                     "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                                       "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                                       "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${precio}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${precio}", "attributes": {"startDate": None},
                          "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp[0]}}}}]}),
           "precio " + c["id"])
        print("  %-28s US$%s (los demás países, por equivalencia de Apple)" % (c["id"], pp[1]))

    print("\nLISTO: 16 suscripciones y 4 pases en App Store Connect (estado real: ver el diagnóstico).")


def subir_capturas(carpeta):
    """Sube la captura de revisión de cada compra: planes_01.png para las de 1 celular, planes_03.png para 3, etc.
    Si la compra ya tiene una captura igual (mismo MD5) no la vuelve a subir; si es distinta, la reemplaza."""
    import hashlib
    from asc import error_corto, pedir, subir_archivo
    from publicar_app_store import app_id

    def ok(st, r, que):
        if st not in (200, 201, 204):
            raise RuntimeError("%s (%s): %s" % (que, st, error_corto(r)))
        return r

    aid = app_id(BUNDLE)
    grupos, _ = todos(pedir, ok, "/v1/apps/%s/subscriptionGroups?limit=50" % aid)
    gid = next(g["id"] for g in grupos if g["attributes"]["referenceName"] == "TuBroadcast")
    compras = [("subscriptions", s["id"], s["attributes"]["productId"])
               for s in todos(pedir, ok, "/v1/subscriptionGroups/%s/subscriptions?limit=50" % gid)[0]]
    compras += [("inAppPurchases", i["id"], i["attributes"]["productId"])
                for i in todos(pedir, ok, "/v1/apps/%s/inAppPurchasesV2?limit=200" % aid)[0]
                if i["attributes"]["productId"].startswith("tubroadcast.")]
    hechas = 0
    for tipo, cid, pid in sorted(compras, key=lambda c: c[2]):
        n = int(pid.split(".")[2])
        ruta = os.path.join(carpeta, "planes_%02d.png" % n)
        contenido = open(ruta, "rb").read()
        md5 = hashlib.md5(contenido).hexdigest()
        if tipo == "subscriptions":
            rel_get = "/v1/subscriptions/%s/appStoreReviewScreenshot" % cid
            recurso, relacion, tipo_rel = "subscriptionAppStoreReviewScreenshots", "subscription", "subscriptions"
        else:
            rel_get = "/v2/inAppPurchases/%s/appStoreReviewScreenshot" % cid
            recurso, relacion, tipo_rel = "inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseV2", "inAppPurchases"
        st, r = pedir("GET", rel_get)
        actual = (r.get("data") or None) if st == 200 else None
        if actual and actual["attributes"].get("sourceFileChecksum") == md5:
            print("  %-28s ya tenía esta captura" % pid)
            continue
        if actual:
            pedir("DELETE", "/v1/%s/%s" % (recurso, actual["id"]))
        r = ok(*pedir("POST", "/v1/" + recurso, {"data": {"type": recurso,
              "attributes": {"fileName": os.path.basename(ruta), "fileSize": len(contenido)},
              "relationships": {relacion: {"data": {"type": tipo_rel, "id": cid}}}}}), "reservar captura " + pid)
        sid = r["data"]["id"]
        subir_archivo(r["data"]["attributes"]["uploadOperations"], contenido)
        ok(*pedir("PATCH", "/v1/%s/%s" % (recurso, sid), {"data": {"type": recurso, "id": sid,
              "attributes": {"uploaded": True, "sourceFileChecksum": md5}}}), "confirmar captura " + pid)
        hechas += 1
        print("  %-28s captura subida (%s)" % (pid, os.path.basename(ruta)))
    print("LISTO: %d capturas de revisión subidas." % hechas)


def crear_desde_lista(bundle, ruta_lista, carpeta_capturas=None):
    """(25 nov 2026) Compras simples (consumibles y «una sola vez») de una app web, p. ej. EN VIVO Tycoon.
    ruta_lista: JSON [{id, nombre (<=30), detalle (<=45), precio_usd, tipo: CONSUMABLE|NON_CONSUMABLE}].
    Crea lo que falta, pone texto en es-MX, países de la app, precio (punto de Apple más cercano, EE. UU. como base)
    y, si hay carpeta_capturas/<id>.png o carpeta_capturas/tienda.png, la captura de revisión. Se puede repetir."""
    import hashlib
    from asc import error_corto, pedir, subir_archivo
    from publicar_app_store import app_id

    def ok(st, r, que):
        if st not in (200, 201, 204):
            raise RuntimeError("%s (%s): %s" % (que, st, error_corto(r)))
        return r

    lista = json.load(open(ruta_lista, encoding="utf-8"))
    aid = app_id(bundle)
    r = ok(*pedir("GET", "/v1/apps/%s/appAvailabilityV2" % aid), "leer disponibilidad")
    ta, _ = todos(pedir, ok, "/v2/appAvailabilities/%s/territoryAvailabilities?include=territory&limit=200" % r["data"]["id"])
    paises = sorted({t["relationships"]["territory"]["data"]["id"] for t in ta if t["attributes"].get("available")})
    print("App %s: %s · %d países · %d compras en la lista" % (bundle, aid, len(paises), len(lista)))
    # Avisos del servidor de Apple (V2): reembolsos y revocaciones van al servidor de esa app
    avisos = AVISOS_POR_APP.get(bundle)
    if avisos:
        ok(*pedir("PATCH", "/v1/apps/" + aid, {"data": {"type": "apps", "id": aid, "attributes": {
            "subscriptionStatusUrl": avisos, "subscriptionStatusUrlVersion": "V2",
            "subscriptionStatusUrlForSandbox": avisos, "subscriptionStatusUrlVersionForSandbox": "V2"}}}), "poner avisos V2")
        print("Avisos V2 →", avisos)
    iaps = {i["attributes"]["productId"]: i for i in todos(pedir, ok, "/v1/apps/%s/inAppPurchasesV2?limit=200" % aid)[0]}
    for c in lista:
        nombre = nombre_corto(c["nombre"])
        detalle = c["detalle"][:45]
        iap = iaps.get(c["id"])
        if not iap:
            iap = ok(*pedir("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
                "name": c["id"], "productId": c["id"], "inAppPurchaseType": c["tipo"], "familySharable": False,
                "reviewNote": c.get("nota_revisor") or ("In-game item for EN VIVO Tycoon, delivered by our server after it "
                                                       "verifies the signed StoreKit transaction. Test: Tienda tab > store.")},
                "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}), "crear " + c["id"])["data"]
        iid = iap["id"]
        locs, _ = todos(pedir, ok, "/v2/inAppPurchases/%s/inAppPurchaseLocalizations" % iid)
        if not any(l["attributes"]["locale"] == LOCALE for l in locs):
            ok(*pedir("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations",
                "attributes": {"locale": LOCALE, "name": nombre, "description": detalle},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}}), "texto " + c["id"])
        st, r = pedir("GET", "/v2/inAppPurchases/%s/inAppPurchaseAvailability" % iid)
        if st != 200 or not r.get("data"):
            ok(*pedir("POST", "/v1/inAppPurchaseAvailabilities", {"data": {"type": "inAppPurchaseAvailabilities",
                "attributes": {"availableInNewTerritories": False},
                "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                                  "availableTerritories": {"data": [{"type": "territories", "id": p} for p in paises]}}}}),
               "países " + c["id"])
        con_precio = False
        st, r = pedir("GET", "/v2/inAppPurchases/%s/iapPriceSchedule" % iid)
        if st == 200 and r.get("data"):
            st2, r2 = pedir("GET", "/v1/inAppPurchasePriceSchedules/%s/manualPrices?limit=1" % r["data"]["id"])
            con_precio = st2 == 200 and bool(r2.get("data"))
        precio_txt = "ya tenía precio"
        if not con_precio:
            puntos, _ = todos(pedir, ok, "/v2/inAppPurchases/%s/pricePoints?filter[territory]=USA&limit=200" % iid)
            pp = mas_cercano([(p["id"], p["attributes"]["customerPrice"]) for p in puntos], float(c["precio_usd"]))
            ok(*pedir("POST", "/v1/inAppPurchasePriceSchedules", {
                "data": {"type": "inAppPurchasePriceSchedules",
                         "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                                           "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                                           "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${precio}"}]}}},
                "included": [{"type": "inAppPurchasePrices", "id": "${precio}", "attributes": {"startDate": None},
                              "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp[0]}}}}]}),
               "precio " + c["id"])
            precio_txt = "US$%s" % pp[1]
        captura_txt = ""
        if carpeta_capturas:
            ruta = next((x for x in (os.path.join(carpeta_capturas, c["id"] + ".png"),
                                     os.path.join(carpeta_capturas, "tienda.png")) if os.path.exists(x)), None)
            if ruta:
                contenido = open(ruta, "rb").read()
                md5 = hashlib.md5(contenido).hexdigest()
                st, r = pedir("GET", "/v2/inAppPurchases/%s/appStoreReviewScreenshot" % iid)
                actual = (r.get("data") or None) if st == 200 else None
                if not (actual and actual["attributes"].get("sourceFileChecksum") == md5):
                    if actual:
                        pedir("DELETE", "/v1/inAppPurchaseAppStoreReviewScreenshots/" + actual["id"])
                    r = ok(*pedir("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
                        "type": "inAppPurchaseAppStoreReviewScreenshots",
                        "attributes": {"fileName": os.path.basename(ruta), "fileSize": len(contenido)},
                        "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}}),
                        "reservar captura " + c["id"])
                    subir_archivo(r["data"]["attributes"]["uploadOperations"], contenido)
                    ok(*pedir("PATCH", "/v1/inAppPurchaseAppStoreReviewScreenshots/" + r["data"]["id"], {"data": {
                        "type": "inAppPurchaseAppStoreReviewScreenshots", "id": r["data"]["id"],
                        "attributes": {"uploaded": True, "sourceFileChecksum": md5}}}), "confirmar captura " + c["id"])
                    captura_txt = " · captura subida"
        print("  %-34s %-15s %s%s" % (c["id"], c["tipo"], precio_txt, captura_txt))
    print("LISTO: %d compras de %s." % (len(lista), bundle))


def _corto(obj, maximo=1500):
    t = json.dumps(obj, ensure_ascii=False, sort_keys=True)
    return t if len(t) <= maximo else t[:maximo] + "…"


def _mostrar(pedir, titulo, ruta, maximo=1500):
    """Diagnóstico: GET y muestra código, atributos y relaciones (sin parar si Apple responde error)."""
    from asc import error_corto
    st, r = pedir("GET", ruta)
    print("  · %s  [%s %s]" % (titulo, st, ruta.split("?")[0]))
    if st != 200:
        print("      ERROR:", error_corto(r)[:600])
        return st, r
    data = r.get("data")
    filas = data if isinstance(data, list) else ([data] if data else [])
    if not filas:
        print("      (vacío)")
    for d in filas[:6]:
        print("      %s %s attrs=%s" % (d.get("type"), d.get("id"), _corto(d.get("attributes"), maximo)))
        rels = {k: (v.get("data") if isinstance(v, dict) else None) for k, v in (d.get("relationships") or {}).items()}
        rels = {k: (len(v) if isinstance(v, list) else (v or {}).get("id")) for k, v in rels.items() if v is not None}
        if rels:
            print("        rels=%s" % _corto(rels, 600))
    if isinstance(data, list) and len(data) > 6:
        print("      … %d en total (esta página)" % len(data))
    if (r.get("meta") or {}).get("paging"):
        print("      paging=%s" % _corto(r["meta"]["paging"]))
    return st, r


def resumen_precios(precios, inc):
    """Cuenta precios de suscripción por planType y por país. precios: data de /prices con include=territory."""
    por_plan = {}
    for p in precios:
        plan = (p.get("attributes") or {}).get("planType") or "SIN_PLANTYPE"
        por_plan[plan] = por_plan.get(plan, 0) + 1
    return por_plan


def pais_de(precio):
    return (((precio.get("relationships") or {}).get("territory") or {}).get("data") or {}).get("id")


def comparar_paises(paises_app, paises_plan, paises_precio, territorios=None):
    """Problemas entre países de la app, del plan UPFRONT y con precio UPFRONT.
    Regla (27 nov 2026, autorizado por Dimitry): el plan cubre al menos los países de la app; hay precio UPFRONT en
    todo el plan y, si se da «territorios» (los 175 de Apple), también en todos ellos (UE y China incluidas: la app
    no está disponible allí, así que no se vende)."""
    app, plan, precio = set(paises_app), set(paises_plan), set(paises_precio)
    problemas = []
    if app - plan:
        problemas.append("plan sin países de la app %s" % sorted(app - plan)[:8])
    if plan - precio:
        problemas.append("plan sin precio en %s" % sorted(plan - precio)[:8])
    if territorios and set(territorios) - precio:
        problemas.append("sin precio en %d territorios %s" % (len(set(territorios) - precio), sorted(set(territorios) - precio)[:8]))
    return problemas


def ampliar_plan(paises_plan, paises_app, extra=()):
    """Países que debe tener el plan UPFRONT: nunca quita ninguno; suma los de la app y los extra."""
    return sorted(set(paises_plan) | set(paises_app) | set(extra))


def revisar_suscripcion(pedir, ok, sid, pid, paises, territorios=None):
    """Una línea con todo lo que Apple pide para una suscripción (solo lee)."""
    pas, _ = todos(pedir, ok, "/v1/subscriptions/%s/planAvailabilities" % sid)
    planes = {}
    for pa in pas:
        ter, _ = todos(pedir, ok, "/v1/subscriptionPlanAvailabilities/%s/availableTerritories?limit=200" % pa["id"])
        planes[(pa.get("attributes") or {}).get("planType")] = [t["id"] for t in ter]
    precios, _ = todos(pedir, ok, "/v1/subscriptions/%s/prices?include=territory&limit=200" % sid)
    por_plan = {}
    futuros = 0
    for p in precios:
        a = p.get("attributes") or {}
        por_plan.setdefault(a.get("planType") or "SIN_PLANTYPE", []).append(pais_de(p))
        futuros += 1 if a.get("startDate") else 0
    locs, _ = todos(pedir, ok, "/v1/subscriptions/%s/subscriptionLocalizations" % sid)
    st, r = pedir("GET", "/v1/subscriptions/%s/appStoreReviewScreenshot" % sid)
    cap = (((r.get("data") or {}).get("attributes") or {}).get("assetDeliveryState") or {}).get("state") if st == 200 else st
    problemas = comparar_paises(paises, planes.get("UPFRONT", []), por_plan.get("UPFRONT", []), territorios)
    return "%-28s planes=%s precios=%s futuros=%d textos=%s captura=%s %s" % (
        pid, {k: len(v) for k, v in planes.items()}, {k: len(v) for k, v in por_plan.items()}, futuros,
        [l["attributes"]["locale"] for l in locs], cap, "; ".join(problemas) or "OK")


def diagnostico():
    """(27 nov 2026) Solo lee: estado de las 20 compras y detalle de basico.1.mes, completo.1.anio y un pase."""
    from asc import error_corto, pedir
    from publicar_app_store import app_id

    def ok(st, r, que):
        if st not in (200, 201, 204):
            raise RuntimeError("%s (%s): %s" % (que, st, error_corto(r)))
        return r

    aid = app_id(BUNDLE)
    print("== App", aid)
    _mostrar(pedir, "app", "/v1/apps/%s?fields[apps]=name,bundleId,primaryLocale,contentRightsDeclaration,"
                            "subscriptionStatusUrl,subscriptionStatusUrlVersion,subscriptionStatusUrlForSandbox,"
                            "streamlinedPurchasingEnabled" % aid)
    r = ok(*pedir("GET", "/v1/apps/%s/appAvailabilityV2" % aid), "leer disponibilidad")
    print("  · appAvailabilityV2 attrs=%s" % _corto(r["data"].get("attributes")))
    ta, _ = todos(pedir, ok, "/v2/appAvailabilities/%s/territoryAvailabilities?include=territory&limit=200" % r["data"]["id"])
    paises = sorted({t["relationships"]["territory"]["data"]["id"] for t in ta if t["attributes"].get("available")})
    print("  países de la app:", len(paises), "· USA" if "USA" in paises else "", "· ECU" if "ECU" in paises else "")
    raros = [(t["relationships"]["territory"]["data"]["id"], t["attributes"].get("contentStatuses"))
             for t in ta if t["attributes"].get("available") and t["attributes"].get("contentStatuses") != ["AVAILABLE"]]
    print("  países disponibles con contentStatuses distinto de AVAILABLE:", raros[:20])

    grupos, _ = todos(pedir, ok, "/v1/apps/%s/subscriptionGroups?limit=50" % aid)
    grupo = next(g for g in grupos if g["attributes"]["referenceName"] == "TuBroadcast")
    gid = grupo["id"]
    print("\n== Grupo", gid, _corto(grupo["attributes"]))
    print("  relaciones:", sorted((grupo.get("relationships") or {}).keys()))
    _mostrar(pedir, "localizaciones del grupo", "/v1/subscriptionGroups/%s/subscriptionGroupLocalizations" % gid)

    subs = todos(pedir, ok, "/v1/subscriptionGroups/%s/subscriptions?limit=50" % gid)[0]
    iaps = [i for i in todos(pedir, ok, "/v1/apps/%s/inAppPurchasesV2?limit=200" % aid)[0]
            if i["attributes"]["productId"].startswith("tubroadcast.")]
    print("\n== Estado de las %d suscripciones y %d pases" % (len(subs), len(iaps)))
    estados = {}
    for x in sorted(subs, key=lambda s: s["attributes"]["productId"]) + sorted(iaps, key=lambda s: s["attributes"]["productId"]):
        e = x["attributes"].get("state")
        estados[e] = estados.get(e, 0) + 1
        print("  %-28s %-8s %s" % (x["attributes"]["productId"], x["id"], e))
    print("  RESUMEN:", _corto(estados))

    territorios = [t["id"] for t in todos(pedir, ok, "/v1/territories?limit=200")[0]]
    print("\n== Revisión completa de las suscripciones (plan UPFRONT, precios en los %d territorios, textos, captura)" % len(territorios))
    for x in sorted(subs, key=lambda s: s["attributes"]["productId"]):
        print("  " + revisar_suscripcion(pedir, ok, x["id"], x["attributes"]["productId"], paises, territorios))

    elegidas = [s for s in subs if s["attributes"]["productId"] in ("tubroadcast.basico.1.mes", "tubroadcast.completo.1.anio")]
    for s in elegidas:
        sid = s["id"]
        print("\n== Suscripción %s (%s)" % (s["attributes"]["productId"], sid))
        print("  attrs:", _corto(s["attributes"], 3000))
        print("  relaciones:", sorted((s.get("relationships") or {}).keys()))
        _mostrar(pedir, "subscriptionAvailability", "/v1/subscriptions/%s/subscriptionAvailability" % sid)
        _mostrar(pedir, "planAvailabilities", "/v1/subscriptions/%s/planAvailabilities" % sid)
        st, r = pedir("GET", "/v1/subscriptions/%s/planAvailabilities" % sid)
        for pa in (r.get("data") or []) if st == 200 else []:
            _mostrar(pedir, "  territorios del plan %s" % (pa.get("attributes") or {}).get("planType"),
                     "/v1/subscriptionPlanAvailabilities/%s/availableTerritories?limit=200" % pa["id"], 200)
        _mostrar(pedir, "localizaciones", "/v1/subscriptions/%s/subscriptionLocalizations" % sid)
        _mostrar(pedir, "captura de revisión", "/v1/subscriptions/%s/appStoreReviewScreenshot" % sid)
        try:
            precios, inc = todos(pedir, ok, "/v1/subscriptions/%s/prices?include=territory,subscriptionPricePoint&limit=200" % sid)
            print("  · precios: %d · por planType %s" % (len(precios), _corto(resumen_precios(precios, inc))))
            pps = {i["id"]: i.get("attributes") for i in inc if i.get("type") == "subscriptionPricePoints"}
            for p in precios:
                if pais_de(p) in ("USA", "ECU"):
                    ppid = (((p.get("relationships") or {}).get("subscriptionPricePoint") or {}).get("data") or {}).get("id")
                    print("      %s attrs=%s punto=%s" % (pais_de(p), _corto(p.get("attributes")), _corto(pps.get(ppid))))
            sin_pais = sum(1 for p in precios if not pais_de(p))
            if sin_pais:
                print("      (%d precios sin país en la respuesta)" % sin_pais)
        except RuntimeError as e:
            print("  · precios: ERROR", e)
        for plan in ("UPFRONT", "MONTHLY"):
            _mostrar(pedir, "precios %s en USA" % plan,
                     "/v1/subscriptions/%s/prices?filter[planType]=%s&filter[territory]=USA&include=subscriptionPricePoint,territory" % (sid, plan))
        _mostrar(pedir, "precio introductorio", "/v1/subscriptions/%s/introductoryOffers?limit=5" % sid)
        _mostrar(pedir, "versiones", "/v1/subscriptions/%s/versions" % sid, 3000)
        st, r = pedir("GET", "/v1/subscriptions/%s/versions" % sid)
        for v in (r.get("data") or [])[:1] if st == 200 else []:
            _mostrar(pedir, "  localizaciones de la versión %s" % v["attributes"].get("version"),
                     "/v1/subscriptionVersions/%s/localizations" % v["id"])
        _mostrar(pedir, "imágenes", "/v1/subscriptions/%s/images" % sid)
        _mostrar(pedir, "compra promocionada", "/v1/subscriptions/%s/promotedPurchase" % sid)

    if iaps:
        i = sorted(iaps, key=lambda s: s["attributes"]["productId"])[0]
        iid = i["id"]
        print("\n== Pase %s (%s)" % (i["attributes"]["productId"], iid))
        print("  attrs:", _corto(i["attributes"], 3000))
        print("  relaciones:", sorted((i.get("relationships") or {}).keys()))
        _mostrar(pedir, "versiones", "/v2/inAppPurchases/%s/versions" % iid, 3000)
        st, r = pedir("GET", "/v2/inAppPurchases/%s/versions" % iid)
        for v in (r.get("data") or [])[:1] if st == 200 else []:
            _mostrar(pedir, "  localizaciones de la versión %s" % v["attributes"].get("version"),
                     "/v1/inAppPurchaseVersions/%s/localizations" % v["id"])
        _mostrar(pedir, "inAppPurchaseAvailability", "/v2/inAppPurchases/%s/inAppPurchaseAvailability" % iid)
        _mostrar(pedir, "localizaciones", "/v2/inAppPurchases/%s/inAppPurchaseLocalizations" % iid)
        _mostrar(pedir, "captura de revisión", "/v2/inAppPurchases/%s/appStoreReviewScreenshot" % iid)
        st, r = _mostrar(pedir, "horario de precios", "/v2/inAppPurchases/%s/iapPriceSchedule?include=baseTerritory" % iid)
        if st == 200 and r.get("data"):
            _mostrar(pedir, "precios manuales", "/v1/inAppPurchasePriceSchedules/%s/manualPrices?include=territory&limit=5" % r["data"]["id"])
    print("\nFIN del diagnóstico (no se cambió nada).")


def probar():
    subs, cons = productos()
    assert len(subs) == 16 and len(cons) == 4, (len(subs), len(cons))
    for p in subs + cons:
        assert len(p["nombre"]) <= 30, p
        assert len(p["descripcion"]) <= 45, p
    assert mas_cercano([("a", "5.99"), ("b", "6.99")], 5.99)[0] == "a"
    assert mas_cercano([("a", "14.99"), ("b", "15.99")], 15.4)[0] == "a"
    assert precio_objetivo("tubroadcast.basico.1.mes") == 5.99
    assert precio_objetivo("tubroadcast.basico.1.anio") == 71.88      # 12 × 5,99
    assert precio_objetivo("tubroadcast.completo.3.mes") == 28.02     # 10,99 × 3 × 0,85
    assert precio_objetivo("tubroadcast.completo.3.anio") == 336.29   # 12 × 28,0245
    assert precio_objetivo("tubroadcast.pase24.10") == 33.91          # 3,99 × 10 × 0,85
    assert nombre_corto("Completo mensual (10 celulares)") == "Completo mensual (10 cel.)"
    assert nombre_corto("Pase de 24 horas (10 celulares)") == "Pase de 24 horas (10 cel.)"
    # Modelo de precios 2026 (sin red)
    c = cuerpo_plan("1", ["USA", "ECU"])
    assert c["data"]["attributes"] == {"planType": "UPFRONT", "availableInNewTerritories": False}, c
    assert [t["id"] for t in c["data"]["relationships"]["availableTerritories"]["data"]] == ["USA", "ECU"]
    assert c["data"]["relationships"]["subscription"]["data"]["id"] == "1"
    c = cuerpo_plan("1", ["USA"], "pa1")
    assert c["data"]["id"] == "pa1" and "planType" not in c["data"]["attributes"] and "subscription" not in c["data"]["relationships"]
    c = cuerpo_precio("1", "ECU", "pp9")
    assert c["data"]["attributes"]["planType"] == "UPFRONT" and c["data"]["attributes"]["startDate"] is None
    assert c["data"]["relationships"]["territory"]["data"]["id"] == "ECU"
    assert c["data"]["relationships"]["subscriptionPricePoint"]["data"]["id"] == "pp9"
    assert comparar_paises(["USA", "ECU"], ["ECU", "USA"], ["USA", "ECU"]) == []
    assert comparar_paises(["USA", "ECU"], ["USA"], ["USA", "ECU"])[0].startswith("plan sin países de la app")
    assert comparar_paises(["USA", "ECU"], ["USA", "ECU"], ["USA"])[0].startswith("plan sin precio")
    assert comparar_paises(["USA"], ["USA"], ["USA"], ["USA", "FRA", "CHN"]) == ["sin precio en 2 territorios ['CHN', 'FRA']"]
    assert comparar_paises(["USA"], ["USA", "FRA"], ["USA", "FRA", "CHN"], ["USA", "FRA", "CHN"]) == []
    assert ampliar_plan(["USA", "FRA"], ["USA", "ECU"]) == ["ECU", "FRA", "USA"]      # nunca quita países
    assert ampliar_plan(["USA"], ["USA"], ["CHN"]) == ["CHN", "USA"]
    assert pais_de({"relationships": {"territory": {"data": {"id": "ECU"}}}}) == "ECU" and pais_de({}) is None
    assert resumen_precios([{"attributes": {"planType": "UPFRONT"}}, {"attributes": {}}], []) == {"UPFRONT": 1, "SIN_PLANTYPE": 1}
    for p in subs + cons:
        print("  %-28s %-26s US$%7.2f" % (p["id"], p["nombre"], p["precio"]))
    print("OK: 20 productos, nombres de hasta 30 letras y descripciones de hasta 45.")
    carpeta = os.path.join(REPO, "publicacion", "compras")
    for archivo in sorted(os.listdir(carpeta)) if os.path.isdir(carpeta) else []:
        if archivo.endswith(".json"):
            probar_lista(os.path.join(carpeta, archivo))


def probar_lista(ruta):
    """Revisa (sin Apple) una lista del modo «lista»: claves, ids únicos con el prefijo de la app, nombres <= 30,
    detalles <= 45, precio y tipo válidos. El prefijo es el nombre del archivo: compras/envivo.json → «envivo.»."""
    import re
    lista = json.load(open(ruta, encoding="utf-8"))
    prefijo = os.path.splitext(os.path.basename(ruta))[0] + "."
    assert isinstance(lista, list) and lista, ruta
    ids = set()
    for c in lista:
        faltan = {"id", "nombre", "detalle", "precio_usd", "tipo"} - set(c)
        assert not faltan, (ruta, c.get("id"), "faltan", faltan)
        assert c["id"].startswith(prefijo) and re.fullmatch(r"[A-Za-z0-9._]+", c["id"]), (ruta, c["id"])
        assert c["id"] not in ids, (ruta, "repetido", c["id"])
        ids.add(c["id"])
        assert 0 < len(c["nombre"]) <= 30, (ruta, c["id"], c["nombre"])
        assert 0 < len(c["detalle"]) <= 45, (ruta, c["id"], c["detalle"])
        assert c["tipo"] in ("CONSUMABLE", "NON_CONSUMABLE"), (ruta, c["id"], c["tipo"])
        assert float(c["precio_usd"]) > 0, (ruta, c["id"])
    print("OK: %s · %d compras (%d de una sola vez), nombres <= 30 y detalles <= 45." % (
        os.path.relpath(ruta, REPO), len(lista), sum(c["tipo"] == "NON_CONSUMABLE" for c in lista)))


if __name__ == "__main__":
    if sys.argv[1:] == ["probar"]:
        probar()
    elif sys.argv[1:2] == ["solo"]:
        correr(solo=sys.argv[2])
    elif sys.argv[1:] == ["diagnostico"]:
        diagnostico()
    elif sys.argv[1:2] == ["capturas"]:
        subir_capturas(sys.argv[2])
    elif sys.argv[1:2] == ["lista"]:
        # python3 herramientas/crear_compras.py lista <bundle> <lista.json> [carpeta_capturas]
        crear_desde_lista(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    else:
        correr()
