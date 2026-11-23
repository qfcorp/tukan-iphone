// Compras con Apple (StoreKitTest + archivo TuBroadcast.storekit): los 20 productos, compra -> apple_compra en el panel.
import StoreKit
import StoreKitTest
import XCTest
@testable import TuBroadcast

@MainActor
final class PruebasTienda: XCTestCase {
    var sesion: SKTestSession!

    override func setUp() async throws {
        PanelFalso.reiniciar()
        sesion = try SKTestSession(configurationFileNamed: "TuBroadcast")
        sesion.disableDialogs = true
        sesion.resetToDefaultState()
        sesion.clearTransactions()
    }

    override func tearDown() async throws {
        sesion?.clearTransactions()
        sesion = nil
    }

    /// Panel falso que acepta la compra de Apple y devuelve licencia + código del paquete.
    func panelQueAceptaCompras(plan: String = "completo", celulares: Int = 3) {
        PanelFalso.responder = { accion, json in
            guard accion == "apple_compra" else { return (404, ["ok": false]) }
            let l = LlavePrueba.licencia(dispositivo: json["dispositivo"] as! String, plan: plan, modulos: ["rtmp", "srt", "abr"])
            return (200, ["ok": true, "mensaje": "¡Listo! Plan Completo activado.", "licencia": LlavePrueba.json(l),
                          "token": "token-apple-0123456789abcdef", "codigo": "TB-PAQU-ETE3", "plan": plan,
                          "celulares": celulares, "expira": 1_798_000_000])
        }
    }

