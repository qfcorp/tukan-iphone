// Revisión de Apple del 27 nov 2026 (regla 3.1.1): en iPhone los planes se desbloquean SOLO con In-App Purchase.
// Estas pruebas comprueban que:
//   1. No existe ninguna pantalla, campo ni acción para escribir o pegar un código de activación o un token.
//   2. Sin una compra de StoreKit no hay plan, aunque haya un token o una licencia viejos guardados en el llavero.
//   3. La app no muestra el código del paquete que manda el panel (es para Android y la web).
//   4. La ficha de la App Store (notas para el revisor) ya no habla de códigos ni de la regla 3.1.3(b).
import StoreKit
import StoreKitTest
import XCTest
@testable import TuBroadcast

@MainActor
final class PruebasSoloCompraApple: XCTestCase {
    override func setUp() async throws {
        PanelFalso.reiniciar()
    }

    /// Carpeta nativas/tubroadcast (o construir/tubroadcast en la Mac de GitHub, que es una copia).
    private var carpetaApp: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    private func fuentes() throws -> [String: String] {
        let carpeta = carpetaApp.appendingPathComponent("Sources")
        let nombres = try FileManager.default.contentsOfDirectory(atPath: carpeta.path).filter { $0.hasSuffix(".swift") }
        var r: [String: String] = [:]
        for n in nombres { r[n] = try String(contentsOf: carpeta.appendingPathComponent(n), encoding: .utf8) }
        return r
    }

