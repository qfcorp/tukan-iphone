// Ayudas de las pruebas: panel falso (URLProtocol), llave de prueba para firmar licencias y reloj falso.
import CryptoKit
import Foundation
import XCTest
@testable import TuBroadcast

/// Simula el Panel Tukán Central: guarda cada pedido y responde lo que diga `responder`.
final class PanelFalso: URLProtocol {
    struct Pedido {
        let accion: String
        let json: [String: Any]
    }

    static var pedidos: [Pedido] = []
    /// Devuelve (código HTTP, JSON). nil = sin internet.
    static var responder: (String, [String: Any]) -> (Int, [String: Any])? = { _, _ in (500, ["ok": false]) }

    static func reiniciar() {
        pedidos = []
        responder = { _, _ in (500, ["ok": false]) }
    }

    static func sesion() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [PanelFalso.self]
        return URLSession(configuration: c)
    }

    static func ultimo(_ accion: String) -> Pedido? { pedidos.last { $0.accion == accion } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let accion = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "a" }?.value ?? ""
        var cuerpo = request.httpBody ?? Data()
        if cuerpo.isEmpty, let s = request.httpBodyStream { cuerpo = Self.leer(s) }
        let json = (try? JSONSerialization.jsonObject(with: cuerpo)) as? [String: Any] ?? [:]
        PanelFalso.pedidos.append(Pedido(accion: accion, json: json))
        guard let respuesta = PanelFalso.responder(accion, json) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (codigo, resp) = respuesta
        let datos = try! JSONSerialization.data(withJSONObject: resp)
        let r = HTTPURLResponse(url: url, statusCode: codigo, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: datos)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func leer(_ s: InputStream) -> Data {
        s.open(); defer { s.close() }
        var d = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable {
            let n = s.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            d.append(buf, count: n)
        }
        return d
    }
}

/// Llave de prueba (se crea en cada corrida): hace el papel de la llave privada del panel.
enum LlavePrueba {
    static let privada = P256.Signing.PrivateKey()
    static var publicaBase64: String { privada.publicKey.derRepresentation.base64EncodedString() }

    static func firmar(_ l: Licencia, con llave: P256.Signing.PrivateKey = LlavePrueba.privada) -> Licencia {
        var c = l
        c.firma = try! llave.signature(for: Data(l.textoFirmado.utf8)).derRepresentation.base64EncodedString()
        return c
    }

    static func licencia(dispositivo: String, plan: String = "completo", modulos: [String] = ["rtmp", "srt", "abr", "grove"],
                         ahora: Date = Date(), horas: Int = 24 * 30, con llave: P256.Signing.PrivateKey = LlavePrueba.privada) -> Licencia {
        let t = Int64(ahora.timeIntervalSince1970)
        return firmar(Licencia(dispositivo: dispositivo, cliente: "Productora de prueba", plan: plan, modulos: modulos,
                               emitida: t, vence: t + Int64(horas) * 3600), con: llave)
    }

    /// La licencia como la manda el panel en JSON.
    static func json(_ l: Licencia) -> [String: Any] {
        let d = try! JSONEncoder().encode(l)
        return try! JSONSerialization.jsonObject(with: d) as! [String: Any]
    }
}

final class RelojFalso: Reloj {
    var momento: Date
    init(_ momento: Date = Date(timeIntervalSince1970: 1_795_000_000)) { self.momento = momento }
    func ahora() -> Date { momento }
    func avanzar(_ segundos: TimeInterval) { momento = momento.addingTimeInterval(segundos) }
}

@MainActor
func gestorDePrueba(reloj: Reloj = RelojSistema()) -> GestorLicencia {
    GestorLicencia(panel: PanelCliente(servidor: URL(string: "https://panel.prueba")!, sesion: PanelFalso.sesion()),
                   almacen: AlmacenMemoria(), llavePublica: LlavePrueba.publicaBase64, reloj: reloj)
}