    /// Lee el contenido (payload) de un JWS de StoreKit.
    func contenidoJWS(_ jws: String) -> [String: Any] {
        let partes = jws.split(separator: ".")
        guard partes.count == 3 else { return [:] }
        var b = String(partes[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    func testIdsDeLosProductos() {
        XCTAssertEqual(InfoProducto.todos.count, 20)
        XCTAssertEqual(InfoProducto.de("tubroadcast.basico.3.mes"), InfoProducto(tipo: .basico, celulares: 3, periodo: .mes))
        XCTAssertEqual(InfoProducto.de("tubroadcast.completo.10.anio"), InfoProducto(tipo: .completo, celulares: 10, periodo: .anio))
        XCTAssertEqual(InfoProducto.de("tubroadcast.pase24.5"), InfoProducto(tipo: .pase24, celulares: 5, periodo: .pase))
        XCTAssertNil(InfoProducto.de("tubroadcast.basico.2.mes"))
        XCTAssertNil(InfoProducto.de("tubroadcast.pase24.1.mes"))
        XCTAssertNil(InfoProducto.de("otra.cosa"))
        for id in InfoProducto.todos { XCTAssertEqual(InfoProducto.de(id)?.id, id) }
    }

    func testCargaLos20ProductosDeApple() async throws {
        let g = gestorDePrueba()
        let tienda = Tienda(gestor: g)
        await tienda.cargarProductos()
        XCTAssertEqual(tienda.productos.count, 20)
        let subs = tienda.productos.filter { $0.type == .autoRenewable }
        XCTAssertEqual(subs.count, 16)
        XCTAssertEqual(Set(subs.compactMap { $0.subscription?.subscriptionGroupID }).count, 1, "Un solo grupo de suscripción")
        XCTAssertEqual(tienda.productos.filter { $0.type == .consumable }.count, 4)
        for n in InfoProducto.celularesPosibles {
            let ps = tienda.productos(celulares: n)
            XCTAssertEqual(ps.map(\.id), ["tubroadcast.basico.\(n).mes", "tubroadcast.basico.\(n).anio",
                                          "tubroadcast.completo.\(n).mes", "tubroadcast.completo.\(n).anio",
                                          "tubroadcast.pase24.\(n)"])
            // El precio lo pone Apple
            XCTAssertTrue(ps.allSatisfy { !$0.displayPrice.isEmpty })
        }
    }

    func testCompraEnviaLaTransaccionAlPanel() async throws {
        panelQueAceptaCompras()
        let g = gestorDePrueba()
        let tienda = Tienda(gestor: g)
        await tienda.cargarProductos()
        let producto = try XCTUnwrap(tienda.productos.first { $0.id == "tubroadcast.completo.3.mes" })

        let resultado = await tienda.comprar(producto)
        guard case .listo(let r) = resultado else { return XCTFail("La compra debía quedar lista: \(resultado)") }
        XCTAssertEqual(r.codigo, "TB-PAQU-ETE3")

        // Lo que llegó al panel: {dispositivo, modelo, version, transaccion (JWS), app_cuenta}
        let p = try XCTUnwrap(PanelFalso.ultimo("apple_compra"))
        XCTAssertEqual(p.json["dispositivo"] as? String, g.dispositivo)
        XCTAssertNotNil(p.json["modelo"] as? String)
        XCTAssertNotNil(p.json["version"] as? String)
        XCTAssertEqual(p.json["app_cuenta"] as? String, g.appCuenta.uuidString.lowercased())
        let jws = try XCTUnwrap(p.json["transaccion"] as? String)
        let contenido = contenidoJWS(jws)
        XCTAssertEqual(contenido["productId"] as? String, "tubroadcast.completo.3.mes")
        XCTAssertEqual((contenido["appAccountToken"] as? String)?.lowercased(), g.appCuenta.uuidString.lowercased())

        // Licencia activa y código del paquete guardado para los otros celulares
        XCTAssertTrue(g.estado.esValida)
        XCTAssertEqual(g.limites(tipoConexion: "SRT"), .sinLimites)
        XCTAssertEqual(g.paquete, Paquete(codigo: "TB-PAQU-ETE3", plan: "completo", celulares: 3, expira: "1798000000"))

        // La transacción quedó terminada (finish)
        var pendientes = 0
        for await _ in StoreKit.Transaction.unfinished { pendientes += 1 }
        XCTAssertEqual(pendientes, 0)
    }

    func testCompraDelPase24Horas() async throws {
        panelQueAceptaCompras(plan: "dia", celulares: 1)
        let g = gestorDePrueba()
        let tienda = Tienda(gestor: g)
        await tienda.cargarProductos()
        let producto = try XCTUnwrap(tienda.productos.first { $0.id == "tubroadcast.pase24.1" })
        XCTAssertEqual(producto.type, .consumable)
        guard case .listo = await tienda.comprar(producto) else { return XCTFail("El pase debía quedar listo") }
        let jws = try XCTUnwrap(PanelFalso.ultimo("apple_compra")?.json["transaccion"] as? String)
        XCTAssertEqual(contenidoJWS(jws)["productId"] as? String, "tubroadcast.pase24.1")
        XCTAssertTrue(g.estado.esValida)
    }

    func testCompraSinInternetNoSeTerminaParaReintentar() async throws {
        PanelFalso.responder = { _, _ in nil }
        let g = gestorDePrueba()
        let tienda = Tienda(gestor: g)
        await tienda.cargarProductos()
        let producto = try XCTUnwrap(tienda.productos.first { $0.id == "tubroadcast.basico.1.mes" })
        guard case .error(let m) = await tienda.comprar(producto) else { return XCTFail("Sin internet debía dar error") }
        XCTAssertTrue(m.contains("Restaurar compras"))
        XCTAssertFalse(g.estado.esValida)
        var pendientes = 0
        for await _ in StoreKit.Transaction.unfinished { pendientes += 1 }
        XCTAssertEqual(pendientes, 1, "La compra queda sin terminar para mandarla al panel cuando haya internet")

        // Vuelve el internet: se reintenta y queda activa
        panelQueAceptaCompras(plan: "basico", celulares: 1)
        await tienda.revisarPendientes()
        XCTAssertTrue(g.estado.esValida)
        pendientes = 0
        for await _ in StoreKit.Transaction.unfinished { pendientes += 1 }
        XCTAssertEqual(pendientes, 0)
    }
}
