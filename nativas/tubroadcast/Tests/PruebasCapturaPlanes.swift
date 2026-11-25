// Capturas de la pantalla de planes para la revisión de Apple (cada compra necesita una «captura de revisión»).
// Corre con StoreKitTest (TuBroadcast.storekit, mismos precios que App Store Connect) y guarda un PNG por paquete
// (1, 3, 5 y 10 celulares) en la carpeta CAPTURAS_DIR (el workflow la pasa con TEST_RUNNER_CAPTURAS_DIR).
import StoreKitTest
import SwiftUI
import UIKit
import XCTest
@testable import TuBroadcast

@MainActor
final class PruebasCapturaPlanes: XCTestCase {
    func testCapturasDeLaPantallaDePlanesParaApple() async throws {
        let sesion = try SKTestSession(configurationFileNamed: "TuBroadcast")
        sesion.disableDialogs = true
        sesion.resetToDefaultState()
        sesion.clearTransactions()
        PanelFalso.reiniciar()
        let g = gestorDePrueba()
        let tienda = Tienda(gestor: g)
        await tienda.cargarProductos(avisar: false)
        XCTAssertEqual(tienda.productos.count, 20, "Deben cargar los 20 productos del .storekit")

        guard let escena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Sin escena de ventana en el simulador")
        }
        let carpeta = ProcessInfo.processInfo.environment["CAPTURAS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("capturas-planes")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

        for n in InfoProducto.celularesPosibles {
            XCTAssertEqual(tienda.productos(celulares: n).count, 5, "\(n) celulares: 2 Básico + 2 Completo + 1 Pase")
            let ventana = UIWindow(windowScene: escena)
            ventana.overrideUserInterfaceStyle = .dark
            ventana.rootViewController = UIHostingController(rootView:
                NavigationStack { PantallaPlanes(celularesIniciales: n) }
                    .environmentObject(tienda)
                    .environmentObject(g))
            ventana.windowLevel = .alert + 1
            ventana.makeKeyAndVisible()
            try await Task.sleep(for: .seconds(2))
            let imagen = UIGraphicsImageRenderer(bounds: ventana.bounds).image { _ in
                ventana.drawHierarchy(in: ventana.bounds, afterScreenUpdates: true)
            }
            let png = try XCTUnwrap(imagen.pngData())
            XCTAssertGreaterThan(png.count, 20_000, "La captura no debe salir vacía")
            let archivo = carpeta.appendingPathComponent(String(format: "planes_%02d.png", n))
            try png.write(to: archivo)
            let adjunto = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            adjunto.name = archivo.lastPathComponent
            adjunto.lifetime = .keepAlways
            add(adjunto)
            print("CAPTURA_PLANES \(archivo.path) \(png.count) bytes")
            ventana.isHidden = true
        }
        sesion.clearTransactions()
    }
}
