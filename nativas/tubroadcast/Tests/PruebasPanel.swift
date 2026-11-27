// Liberar (OK, 429 y 401) y latido contra un panel falso. El plan llega SOLO por una compra de Apple
// (apple_compra con la transacción de StoreKit): en iPhone no existe activar con código.
import CryptoKit
import XCTest
@testable import TuBroadcast

@MainActor
final class PruebasPanel: XCTestCase {
    override func setUp() async throws {
        PanelFalso.reiniciar()
    }

    /// Panel falso que acepta la compra de Apple con una licencia firmada para el celular que la manda.
    /// Igual que el panel de verdad, el mensaje nombra el código del paquete (la app NO lo debe mostrar).
    func panelQueAceptaCompra(plan: String = "basico", modulos: [String] = ["rtmp", "abr", "grove"],
                              llave: P256.Signing.PrivateKey = LlavePrueba.privada) {
        PanelFalso.responder = { accion, json in
            switch accion {
            case "apple_compra":
                let l = LlavePrueba.licencia(dispositivo: json["dispositivo"] as! String, plan: plan, modulos: modulos, con: llave)
                return (200, ["ok": true, "mensaje": "¡Listo! Plan Básico activado con el App Store. Para los otros celulares usa el código TB-ABCD-EFGH.",
                              "licencia": LlavePrueba.json(l), "token": "token-de-prueba-0123456789abcdef",
                              "codigo": "TB-ABCD-EFGH", "plan": plan, "celulares": 3, "expira": 1_798_000_000])
            default:
                return (404, ["ok": false, "mensaje": "no existe"])
            }
        }
    }

    /// Celular con plan comprado con Apple (la transacción la verifica el panel; aquí el panel es falso).
    func gestorConCompra(plan: String = "basico", modulos: [String] = ["rtmp", "abr", "grove"],
                         reloj: Reloj = RelojSistema()) async throws -> GestorLicencia {
        panelQueAceptaCompra(plan: plan, modulos: modulos)
        let g = gestorDePrueba(reloj: reloj)
        let r = try await g.registrarCompraApple(jws: "jws-de-prueba")
        XCTAssertTrue(r.ok, r.mensaje)
        XCTAssertTrue(g.estado.esValida)
        return g
    }

    func testCompraDeAppleDaElPlan() async throws {
        panelQueAceptaCompra()
        let g = gestorDePrueba()
        XCTAssertFalse(g.estado.esValida)
        let r = try await g.registrarCompraApple(jws: "jws-de-prueba")
        XCTAssertTrue(r.ok, r.mensaje)
        XCTAssertEqual(r.mensaje, "¡Listo! Plan Básico activo en este iPhone.")
        XCTAssertFalse(r.mensaje.contains("TB-"), "En iPhone no se muestra ningún código")
        XCTAssertEqual(g.estado.licencia?.plan, "basico")
        XCTAssertEqual(g.token, "token-de-prueba-0123456789abcdef")
        let p = PanelFalso.ultimo("apple_compra")!
        XCTAssertEqual(p.json["dispositivo"] as? String, g.dispositivo)
        XCTAssertNotNil(UUID(uuidString: g.dispositivo), "El id del celular es un UUID propio")
        XCTAssertEqual(p.json["transaccion"] as? String, "jws-de-prueba")
        XCTAssertTrue((p.json["versionApp"] as? String ?? "").hasPrefix("ios-"))
        XCTAssertNil(PanelFalso.ultimo("activar"), "La app nunca usa «activar» (código)")
        // Básico: RTMP sin límites, SRT con los límites gratis
        XCTAssertEqual(g.limites(tipoConexion: "RTMP"), .sinLimites)
        XCTAssertEqual(g.limites(tipoConexion: "SRT"), .gratis)
    }

    func testCompraRechazaLicenciaConFirmaFalsa() async throws {
        panelQueAceptaCompra(llave: P256.Signing.PrivateKey())
        let g = gestorDePrueba()
        let r = try await g.registrarCompraApple(jws: "jws-de-prueba")
        XCTAssertFalse(r.ok)
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
    }

