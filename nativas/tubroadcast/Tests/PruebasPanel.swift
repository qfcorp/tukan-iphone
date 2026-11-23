// Activar con código, liberar (OK y 429) y latido, contra un panel falso.
import CryptoKit
import XCTest
@testable import TuBroadcast

@MainActor
final class PruebasPanel: XCTestCase {
    override func setUp() async throws {
        PanelFalso.reiniciar()
    }

    /// Panel falso que activa el código TB-ABCD-EFGH con una licencia firmada para el celular que la pide.
    func panelQueActiva(plan: String = "basico", modulos: [String] = ["rtmp", "abr", "grove"],
                        llave: P256.Signing.PrivateKey = LlavePrueba.privada) {
        PanelFalso.responder = { accion, json in
            switch accion {
            case "activar":
                guard json["codigo"] as? String == "TB-ABCD-EFGH" else {
                    return (404, ["ok": false, "mensaje": "Ese código de activación no existe. Revísalo o pídelo a Tukán Software."])
                }
                let l = LlavePrueba.licencia(dispositivo: json["dispositivo"] as! String, plan: plan, modulos: modulos, con: llave)
                return (200, ["ok": true, "mensaje": "¡Listo! Plan Básico activado para Productora de prueba.",
                              "licencia": LlavePrueba.json(l), "token": "token-de-prueba-0123456789abcdef"])
            default:
                return (404, ["ok": false, "mensaje": "no existe"])
            }
        }
    }

    func testActivarConCodigo() async {
        panelQueActiva()
        let g = gestorDePrueba()
        XCTAssertFalse(g.estado.esValida)
        let (ok, mensaje) = await g.activar(codigo: "TB-ABCD-EFGH")
        XCTAssertTrue(ok, mensaje)
        XCTAssertEqual(mensaje, "¡Listo! Plan Básico activado para Productora de prueba.")
        XCTAssertTrue(g.estado.esValida)
        XCTAssertEqual(g.estado.licencia?.plan, "basico")
        XCTAssertEqual(g.token, "token-de-prueba-0123456789abcdef")
        // Mismo JSON que Android: {codigo, dispositivo, modelo, versionApp}
        let p = PanelFalso.ultimo("activar")!
        XCTAssertEqual(p.json["codigo"] as? String, "TB-ABCD-EFGH")
        XCTAssertEqual(p.json["dispositivo"] as? String, g.dispositivo)
        XCTAssertNotNil(UUID(uuidString: g.dispositivo), "El id del celular es un UUID propio")
        XCTAssertNotNil(p.json["modelo"] as? String)
        XCTAssertTrue((p.json["versionApp"] as? String ?? "").hasPrefix("ios-"))
        // Básico: RTMP sin límites, SRT con los límites gratis
        XCTAssertEqual(g.limites(tipoConexion: "RTMP"), .sinLimites)
        XCTAssertEqual(g.limites(tipoConexion: "SRT"), .gratis)
    }

    func testActivarConCodigoQueNoExiste() async {
        panelQueActiva()
        let g = gestorDePrueba()
        let (ok, mensaje) = await g.activar(codigo: "TB-ZZZZ-ZZZZ")
        XCTAssertFalse(ok)
        XCTAssertEqual(mensaje, "Ese código de activación no existe. Revísalo o pídelo a Tukán Software.")
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
    }

    func testActivarRechazaLicenciaConFirmaFalsa() async {
        panelQueActiva(llave: P256.Signing.PrivateKey())
        let g = gestorDePrueba()
        let (ok, _) = await g.activar(codigo: "TB-ABCD-EFGH")
        XCTAssertFalse(ok)
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
    }

    func testActivarSinInternet() async {
        PanelFalso.responder = { _, _ in nil }
        let g = gestorDePrueba()
        let (ok, mensaje) = await g.activar(codigo: "TB-ABCD-EFGH")
        XCTAssertFalse(ok)
        XCTAssertTrue(mensaje.contains("internet"))
    }

    func testLiberarEsteCelular() async {
        panelQueActiva()
        let g = gestorDePrueba()
        _ = await g.activar(codigo: "TB-ABCD-EFGH")
        XCTAssertTrue(g.estado.esValida)
        PanelFalso.responder = { accion, _ in
            accion == "liberar" ? (200, ["ok": true, "mensaje": "Listo. Este celular quedó libre.", "cambios_restantes": 2])
                                : (404, ["ok": false])
        }
        let (ok, mensaje) = await g.liberar()
        XCTAssertTrue(ok)
        XCTAssertTrue(mensaje.contains("Listo. Este celular quedó libre."))
        XCTAssertTrue(mensaje.contains("2"))
        let p = PanelFalso.ultimo("liberar")!
        XCTAssertEqual(p.json["dispositivo"] as? String, g.dispositivo)
        XCTAssertEqual(p.json["token"] as? String, "token-de-prueba-0123456789abcdef")
        // Vuelve a modo gratis
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
        XCTAssertEqual(g.limites(tipoConexion: "RTMP"), .gratis)
    }

    func testLiberarConDemasiadosCambios429() async {
        panelQueActiva()
        let g = gestorDePrueba()
        _ = await g.activar(codigo: "TB-ABCD-EFGH")
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

    func testLatidoRenuevaLicencia() async {
        panelQueActiva(plan: "basico", modulos: ["rtmp"])
        let g = gestorDePrueba()
        _ = await g.activar(codigo: "TB-ABCD-EFGH")
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

    func testLatido401VuelveAGratis() async {
        panelQueActiva()
        let g = gestorDePrueba()
        _ = await g.activar(codigo: "TB-ABCD-EFGH")
        PanelFalso.responder = { _, _ in (401, ["ok": false, "mensaje": "Este celular ya no está activado. Vuelve a activar la licencia."]) }
        await g.latido()
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
        XCTAssertEqual(g.mensaje, "Este celular ya no está activado. Vuelve a activar la licencia.")
    }

    func testLatidoSinInternetMantieneLaLicencia() async {
        panelQueActiva()
        let g = gestorDePrueba()
        _ = await g.activar(codigo: "TB-ABCD-EFGH")
        PanelFalso.responder = { _, _ in nil }
        await g.latido()
        XCTAssertTrue(g.estado.esValida)
    }

    func testSinInternetMasDe72HorasVuelveAGratis() async {
        panelQueActiva()
        let reloj = RelojFalso(Date())
        let g = gestorDePrueba(reloj: reloj)
        _ = await g.activar(codigo: "TB-ABCD-EFGH")
        XCTAssertTrue(g.estado.esValida)
        PanelFalso.responder = { _, _ in nil }
        reloj.avanzar(72 * 3600 + 60)
        await g.latido()
        XCTAssertEqual(g.estado, .gratis("Conéctate a internet para confirmar tu licencia."))
    }
}
