// TuBroadcast para iPhone (familia Tukan) - transmite en vivo por RTMP/RTMPS y SRT desde el celular.
// El video va directo del celular al destino del cliente (YouTube, Facebook, vMix...). No pasa por servidores de Tukan.
import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

@main
struct TuBroadcastApp: App {
    @StateObject private var ajustes = Ajustes()
    @StateObject private var motor = Motor()
    @StateObject private var gestor: GestorLicencia
    @StateObject private var tienda: Tienda
    @State private var iniciado = false
    @Environment(\.scenePhase) private var fase

    /// true cuando la app solo hospeda las pruebas (XCTest): no arranca latidos, compras ni cámara.
    static let enPruebas = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let g = GestorLicencia(almacen: TuBroadcastApp.enPruebas ? AlmacenMemoria() : AlmacenLlavero())
        _gestor = StateObject(wrappedValue: g)
        _tienda = StateObject(wrappedValue: Tienda(gestor: g))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if TuBroadcastApp.enPruebas {
                    Text("TuBroadcast · pruebas")
                } else if iniciado {
                    PantallaCamara()
                        .environmentObject(ajustes)
                        .environmentObject(motor)
                        .environmentObject(gestor)
                        .environmentObject(tienda)
                } else {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Text("TuBroadcast").font(.largeTitle.bold()).foregroundColor(.white)
                    }
                    .task {
                        await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
                        await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
                        // Solo para las capturas de la App Store (argumento de arranque -conexionesDemo YES):
                        // carga dos conexiones de ejemplo sin mostrar aviso.
                        if UserDefaults.standard.bool(forKey: "conexionesDemo"), ajustes.conexiones.isEmpty {
                            ajustes.conexiones = [
                                Conexion(nombre: "Estadio - vMix", url: "srt://192.168.1.50:9000"),
                                Conexion(nombre: "YouTube Live", url: "rtmp://a.rtmp.youtube.com/live2", clave: "abcd-efgh-ijkl")]
                            ajustes.activa = ajustes.conexiones.first?.id
                            ajustes.resolucion = .p1080
                            ajustes.bitrateKbps = 4500
                        }
                        // Licencia: latido con el panel cada 30 s y compras de Apple (renovaciones, pendientes).
                        let m = motor
                        gestor.estadisticas = { m.estadisticas }
                        gestor.empezarLatidos()
                        tienda.escucharTransacciones()
                        await tienda.cargarProductos(avisar: false)
                        iniciado = true
                        await tienda.revisarPendientes()
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: fase) { nueva in
                if nueva == .active && !TuBroadcastApp.enPruebas {
                    gestor.recalcular()
                    Task { await gestor.latido() }
                }
            }
            .onOpenURL { url in
                // tubroadcast://set/v1?... o larix://set/v1?... (configuracion por QR o enlace)
                let n = ajustes.importarEnlace(url)
                motor.aviso = n > 0 ? "Se cargaron \(n) conexiones" : "El enlace no trae conexiones"
            }
        }
    }
}
