// Compras dentro de la app con Apple (StoreKit 2) para las apps web que venden algo digital (p. ej. EN VIVO Tycoon).
// Solo se activa si apps/<app>/app.json trae "compras_apple": true (Config.comprasApple).
//
// La página habla con este puente así (la respuesta llega como Promise):
//   await window.webkit.messageHandlers.tukanAppStore.postMessage({accion:'productos', ids:[...]})
//     -> {ok, productos:[{id, titulo, descripcion, precio, moneda, valor}]}
//   ... {accion:'comprar', id, cuenta?}   -> {ok, estado:'comprado', jws, transaccion, producto} | {ok:false, estado:'cancelado'|'pendiente'|'error', mensaje?}
//   ... {accion:'terminar', transaccion}  -> {ok}   (solo después de que el servidor entregó la compra)
//   ... {accion:'pendientes'}             -> {ok, transacciones:[{jws, transaccion, producto}]}
//   ... {accion:'restaurar'}              -> {ok, transacciones:[...]}   (compras «una sola vez» del usuario)
// Y cuando Apple aprueba una compra más tarde (p. ej. «Pedir permiso para comprar») la app avisa con el evento
//   window 'tukanAppStore' {detail:{tipo:'transaccion', jws, transaccion, producto}}.
// La app NUNCA entrega nada por su cuenta: el servidor verifica el JWS con Apple y recién ahí se «termina» la transacción.
import StoreKit
import WebKit

@MainActor
final class PuenteTienda: NSObject, WKScriptMessageHandlerWithReply {
    static let nombre = "tukanAppStore"
    weak var web: WKWebView?
    private var productos: [String: Product] = [:]
    private var porTerminar: [UInt64: Transaction] = [:]
    private var escucha: Task<Void, Never>?

    override init() {
        super.init()
        // Compras que Apple aprueba fuera del momento de comprar (Ask to Buy, renovaciones, otros aparatos)
        escucha = Task { [weak self] in
            for await resultado in Transaction.updates {
                await self?.avisarPagina(resultado)
            }
        }
    }


    func userContentController(_ controlador: WKUserContentController, didReceive mensaje: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let datos = mensaje.body as? [String: Any] ?? [:]
        let accion = datos["accion"] as? String ?? ""
        Task { @MainActor in
            replyHandler(await self.atender(accion, datos), nil)
        }
    }

    func atender(_ accion: String, _ datos: [String: Any]) async -> [String: Any] {
        switch accion {
        case "productos":
            return await cargarProductos(datos["ids"] as? [String] ?? [])
        case "comprar":
            return await comprar(datos["id"] as? String ?? "", cuenta: datos["cuenta"] as? String)
        case "terminar":
            return await terminar(datos["transaccion"] as? String ?? "")
        case "pendientes":
            return ["ok": true, "transacciones": await pendientes()]
        case "restaurar":
            return await restaurar()
        default:
            return ["ok": false, "estado": "error", "mensaje": "Acción desconocida."]
        }
    }

    // MARK: - Acciones

    private func cargarProductos(_ ids: [String]) async -> [String: Any] {
        do {
            let lista = try await Product.products(for: ids)
            for p in lista { productos[p.id] = p }
            return ["ok": true, "productos": lista.map(PuenteTienda.describir)]
        } catch {
            return ["ok": false, "estado": "error", "mensaje": error.localizedDescription, "productos": []]
        }
    }

    static func describir(_ p: Product) -> [String: Any] {
        ["id": p.id, "titulo": p.displayName, "descripcion": p.description, "precio": p.displayPrice,
         "moneda": p.priceFormatStyle.currencyCode, "valor": NSDecimalNumber(decimal: p.price).doubleValue]
    }

    private func comprar(_ id: String, cuenta: String?) async -> [String: Any] {
        do {
            var producto = productos[id]
            if producto == nil { producto = try await Product.products(for: [id]).first }
            guard let producto else {
                return ["ok": false, "estado": "error", "mensaje": "Este producto no está disponible en la App Store."]
            }
            var opciones: Set<Product.PurchaseOption> = []
            if let cuenta, let uuid = UUID(uuidString: cuenta) { opciones.insert(.appAccountToken(uuid)) }
            let resultado = try await producto.purchase(options: opciones)
            switch resultado {
            case .success(let verificacion):
                var r: [String: Any] = ["ok": true, "estado": "comprado"]
                r.merge(guardar(verificacion)) { a, _ in a }
                return r
            case .userCancelled:
                return ["ok": false, "estado": "cancelado"]
            case .pending:
                return ["ok": false, "estado": "pendiente"]
            @unknown default:
                return ["ok": false, "estado": "error", "mensaje": "Respuesta desconocida de la App Store."]
            }
        } catch {
            return ["ok": false, "estado": "error", "mensaje": error.localizedDescription]
        }
    }

    /// Guarda la transacción para terminarla después y devuelve lo que necesita el servidor (el JWS firmado por Apple).
    private func guardar(_ verificacion: VerificationResult<Transaction>) -> [String: Any] {
        let t: Transaction
        switch verificacion {
        case .verified(let x): t = x
        case .unverified(let x, _): t = x   // el servidor la vuelve a verificar y la rechaza si no es válida
        }
        porTerminar[t.id] = t
        return ["jws": verificacion.jwsRepresentation, "transaccion": String(t.id), "producto": t.productID]
    }

    private func terminar(_ id: String) async -> [String: Any] {
        guard let n = UInt64(id) else { return ["ok": false, "estado": "error", "mensaje": "Transacción no válida."] }
        if let t = porTerminar.removeValue(forKey: n) {
            await t.finish()
            return ["ok": true]
        }
        for await v in Transaction.unfinished {
            if case .verified(let t) = v, t.id == n { await t.finish(); return ["ok": true] }
            if case .unverified(let t, _) = v, t.id == n { await t.finish(); return ["ok": true] }
        }
        return ["ok": true, "estado": "no_estaba"]
    }

    private func pendientes() async -> [[String: Any]] {
        var lista: [[String: Any]] = []
        for await v in Transaction.unfinished { lista.append(guardar(v)) }
        return lista
    }

    private func restaurar() async -> [String: Any] {
        do { try await AppStore.sync() } catch {
            // Si el usuario cancela el inicio de sesión de Apple igual se devuelve lo que ya está en el aparato
        }
        var lista: [[String: Any]] = []
        for await v in Transaction.currentEntitlements { lista.append(guardar(v)) }
        return ["ok": true, "transacciones": lista]
    }

    private func avisarPagina(_ v: VerificationResult<Transaction>) async {
        var detalle: [String: Any] = guardar(v)
        detalle["tipo"] = "transaccion"
        guard let web, let datos = try? JSONSerialization.data(withJSONObject: detalle),
              let json = String(data: datos, encoding: .utf8) else { return }
        _ = try? await web.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('tukanAppStore', {detail: \(json)}));")
    }
}
