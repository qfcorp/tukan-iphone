#!/usr/bin/env python3
"""
Crea en App Store Connect las 20 compras de TuBroadcast (23 nov 2026, contrato de apps pagadas ya activo):
  - Grupo de suscripción «TuBroadcast» con 16 suscripciones (Básico/Completo × 1/3/5/10 celulares × mes/año).
  - 4 consumibles «Pase de 24 horas» (1/3/5/10 celulares).
Los productos, nombres y niveles salen de nativas/tubroadcast/TuBroadcast.storekit (la misma lista que usa la app);
los precios, de la regla de Dimitry (ver BASE y precio_objetivo).
Precio: el punto de precio de Apple en EE. UU. más cercano; los demás países con la equivalencia de Apple.
Países: los mismos de la app (sin la UE ni China continental).
También pone la dirección de avisos del servidor (App Store Server Notifications V2) del Panel Tukán Central.
Se puede correr varias veces: lo que ya existe no se duplica.

Uso:  python3 herramientas/crear_compras.py [probar]
      probar = solo muestra lo que haría (sin llamar a Apple).
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
STOREKIT = os.path.join(REPO, "nativas", "tubroadcast", "TuBroadcast.storekit")
# Precios (decisión de Dimitry, 23 nov 2026): los mismos de Google Play para 1 celular; paquete = precio × celulares × 0,85;
# anual = 12 × el mensual (sin meses de regalo). Apple usa el punto de precio más cercano.
BASE = {"basico": 5.99, "completo": 10.99, "pase24": 3.99}


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


def correr():
    from asc import app_id, error_corto, pedir

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
        st, r = pedir("GET", "/v1/subscriptions/%s/subscriptionAvailability" % sid)
        if st != 200 or not r.get("data"):
            ok(*pedir("POST", "/v1/subscriptionAvailabilities", {"data": {"type": "subscriptionAvailabilities",
                "attributes": {"availableInNewTerritories": False},
                "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                  "availableTerritories": {"data": [{"type": "territories", "id": p} for p in paises]}}}}),
               "países " + s["id"])
        precios, _ = todos(pedir, ok, "/v1/subscriptions/%s/prices?limit=200" % sid)
        if len(precios) >= len(paises):
            print("  %-28s ya tenía precios (%d)" % (s["id"], len(precios)))
            continue
        puntos, _ = todos(pedir, ok, "/v1/subscriptions/%s/pricePoints?filter[territory]=USA&limit=200" % sid)
        pp = mas_cercano([(p["id"], p["attributes"]["customerPrice"]) for p in puntos], s["precio"])
        eq, _ = todos(pedir, ok, "/v1/subscriptionPricePoints/%s/equalizations?include=territory&limit=200" % pp[0])
        por_pais = {"USA": pp[0]}
        for e in eq:
            t = ((e.get("relationships") or {}).get("territory") or {}).get("data") or {}
            if t.get("id") in paises:
                por_pais[t["id"]] = e["id"]
        hechos = 0
        for pais, ppid in por_pais.items():
            st, r = pedir("POST", "/v1/subscriptionPrices", {"data": {"type": "subscriptionPrices",
                "attributes": {"startDate": None, "preserveCurrentPrice": False},
                "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                  "territory": {"data": {"type": "territories", "id": pais}},
                                  "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": ppid}}}}})
            if st in (200, 201):
                hechos += 1
            elif st != 409:
                print("   aviso precio %s %s (%s): %s" % (s["id"], pais, st, error_corto(r)))
        print("  %-28s US$%s · %d países con precio" % (s["id"], pp[1], hechos))

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

    print("\nLISTO: 16 suscripciones y 4 pases en App Store Connect.")
    print("Falta para enviarlas a revisión: una captura de la pantalla de planes por compra (se suben junto con la versión).")


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
    for p in subs + cons:
        print("  %-28s %-26s US$%7.2f" % (p["id"], p["nombre"], p["precio"]))
    print("OK: 20 productos, nombres de hasta 30 letras y descripciones de hasta 45.")


if __name__ == "__main__":
    probar() if (sys.argv[1:] == ["probar"]) else correr()
