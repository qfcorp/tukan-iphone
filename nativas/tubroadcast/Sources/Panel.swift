// Contrato con el Panel Tukán Central: POST JSON a {servidor}/tubroadcast_api.php?a=...
// (igual que Android, core/.../tuner/Tuner.kt; servidor: src/Broadcast.php). El VIDEO nunca pasa por aquí.
//   activar       {codigo, dispositivo, modelo, versionApp}                     -> {ok, mensaje, licencia, token}
//   apple_compra  {dispositivo, modelo, version, transaccion (JWS), app_cuenta} -> igual que activar + {codigo, plan, celulares, expira (unix s)}
//                 errores: 400, 402 (firma mala, vencida, revocada...), 403 (paquete lleno), 429 -> siempre se muestra «mensaje»
//   liberar       {dispositivo, token}                                          -> {ok, mensaje, cambios_restantes, codigo}
//                 429 = sin cambios (se muestra el mensaje) · 401 = el token ya no sirve (el celular queda libre)
//   latido        {dispositivo, token, controlCedido, versionAjustes, estadisticas} -> {ok, ordenes, licencia?, mensaje}
import Foundation

struct PedidoActivar: Encodable, Sendable {
    let codigo: String
    let dispositivo: String
    let modelo: String
    let versionApp: String
}

struct PedidoCompraApple: Encodable, Sendable {
    let dispositivo: String
    let modelo: String
    let version: String
    /// jwsRepresentation de la Transaction ya verificada por StoreKit 2.
    let transaccion: String
    /// appAccountToken (UUID guardado en el llavero) que se pasó a la compra.
    let app_cuenta: String
    /// Mismo dato que «version», con el nombre que usa activar (por compatibilidad).
    let versionApp: String
}

struct PedidoLiberar: Encodable, Sendable {
    let dispositivo: String
    let token: String
}

struct Estadisticas: Encodable, Sendable {
    var transmitiendo = false
    var bitrateKbps = 0
    var segundosEnVivo = 0
    var camara = ""
    var silenciado = false
    var bateriaPct = -1
    var red = ""
}

struct PedidoLatido: Encodable, Sendable {
    let dispositivo: String
    let token: String
    let controlCedido: Bool
    let versionAjustes: Int
    let estadisticas: Estadisticas
}

/// Respuesta de activar y de apple_compra.
struct RespuestaActivacion: Decodable, Sendable {
    var ok: Bool
    var mensaje: String = ""
    var licencia: Licencia?
    var token: String = ""
    /// Solo apple_compra: código del paquete para activar los otros celulares.
    var codigo: String?
    var plan: String?
    var celulares: Int?
    var expira: String?

    private enum CodingKeys: String, CodingKey { case ok, mensaje, licencia, token, codigo, plan, celulares, expira }

    init(ok: Bool, mensaje: String) { self.ok = ok; self.mensaje = mensaje }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        mensaje = try c.decodeIfPresent(String.self, forKey: .mensaje) ?? ""
        licencia = try? c.decodeIfPresent(Licencia.self, forKey: .licencia)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        codigo = try? c.decodeIfPresent(String.self, forKey: .codigo)
        plan = try? c.decodeIfPresent(String.self, forKey: .plan)
        if let n = try? c.decodeIfPresent(Int.self, forKey: .celulares) { celulares = n }
        else if let s = try? c.decodeIfPresent(String.self, forKey: .celulares) { celulares = Int(s) }
        if let s = try? c.decodeIfPresent(String.self, forKey: .expira) { expira = s }
        else if let n = try? c.decodeIfPresent(Int64.self, forKey: .expira) { expira = String(n) }
    }
}

struct RespuestaLiberar: Decodable, Sendable {
    var ok: Bool
    var mensaje: String = ""
    var cambios_restantes: Int?

    private enum CodingKeys: String, CodingKey { case ok, mensaje, cambios_restantes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        mensaje = try c.decodeIfPresent(String.self, forKey: .mensaje) ?? ""
        cambios_restantes = try? c.decodeIfPresent(Int.self, forKey: .cambios_restantes)
    }
}

struct RespuestaLatido: Decodable, Sendable {
    var ok: Bool
    var licencia: Licencia?
    var mensaje: String = ""

    private enum CodingKeys: String, CodingKey { case ok, licencia, mensaje }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        licencia = try? c.decodeIfPresent(Licencia.self, forKey: .licencia)
        mensaje = try c.decodeIfPresent(String.self, forKey: .mensaje) ?? ""
    }
}

enum ErrorPanel: LocalizedError {
    case sinConexion
    case respuestaRara(Int)

    var errorDescription: String? {
        switch self {
        case .sinConexion: return "No se pudo conectar con el servidor de Tukán. Revisa tu internet e intenta otra vez."
        case .respuestaRara(let c): return "El servidor de Tukán respondió algo inesperado (\(c)). Intenta en un momento."
        }
    }
}

struct PanelCliente: Sendable {
    let servidor: URL
    let sesion: URLSession

    init(servidor: URL = LlavePanel.servidor, sesion: URLSession = .shared) {
        self.servidor = servidor
        self.sesion = sesion
    }

    func url(_ accion: String) -> URL {
        var c = URLComponents(url: servidor.appendingPathComponent("tubroadcast_api.php"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "a", value: accion)]
        return c.url!
    }

    /// Manda el pedido y devuelve (código HTTP, respuesta). El panel responde JSON también en los errores (400, 404, 429...).
    func enviar<P: Encodable & Sendable, R: Decodable & Sendable>(_ accion: String, _ pedido: P, como: R.Type) async throws -> (Int, R) {
        var req = URLRequest(url: url(accion), timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(pedido)
        let datos: Data
        let resp: URLResponse
        do {
            (datos, resp) = try await sesion.data(for: req)
        } catch {
            throw ErrorPanel.sinConexion
        }
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let r = try? JSONDecoder().decode(R.self, from: datos) else { throw ErrorPanel.respuestaRara(codigo) }
        return (codigo, r)
    }
}