    func testCompraRechazadaPorElPanelNoMuestraCodigos() async throws {
        PanelFalso.responder = { _, _ in
            (403, ["ok": false, "mensaje": "Tu paquete ya usa sus 3 celulares. En uno de ellos toca «Liberar este celular» o escribe a Tukán Software."])
        }
        let g = gestorDePrueba()
        let r = try await g.registrarCompraApple(jws: "jws-de-prueba")
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.mensaje, "Tu paquete ya usa sus 3 celulares. En uno de ellos toca «Liberar este celular» o escribe a Tukán Software.")
        XCTAssertFalse(g.estado.esValida)
        PanelFalso.responder = { _, _ in (400, ["ok": false, "mensaje": "El celular no mandó su código."]) }
        let r2 = try await g.registrarCompraApple(jws: "jws-de-prueba")
        XCTAssertFalse(r2.mensaje.lowercased().contains("código"))
    }

    func testLiberarEsteCelular() async throws {
        let g = try await gestorConCompra()
        PanelFalso.responder = { accion, _ in
            accion == "liberar" ? (200, ["ok": true, "mensaje": "Listo. Este celular quedó libre: ya puedes activar el código TB-ABCD-EFGH en otro celular.",
                                         "cambios_restantes": 2, "codigo": "TB-ABCD-EFGH"])
                                : (404, ["ok": false])
        }
        let (ok, mensaje) = await g.liberar()
        XCTAssertTrue(ok)
        XCTAssertTrue(mensaje.contains("Listo. Este celular quedó libre"))
        XCTAssertTrue(mensaje.contains("Restaurar compras"))
        XCTAssertTrue(mensaje.contains("2"))
        XCTAssertFalse(mensaje.contains("TB-"), "En iPhone no se muestra el código del paquete")
        let p = PanelFalso.ultimo("liberar")!
        XCTAssertEqual(p.json["dispositivo"] as? String, g.dispositivo)
        XCTAssertEqual(p.json["token"] as? String, "token-de-prueba-0123456789abcdef")
        // Vuelve a modo gratis
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
        XCTAssertEqual(g.limites(tipoConexion: "RTMP"), .gratis)
    }

    func testLiberarConDemasiadosCambios429() async throws {
        let g = try await gestorConCompra()
        PanelFalso.responder = { _, _ in
            (429, ["ok": false, "mensaje": "Ya usaste los cambios de celular de este mes. Podrás liberar otra vez el 1 de diciembre.",
                   "cambios_restantes": 0])
        }
        let (ok, mensaje) = await g.liberar()
        XCTAssertFalse(ok)
        XCTAssertEqual(mensaje, "Ya usaste los cambios de celular de este mes. Podrás liberar otra vez el 1 de diciembre.")
        // La licencia sigue en este celular
        XCTAssertTrue(g.estado.esValida)
        XCTAssertTrue(g.tieneToken)
    }

    func testLiberarConTokenQueYaNoSirve401() async throws {
        let g = try await gestorConCompra()
        PanelFalso.responder = { _, _ in (401, ["ok": false, "mensaje": "Este celular ya no está activado."]) }
        let (ok, mensaje) = await g.liberar()
        XCTAssertTrue(ok, "Si el panel ya no lo reconoce, el celular igual queda libre")
        XCTAssertEqual(mensaje, "Este celular ya no está activado.")
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
    }

    func testLatidoRenuevaLicencia() async throws {
        let g = try await gestorConCompra(plan: "basico", modulos: ["rtmp"])
        PanelFalso.responder = { accion, json in
            guard accion == "latido" else { return (404, ["ok": false]) }
            let l = LlavePrueba.licencia(dispositivo: json["dispositivo"] as! String, plan: "completo", modulos: ["rtmp", "srt"])
            return (200, ["ok": true, "ordenes": [], "licencia": LlavePrueba.json(l), "pedirVistaPrevia": false, "mensaje": ""])
        }
        await g.latido()
        let p = PanelFalso.ultimo("latido")!
        XCTAssertEqual(p.json["token"] as? String, "token-de-prueba-0123456789abcdef")
        XCTAssertEqual(p.json["controlCedido"] as? Bool, false)
        XCTAssertNotNil(p.json["estadisticas"] as? [String: Any])
        XCTAssertEqual(g.estado.licencia?.plan, "completo")
        XCTAssertEqual(g.limites(tipoConexion: "SRT"), .sinLimites)
    }

    func testLatido401VuelveAGratis() async throws {
        let g = try await gestorConCompra()
        PanelFalso.responder = { _, _ in (401, ["ok": false, "mensaje": "Este celular ya no está activado. Vuelve a activar la licencia."]) }
        await g.latido()
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
        XCTAssertEqual(g.mensaje, "Este celular ya no está activado. Volvió a la versión gratis.")
    }

    func testLatidoSinInternetMantieneLaLicencia() async throws {
        let g = try await gestorConCompra()
        PanelFalso.responder = { _, _ in nil }
        await g.latido()
        XCTAssertTrue(g.estado.esValida)
    }

    func testSinInternetMasDe72HorasVuelveAGratis() async throws {
        let reloj = RelojFalso(Date())
        let g = try await gestorConCompra(reloj: reloj)
        PanelFalso.responder = { _, _ in nil }
        reloj.avanzar(72 * 3600 + 60)
        await g.latido()
        XCTAssertEqual(g.estado, .gratis("Conéctate a internet para confirmar tu licencia."))
    }
}