    /// Almacén como lo dejaba una versión anterior que activó un código: token, licencia firmada y vigente,
    /// último contacto ahora mismo y el código del paquete. Sin la marca de compra de Apple.
    private func almacenConTokenViejo(dispositivo: String = "cel-viejo") -> AlmacenMemoria {
        let a = AlmacenMemoria()
        let l = LlavePrueba.licencia(dispositivo: dispositivo, plan: "completo", modulos: ["rtmp", "srt"])
        a.guardar(dispositivo, "dispositivo")
        a.guardar("token-viejo-de-codigo-0123456789abcdef", "token")
        a.guardar(String(data: try! JSONEncoder().encode(l), encoding: .utf8), "licencia")
        a.guardar(String(Int64(Date().timeIntervalSince1970)), "ultimo_contacto")
        a.guardar(#"{"codigo":"TB-ABCD-EFGH","plan":"completo","celulares":3}"#, "paquete")
        return a
    }

    // MARK: - 1. No hay forma de escribir un código

    func testNoExistePantallaNiAccionParaEscribirCodigo() throws {
        let f = try fuentes()
        XCTAssertGreaterThanOrEqual(f.count, 10, "No se encontraron los archivos de Sources en \(carpetaApp.path)")
        let prohibido = ["PantallaActivarCodigo", "Activar con código", "activar(codigo", "\"activar\"", "PedidoActivar",
                         "BloqueCodigo", "TB-", "UIPasteboard", "struct Paquete"]
        for (archivo, texto) in f {
            for p in prohibido {
                XCTAssertFalse(texto.contains(p), "\(archivo) todavía tiene «\(p)»: en iPhone no puede haber activación con código")
            }
        }
        // Las pantallas de licencia no tienen ningún campo de texto (ni para código ni para token).
        let licencia = try XCTUnwrap(f["PantallasLicencia.swift"])
        for campo in ["TextField", "SecureField", "TextEditor", "onOpenURL", "DataScannerViewController", "AVCaptureMetadataOutput"] {
            XCTAssertFalse(licencia.contains(campo), "PantallasLicencia.swift no debe tener \(campo)")
        }
        // En toda la app: ningún lector de QR ni enlace que traiga un token o un código.
        for (archivo, texto) in f {
            for p in ["AVCaptureMetadataOutput", "DataScannerViewController", "\"token\"]", "queryItems?.first(where: { $0.name == \"token\""] {
                XCTAssertFalse(texto.contains(p), "\(archivo) no debe leer tokens de QR o enlaces (\(p))")
            }
        }
        // El único lugar donde se guarda un token es la respuesta a una compra de Apple.
        let gestor = try XCTUnwrap(f["GestorLicencia.swift"])
        XCTAssertEqual(gestor.components(separatedBy: "almacen.guardar(r.token, \"token\")").count - 1, 1)
        XCTAssertTrue(gestor.contains("\"apple_compra\""))
    }

    func testLosEnlacesDeLaAppSoloCarganConexiones() {
        let g = gestorDePrueba()
        let ajustes = Ajustes()
        let antes = ajustes.conexiones
        defer { ajustes.conexiones = antes }
        let n = ajustes.importarEnlace(URL(string: "tubroadcast://activar?codigo=TB-ABCD-EFGH&token=abc0123456789abcdef0123")!)
        XCTAssertEqual(n, 0)
        XCTAssertFalse(g.estado.esValida)
        XCTAssertTrue(PanelFalso.pedidos.isEmpty, "Un enlace no puede activar nada")
    }

    // MARK: - 2. Sin compra de StoreKit no hay plan aunque haya un token viejo

    func testTokenViejoGuardadoNoDaPlan() async {
        let almacen = almacenConTokenViejo()
        PanelFalso.responder = { accion, json in
            // Aunque el panel todavía reconociera el token viejo, la app ni siquiera lo manda.
            let l = LlavePrueba.licencia(dispositivo: json["dispositivo"] as? String ?? "", plan: "completo", modulos: ["rtmp", "srt"])
            return (200, ["ok": true, "ordenes": [], "licencia": LlavePrueba.json(l), "mensaje": "", "accion": accion])
        }
        let g = gestorDePrueba(almacen: almacen)
        XCTAssertFalse(g.estado.esValida, "Un token o licencia que no vino de una compra de Apple no vale en iPhone")
        XCTAssertFalse(g.tieneToken)
        XCTAssertEqual(g.token, "")
        XCTAssertEqual(g.limites(tipoConexion: "RTMP"), .gratis)
        XCTAssertEqual(g.limites(tipoConexion: "SRT"), .gratis)
        // Se borró del llavero (también el código del paquete)
        XCTAssertNil(almacen.leer("token"))
        XCTAssertNil(almacen.leer("licencia"))
        XCTAssertNil(almacen.leer("paquete"))
        XCTAssertEqual(almacen.leer("dispositivo"), "cel-viejo", "El id del celular se conserva")
        // El latido no manda nada con el token viejo y sigue gratis
        await g.latido()
        XCTAssertTrue(PanelFalso.pedidos.isEmpty, "Sin compra de Apple no se habla con el panel")
        XCTAssertFalse(g.estado.esValida)
    }

    func testTokenEscritoDespuesSinCompraTampocoVale() {
        // Aunque algo escribiera un token y una licencia en el llavero sin pasar por la compra, no vale.
        let almacen = AlmacenMemoria()
        let g = gestorDePrueba(almacen: almacen)
        let l = LlavePrueba.licencia(dispositivo: g.dispositivo)
        almacen.guardar("token-pegado-0123456789abcdef", "token")
        almacen.guardar(String(data: try! JSONEncoder().encode(l), encoding: .utf8), "licencia")
        almacen.guardar(String(Int64(Date().timeIntervalSince1970)), "ultimo_contacto")
        g.recalcular()
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
    }

    func testSinCompraDeStoreKitNoHayPlanAunqueHayaTokenViejo() async throws {
        let sesion = try SKTestSession(configurationFileNamed: "TuBroadcast")
        sesion.disableDialogs = true
        sesion.resetToDefaultState()
        sesion.clearTransactions()
        defer { sesion.clearTransactions() }
        PanelFalso.responder = { _, json in
            let l = LlavePrueba.licencia(dispositivo: json["dispositivo"] as? String ?? "")
            return (200, ["ok": true, "mensaje": "", "licencia": LlavePrueba.json(l), "token": "token-0123456789abcdef"])
        }
        let g = gestorDePrueba(almacen: almacenConTokenViejo())
        let tienda = Tienda(gestor: g)
        await tienda.cargarProductos(avisar: false)
        XCTAssertTrue(tienda.hayPlanes)
        // Sin compras en StoreKit: ninguna transacción vigente ni pendiente
        var vigentes = 0
        for await _ in StoreKit.Transaction.currentEntitlements { vigentes += 1 }
        XCTAssertEqual(vigentes, 0)
        await tienda.revisarPendientes()
        XCTAssertNil(PanelFalso.ultimo("apple_compra"), "Sin compra de Apple no se pide licencia")
        XCTAssertFalse(g.estado.esValida)
        XCTAssertFalse(g.tieneToken)
        XCTAssertEqual(g.limites(tipoConexion: "RTMP"), .gratis)
    }

    func testConCompraDeAppleSiHayPlan() async throws {
        // Control: la misma licencia SÍ vale cuando llega por una compra de Apple.
        PanelFalso.responder = { accion, json in
            guard accion == "apple_compra" else { return (404, ["ok": false]) }
            let l = LlavePrueba.licencia(dispositivo: json["dispositivo"] as! String, plan: "completo", modulos: ["rtmp", "srt"])
            return (200, ["ok": true, "mensaje": "", "licencia": LlavePrueba.json(l), "token": "token-apple-0123456789abcdef"])
        }
        let almacen = almacenConTokenViejo()
        let g = gestorDePrueba(almacen: almacen)
        XCTAssertFalse(g.estado.esValida)
        let r = try await g.registrarCompraApple(jws: "jws-de-prueba")
        XCTAssertTrue(r.ok)
        XCTAssertTrue(g.estado.esValida)
        XCTAssertEqual(g.token, "token-apple-0123456789abcdef")
        XCTAssertEqual(almacen.leer(GestorLicencia.claveOrigen), GestorLicencia.origenApple)
        // Al abrir otra vez la app (nuevo gestor con el mismo llavero) la compra de Apple se conserva
        let otra = gestorDePrueba(almacen: almacen)
        XCTAssertTrue(otra.estado.esValida)
        XCTAssertTrue(otra.tieneToken)
    }

    // MARK: - 3. Textos del panel sin códigos

    func testTextosDelPanelSinCodigos() {
        XCTAssertEqual(GestorLicencia.textoParaIPhone(
            "¡Listo! Plan Completo activado con el App Store. Para los otros celulares usa el código TB-ABCD-EFGH.", siVacio: "x"),
            "¡Listo! Plan Completo activado con el App Store.")
        XCTAssertEqual(GestorLicencia.textoParaIPhone(
            "Listo. Este celular quedó libre: ya puedes activar el código TB-ABCD-EFGH en otro celular. Te quedan 2 cambios.", siVacio: "x"),
            "Listo. Te quedan 2 cambios.")
        XCTAssertEqual(GestorLicencia.textoParaIPhone("El celular no mandó su código.", siVacio: "No se pudo."), "No se pudo.")
        XCTAssertEqual(GestorLicencia.textoParaIPhone("", siVacio: "Vacío."), "Vacío.")
        XCTAssertEqual(GestorLicencia.textoParaIPhone("Demasiados intentos. Espera una hora e intenta otra vez.", siVacio: "x"),
                       "Demasiados intentos. Espera una hora e intenta otra vez.")
    }

    // MARK: - 4. Ficha de la App Store

    func testFichaSinCodigosNiComprasFuera() throws {
        let raiz = carpetaApp.deletingLastPathComponent().deletingLastPathComponent()
        let archivo = raiz.appendingPathComponent("publicacion/fichas/tubroadcast.json")
        let datos = try Data(contentsOf: archivo)
        let ficha = try XCTUnwrap(try JSONSerialization.jsonObject(with: datos) as? [String: Any])
        let notas = try XCTUnwrap(ficha["notas_revisor"] as? String)
        XCTAssertTrue(notas.contains("{video}"))
        XCTAssertTrue(notas.contains("In-App Purchase"))
        XCTAssertTrue(notas.contains("Ajustes > Licencia > Ver planes"))
        for p in ["TB-", "3.1.3", "website", "web site", "Google", "activation code can", "bought on"] {
            XCTAssertFalse(notas.contains(p), "Las notas para el revisor no deben decir «\(p)»")
        }
        for clave in ["descripcion", "descripcion_con_planes", "descripcion_gratis", "texto_promocional", "subtitulo", "palabras_clave"] {
            let t = (ficha[clave] as? String ?? "").lowercased()
            for p in ["tb-", "código", "codigo", "google play", "vendedor", "whatsapp", "precio especial"] {
                XCTAssertFalse(t.contains(p), "\(clave) no debe decir «\(p)»")
            }
        }
    }
}
