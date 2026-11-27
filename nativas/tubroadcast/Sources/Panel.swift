// Contrato con el Panel Tukán Central: POST JSON a {servidor}/tubroadcast_api.php?a=...
// (igual que Android, core/.../tuner/Tuner.kt; servidor: src/Broadcast.php). El VIDEO nunca pasa por aquí.
// En iPhone los planes se desbloquean SOLO con la compra de Apple (regla 3.1.1; revisión de Apple del 27 nov 2026):
// la app NO usa la acción «activar» (código de activación) ni deja escribir ningún código o token.
//   apple_compra  {dispositivo, modelo, version, transaccion (JWS), app_cuenta} -> {ok, mensaje, licencia, token}
//                 errores: 400, 402 (firma mala, vencida, revocada...), 403 (paquete lleno), 429 -> se muestra «mensaje» (sin frases que nombren códigos)
//   liberar       {dispositivo, token}                                          -> {ok, mensaje, cambios_restantes}
//                 429 = sin cambios (se muestra el mensaje) · 401 = el token ya no sirve (el celular queda libre)
//   latido        {dispositivo, token, controlCedido, versionAjustes, estadisticas} -> {ok, ordenes, licencia?, mensaje}
import Foundation

struct PedidoCompraApple: Encodable, Sendable {
    let dispositivo: String
    let modelo: String
    let version: String
    /// jwsRepresentation de la Transaction ya verificada por StoreKit 2.
    let transaccion: String
    /// appAccountToken (UUID guardado en el llavero) que se pasó a la compra.
    let app_cuenta: String
    /// Mismo dato que «version» (el panel lo lee con este nombre en sus registros).
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

/// Respuesta de apple_compra. Si el panel manda otros datos (por ejemplo un código de paquete) la app los ignora:
/// en iPhone no se muestra ni se usa ningún código.
struct RespuestaCompra: Decodable, Sendable {
    var ok: Bool
    var mensaje: String = ""
    var licencia: Licencia?
    var token: String = ""

    private enum CodingKeys: String, CodingKey { case ok, mensaje, licencia, token }

    init(ok: Bool, mensaje: String) { self.ok = ok; self.mensaje = mensaje }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        mensaje = try c.decodeIfPresent(String.self, forKey: .mensaje) ?? ""
        licencia = try? c.decodeIfPresent(Licencia.self, forKey: .licencia)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
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
